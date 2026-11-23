import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

// MARK: - Model

/// De handtekening die in de editor open staat (per mailbox, of "" voor alle). Elke wijziging wordt na een korte pauze
/// bewaard, samen met de HTML die bij versturen onder de mail komt.
@MainActor
@Observable
final class SignatureEditorModel {
    private(set) var key: String
    var document = SignatureDocument() {
        didSet { documentChanged(from: oldValue) }
    }
    var selection: UUID?
    private(set) var showsHTML = false
    /// De HTML zoals hij in de HTML-weergave staat (en getypt wordt).
    var htmlText = ""
    private(set) var logo: Data?
    private(set) var logoImage: NSImage?
    /// Hoogte van het logo volgt de breedte.
    var lockRatio = true
    private var undoStack: [SignatureDocument] = []
    private var redoStack: [SignatureDocument] = []

    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSnapshot = Date.distantPast
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var htmlTask: Task<Void, Never>?

    init(key: String) {
        self.key = key
        open(key)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Openen en bewaren

    /// Een andere mailbox: eerst bewaren wat er openstaat.
    func load(_ key: String) {
        guard key != self.key else { return }
        saveNow()
        self.key = key
        open(key)
    }

    private func open(_ key: String) {
        logo = MailSignatures.ownLogo(key) ?? MailSignatures.ownLogo(MailSignatures.defaultKey)
        logoImage = logo.flatMap(NSImage.init(data:))
        var document = MailSignatures.editableDocument(key)
        fixLogoSizes(&document)
        replace(with: document)
        undoStack.removeAll()
        redoStack.removeAll()
        dirty = false
        selection = document.blocks.first?.id
        if showsHTML { htmlText = document.html() }
    }

    private func replace(with document: SignatureDocument) {
        restoring = true
        self.document = document
        restoring = false
    }

    private func documentChanged(from old: SignatureDocument) {
        guard !restoring, old != document else { return }
        // Snel na elkaar (typen, een schuif): één stap terug.
        if Date().timeIntervalSince(lastSnapshot) > 0.8 {
            undoStack.append(old)
            if undoStack.count > 200 { undoStack.removeFirst() }
        }
        lastSnapshot = Date()
        redoStack.removeAll()
        scheduleSave()
    }

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard dirty else { return }
        dirty = false
        MailSignatures.setDocument(document, for: key)
    }

    /// ⌘S: wat in de HTML-weergave getypt is meteen verwerken (niet wachten tot het typen stilstaat) en bewaren.
    func saveExplicitly() {
        htmlTask?.cancel()
        if showsHTML, htmlText != document.html() {
            var imported = SignatureImport.document(fromHTML: htmlText)
            fixLogoSizes(&imported)
            document = imported
            if let selection, block(selection) == nil { self.selection = imported.blocks.first?.id }
        }
        dirty = true
        saveNow()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        restore(next)
    }

    private func restore(_ document: SignatureDocument) {
        replace(with: document)
        lastSnapshot = .distantPast
        if let selection, block(selection) == nil { self.selection = document.blocks.first?.id }
        if showsHTML { htmlText = document.html() }
        scheduleSave()
    }

    // MARK: HTML

    func setShowsHTML(_ value: Bool) {
        if value { htmlText = document.html() }
        showsHTML = value
    }

