import UIKit

/// System (soft) keyboard input. We translate the few characters the on-screen
/// keyboard emits as text but which terminals expect as key events (newline,
/// tab) into proper key events so ghostty encodes them correctly; everything
/// else is sent as text.
extension TerminalSurfaceView: UIKeyInput {
    var hasText: Bool { true }

    func insertText(_ text: String) {
        switch text {
        case "\n", "\r":
            sendKey(.enter)
        case "\t":
            sendKey(.tab)
        default:
            sendText(text)
        }
    }

    func deleteBackward() {
        sendKey(.backspace)
    }
}

/// Terminal-friendly text input traits: no autocorrect/autocapitalize/smart
/// punctuation, which would otherwise corrupt what the user types into a shell.
/// (UIKeyInput already implies UITextInputTraits conformance; these computed
/// properties satisfy its requirements.)
extension TerminalSurfaceView {
    var autocorrectionType: UITextAutocorrectionType {
        get { .no } set {}
    }
    var autocapitalizationType: UITextAutocapitalizationType {
        get { .none } set {}
    }
    var spellCheckingType: UITextSpellCheckingType {
        get { .no } set {}
    }
    var smartQuotesType: UITextSmartQuotesType {
        get { .no } set {}
    }
    var smartDashesType: UITextSmartDashesType {
        get { .no } set {}
    }
    var smartInsertDeleteType: UITextSmartInsertDeleteType {
        get { .no } set {}
    }
    var keyboardType: UIKeyboardType {
        get { .asciiCapable } set {}
    }
    var keyboardAppearance: UIKeyboardAppearance {
        get { .dark } set {}
    }
    var returnKeyType: UIReturnKeyType {
        get { .default } set {}
    }
}
