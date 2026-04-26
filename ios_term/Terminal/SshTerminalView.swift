import UIKit
import SwiftTerm

class SshTerminalView: TerminalView, TerminalViewDelegate {
    private var sshConnection: SSHConnection?

    func setupSSH(info: SSHConnectionInfo) {
        terminalDelegate = self
        let conn = SSHConnection()
        self.sshConnection = conn

        conn.onData = { [weak self] bytes in
            self?.feed(byteArray: ArraySlice(bytes))
        }
        conn.onError = { [weak self] error in
            self?.feed(text: "\r\n[SSH error: \(error)]\r\n")
        }
        conn.onClose = { [weak self] in
            self?.feed(text: "\r\n[Connection closed]\r\n")
        }
        conn.connect(info: info)
    }

    func disconnect() {
        sshConnection?.disconnect()
        sshConnection = nil
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sshConnection?.send(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}

    func setTerminalTitle(source: TerminalView, title: String) {}

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        sshConnection?.resize(cols: newCols, rows: newRows)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = str
        }
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
    }

    func bell(source: TerminalView) {}

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}
