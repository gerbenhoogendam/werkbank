import SwiftUI
import WerkbankCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Het icoon van een kolom: een SF Symbol of een emoji.
struct ColumnIcon: View {
    let symbol: String
    var color: Color = ThingsColor.textSecondary

    var body: some View {
        if IconName.isEmoji(symbol) {
            Text(symbol)
        } else {
            Image(systemName: symbol.isEmpty ? "rectangle.stack.fill" : symbol)
                .foregroundStyle(color)
        }
    }
}

extension BoardColumn {
    /// Een SF Symbol-naam, ook voor plekken die geen emoji kunnen tonen (lege staat).
    var symbolName: String { IconName.isEmoji(symbol) ? "square.stack.3d.up" : symbol }
}

private enum SymbolCatalog {
    static func exists(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        #if os(macOS)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        return UIImage(systemName: name) != nil
        #endif
    }

    /// Een keuze van gangbare symbolen; wat op dit systeem niet bestaat wordt overgeslagen.
    static let curated: [String] = [
        "tray.fill", "tray.full.fill", "square.stack.3d.up.fill", "star.fill", "hourglass", "flag.fill", "bolt.fill",
        "flame.fill", "bell.fill", "bookmark.fill", "tag.fill", "pin.fill", "paperclip", "link",
        "envelope.fill", "phone.fill", "bubble.left.fill", "person.fill", "person.2.fill", "building.2.fill",
        "briefcase.fill", "folder.fill", "doc.text.fill", "list.bullet", "checklist", "calendar", "clock.fill",
        "timer", "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "desktopcomputer", "laptopcomputer",
        "server.rack", "network", "wifi", "externaldrive.fill", "printer.fill", "lock.fill", "key.fill",
        "shield.fill", "cart.fill", "creditcard.fill", "eurosign.circle.fill", "chart.bar.fill", "chart.pie.fill",
        "lightbulb.fill", "pencil", "paperplane.fill", "shippingbox.fill", "truck.box.fill", "house.fill",
        "questionmark.circle.fill", "exclamationmark.triangle.fill", "pause.circle.fill", "play.circle.fill",
        "checkmark.circle.fill", "xmark.circle.fill", "arrow.triangle.2.circlepath", "magnifyingglass",
        "eye.fill", "heart.fill", "leaf.fill", "sparkles", "globe", "map.fill", "airplane", "car.fill",
    ].filter { SymbolCatalog.exists($0) }

    static let emoji: [String] = [
        "📥", "📬", "📌", "⭐️", "🔥", "⏳", "⏰", "📅", "✅", "❗️", "❓", "💡", "🎯", "🚀", "🛠️", "🔧",
        "💻", "🖥️", "🌐", "🔒", "🔑", "🛒", "💶", "📈", "📞", "✉️", "👤", "👥", "🏢", "📁", "📝", "📎",
        "🧾", "📦", "🚚", "🏠", "☕️", "🎉", "💬", "🔍", "⚠️", "⏸️", "▶️", "🧪", "🐞", "🧹", "🗂️", "🤝",
    ]
}

/// Kies het icoon (SF Symbol of emoji) en de kleur van een kolom. Keuzes gelden direct.
struct ColumnIconPicker: View {
    let record: ColumnRecord

    private enum Kind: String, CaseIterable, Identifiable {
        case symbol = "SF Symbol"
        case emoji = "Emoji"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .symbol
    @State private var symbolText = ""
    @State private var emojiText = ""
    @State private var symbolError = false
    @FocusState private var emojiFocused: Bool

    private let grid = [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview
                    Picker("Soort icoon", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if kind == .symbol { symbolSection } else { emojiSection }
                    colorSection
                }
                .padding(20)
            }
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            HStack {
                Spacer()
                Button("Klaar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .background(ThingsColor.backgroundContent)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 460, minHeight: 540)
        #endif
        .onAppear { kind = IconName.isEmoji(record.symbol) ? .emoji : .symbol }
    }

    // MARK: Voorbeeld

    private var preview: some View {
        HStack(spacing: 10) {
            ColumnIcon(symbol: record.symbol, color: ColumnPalette.color(at: record.colorIndex))
                .font(.system(size: 26))
            Text(record.title)
                .thingsFont(.listTitle)
                .foregroundStyle(ThingsColor.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: SF Symbols

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: grid, spacing: 6) {
                ForEach(SymbolCatalog.curated, id: \.self) { name in
                    Button {
                        BoardService.setIcon(record, symbol: name, in: context)
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 16))
                            .foregroundStyle(ColumnPalette.color(at: record.colorIndex))
                            .frame(width: 38, height: 38)
                            .background(cellBackground(selected: record.symbol == name))
                    }
                    .buttonStyle(.plain)
                    .help(name)
                    .accessibilityLabel(name)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Of een andere SF Symbol")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                HStack {
                    TextField("", text: $symbolText, prompt: Text("bijv. tray.2.fill"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabledCompat()
                        .onSubmit(applySymbolText)
                    Button("Gebruik", action: applySymbolText)
                        .disabled(symbolText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if symbolError {
                    Text("Dit symbool bestaat niet op dit systeem. Controleer de naam.")
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.deadline)
                }
                Text("Namen vind je in de gratis app SF Symbols van Apple.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textTertiary)
            }
        }
    }

    private func applySymbolText() {
        let name = symbolText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if SymbolCatalog.exists(name) {
            symbolError = false
            BoardService.setIcon(record, symbol: name, in: context)
            symbolText = ""
        } else {
            symbolError = true
        }
    }

    // MARK: Emoji

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: grid, spacing: 6) {
                ForEach(SymbolCatalog.emoji, id: \.self) { emoji in
                    Button {
                        BoardService.setIcon(record, symbol: emoji, in: context)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 22))
                            .frame(width: 38, height: 38)
                            .background(cellBackground(selected: record.symbol == emoji))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Of typ of plak een emoji")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                HStack {
                    TextField("", text: $emojiText, prompt: Text("😀"))
                        .textFieldStyle(.roundedBorder)
                        .focused($emojiFocused)
                        .onChange(of: emojiText) { _, new in
                            guard let emoji = IconName.firstEmoji(in: new) else { return }
                            BoardService.setIcon(record, symbol: emoji, in: context)
                            emojiText = ""
                        }
                    #if os(macOS)
                    Button("Emoji-kiezer") {
                        emojiFocused = true
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                    #endif
                }
            }
        }
    }

    // MARK: Kleur

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kleur")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
            HStack(spacing: 10) {
                ForEach(0..<ColumnPalette.colors.count, id: \.self) { index in
                    Button {
                        BoardService.setColor(record, index: index, in: context)
                    } label: {
                        Circle()
                            .fill(ColumnPalette.color(at: index))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(ThingsColor.textPrimary, lineWidth: 2)
                                    .padding(-4)
                                    .opacity(record.colorIndex % ColumnPalette.colors.count == index ? 1 : 0)
                            )
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kleur \(index + 1)")
                }
            }
        }
    }

    private func cellBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: ThingsMetrics.selectionRadius, style: .continuous)
            .fill(selected ? ThingsColor.selection : ThingsColor.backgroundSidebar)
    }
}

private extension View {
    /// Geen autocorrectie in een veld met symboolnamen (alleen op iOS beschikbaar).
    @ViewBuilder func autocorrectionDisabledCompat() -> some View {
        #if os(iOS)
        self.autocorrectionDisabled().textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
