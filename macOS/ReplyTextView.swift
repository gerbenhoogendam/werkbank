import AppKit
import SwiftUI

/// Tekstvak voor het opstellen van een mail (NSTextView zonder eigen scrollbalk): het groeit mee met de tekst, zodat
/// de handtekening er direct onder staat en alles samen scrolt. Een lichtgrijze suggestie van Claude staat in een
/// leeg vak; Tab neemt hem over, zelf typen laat hem vallen.
struct ReplyTextView: NSViewRepresentable {
    @Binding var text: String
    var suggestion: String?
    var focusOnAppear = false
    var minHeight: CGFloat = 80
    /// Tab met een actieve suggestie: `true` = afgehandeld.
    var onTab: () -> Bool
    /// De gebruiker typte zelf iets (geen overname van de suggestie).
    var onTyped: () -> Void

    private static let font = NSFont.systemFont(ofSize: 13)
    private static let inset = NSSize(width: 0, height: 4)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = Self.inset
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.updatePlaceholder()
        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.isUpdating = false
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
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: Self.font])
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
                    field.font = ReplyTextView.font
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
