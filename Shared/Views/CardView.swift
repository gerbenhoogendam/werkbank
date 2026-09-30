import SwiftUI

/// Kaart op het board: titel, optioneel klantlabel en -logo, afzenderregel en een timerknop.
struct CardView: View {
    let card: TodoCard
    var isTimerRunning = false
    var onStartTimer: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if card.isNew {
                        Circle()
                            .fill(ThingsColor.accent)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Nieuw")
                    }
                    Text(card.title)
                        .thingsFont(.todoTitle)
                        .foregroundStyle(ThingsColor.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if card.logoDomain != nil || card.clientLabel != nil {
                    HStack(spacing: 6) {
                        if let domain = card.logoDomain {
                            LogoView(domain: domain, fallbackName: card.clientLabel ?? domain, size: 16)
                        }
                        if let label = card.clientLabel {
                            TagPill(name: label)
                        }
                    }
                }

                if let sender = card.senderLine {
                    Text(sender)
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            TimerButton(isRunning: isTimerRunning, action: onStartTimer)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous)
                .fill(ThingsColor.backgroundContent)
                .shadow(color: ThingsColor.cardShadow, radius: 3, x: 0, y: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: ThingsMetrics.cardRadius, style: .continuous))
    }
}

/// Startknop voor de timer van een kaart.
struct TimerButton: View {
    var isRunning: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRunning ? "waveform" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isRunning ? Color.white : ThingsColor.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isRunning ? ThingsColor.running : ThingsColor.accent.opacity(0.12)))
                .frame(width: ThingsMetrics.minTapTarget * 0.6, height: ThingsMetrics.minTapTarget * 0.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .help(isRunning ? "Timer loopt" : "Start timer")
        .accessibilityLabel(isRunning ? "Timer loopt" : "Start timer")
    }
}

/// Bewerken van titel, klantlabel en logodomein van een kaart.
struct CardEditSheet: View {
    let card: TodoCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var label = ""
    @State private var logoDomain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kaart bewerken")
                .thingsFont(.listTitle)
                .foregroundStyle(ThingsColor.textPrimary)

            field("Titel", text: $title)
            field("Klantlabel", text: $label)
            VStack(alignment: .leading, spacing: 4) {
                field("Logo van domein", text: $logoDomain, prompt: "bijv. studio-noord.nl")
                Text("Leeg laten voor geen logo. Wijzig je het label van een kaart met logodomein, dan onthoudt Werkbank die koppeling voor volgende mails.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Annuleer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Bewaar") {
                    BoardService.update(card, title: title, label: label, logoDomain: logoDomain, in: context)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 360)
        #endif
        .background(ThingsColor.backgroundContent)
        .onAppear {
            title = card.title
            label = card.clientLabel ?? ""
            logoDomain = card.logoDomain ?? ""
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).thingsFont(.metadata).foregroundStyle(ThingsColor.textSecondary)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
    }
}