    /// Getypt in de HTML-weergave: even wachten, dan opnieuw in blokken.
    func htmlEdited(_ text: String) {
        htmlTask?.cancel()
        htmlTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, text != self.document.html() else { return }
            self.adopt(SignatureImport.document(fromHTML: text))
        }
    }

    /// HTML van elders (een bestand): de blokken worden opnieuw opgebouwd.
    func importHTML(_ text: String) {
        adopt(SignatureImport.document(fromHTML: text))
        if showsHTML { htmlText = document.html() }
    }

    private func adopt(_ imported: SignatureDocument) {
        var imported = imported
        fixLogoSizes(&imported)
        document = imported
        selection = imported.blocks.first?.id
    }

    func copyHTML() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let html = document.html()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    // MARK: Blokken

    func block(_ id: UUID) -> SignatureBlock? { document.blocks.first { $0.id == id } }
    func index(of id: UUID) -> Int? { document.blocks.firstIndex { $0.id == id } }
    var selectedIndex: Int? { selection.flatMap(index(of:)) }
    var selectedBlock: SignatureBlock? { selection.flatMap(block) }

    func update(_ id: UUID, _ change: (inout SignatureBlock) -> Void) {
        guard let index = index(of: id) else { return }
        var block = document.blocks[index]
        change(&block)
        guard block != document.blocks[index] else { return }
        document.blocks[index] = block
    }

    private var insertionIndex: Int {
        selectedIndex.map { $0 + 1 } ?? document.blocks.count
    }

    func addText() {
        let block = SignatureBlock.text([])
        document.blocks.insert(block, at: insertionIndex)
        selection = block.id
    }

    /// Een logo-blok met het logo van deze handtekening.
    func addLogo() {
        guard !document.hasLogo else { return }
        let width = min(logoPixels?.width ?? 200, 200)
        let block = SignatureBlock.logo(width: width, height: height(forWidth: width, current: 52))
        document.blocks.insert(block, at: insertionIndex)
        selection = block.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        document.blocks.remove(at: index)
        let next = min(index, document.blocks.count - 1)
        selection = next >= 0 ? document.blocks[next].id : nil
    }

    func move(from source: IndexSet, to destination: Int) {
        document.blocks.move(fromOffsets: source, toOffset: destination)
    }

    /// De ruimte onder een blok is de ruimte boven het volgende (of onder de hele handtekening).
    func spaceBelow(_ index: Int) -> Int {
        index + 1 < document.blocks.count ? document.blocks[index + 1].spaceAbove : document.spaceBelow
    }

    func setSpaceBelow(_ index: Int, _ value: Int) {
        if index + 1 < document.blocks.count {
            document.blocks[index + 1].spaceAbove = value
        } else {
            document.spaceBelow = value
        }
    }

    /// Vet, cursief of onderstreept voor het hele blok aan of uit.
    func toggleStyle(_ id: UUID, _ keyPath: WritableKeyPath<SignatureRun, Bool>) {
        guard let block = block(id), !block.runs.isEmpty else { return }
        let on = !block.runs.allSatisfy { $0[keyPath: keyPath] }
        update(id) { block in
            block.runs = block.runs.map { run in
                var run = run
                run[keyPath: keyPath] = on
                return run
            }
        }
    }

    /// Alle links in de handtekening (in de tekst en op het logo).
    var links: [(id: UUID, title: String, href: String)] {
        document.blocks.flatMap { block -> [(id: UUID, title: String, href: String)] in
            switch block.kind {
            case .text:
                return block.runs.compactMap { run in run.link.map { (block.id, run.text, $0) } }
            case .logo:
                return block.link.flatMap { $0.isEmpty ? nil : [(block.id, "Logo", $0)] } ?? []
            case .html:
                return []
            }
        }
    }

    // MARK: Logo

    var logoPixels: (width: Int, height: Int)? {
        guard let logo, let rep = NSBitmapImageRep(data: logo), rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            guard let size = logoImage?.size, size.width > 0, size.height > 0 else { return nil }
            return (Int(size.width), Int(size.height))
        }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    private func height(forWidth width: Int, current: Int) -> Int {
        guard let pixels = logoPixels else { return current }
        return max(1, Int((Double(width) * Double(pixels.height) / Double(pixels.width)).rounded()))
    }

    func setLogoWidth(_ id: UUID, _ width: Int) {
        let width = min(max(width, 16), 600)
        update(id) { block in
            let ratio = block.width > 0 ? Double(block.height) / Double(block.width) : nil
            block.width = width
            if lockRatio {
                if logoPixels != nil {
                    block.height = height(forWidth: width, current: block.height)
                } else if let ratio {
                    block.height = max(1, Int((Double(width) * ratio).rounded()))
                }
            }
        }
    }

    func setLogoHeight(_ id: UUID, _ height: Int) {
        update(id) { $0.height = min(max(height, 8), 400) }
    }

    func replaceLogo(_ data: Data) {
        MailSignatures.setLogo(data, for: key)
        logo = data
        logoImage = NSImage(data: data)
        for block in document.blocks where block.kind == .logo {
            update(block.id) { $0.height = height(forWidth: $0.width, current: $0.height) }
        }
        NotificationCenter.default.post(name: MailSignatures.changed, object: nil)
        scheduleSave()
    }

    /// Ingelezen zonder maat: de maat van het plaatje (hoogstens 200 breed).
    private func fixLogoSizes(_ document: inout SignatureDocument) {
        for index in document.blocks.indices where document.blocks[index].kind == .logo {
            var block = document.blocks[index]
            guard block.width <= 0 || block.height <= 0 else { continue }
            if block.width <= 0 { block.width = min(logoPixels?.width ?? 200, 200) }
            block.height = height(forWidth: block.width, current: 52)
            document.blocks[index] = block
        }
    }
}

// MARK: - Venster

