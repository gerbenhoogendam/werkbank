import AppKit
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Bijlagen van een mail, onder de tekst: afbeeldingen en pdf's als voorbeeld, andere bestanden als tegel.
/// Zoals in de Finder: klik kiest de bijlage, spatie of vasthouden toont hem in Snelle weergave (Quick Look),
/// dubbelklik opent hem in het standaardprogramma; slepen zet hem in de Finder of een andere app.
struct MailAttachmentsView: View {
    let files: [MailAttachment]
    /// Map waarin de bijlagen voor openen en slepen worden neergezet (één per mail).
    let folderName: String

    var body: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(files.count) bijlage\(files.count == 1 ? "" : "n")", systemImage: "paperclip")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    AttachmentItem(file: file, folderName: folderName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AttachmentItem: View {
    let file: MailAttachment
    let folderName: String

    @State private var preview: NSImage?
    @State private var pageCount = 0
    @State private var isSelected = false

    private var kind: Kind {
        if file.mediaType.hasPrefix("image/") || Self.imageExtensions.contains(ext) { return .image }
        if file.mediaType == "application/pdf" || ext == "pdf" { return .pdf }
        return .other
    }

    private enum Kind { case image, pdf, other }
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp", "bmp"]
    private var ext: String { (file.name as NSString).pathExtension.lowercased() }
    private var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file) }

    var body: some View {
        Group {
            switch kind {
            case .image, .pdf:
                VStack(alignment: .leading, spacing: 4) {
                    if let preview {
                        // Nooit groter dan het plaatje zelf (een klein icoon werd over de hele breedte opgeblazen).
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: min(preview.size.width, 360),
                                   maxHeight: min(preview.size.height, kind == .pdf ? 460 : 300), alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ThingsColor.separator))
                    } else {
                        tile
                    }
                    caption
                }
            case .other:
                tile
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? ThingsColor.selection : Color.clear)
                .padding(-4)
        )
        // Klikken, vasthouden, slepen en de spatiebalk gaan via AppKit (zoals in de Finder, zonder wachttijd).
        .overlay(AttachmentMouseArea(name: file.name, fileURL: { writeTemporary() }, onSelect: { isSelected = $0 },
                                     onOpen: { open() }, onSaveAs: { saveAs() }))
        .task(id: file.name) { await makePreview() }
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text(file.name).lineLimit(1)
            if kind == .pdf, pageCount > 0 {
                Text("· \(pageCount) pagina\(pageCount == 1 ? "" : "'s")").foregroundStyle(ThingsColor.textTertiary)
            }
            Text("· \(sizeText)").foregroundStyle(ThingsColor.textTertiary)
        }
        .thingsFont(.metadata)
        .foregroundStyle(ThingsColor.textSecondary)
    }

    private var tile: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.werk(size: 13))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                Text(sizeText)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
    }

    // MARK: Voorbeeld

    private func makePreview() async {
        switch kind {
        case .image:
            preview = NSImage(data: file.data)
        case .pdf:
            guard let document = PDFDocument(data: file.data), let page = document.page(at: 0) else { return }
            pageCount = document.pageCount
            let bounds = page.bounds(for: .mediaBox)
            let scale = 720 / max(bounds.width, 1)
            preview = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        case .other:
            break
        }
    }

    // MARK: Openen en bewaren

    /// Zet de bijlage in een eigen tijdelijke map (nodig om hem te openen of te slepen).
    private func writeTemporary() -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Werkbank-bijlagen", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = file.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(safeName.isEmpty ? "bijlage" : safeName)
        do {
            try file.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func open() {
        guard let url = writeTemporary() else { return }
        NSWorkspace.shared.open(url)
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? file.data.write(to: url, options: .atomic)
    }
}

// MARK: - Klikken, vasthouden, slepen, spatie

