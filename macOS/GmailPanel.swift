import SwiftUI
import WerkbankCore

/// Uitklapvenster links: je Gmail-inbox. Sleep een mail naar een kolom van het board; daarna wordt hij in Gmail gearchiveerd.
struct GmailPanel: View {
    private let gmail = GmailSession.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ThingsColor.separator).frame(height: 1)
            content
        }
        .frame(maxHeight: .infinity)
        .background(ThingsColor.backgroundSidebar)
        // Een Gmail-mail loslaten op het paneel zelf doet niets (zo kun je een sleepactie afbreken).
        .onDrop(of: [.gmailMessage], isTargeted: nil) { _ in true }
        .task {
            if gmail.state == .signedIn {
                if gmail.emailAddress == nil { await gmail.loadProfile() }
                await gmail.reload()
            }
            // Gmail kent geen push naar deze app: ververs af en toe zolang het paneel open staat.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await gmail.reload()
            }
        }
    }

    // MARK: Kop

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(ThingsColor.accent)
            Text("Gmail")
                .thingsFont(.heading)
                .foregroundStyle(ThingsColor.textPrimary)
            Spacer()
            if gmail.state == .signedIn {
                if gmail.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await gmail.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .help("Inbox verversen")
                }
                Menu {
                    if let email = gmail.emailAddress { Text(email) }
                    Button("Uitloggen", role: .destructive) { gmail.signOut() }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(gmail.emailAddress ?? "Account")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    // MARK: Inhoud

    @ViewBuilder
    private var content: some View {
        if !gmail.isConfigured {
            notice(symbol: "wrench.and.screwdriver",
                   title: "Gmail is nog niet gekoppeld",
                   text: "Zet GOOGLE_CLIENT_ID in Config/Local.xcconfig, draai xcodegen generate en bouw opnieuw. Zie de README, \"Gmail koppelen\".")
        } else if gmail.state == .signedIn {
            inbox
        } else {
            signInPrompt
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 30))
                .foregroundStyle(ThingsColor.textTertiary)
            Text("Log in om je inbox hier te zien")
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
                .multilineTextAlignment(.center)
            Button {
                Task { await gmail.signIn() }
            } label: {
                if gmail.state == .signingIn {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Inloggen met Google")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(gmail.state == .signingIn)
            if let error = gmail.lastError {
                Text(error)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.deadline)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notice(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(ThingsColor.textTertiary)
            Text(title)
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
            Text(text)
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inbox: some View {
        VStack(spacing: 0) {
            if let error = gmail.lastError {
                Text(error)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.deadline)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if gmail.messages.isEmpty {
                Text(gmail.isLoading ? "Inbox ophalen…" : "Geen mail in je Gmail-inbox.")
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(gmail.messages) { message in
                            GmailRow(message: message, isBusy: gmail.busyMessageIDs.contains(message.id))
                            Rectangle().fill(ThingsColor.separator).frame(height: 1)
                        }
                    }
                }
            }
            Text("Sleep een mail naar een kolom. Hij wordt daarna in Gmail gearchiveerd.")
                .thingsFont(.metadata)
                .foregroundStyle(ThingsColor.textTertiary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GmailRow: View {
    let message: GmailMessageSummary
    let isBusy: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.isUnread ? ThingsColor.accent : Color.clear)
                    .frame(width: 7, height: 7)
                Text(message.senderDisplay)
                    .font(.system(size: 13, weight: message.isUnread ? .semibold : .regular))
                    .foregroundStyle(ThingsColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else if let date = message.date {
                    Text(Self.dateText(date))
                        .thingsFont(.metadata)
                        .foregroundStyle(ThingsColor.textSecondary)
                }
            }
            Text(message.subject)
                .thingsFont(.todoTitle)
                .foregroundStyle(ThingsColor.textPrimary)
                .lineLimit(1)
                .padding(.leading, 13)
            if !message.snippet.isEmpty {
                Text(message.snippet)
                    .thingsFont(.metadata)
                    .foregroundStyle(ThingsColor.textSecondary)
                    .lineLimit(2)
                    .padding(.leading, 13)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? ThingsColor.selection.opacity(0.5) : Color.clear)
        .opacity(isBusy ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onDrag { GmailSession.shared.dragProvider(for: message) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Sleep naar een kolom om er een kaart van te maken")
    }

    private static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