/// Het venster "Handtekening": links de blokken, in het midden het voorbeeld op ware grootte (de tekst is daar te
/// bewerken), rechts de instellingen van het gekozen blok. Of de HTML naast het voorbeeld.
struct SignatureEditorWindow: View {
    @State private var model: SignatureEditorModel
    @State private var focus = SignatureTextFocus()
    @State private var importKind: ImportKind?
    @State private var pendingImport: ImportKind = .logo
    @State private var importError: String?
    /// Net bewaard met ⌘S: de melding midden in het venster.
    @State private var savedFlash: Date?
    private let gmail = GmailSession.shared

    private enum ImportKind { case logo, newLogo, html }

    init(key: String) {
        _model = State(initialValue: SignatureEditorModel(key: key))
    }

    var body: some View {
        Group {
            if model.showsHTML {
                SignatureHTMLPane(model: model)
            } else {
                HStack(spacing: 0) {
                    SignatureBlockList(model: model, onAddLogo: { requestLogo(adding: true) })
                        .frame(width: 250)
                    Divider()
                    SignatureCanvas(model: model, focus: focus)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    SignatureInspector(model: model, onReplaceLogo: { requestLogo(adding: false) })
                        .frame(width: 300)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .overlay {
            if savedFlash != nil {
                SignatureSavedHUD()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .background {
            Button("Bewaar", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .navigationTitle("Handtekening")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Weergave", selection: Binding(get: { model.showsHTML }, set: { model.setShowsHTML($0) })) {
                    Text("Ontwerp").tag(false)
                    Text("HTML").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Ongedaan maken")
                    .disabled(!model.canUndo)
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help("Opnieuw")
                    .disabled(!model.canRedo)
                if model.showsHTML {
                    Button("Kopieer HTML") { model.copyHTML() }
                    Button("Importeer…") { open(.html) }
                }
                Picker("Mailbox", selection: Binding(get: { model.key }, set: { model.load($0) })) {
                    Text("Alle mailboxen").tag(MailSignatures.defaultKey)
                    ForEach(gmail.accounts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 220)
            }
        }
        .fileImporter(isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
                      allowedContentTypes: pendingImport == .html ? [.html, .plainText] : [.png, .jpeg, .gif]) { result in
            handleImport(result)
        }
        .alert("Kon het bestand niet lezen",
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
        .onDisappear { model.saveNow() }
    }

    private func save() {
        model.saveExplicitly()
        let stamp = Date()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { savedFlash = stamp }
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            guard savedFlash == stamp else { return }
            withAnimation(.easeOut(duration: 0.35)) { savedFlash = nil }
        }
    }

    private func open(_ kind: ImportKind) {
        pendingImport = kind
        importKind = kind
    }

    /// Een logo toevoegen kan pas met een plaatje; is er nog geen, dan eerst kiezen.
    private func requestLogo(adding: Bool) {
        if adding, model.logo != nil {
            model.addLogo()
        } else {
            open(adding ? .newLogo : .logo)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importError = url.lastPathComponent
                return
            }
            switch pendingImport {
            case .html:
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    importError = url.lastPathComponent
                    return
                }
                model.importHTML(text)
            case .logo, .newLogo:
                guard NSImage(data: data) != nil else {
                    importError = url.lastPathComponent
                    return
                }
                model.replaceLogo(data)
                if pendingImport == .newLogo { model.addLogo() }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

/// "Bewaard" na ⌘S, zoals de melding van macOS bij het volume.
private struct SignatureSavedHUD: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.werk(size: 46, weight: .semibold))
                .foregroundStyle(.white, Color.green)
            Text("Bewaard")
                .font(.werk(size: 15, weight: .semibold))
        }
        .frame(width: 150, height: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
    }
}

// MARK: - Blokken (links)

private struct SignatureBlockList: View {
    @Bindable var model: SignatureEditorModel
    var onAddLogo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Blokken")
                    .font(.werk(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fieldLabel)
                Spacer()
                Menu {
                    Button("Tekst") { model.addText() }
                    Button("Logo") { onAddLogo() }
                        .disabled(model.document.hasLogo)
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Blok toevoegen")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            List(selection: $model.selection) {
                ForEach(model.document.blocks) { block in
                    SignatureBlockRow(block: block).tag(block.id)
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            .listStyle(.sidebar)
            .onDeleteCommand { model.removeSelected() }
            Divider()
            SignatureGlobalSettings(model: model)
                .padding(14)
        }
    }
}

private struct SignatureBlockRow: View {
    let block: SignatureBlock

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.fieldLabel)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if block.kind == .logo {
                Text("\(block.width) px")
                    .font(.werk(size: 11))
                    .foregroundStyle(Color.fieldLabel)
            }
        }
    }

    private var icon: String {
        switch block.kind {
        case .text: block.hasLink ? "link" : "text.alignleft"
        case .logo: "photo"
        case .html: "chevron.left.forwardslash.chevron.right"
        }
    }

    private var title: String {
        switch block.kind {
        case .text:
            let line = block.plainText.split(separator: "\n").first.map(String.init) ?? ""
            return line.isEmpty ? "Tekst" : line
        case .logo: return "Logo"
        case .html: return "HTML"
        }
    }
}

/// Lettertype, grootte, regelafstand, breedte en kleuren van de hele handtekening.
private struct SignatureGlobalSettings: View {
    @Bindable var model: SignatureEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hele handtekening")
                .font(.werk(size: 11, weight: .semibold))
                .foregroundStyle(Color.fieldLabel)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 7) {
                GridRow {
                    label("Lettertype")
                    Picker("Lettertype", selection: $model.document.fontFamily) {
                        ForEach(fontChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    label("Grootte")
                    NumberField(value: $model.document.fontSize, range: 8...40, unit: "px")
                }
                GridRow {
                    label("Regelafstand")
                    Picker("Regelafstand", selection: $model.document.lineHeight) {
                        ForEach(SignatureLineHeights.choices, id: \.self) { Text(SignatureLineHeights.title($0)).tag($0) }
                        if !SignatureLineHeights.choices.contains(model.document.lineHeight) {
                            Text(SignatureLineHeights.title(model.document.lineHeight)).tag(model.document.lineHeight)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    label("Breedte")
                    PixelField(value: $model.document.width, range: 200...1000, step: 10)
                }
                GridRow {
                    label("Tekst")
                    HexColorPicker(hex: $model.document.color)
                }
                GridRow {
                    label("Links")
                    HexColorPicker(hex: $model.document.linkColor)
                }
            }
        }
    }

    private var fontChoices: [String] {
        let fonts = SignatureDocument.fonts
        return fonts.contains(model.document.fontFamily) ? fonts : fonts + [model.document.fontFamily]
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.werk(size: 12))
            .foregroundStyle(Color.fieldLabel)
    }
}

enum SignatureLineHeights {
    static let choices: [Double] = [1, 1.15, 1.2, 1.3, 1.45, 1.5, 2]

    static func title(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "nl_NL")))
    }
}

