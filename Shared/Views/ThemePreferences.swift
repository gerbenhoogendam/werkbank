import SwiftUI

/// Voorkeuren › Thema: een thema kiezen, de letter en grootte, en per onderdeel een eigen kleur voor licht en donker.
struct ThemePreferences: View {
    private let store = ThemeStore.shared

    var body: some View {
        Form {
            Section("Thema") {
                ForEach(WerkbankTheme.all) { theme in
                    ThemeRow(theme: theme, isSelected: store.theme.id == theme.id) { store.select(theme.id) }
                }
            }

            Section("Letter") {
                Picker("Lettertype", selection: Binding(get: { store.fontChoice }, set: { store.setFont($0) })) {
                    Text("Van het thema (\(store.theme.fontFamily ?? "systeem"))").tag("")
                    Text("Systeem").tag("system")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Picker("Cijfers", selection: Binding(get: { store.numberFontChoice }, set: { store.setNumberFont($0) })) {
                    Text("Van het thema (\(store.theme.numberFamily ?? "zelfde als tekst"))").tag("")
                    Text("Zelfde als tekst").tag("system")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Grootte") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { store.baseSize }, set: { store.setBaseSize($0.rounded()) }),
                               in: ThemeStore.sizeRange, step: 1)
                            .frame(width: 180)
                        Text("\(Int(store.baseSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            ForEach(ThemeRole.Group.allCases) { group in
                Section {
                    ForEach(group.roles) { role in ThemeColorRow(role: role, store: store) }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text("Licht").frame(width: 46)
                        Text("Donker").frame(width: 46)
                        Color.clear.frame(width: 22, height: 1)
                    }
                }
            }

            Section {
                Button("Alle kleuren terug naar het thema") { store.resetAll() }
                    .disabled(!store.hasOverrides)
            }
        }
        .formStyle(.grouped)
    }

    private var families: [String] { ThemeStore.installedFamilies }
}

/// Een thema met een strookje van zijn kleuren.
private struct ThemeRow: View {
    let theme: WerkbankTheme
    let isSelected: Bool
    let select: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach([ThemeRole.window, .mail, .card, .accent, .running], id: \.self) { role in
                        Rectangle().fill(swatch(role))
                    }
                }
                .frame(width: 90, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                Text(theme.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatch(_ role: ThemeRole) -> Color {
        let color = theme.color(role)
        return Color(hex: scheme == .dark ? color.dark : color.light)
    }
}

/// Eén onderdeel: kleur voor licht, voor donker, en terug naar het thema.
private struct ThemeColorRow: View {
    let role: ThemeRole
    let store: ThemeStore

    var body: some View {
        let color = store.themeColor(role)
        // Een omgekeerde agenda (Karmijn) tekent in de lichte weergave met de donkere kleur, en andersom: de kolommen
        // tonen wat je in die weergave ziet.
        let swapped = role == .agenda && store.theme.invertedAgenda
        LabeledContent(role.title) {
            HStack(spacing: 10) {
                ColorPicker("\(role.title), licht", selection: Binding(
                    get: { Color(hex: swapped ? color.dark : color.light) },
                    set: { new in
                        guard let hex = ThemeColor.hex(of: new) else { return }
                        if swapped { store.setColor(role, dark: hex) } else { store.setColor(role, light: hex) }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 46)
                ColorPicker("\(role.title), donker", selection: Binding(
                    get: { Color(hex: swapped ? color.light : color.dark) },
                    set: { new in
                        guard let hex = ThemeColor.hex(of: new) else { return }
                        if swapped { store.setColor(role, light: hex) } else { store.setColor(role, dark: hex) }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 46)
                Button { store.reset(role) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Terug naar het thema")
                .accessibilityLabel("\(role.title) terug naar het thema")
                .opacity(store.isOverridden(role) ? 1 : 0)
                .disabled(!store.isOverridden(role))
                .frame(width: 22)
            }
        }
    }
}