/// Over een bijlage heen: klik kiest hem, dubbelklik opent hem, vasthouden (een halve seconde zonder te bewegen) of de
/// spatiebalk toont hem in Snelle weergave, slepen zet hem in de Finder of een andere app, rechtsklik geeft het menu.
private struct AttachmentMouseArea: NSViewRepresentable {
    let name: String
    let fileURL: () -> URL?
    let onSelect: (Bool) -> Void
    let onOpen: () -> Void
    let onSaveAs: () -> Void

    func makeNSView(context: Context) -> AttachmentMouseView {
        let view = AttachmentMouseView()
        update(view)
        return view
    }

    func updateNSView(_ view: AttachmentMouseView, context: Context) {
        update(view)
    }

    private func update(_ view: AttachmentMouseView) {
        view.toolTip = name
        view.setAccessibilityLabel(name)
        view.fileURL = fileURL
        view.onSelect = onSelect
        view.onOpen = onOpen
        view.onSaveAs = onSaveAs
    }
}

/// De bijlage is gekozen zolang dit view de eerste responder van zijn venster is (klik ernaast: niet meer gekozen).
/// Snelle weergave zoekt zijn bron in de responder-keten (`acceptsPreviewPanelControl`), dus via de gekozen bijlage.
final class AttachmentMouseView: NSView, NSDraggingSource, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var fileURL: () -> URL? = { nil }
    var onSelect: (Bool) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var onSaveAs: () -> Void = {}

    /// Hoe lang vasthouden voor Snelle weergave, en hoe ver bewegen voordat het slepen is.
    private static let holdDelay = Duration.milliseconds(500)
    private static let dragDistance: CGFloat = 4

    private var downEvent: NSEvent?
    private var dragging = false
    private var holdTask: Task<Void, Never>?
    /// Het bestand dat Snelle weergave toont.
    private var previewURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        onSelect(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        onSelect(false)
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        holdTask?.cancel()
        // Weg uit beeld (andere mail): Snelle weergave mag niet meer naar dit view vragen.
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
           (panel.dataSource as AnyObject?) === self {
            panel.orderOut(nil)
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    // MARK: Muis

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        holdTask?.cancel()
        if event.clickCount >= 2 {
            downEvent = nil
            onOpen()
            return
        }
        downEvent = event
        dragging = false
        // Staat Snelle weergave al open: meteen deze bijlage tonen.
        if Self.previewIsOpen {
            showPreview()
            return
        }
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled, let self, self.downEvent != nil, !self.dragging else { return }
            self.showPreview()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downEvent, !dragging else { return }
        let from = start.locationInWindow, to = event.locationInWindow
        guard hypot(to.x - from.x, to.y - from.y) >= Self.dragDistance else { return }
        dragging = true
        holdTask?.cancel()
        guard let url = fileURL() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 48, height: 48)
        let point = convert(from, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        holdTask?.cancel()
        downEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let menu = NSMenu()
        menu.addItem(withTitle: "Openen", action: #selector(openItem), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Snelle weergave", action: #selector(previewItem), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Bewaar als…", action: #selector(saveItem), keyEquivalent: "").target = self
        return menu
    }

    @objc private func openItem() { onOpen() }
    @objc private func previewItem() { showPreview() }
    @objc private func saveItem() { onSaveAs() }

    // MARK: Toetsen

    /// Spatie: Snelle weergave open of dicht (in Snelle weergave zelf sluit de spatie hem ook).
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            if Self.previewIsOpen { QLPreviewPanel.shared()?.orderOut(nil) } else { showPreview() }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Snelle weergave

    private static var previewIsOpen: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
    }

    private func showPreview() {
        guard let url = fileURL(), let panel = QLPreviewPanel.shared() else { return }
        previewURL = url
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        if panel.isVisible {
            panel.updateController()
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if previewURL == nil { previewURL = fileURL() }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if (panel.dataSource as AnyObject?) === self {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let previewURL else { return nil }
        return previewURL as NSURL
    }

    /// Snelle weergave groeit uit de bijlage en krimpt er weer naartoe.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}