// MARK: - Voorbeeld (midden)

private struct SignatureCanvas: View {
    @Bindable var model: SignatureEditorModel
    let focus: SignatureTextFocus

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                paper
                    .padding(.vertical, 48)
                    .padding(.horizontal, 32)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.never)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// Wit, zoals de ontvanger hem ziet (ook in donker).
    private var paper: some View {
        let blocks = model.document.blocks
        let selected = model.selectedIndex
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                SignatureGap(value: block.spaceAbove,
                             highlighted: selected.map { $0 == index || $0 == index - 1 } ?? false)
                blockView(block)
            }
            if !blocks.isEmpty {
                SignatureGap(value: model.document.spaceBelow, highlighted: selected == blocks.count - 1)
            }
        }
        .frame(width: CGFloat(model.document.width), alignment: .leading)
        .frame(minHeight: 60, alignment: .top)
        .padding(.vertical, 28)
        .padding(.horizontal, 40)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white).shadow(color: .black.opacity(0.12), radius: 2, y: 1))
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private func blockView(_ block: SignatureBlock) -> some View {
        let isSelected = model.selection == block.id
        switch block.kind {
        case .text:
            SignatureTextView(block: block, document: model.document, focus: focus,
                              onChange: { runs in model.update(block.id) { $0.runs = runs } },
                              onFocus: { model.selection = block.id })
                .overlay {
                    if isSelected {
                        Rectangle().stroke(ThingsColor.accent, lineWidth: 1.5).padding(-4).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isSelected {
                        SignatureFormatBar(model: model, focus: focus, block: block)
                            .offset(y: -46)
                    }
                }
                .zIndex(isSelected ? 1 : 0)
        case .logo:
            SignatureLogoView(model: model, block: block, isSelected: isSelected)
        case .html:
            SignatureHTMLBlockView(html: block.rawHTML, isSelected: isSelected) { model.selection = block.id }
        }
    }
}

/// Ruimte tussen twee blokken; die bij het gekozen blok roze met de maat.
private struct SignatureGap: View {
    let value: Int
    let highlighted: Bool

    static let pink = Color(red: 0.90, green: 0.28, blue: 0.48)
    static let pinkText = Color(red: 0.76, green: 0.09, blue: 0.36)

