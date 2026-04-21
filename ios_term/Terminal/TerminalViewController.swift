import UIKit
import SwiftTerm

class TerminalViewController: UIViewController {
    private var terminalView: SshTerminalView?
    private var connectionInfo: SSHConnectionInfo?

    func configure(with info: SSHConnectionInfo) {
        self.connectionInfo = info
        if isViewLoaded {
            startConnection()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let tv = SshTerminalView(frame: view.bounds)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.nativeBackgroundColor = .black
        tv.nativeForegroundColor = UIColor(red: 0.87, green: 0.87, blue: 0.87, alpha: 1)
        view.addSubview(tv)

        if #available(iOS 15.0, *) {
            NSLayoutConstraint.activate([
                tv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                tv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                tv.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                tv.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                tv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                tv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                tv.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                tv.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
        }

        self.terminalView = tv

        let extraKeys = ExtraKeysView(terminalView: tv)
        tv.inputAccessoryView = extraKeys

        if connectionInfo != nil {
            startConnection()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        terminalView?.becomeFirstResponder()
    }

    private func startConnection() {
        guard let info = connectionInfo else { return }
        terminalView?.setupSSH(info: info)
    }

    deinit {
        terminalView?.disconnect()
    }
}
