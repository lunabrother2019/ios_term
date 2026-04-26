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
    private var tried = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        print("[SSH] auth callback: methods=\(availableMethods), tried=\(tried)")
        guard !tried, availableMethods.contains(.password) else {
            print("[SSH] auth: no more methods")
            nextChallengePromise.succeed(nil)
            return
        }
        tried = true
        print("[SSH] auth: sending password for \(username), pwd length=\(password.count), first=\(password.prefix(1)), last=\(password.suffix(1))")
        nextChallengePromise.succeed(.init(
            username: username,
            serviceName: "",
            offer: .password(.init(password: password))
        ))
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

final class SSHDebugHandler: ChannelDuplexHandler {
    typealias InboundIn = Any
    typealias OutboundIn = Any

    func channelActive(context: ChannelHandlerContext) {
        print("[SSH] TCP connected to \(context.channel.remoteAddress?.description ?? "?")")
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        print("[SSH] TCP disconnected")
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(data, promise: promise)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[SSH] pipeline error: \(error)")
        context.fireErrorCaught(error)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        print("[SSH] event: \(event)")
        context.fireUserInboundEventTriggered(event)
    }
}

final class SSHErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    var onError: ((Error) -> Void)?

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[SSH] error handler: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
        context.close(promise: nil)
    }
}

final class SSHConnection {
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var shellChannel: Channel?
    private let shellHandler = SSHShellChannelHandler(columns: 80, rows: 24)
    private let errorHandler = SSHErrorHandler()

    var onData: (([UInt8]) -> Void)? {
        get { shellHandler.onData }
        set { shellHandler.onData = newValue }
    }

    var onClose: (() -> Void)? {
        get { shellHandler.onClose }
        set { shellHandler.onClose = newValue }
    }

    var onError: ((Error) -> Void)? {
        get { errorHandler.onError }
        set { errorHandler.onError = newValue }
    }

    func connect(info: SSHConnectionInfo) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let userAuthDelegate = SimplePasswordDelegate(
            username: info.username, password: info.password ?? "")
        let serverAuthDelegate = AcceptAllHostKeysDelegate()
        let errHandler = self.errorHandler

        print("[SSH] connecting to \(info.host):\(info.port) as \(info.username)")

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    SSHDebugHandler(),
                    NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: userAuthDelegate,
                            serverAuthDelegate: serverAuthDelegate)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil),
                    errHandler
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
                DispatchQueue.main.async {
                    self.onError?(error)
                    self.onClose?()
                }
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