    var body: some View {
        Rectangle()
            .fill(highlighted && value > 0 ? Self.pink.opacity(0.12) : Color.clear)
            .frame(height: CGFloat(value))
            .overlay(alignment: .leading) {
                if value > 0 {
                    Text("\(value)")
                        .font(.werk(size: 9.5, weight: highlighted ? .semibold : .regular))
                        .foregroundStyle(highlighted ? Self.pinkText : Color(white: 0.55))
                        .fixedSize()
                        .offset(x: -30)
                }
            }
    }
}

/// Opmaak van de selectie in het tekstblok met de cursor.
private struct SignatureFormatBar: View {
    @Bindable var model: SignatureEditorModel
    let focus: SignatureTextFocus
    let block: SignatureBlock
    @State private var linkOpen = false

    private var active: Bool { focus.blockID == block.id }

    var body: some View {
        HStack(spacing: 2) {
            traitButton(.bold, label: "B", help: "Vet") { $0.bold() }
            traitButton(.italic, label: "I", help: "Cursief") { $0.italic() }
            traitButton(.underline, label: "U", help: "Onderstrepen") { $0.underline() }
            Divider().frame(height: 16).padding(.horizontal, 3)
            ColorPicker("Tekstkleur", selection: Binding(
                get: { Color(nsColor: focus.color ?? SignatureText.color(model.document.color(of: block))) },
                set: { focus.setColor(NSColor($0)) }), supportsOpacity: false)
                .labelsHidden()
                .help("Tekstkleur")
            Button { linkOpen = true } label: {
                Image(systemName: "link").frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("Link")
            .popover(isPresented: $linkOpen, arrowEdge: .bottom) {
                SignatureLinkEditor(focus: focus, document: model.document, block: block, isPresented: $linkOpen)
            }
        }
        .disabled(!active)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .environment(\.colorScheme, .light)
        .fixedSize()
    }

    private func traitButton(_ trait: SignatureTextFocus.Trait, label: String, help: String,
                             style: (Text) -> Text) -> some View {
        let on = active && focus.has(trait)
        return Button { focus.toggle(trait) } label: {
            style(Text(label))
                .font(.werk(size: 13, weight: trait == .bold ? .bold : .regular, design: trait == .italic ? .serif : .default))
                .frame(width: 24, height: 22)
                .background(on ? Color.black.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Tekst, adres, soort, kleur en onderstreping van een link (of een nieuwe link op de selectie).
private struct SignatureLinkEditor: View {
    let focus: SignatureTextFocus
    let document: SignatureDocument
    let block: SignatureBlock
    @Binding var isPresented: Bool

    @State private var info: SignatureTextFocus.LinkInfo?
    @State private var text = ""
    @State private var address = ""
    @State private var kind: SignatureDocument.LinkKind = .website
    @State private var color = Color.blue
    @State private var underline = true

    private typealias LinkKind = SignatureDocument.LinkKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                GridRow {
                    label("Tekst")
                    TextField("Tekst", text: $text).labelsHidden().textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label("Adres")
                    TextField("Adres", text: $address).labelsHidden().textFieldStyle(.roundedBorder)
                        .onChange(of: address) { _, new in
                            // Een e-mailadres herkennen terwijl je typt.
                            if kind == .website, new.contains("@"), !new.contains("/") { kind = .email }
                        }
                }
                GridRow {
                    label("Soort")
                    Picker("Soort", selection: $kind) {
                        Text("Website").tag(LinkKind.website)
                        Text("E-mail").tag(LinkKind.email)
                        Text("Telefoon").tag(LinkKind.phone)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    label("Kleur")
                    HStack(spacing: 6) {
                        ForEach(swatches, id: \.self) { hex in
                            Button { color = Color(nsColor: SignatureText.color(hex)) } label: {
                                Circle()
                                    .fill(Color(nsColor: SignatureText.color(hex)))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.primary.opacity(isCurrent(hex) ? 0.8 : 0.15),
                                                             lineWidth: isCurrent(hex) ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .help(hex)
                        }
                        ColorPicker("Kleur", selection: $color, supportsOpacity: false).labelsHidden()
                        Spacer(minLength: 8)
                        Toggle("Onderstreept", isOn: $underline).toggleStyle(.checkbox)
                    }
                }
            }
            Divider()
            HStack {
                Button("Link weg", role: .destructive) {
                    if let info { focus.removeLink(info, color: SignatureText.color(document.color(of: block))) }
                    isPresented = false
                }
                .disabled(info?.href.isEmpty ?? true)
                Button("Openen") {
                    if let url = URL(string: kind.href(address)) { NSWorkspace.shared.open(url) }
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Klaar") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty
                              || (text.isEmpty && (info?.text.isEmpty ?? true) && address.isEmpty))
            }
        }
        .padding(14)
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private var swatches: [String] {
        var result: [String] = []
        for hex in [document.linkColor, document.color(of: block), document.color, "#6E6E73", "#000000"]
        where !result.contains(hex.uppercased()) {
            result.append(hex.uppercased())
        }
        return result
    }

    private func isCurrent(_ hex: String) -> Bool { SignatureText.hex(color) == hex }

    private func load() {
        info = focus.linkInfo()
        text = info?.text ?? ""
        let href = info?.href ?? ""
        kind = LinkKind.of(href)
        address = LinkKind.address(of: href)
        if href.isEmpty, text.contains("@"), !text.contains(" ") {
            kind = .email
            address = text
        }
        underline = info.map { $0.href.isEmpty ? true : $0.underline } ?? true
        let current = (info?.href.isEmpty == false ? info?.color : nil) ?? SignatureText.color(document.linkColor)
        color = Color(nsColor: current)
    }

    private func apply() {
        guard let info else { return }
        let href = kind.href(address)
        let shown = text.isEmpty ? LinkKind.address(of: href) : text
        focus.applyLink(info, text: shown, href: href, color: NSColor(color), underline: underline)
        isPresented = false
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.werk(size: 12)).foregroundStyle(Color.fieldLabel)
    }
}

/// Het logo op ware grootte; gekozen met hoekjes, het hoekje rechtsonder sleept de breedte.
private struct SignatureLogoView: View {
    @Bindable var model: SignatureEditorModel
    let block: SignatureBlock
    let isSelected: Bool
    @State private var dragStart: Int?

    var body: some View {
        let width = CGFloat(max(block.width, 1))
        let height = CGFloat(max(block.height, 1))
        image
            .frame(width: width, height: height)
            .overlay {
                if isSelected {
                    Rectangle().stroke(ThingsColor.accent, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topLeading) { if isSelected { handle.offset(x: -4, y: -4) } }
            .overlay(alignment: .topTrailing) { if isSelected { handle.offset(x: 4, y: -4) } }
            .overlay(alignment: .bottomLeading) { if isSelected { handle.offset(x: -4, y: 4) } }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    handle
                        .offset(x: 4, y: 4)
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let start = dragStart ?? block.width
                                dragStart = start
                                let delta = Int(value.translation.width) * (block.alignment == .right ? -1 : 1)
                                model.setLogoWidth(block.id, start + delta)
                            }
                            .onEnded { _ in dragStart = nil })
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Text("\(block.width) × \(block.height)")
                        .font(.werk(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(ThingsColor.accent, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .offset(y: 22)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selection = block.id }
            .frame(maxWidth: .infinity, alignment: alignment)
            .zIndex(isSelected ? 1 : 0)
    }

    @ViewBuilder private var image: some View {
        if let image = model.logoImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .overlay(Text("Geen logo").font(.werk(size: 11)).foregroundStyle(Color(white: 0.45)))
        }
    }

    private var handle: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .overlay(Rectangle().stroke(ThingsColor.accent, lineWidth: 1.5))
    }

    private var alignment: Alignment {
        switch block.alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

/// HTML die niet als blok te lezen was, zoals hij in de mail staat.
private struct SignatureHTMLBlockView: View {
    let html: String
    let isSelected: Bool
    var onSelect: () -> Void
    @State private var height: CGFloat = 20

    var body: some View {
        AutoHeightMailWebView(html: html, height: $height)
            .frame(height: height)
            .allowsHitTesting(false)
            .overlay {
                if isSelected {
                    Rectangle().stroke(ThingsColor.accent, lineWidth: 1.5).padding(-4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
    }
}

// MARK: - Instellingen (rechts)

private struct SignatureInspector: View {
    @Bindable var model: SignatureEditorModel
    var onReplaceLogo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.werk(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            Divider()
            Form {
                if let block = model.selectedBlock, let index = model.index(of: block.id) {
                    switch block.kind {
                    case .text: textSections(block)
                    case .logo: logoSections(block)
                    case .html: htmlSections(block)
                    }
                    alignmentSection(block)
                    spaceSection(index)
                }
                linksSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            if model.selectedBlock != nil {
                Divider()
                HStack {
                    Button("Verwijder blok", role: .destructive) { model.removeSelected() }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var title: String {
        switch model.selectedBlock?.kind {
        case .text: "Tekst"
        case .logo: "Logo"
        case .html: "HTML"
        case nil: "Handtekening"
        }
    }

    private func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<SignatureBlock, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { model.block(id)?[keyPath: keyPath] ?? fallback },
                set: { value in model.update(id) { $0[keyPath: keyPath] = value } })
    }

    // MARK: Tekst

    @ViewBuilder private func textSections(_ block: SignatureBlock) -> some View {
        let document = model.document
        Section("Letter") {
            Picker("Lettertype", selection: binding(block.id, \.fontFamily, nil)) {
                Text("\(document.fontFamily) (hele handtekening)").tag(String?.none)
                ForEach(fontChoices(block), id: \.self) { Text($0).tag(String?.some($0)) }
            }
            LabeledContent("Grootte") {
                NumberField(value: Binding(
                    get: { model.block(block.id).map(document.fontSize(of:)) ?? document.fontSize },
                    set: { value in model.update(block.id) { $0.fontSize = value == model.document.fontSize ? nil : value } }),
                    range: 8...40, unit: "px")
            }
            LabeledContent("Kleur") {
                HexColorPicker(hex: Binding(
                    get: { model.block(block.id).map(document.color(of:)) ?? document.color },
                    set: { value in model.update(block.id) { $0.color = value == model.document.color ? nil : value } }))
            }
            LabeledContent("Stijl") {
                HStack(spacing: 4) {
                    styleToggle(block, \.bold, "B", help: "Vet (hele blok)") { $0.bold() }
                    styleToggle(block, \.italic, "I", help: "Cursief (hele blok)") { $0.italic() }
                    styleToggle(block, \.underline, "U", help: "Onderstrepen (hele blok)") { $0.underline() }
                }
            }
        }
        Section("Regelafstand") {
            Picker("Regelafstand", selection: Binding(
                get: { model.block(block.id).map(model.document.lineHeight(of:)) ?? model.document.lineHeight },
                set: { value in model.update(block.id) { $0.lineHeight = value == model.document.lineHeight ? nil : value } })) {
                ForEach([1, 1.15, 1.3, 1.5, 2] as [Double], id: \.self) { Text(SignatureLineHeights.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LabeledContent("Exact") {
                NumberField(value: Binding(
                    get: { model.block(block.id).map(model.document.lineHeightPixels(of:)) ?? 0 },
                    set: { pixels in
                        let size = model.block(block.id).map(model.document.fontSize(of:)) ?? model.document.fontSize
                        guard size > 0, pixels > 0 else { return }
                        let factor = (pixels / size * 1000).rounded() / 1000
                        model.update(block.id) { $0.lineHeight = factor }
                    }), range: 4...120, unit: "px", fraction: true)
            }
        }
    }

    private func fontChoices(_ block: SignatureBlock) -> [String] {
        let fonts = SignatureDocument.fonts
        guard let own = block.fontFamily, !fonts.contains(own) else { return fonts }
        return fonts + [own]
    }

    private func styleToggle(_ block: SignatureBlock, _ keyPath: WritableKeyPath<SignatureRun, Bool>, _ label: String,
                             help: String, style: (Text) -> Text) -> some View {
        let on = !block.runs.isEmpty && block.runs.allSatisfy { $0[keyPath: keyPath] }
        return Button { model.toggleStyle(block.id, keyPath) } label: {
            style(Text(label))
                .font(.werk(size: 13, design: keyPath == \SignatureRun.italic ? .serif : .default))
                .frame(width: 28, height: 22)
                .background(on ? ThingsColor.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? ThingsColor.accent : Color.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Logo

    @ViewBuilder private func logoSections(_ block: SignatureBlock) -> some View {
        Section("Logo") {
            HStack(spacing: 10) {
                if let image = model.logoImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let pixels = model.logoPixels {
                        Text("\(pixels.width) × \(pixels.height)")
                    }
                    if let logo = model.logo {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(logo.count), countStyle: .file))
                            .font(.werk(size: 11))
                            .foregroundStyle(Color.fieldLabel)
                    }
                }
                Spacer()
                Button("Vervang…", action: onReplaceLogo)
            }
        }
        Section("Grootte") {
            LabeledContent("Breedte") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(model.block(block.id)?.width ?? block.width) },
                                          set: { model.setLogoWidth(block.id, Int($0.rounded())) }),
                           in: 16...600)
                        .frame(width: 90)
                    PixelField(value: Binding(get: { model.block(block.id)?.width ?? block.width },
                                              set: { model.setLogoWidth(block.id, $0) }), range: 16...600)
                }
            }
            LabeledContent("Hoogte") {
                HStack(spacing: 8) {
                    PixelField(value: Binding(get: { model.block(block.id)?.height ?? block.height },
                                              set: { model.setLogoHeight(block.id, $0) }), range: 8...400)
                        .disabled(model.lockRatio)
                    Toggle(isOn: $model.lockRatio) {
                        Image(systemName: model.lockRatio ? "lock.fill" : "lock.open")
                    }
                    .toggleStyle(.button)
                    .help("Verhouding vast")
                }
            }
        }
        Section("Link op het logo") {
            TextField("Link", text: Binding(get: { model.block(block.id)?.link ?? "" },
                                            set: { value in model.update(block.id) { $0.link = value.isEmpty ? nil : value } }))
                .labelsHidden()
        }
        Section("Alt-tekst") {
            TextField("Alt-tekst", text: binding(block.id, \.alt, "")).labelsHidden()
        }
    }

    // MARK: HTML

    @ViewBuilder private func htmlSections(_ block: SignatureBlock) -> some View {
        Section("HTML") {
            TextEditor(text: binding(block.id, \.rawHTML, ""))
                .font(.werk(size: 11, design: .monospaced))
                .frame(minHeight: 120)
        }
    }

    // MARK: Samen

    private func alignmentSection(_ block: SignatureBlock) -> some View {
        Section("Uitlijning") {
            Picker("Uitlijning", selection: binding(block.id, \.alignment, .left)) {
                Image(systemName: "text.alignleft").tag(SignatureAlignment.left).help("Links")
                Image(systemName: "text.aligncenter").tag(SignatureAlignment.center).help("Midden")
                Image(systemName: "text.alignright").tag(SignatureAlignment.right).help("Rechts")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func spaceSection(_ index: Int) -> some View {
        Section("Ruimte") {
            LabeledContent("Boven") {
                PixelField(value: Binding(
                    get: { index < model.document.blocks.count ? model.document.blocks[index].spaceAbove : 0 },
                    set: { value in
                        guard index < model.document.blocks.count else { return }
                        model.document.blocks[index].spaceAbove = value
                    }), range: 0...200)
            }
            LabeledContent("Onder") {
                PixelField(value: Binding(
                    get: { index < model.document.blocks.count ? model.spaceBelow(index) : 0 },
                    set: { value in
                        guard index < model.document.blocks.count else { return }
                        model.setSpaceBelow(index, value)
                    }), range: 0...200)
            }
        }
    }

    @ViewBuilder private var linksSection: some View {
        let links = model.links
        if !links.isEmpty {
            Section("Alle links") {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Button { model.selection = link.id } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title).lineLimit(1)
                            Text(link.href)
                                .font(.werk(size: 11))
                                .foregroundStyle(Color.fieldLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - HTML-weergave

private struct SignatureHTMLPane: View {
    @Bindable var model: SignatureEditorModel

    var body: some View {
        HStack(spacing: 0) {
            TextEditor(text: $model.htmlText)
                .font(.werk(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.htmlText) { _, new in model.htmlEdited(new) }
            Divider()
            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(model.document.html().utf8.count), countStyle: .file))
                    .font(.werk(size: 11))
                    .foregroundStyle(Color.fieldLabel)
                MailWebView(html: MailSignatures.previewHTML(model.document.html(), logo: model.logo), allowRemote: true)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(16)
            .frame(width: 560)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}

// MARK: - Velden

/// Een getal in px met pijltjes.
private struct PixelField: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(get: { value },
                                         set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
            Text("px").font(.werk(size: 11)).foregroundStyle(Color.fieldLabel)
            Stepper("", value: $value, in: range, step: step).labelsHidden()
        }
    }
}

/// Een getal met eenheid en pijltjes (lettergrootte, regelafstand), eventueel met een decimaal.
private struct NumberField: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var fraction = false

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(get: { value },
                                         set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.precision(.fractionLength(0...1)).locale(Locale(identifier: "nl_NL")))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
            Text(unit).font(.werk(size: 11)).foregroundStyle(Color.fieldLabel)
            Stepper("", value: $value, in: range, step: fraction ? 0.5 : 1).labelsHidden()
        }
    }
}

/// Kleurkiezer voor een kleur als "#RRGGBB".
private struct HexColorPicker: View {
    @Binding var hex: String

    var body: some View {
        HStack(spacing: 6) {
            ColorPicker("Kleur", selection: Binding(
                get: { Color(nsColor: SignatureText.color(hex)) },
                set: { if let value = SignatureText.hex($0) { hex = value } }), supportsOpacity: false)
                .labelsHidden()
            Text(hex.uppercased())
                .font(.werk(size: 11, design: .monospaced))
                .foregroundStyle(Color.fieldLabel)
        }
    }
}
