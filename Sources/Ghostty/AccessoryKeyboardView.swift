import UIKit

/// A terminal accessory bar shown above the system keyboard, giving mobile
/// users the keys a shell needs but iOS keyboards lack: Esc, Ctrl, Alt, Tab,
/// arrows, navigation, and common punctuation. Ctrl/Alt are sticky (tap to
/// arm; applied to the next keystroke).
///
/// When the user is typing a command, a history-based autocomplete row appears
/// above the key bar; tapping a suggestion sends its remaining characters.
final class AccessoryKeyboardView: UIInputView {
    private weak var target: TerminalSurfaceView?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var fnButton: UIButton?
    private var functionKeys: [UIButton] = []
    private var fnVisible = false

    private var suggestionScroll: UIScrollView?
    private var suggestionStack: UIStackView?
    private var suggestionsVisible = false

    private static let keysHeight: CGFloat = 48
    private static let suggestionHeight: CGFloat = 44
    private static let functionKeyList: [Ghostty.Key] =
        [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]

    init(target: TerminalSurfaceView) {
        self.target = target
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: Self.keysHeight),
            inputViewStyle: .keyboard
        )
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var intrinsicContentSize: CGSize {
        let height = Self.keysHeight + (suggestionsVisible ? Self.suggestionHeight : 0)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    private func build() {
        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        root.addArrangedSubview(buildSuggestionRow())
        root.addArrangedSubview(buildKeysRow())
    }

    // MARK: Suggestion row

    private func buildSuggestionRow() -> UIView {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.keyboardDismissMode = .none

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: Self.suggestionHeight),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        scroll.isHidden = true // collapsed until there are suggestions
        suggestionScroll = scroll
        suggestionStack = stack
        return scroll
    }

    /// Replace the autocomplete suggestions. Passing an empty array collapses
    /// the row.
    func updateSuggestions(_ suggestions: [String]) {
        guard let stack = suggestionStack, let scroll = suggestionScroll else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for suggestion in suggestions {
            stack.addArrangedSubview(suggestionChip(suggestion))
        }
        scroll.setContentOffset(.zero, animated: false)

        let visible = !suggestions.isEmpty
        guard visible != suggestionsVisible else { return }
        suggestionsVisible = visible
        scroll.isHidden = !visible
        invalidateIntrinsicContentSize()
    }

    private func suggestionChip(_ text: String) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.tinted()
        config.title = text
        config.baseForegroundColor = .label
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 14)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.target?.applySuggestion(text)
        }, for: .touchUpInside)
        return button
    }

    // MARK: Keys row

    private func buildKeysRow() -> UIView {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.keyboardDismissMode = .none

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: Self.keysHeight),
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

        // Fn toggles a function-key row (F1–F12) in/out of view.
        let fn = makeButton("fn")
        fn.addAction(UIAction { [weak self] _ in self?.toggleFunctionKeys() }, for: .touchUpInside)
        fnButton = fn
        stack.addArrangedSubview(fn)

        stack.addArrangedSubview(specialButton("◀") { $0.pressSpecial(.left) })
        stack.addArrangedSubview(specialButton("▲") { $0.pressSpecial(.up) })
        stack.addArrangedSubview(specialButton("▼") { $0.pressSpecial(.down) })
        stack.addArrangedSubview(specialButton("▶") { $0.pressSpecial(.right) })

        // Common symbols.
        for sym in ["-", "/", "|", "~", "`", ":", "_"] {
            stack.addArrangedSubview(specialButton(sym) { $0.insertSymbol(sym) })
        }

        stack.addArrangedSubview(specialButton("del") { $0.pressSpecial(.delete) })
        stack.addArrangedSubview(specialButton("home") { $0.pressSpecial(.home) })
        stack.addArrangedSubview(specialButton("end") { $0.pressSpecial(.end) })
        stack.addArrangedSubview(specialButton("pgup") { $0.pressSpecial(.pageUp) })
        stack.addArrangedSubview(specialButton("pgdn") { $0.pressSpecial(.pageDown) })

        // Function keys (hidden until Fn is tapped).
        for (i, key) in Self.functionKeyList.enumerated() {
            let button = specialButton("F\(i + 1)") { $0.pressSpecial(key) }
            button.isHidden = true
            functionKeys.append(button)
            stack.addArrangedSubview(button)
        }

        return scroll
    }

    /// Show/hide the F1–F12 row.
    private func toggleFunctionKeys() {
        fnVisible.toggle()
        setArmed(fnButton, fnVisible)
        for button in functionKeys { button.isHidden = !fnVisible }
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
