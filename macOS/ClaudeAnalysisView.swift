import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

// MARK: - Merk

/// Een eenvoudige 8-strals vonk in Claude-oranje; vervangbaar door het officiële logo als je dat als afbeelding toevoegt.
struct ClaudeSpark: View {
    var color = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: size * 0.14, height: size * (index.isMultiple(of: 2) ? 0.5 : 0.36))
                        .offset(y: -size * (index.isMultiple(of: 2) ? 0.25 : 0.18))
                        .rotationEffect(.degrees(Double(index) * 45))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Ronde sleepdoel onderaan de maillijst: een mail erop loslaten start de analyse.
struct ClaudeDropTarget: View {
    @State private var isTargeted = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Circle()
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: isTargeted ? 14 : 8, x: 0, y: 3)
            Circle()
                .strokeBorder(isTargeted ? Color(red: 0.85, green: 0.47, blue: 0.34) : ThingsColor.separator,
                              style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [] : [5, 4]))
            ClaudeSpark()
                .padding(15)
        }
        .frame(width: 64, height: 64)
        .scaleEffect(isTargeted ? 1.18 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
        .help("Laat een mail hier los om hem door Claude te laten analyseren")
        .accessibilityLabel("Mail analyseren met Claude")
        .onDrop(of: [.gmailMessage], isTargeted: $isTargeted) { providers in
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.gmailMessage.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.gmailMessage.identifier) { data, _ in
                    guard let data, let payload = try? JSONDecoder().decode(GmailDragPayload.self, from: data) else { return }
                    Task { @MainActor in
                        ClaudeAnalyzer.shared.analyze(messageID: payload.messageID, subject: payload.subject ?? "")
                        openWindow(id: "claude")
                    }
                }
                return true
            }
            return false
        }
    }
}

// MARK: - Blad met de analyse

struct ClaudeAnalysisView: View {
    private let analyzer = ClaudeAnalyzer.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ClaudeSettings.modelKey) private var modelRaw = ClaudeModel.opus.rawValue
    @State private var keyText = ""
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            if !analyzer.hasKey {
                keyPrompt
            } else {
                transcript
                Rectangle().fill(ThingsColor.separator).frame(height: 1)
                footer
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(ThingsColor.backgroundContent)
    }

    // MARK: Kop

    private var header: some View {
        HStack(spacing: 10) {
            ClaudeSpark().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Analyse door Claude")
                    .thingsFont(.heading)
                    .foregroundStyle(ThingsColor.textPrimary)
                Text(analyzer.subject.isEmpty ? "Mail" : analyzer.subject)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if analyzer.isBusy { ProgressView().controlSize(.small) }
            Picker("Model", selection: $modelRaw) {
                ForEach(ClaudeModel.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            .help("Model voor de volgende analyse")
            Button("Opnieuw") { analyzer.restart() }
                .disabled(analyzer.isBusy)
                .help("Dezelfde mail opnieuw analyseren (met het gekozen model)")
            Button("Sluit") {
                analyzer.close()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Zonder sleutel

    private var keyPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            ClaudeSpark().frame(width: 40, height: 40)
            Text("Er is nog geen API-sleutel ingesteld")
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
            Text("Maak een sleutel op platform.claude.com (Settings › API keys), zet er tegoed bij en plak hem hieronder. Hij wordt bewaard in je sleutelhanger.")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                SecureField("sk-ant-…", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit(save)
                Button("Bewaar en analyseer", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        analyzer.saveKey(keyText)
        keyText = ""
    }

    // MARK: Gesprek

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !analyzer.attachmentSummary.isEmpty {
                        Label(analyzer.attachmentSummary, systemImage: "paperclip")
                            .thingsFont(.metadata)
                            .foregroundStyle(ThingsColor.textSecondary)
                    }
                    ForEach(analyzer.turns) { turn in
                        if let q = turn.question { bubble(q) }
                        MarkdownLite(text: turn.answer)
                    }
                    if let q = analyzer.liveQuestion { bubble(q) }
                    status
                    if !analyzer.liveAnswer.isEmpty { MarkdownLite(text: analyzer.liveAnswer) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: analyzer.liveAnswer) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: analyzer.turns.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .thingsFont(.notes)
            .foregroundStyle(ThingsColor.textPrimary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThingsColor.backgroundSidebar))
    }

    @ViewBuilder private var status: some View {
        switch analyzer.phase {
        case .preparing:
            Label("Mail ophalen en uitlezen…", systemImage: "envelope.open")
                .thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
        case .waiting:
            Label("Claude leest de mail en de bijlagen…", systemImage: "ellipsis.circle")
                .thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .thingsFont(.notes)
                    .foregroundStyle(ThingsColor.deadline)
                    .textSelection(.enabled)
                Button("Opnieuw proberen") { analyzer.restart() }
            }
        default:
            EmptyView()
        }
    }

    // MARK: Vervolgvraag

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let usage = analyzer.usageNote {
                Text(usage)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Vervolgvraag of extra context (bijvoorbeeld wat je al hebt geprobeerd)…", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($questionFocused)
                    .onSubmit(send)
                Button("Stuur", action: send)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(analyzer.isBusy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || analyzer.turns.isEmpty)
            }
        }
        .padding(12)
    }

    private func send() {
        guard !analyzer.isBusy, !analyzer.turns.isEmpty else { return }
        let text = question
        question = ""
        analyzer.ask(text)
    }
}

// MARK: - Eenvoudige Markdown

/// Toont de kopjes, lijsten en codeblokken die Claude teruggeeft; binnen een regel werkt `**vet**`, `*cursief*` en `code`.
struct MarkdownLite: View {
    let text: String

    private enum Line: Hashable {
        case heading(Int, String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
        case paragraph(String)
        case blank
    }

    private var lines: [Line] {
        var result: [Line] = []
        var inCode = false
        for raw in text.components(separatedBy: "\n") {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle(); continue }
            if inCode { result.append(.code(raw)); continue }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { result.append(.blank); continue }
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if hashes > 0, hashes <= 4, trimmed.dropFirst(hashes).first == " " {
                result.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else if let dot = trimmed.firstIndex(of: "."), dot != trimmed.startIndex,
                      trimmed[trimmed.startIndex..<dot].allSatisfy(\.isNumber),
                      trimmed[trimmed.index(after: dot)...].first == " " {
                result.append(.numbered(String(trimmed[trimmed.startIndex..<dot]) + ".",
                                        String(trimmed[trimmed.index(dot, offsetBy: 2)...])))
            } else {
                result.append(.paragraph(trimmed))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let level, let content):
                    inline(content)
                        .font(.system(size: level <= 2 ? 15 : 13, weight: .semibold))
                        .foregroundStyle(ThingsColor.textPrimary)
                        .padding(.top, level <= 2 ? 8 : 4)
                case .bullet(let content):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(ThingsColor.textSecondary)
                        inline(content)
                    }
                    .padding(.leading, 8)
                case .numbered(let number, let content):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(number).foregroundStyle(ThingsColor.textSecondary).monospacedDigit()
                        inline(content)
                    }
                    .padding(.leading, 8)
                case .code(let content):
                    Text(content.isEmpty ? " " : content)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ThingsColor.backgroundSidebar)
                case .paragraph(let content):
                    inline(content)
                case .blank:
                    Color.clear.frame(height: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ content: String) -> some View {
        let attributed = (try? AttributedString(markdown: content,
                                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(content)
        return Text(attributed)
            .font(.system(size: 13))
            .foregroundStyle(ThingsColor.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
