import Foundation
import NIOCore
import NIOPosix
import NIOSSH

struct SSHConnectionInfo {
    let host: String
    let port: Int
    let username: String
    let password: String?
    let privateKey: String?
}

enum SSHAuthMethod {
    case password(String)
    case privateKey(String, passphrase: String?)
}

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

final class SimplePasswordDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        if availableMethods.contains(.password) {
            nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .password(.init(password: password))))
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

final class SSHShellChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    let columns: Int
    let rows: Int
    var onData: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let termEnv = SSHChannelRequestEvent.EnvironmentRequest(
            wantReply: false, name: "LANG", value: "en_US.UTF-8")
        context.channel.setOption(
            ChannelOptions.allowRemoteHalfClosure, value: true
        ).flatMap {
            context.channel.triggerUserOutboundEvent(
                SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: self.columns,
                    terminalRowHeight: self.rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([
                        .ECHO: 1, .ICANON: 1
                    ])
                ))
        }.flatMap {
            context.channel.triggerUserOutboundEvent(termEnv)
        }.flatMap {
            context.channel.triggerUserOutboundEvent(
                SSHChannelRequestEvent.ShellRequest(wantReply: true))
        }.whenFailure { error in
            context.fireErrorCaught(error)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        let bytes = Array(buffer.readableBytesView)
        DispatchQueue.main.async { [weak self] in
            self?.onData?(bytes)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.write(wrapOutboundOut(channelData), promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        DispatchQueue.main.async { [weak self] in
            self?.onClose?()
        }
        context.fireChannelInactive()
    }
}

final class SSHErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("SSH error: \(error)")
        context.close(promise: nil)
    }
}

final class SSHConnection {
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var shellChannel: Channel?
    private let shellHandler = SSHShellChannelHandler(columns: 80, rows: 24)

    var onData: (([UInt8]) -> Void)? {
        get { shellHandler.onData }
        set { shellHandler.onData = newValue }
    }

    var onClose: (() -> Void)? {
        get { shellHandler.onClose }
        set { shellHandler.onClose = newValue }
    }

    func connect(info: SSHConnectionInfo) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let userAuthDelegate = SimplePasswordDelegate(
            username: info.username, password: info.password ?? "")
        let serverAuthDelegate = AcceptAllHostKeysDelegate()

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: userAuthDelegate,
                            serverAuthDelegate: serverAuthDelegate)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil),
                    SSHErrorHandler()
                ])
            }
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(.seconds(10))

        bootstrap.connect(host: info.host, port: info.port).flatMap { channel -> EventLoopFuture<Channel> in
            self.channel = channel
            let createChannel = channel.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler -> EventLoopFuture<Channel> in
                let promise = channel.eventLoop.makePromise(of: Channel.self)
                sshHandler.createChannel(promise) { childChannel, channelType in
                    guard channelType == .session else {
                        return channel.eventLoop.makeFailedFuture(SSHConnectionError.invalidChannelType)
                    }
                    return childChannel.pipeline.addHandler(self.shellHandler)
                }
                return promise.futureResult
            }
            return createChannel
        }.whenComplete { result in
            switch result {
            case .success(let shellChannel):
                self.shellChannel = shellChannel
            case .failure(let error):
                print("SSH connection failed: \(error)")
                DispatchQueue.main.async { self.onClose?() }
            }
        }
    }

    func send(_ data: Data) {
        guard let shellChannel = shellChannel else { return }
        let loop = shellChannel.eventLoop
        loop.execute {
            var buffer = shellChannel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            shellChannel.writeAndFlush(buffer, promise: nil)
        }
    }

    func resize(cols: Int, rows: Int) {
        guard let shellChannel = shellChannel else { return }
        let loop = shellChannel.eventLoop
        loop.execute {
            _ = shellChannel.triggerUserOutboundEvent(
                SSHChannelRequestEvent.WindowChangeRequest(
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0
                ))
        }
    }

    func disconnect() {
        shellChannel?.close(promise: nil)
        channel?.close(promise: nil)
        try? group?.syncShutdownGracefully()
        group = nil
        channel = nil
        shellChannel = nil
    }
}

enum SSHConnectionError: Error {
    case invalidChannelType
    case connectionFailed
}
