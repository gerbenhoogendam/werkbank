import SwiftUI

/// De eerste keer (nog geen mailbox): Werkbank groot, de toegevoegde Gmail-accounts, of de voorkeuren van de Mac via
/// iCloud gevonden zijn, en Verder zodra er een account is.
struct PhoneWelcomeView: View {
    let onContinue: () -> Void
    private let gmail = PhoneGmail.shared
    private let sync = PhonePreferencesSync.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PhEyebrow(text: "Welkom")
                Text("WERKBANK")
                    .font(Ph.poster(96))
                    .foregroundStyle(Ph.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, -10)
                HStack(spacing: 4) {
                    Rectangle().fill(Ph.lime).frame(width: 56, height: 6)
                    Rectangle().fill(Ph.ink).frame(width: 56, height: 6)
                    Rectangle().fill(Ph.line).frame(width: 56, height: 6)
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    accounts
                    cloud
                    if let error = gmail.lastError {
                        Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Group {
                if gmail.accounts.isEmpty {
                    Button {
                        Task { await gmail.signIn() }
                    } label: {
                        HStack(spacing: 10) {
                            if gmail.isSigningIn { ProgressView().tint(Ph.ink) }
                            Text("GMAIL TOEVOEGEN")
                        }
                    }
                } else {
                    Button(action: onContinue) {
                        HStack(spacing: 10) {
                            Text("VERDER")
                            Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
            .buttonStyle(PhPrimaryStyle(height: 54))
            .disabled(gmail.isSigningIn)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .overlay(alignment: .top) { Rectangle().fill(Ph.ink).frame(height: 2) }
        }
        .phScreen()
        .task { await sync.pull() }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PhEyebrow(text: "Gmail-accounts")
                Spacer()
                if !gmail.accounts.isEmpty { PhCaps(text: "\(gmail.accounts.count)") }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(gmail.accounts, id: \.self) { account in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            PhCaps(text: gmail.displayName(account), size: 13, color: Ph.ink)
                            Text(account).font(Ph.text(12)).foregroundStyle(Ph.ink2).lineLimit(1)
                        }
                        Spacer()
                        PhCheck(isOn: true, size: 26).accessibilityLabel("Toegevoegd")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
                }
                Button {
                    Task { await gmail.signIn() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text(gmail.accounts.isEmpty ? "GMAIL TOEVOEGEN" : "ANDER ACCOUNT")
                            .font(Ph.text(11.5, .semibold))
                            .tracking(1.4)
                        Spacer()
                        if gmail.isSigningIn { ProgressView().tint(Ph.ink) }
                    }
                    .foregroundStyle(Ph.ink2)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(gmail.isSigningIn)
            }
            .phCard()
        }
    }

    private var cloud: some View {
        HStack(spacing: 12) {
            Image(systemName: sync.isAvailable ? "icloud" : "icloud.slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ph.ink)
                .frame(width: 36, height: 36)
                .background(sync.lastSource != nil ? Ph.lime : Ph.well)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(cloudTitle).font(Ph.text(14.5, .semibold)).foregroundStyle(Ph.ink).lineLimit(2)
                if let date = sync.lastSync {
                    PhCaps(text: "iCloud · " + date.formatted(date: .omitted, time: .shortened), size: 10.5, color: Ph.olive)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(PhCloudCard(found: sync.lastSource != nil))
    }

    private var cloudTitle: String {
        if let source = sync.lastSource { return "Voorkeuren gevonden van \(source)" }
        return sync.isAvailable ? "iCloud" : "Geen iCloud"
    }
}

/// Gevonden voorkeuren komen naar voren; anders een gewone kaart.
private struct PhCloudCard: ViewModifier {
    let found: Bool

    func body(content: Content) -> some View {
        if found { content.phRaisedCard() } else { content.phCard() }
    }
}
