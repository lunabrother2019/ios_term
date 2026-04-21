import SwiftUI

struct TerminalRepresentable: UIViewControllerRepresentable {
    let connectionInfo: SSHConnectionInfo

    func makeUIViewController(context: Context) -> TerminalViewController {
        let vc = TerminalViewController()
        vc.configure(with: connectionInfo)
        return vc
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {}
}
