import UIKit

/// A terminal accessory bar shown above the system keyboard, giving mobile
/// users the keys a shell needs but iOS keyboards lack: Esc, Ctrl, Alt, Tab,
/// arrows, navigation, and common punctuation. Ctrl/Alt are sticky (tap to
/// arm; applied to the next keystroke).
final class AccessoryKeyboardView: UIInputView {
    private weak var target: TerminalSurfaceView?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?

    private static let barHeight: CGFloat = 48

    init(target: TerminalSurfaceView) {
        self.target = target
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: Self.barHeight),
            inputViewStyle: .keyboard
        )
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight)
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.keyboardDismissMode = .none
        addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -12),
        ])

        // Special keys.
        stack.addArrangedSubview(specialButton("esc") { $0.pressSpecial(.escape) })

        let ctrl = toggleButton("ctrl") { [weak self] in
            guard let self, let t = self.target else { return false }
            return t.toggleCtrl()
        }
        ctrlButton = ctrl
        stack.addArrangedSubview(ctrl)

        let alt = toggleButton("alt") { [weak self] in
            guard let self, let t = self.target else { return false }
            return t.toggleAlt()
        }
        altButton = alt
        stack.addArrangedSubview(alt)

        stack.addArrangedSubview(specialButton("tab") { $0.pressSpecial(.tab) })
        stack.addArrangedSubview(specialButton("◀") { $0.pressSpecial(.left) })
        stack.addArrangedSubview(specialButton("▲") { $0.pressSpecial(.up) })
        stack.addArrangedSubview(specialButton("▼") { $0.pressSpecial(.down) })
        stack.addArrangedSubview(specialButton("▶") { $0.pressSpecial(.right) })

        // Common symbols.
        for sym in ["-", "/", "|", "~", "`", ":", "_"] {
            stack.addArrangedSubview(specialButton(sym) { $0.insertSymbol(sym) })
        }

        stack.addArrangedSubview(specialButton("home") { $0.pressSpecial(.home) })
        stack.addArrangedSubview(specialButton("end") { $0.pressSpecial(.end) })
        stack.addArrangedSubview(specialButton("pgup") { $0.pressSpecial(.pageUp) })
        stack.addArrangedSubview(specialButton("pgdn") { $0.pressSpecial(.pageDown) })
    }

    /// Reset the visual armed state of the modifier keys.
    func updateModifierState(ctrl: Bool, alt: Bool) {
        setArmed(ctrlButton, ctrl)
        setArmed(altButton, alt)
    }

    // MARK: Button factories

    private func specialButton(_ title: String, action: @escaping (TerminalSurfaceView) -> Void) -> UIButton {
        let button = makeButton(title)
        button.addAction(UIAction { [weak self] _ in
            guard let t = self?.target else { return }
            action(t)
        }, for: .touchUpInside)
        return button
    }

    private func toggleButton(_ title: String, toggle: @escaping () -> Bool) -> UIButton {
        let button = makeButton(title)
        button.addAction(UIAction { [weak self] _ in
            let armed = toggle()
            self?.setArmed(button, armed)
        }, for: .touchUpInside)
        return button
    }

    private func makeButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.gray()
        config.title = title
        config.baseForegroundColor = .label
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        return button
    }

    private func setArmed(_ button: UIButton?, _ armed: Bool) {
        guard let button else { return }
        var config = button.configuration
        config?.baseBackgroundColor = armed ? .systemBlue : nil
        config?.baseForegroundColor = armed ? .white : .label
        button.configuration = config
    }
}
