import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Bijlagen van een mail, onder de tekst: afbeeldingen en pdf's als voorbeeld, andere bestanden als tegel.
/// Klik opent de bijlage in het standaardprogramma; slepen zet hem in de Finder of een andere app.
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
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: kind == .pdf ? 360 : .infinity, maxHeight: kind == .pdf ? 460 : 420,
                                   alignment: .leading)
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
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onDrag {
            guard let url = writeTemporary() else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Openen") { open() }
            Button("Bewaar als…") { saveAs() }
        }
        .help("\(file.name) · klik om te openen, sleep om te bewaren")
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
                    .font(.system(size: 13))
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
