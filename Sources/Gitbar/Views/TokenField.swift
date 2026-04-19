import AppKit
import SwiftUI

/// AppKit-backed token entry so **Paste** (⌘V) and the context menu work reliably; SwiftUI `SecureField` often breaks paste on macOS.
struct TokenField: NSViewRepresentable {
    @Binding var text: String
    var isSecure: Bool
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField
        if isSecure {
            field = NSSecureTextField(string: text)
        } else {
            field = NSTextField(string: text)
        }
        field.placeholderString = placeholder
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        context.coordinator.field = field
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        weak var field: NSTextField?

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
