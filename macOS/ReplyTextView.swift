import AppKit
import SwiftUI

/// Tekstvak voor het opstellen van een mail (NSTextView), met een lichtgrijze suggestie van Claude.
/// Tab neemt de suggestie over; zelf typen laat hem vallen.
struct ReplyTextView: NSViewRepresentable {
    @Binding var text: String
    /// Lichtgrijs getoonde suggestie (alleen als het vak leeg is staat hij in het vak zelf; anders eronder).
    var suggestion: String?
    var focusOnAppear = false
    /// Tab met een actieve suggestie: `true` = afgehandeld.
    var onTab: () -> Bool
    /// De gebruiker typte zelf iets (geen overname van de suggestie).
    var onTyped: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.string = text
        context.coordinator.textView = textView
        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.isUpdating = false
        }
        context.coordinator.updatePlaceholder()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReplyTextView
        weak var textView: NSTextView?
        var isUpdating = false
        private var placeholder: NSTextField?

        init(_ parent: ReplyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            parent.text = textView.string
            parent.onTyped()
            updatePlaceholder()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertTab(_:)) { return parent.onTab() }
            return false
        }

        /// De suggestie als grijze tekst in een leeg vak.
        func updatePlaceholder() {
            guard let textView else { return }
            let show = textView.string.isEmpty && !(parent.suggestion ?? "").isEmpty
            if show {
                let label = placeholder ?? {
                    let field = NSTextField(wrappingLabelWithString: "")
                    field.textColor = .tertiaryLabelColor
                    field.font = .systemFont(ofSize: 13)
                    field.isSelectable = false
                    field.translatesAutoresizingMaskIntoConstraints = false
                    textView.addSubview(field)
                    let padding = textView.textContainer?.lineFragmentPadding ?? 5
                    NSLayoutConstraint.activate([
                        field.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: padding),
                        field.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -padding),
                        field.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4),
                    ])
                    placeholder = field
                    return field
                }()
                label.stringValue = parent.suggestion ?? ""
                label.isHidden = false
            } else {
                placeholder?.isHidden = true
            }
        }
    }
}
