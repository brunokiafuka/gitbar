import SwiftUI
import AppKit

/// Suppresses the app's global click-outside dismissal while the character
/// palette is open, so selecting an emoji doesn't close the menu-bar panel.
@MainActor
enum EmojiPaletteState {
    static var isOpen: Bool = false
}

/// Invisible text field that triggers the macOS character palette and captures
/// the first emoji character the user picks. Set `requestFocus = true` to open
/// the picker; the first emoji lands in `selected`.
struct EmojiCaptureField: NSViewRepresentable {
    @Binding var selected: String?
    @Binding var requestFocus: Bool

    func makeNSView(context: Context) -> CaptureField {
        let field = CaptureField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 1)
        field.textColor = .clear
        field.delegate = context.coordinator
        field.refusesFirstResponder = false
        return field
    }

    func updateNSView(_ nsView: CaptureField, context: Context) {
        if requestFocus {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                EmojiPaletteState.isOpen = true
                NSApp.orderFrontCharacterPalette(nil)
                self.requestFocus = false
                // Safety reset — in case the user dismisses the palette without
                // picking anything, we don't want to freeze the panel forever.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    EmojiPaletteState.isOpen = false
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selected: $selected)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let selected: Binding<String?>

        init(selected: Binding<String?>) {
            self.selected = selected
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            let value = field.stringValue
            defer {
                field.stringValue = ""
                Task { @MainActor in EmojiPaletteState.isOpen = false }
            }
            guard let emoji = Self.firstEmoji(in: value) else { return }
            selected.wrappedValue = emoji
        }

        static func firstEmoji(in value: String) -> String? {
            for char in value {
                if char.unicodeScalars.contains(where: { $0.properties.isEmoji })
                    && char.unicodeScalars.contains(where: {
                        $0.properties.isEmojiPresentation
                            || $0.value >= 0x1F000
                    })
                {
                    return String(char)
                }
            }
            return nil
        }
    }

    final class CaptureField: NSTextField {
        override var acceptsFirstResponder: Bool { true }
    }
}
