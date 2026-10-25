import AppKit
import SwiftUI

/// Tekstvak voor het opstellen van een mail (NSTextView zonder eigen scrollbalk): het groeit mee met de tekst, zodat
/// de handtekening er direct onder staat en alles samen scrolt. Met opmaak (`RichTextController`). Een lichtgrijze
/// suggestie van Claude staat in een leeg vak; Tab neemt hem over, zelf typen laat hem vallen.
struct ReplyTextView: NSViewRepresentable {
    @Binding var text: String
    var controller: RichTextController?
    var suggestion: String?
    var focusOnAppear = false
    var minHeight: CGFloat = 80
    /// Tab met een actieve suggestie: `true` = afgehandeld.
    var onTab: () -> Bool
    /// De gebruiker typte zelf iets (geen overname van de suggestie).
    var onTyped: () -> Void

    private static let inset = NSSize(width: 0, height: 4)

    /// Twee lege regels: daaronder staat meteen de handtekening.
    static var twoLines: CGFloat {
        let line = NSLayoutManager().defaultLineHeight(for: RichTextController.defaultFont)
        return ceil(line * 2 + inset.height * 2 + 6)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let textView = RichNSTextView(frame: .zero)
        textView.controller = controller
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.font = RichTextController.defaultFont
        textView.textColor = .textColor
        textView.typingAttributes = RichTextController.defaultAttributes
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = Self.inset
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.updatePlaceholder()
        controller?.attach(textView)
        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.string != text {
            // Van buiten gezet (suggestie, concept, leeg na versturen): standaardopmaak.
            context.coordinator.isUpdating = true
            textView.typingAttributes = RichTextController.defaultAttributes
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.isUpdating = false
            controller?.refreshState()
        }
        context.coordinator.updatePlaceholder()
    }

    /// Zo hoog als de tekst (of de grijze suggestie) bij deze breedte.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let container = textView.textContainer,
              let layout = textView.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(1, width - Self.inset.width * 2), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        var height = layout.usedRect(for: container).height
        if textView.string.isEmpty, let suggestion, !suggestion.isEmpty {
            let padding = container.lineFragmentPadding * 2
            let rect = (suggestion as NSString).boundingRect(
                with: NSSize(width: max(1, width - padding), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: RichTextController.defaultFont])
            height = max(height, rect.height)
        }
        return CGSize(width: width, height: max(minHeight, ceil(height + Self.inset.height * 2 + 6)))
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
            parent.controller?.textDidChange()
            updatePlaceholder()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller?.refreshState()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                return parent.onTab()
            case #selector(NSResponder.insertNewline(_:)):
                return parent.controller?.handleNewline() ?? false
            case #selector(NSResponder.deleteBackward(_:)):
                return parent.controller?.handleDeleteBackward() ?? false
            default:
                return false
            }
        }

        /// De suggestie als grijze tekst in een leeg vak.
        func updatePlaceholder() {
            guard let textView else { return }
            let show = textView.string.isEmpty && !(parent.suggestion ?? "").isEmpty
            if show {
                let label = placeholder ?? {
                    let field = NSTextField(wrappingLabelWithString: "")
                    field.textColor = .tertiaryLabelColor
                    field.font = RichTextController.defaultFont
                    field.isSelectable = false
                    field.translatesAutoresizingMaskIntoConstraints = false
                    textView.addSubview(field)
                    let padding = textView.textContainer?.lineFragmentPadding ?? 5
                    NSLayoutConstraint.activate([
                        field.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: padding),
                        field.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -padding),
                        field.topAnchor.constraint(equalTo: textView.topAnchor, constant: ReplyTextView.inset.height),
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
