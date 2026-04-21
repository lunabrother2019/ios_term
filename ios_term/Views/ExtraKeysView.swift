import UIKit
import SwiftTerm

class ExtraKeysView: UIInputView {
    private weak var terminalView: SshTerminalView?

    init(terminalView: SshTerminalView) {
        self.terminalView = terminalView
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44),
                   inputViewStyle: .keyboard)
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var ctrlActive = false

    private func setupButtons() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -4),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -8),
        ])

        let keys: [(String, [UInt8])] = [
            ("Esc", [0x1b]),
            ("Tab", [0x09]),
            ("Ctrl", []),
            ("|", [0x7c]),
            ("/", [0x2f]),
            ("~", [0x7e]),
            ("-", [0x2d]),
            ("\u{2191}", [0x1b, 0x5b, 0x41]),
            ("\u{2193}", [0x1b, 0x5b, 0x42]),
            ("\u{2190}", [0x1b, 0x5b, 0x44]),
            ("\u{2192}", [0x1b, 0x5b, 0x43]),
        ]

        for (title, bytes) in keys {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            btn.backgroundColor = UIColor(white: 0.25, alpha: 1)
            btn.setTitleColor(.white, for: .normal)
            btn.layer.cornerRadius = 6
            btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

            if title == "Ctrl" {
                btn.tag = 999
                btn.addAction(UIAction { [weak self] _ in
                    self?.toggleCtrl(btn)
                }, for: .touchUpInside)
            } else {
                btn.addAction(UIAction { [weak self] _ in
                    self?.sendBytes(bytes)
                }, for: .touchUpInside)
            }
            stack.addArrangedSubview(btn)
        }
    }

    private func toggleCtrl(_ btn: UIButton) {
        ctrlActive.toggle()
        btn.backgroundColor = ctrlActive
            ? UIColor.systemBlue
            : UIColor(white: 0.25, alpha: 1)
    }

    private func sendBytes(_ bytes: [UInt8]) {
        guard let tv = terminalView else { return }
        if ctrlActive && bytes.count == 1 {
            let b = bytes[0]
            if b >= 0x40 && b <= 0x7e {
                let ctrlByte = b & 0x1f
                tv.send([ctrlByte])
                ctrlActive = false
                if let ctrlBtn = findCtrlButton() {
                    ctrlBtn.backgroundColor = UIColor(white: 0.25, alpha: 1)
                }
                return
            }
        }
        tv.send(bytes)
    }

    private func findCtrlButton() -> UIButton? {
        for sub in subviews {
            for inner in sub.subviews {
                if let stack = inner as? UIStackView {
                    return stack.arrangedSubviews.first(where: { ($0 as? UIButton)?.tag == 999 }) as? UIButton
                }
            }
        }
        return nil
    }
}
