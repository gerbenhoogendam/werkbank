import Contacts
import ContactsUI
import SwiftData
import SwiftUI
import WerkbankCore

/// Wat je met een mail doet vanaf de knoppen in de mail (in plaats van slepen): een taak maken, tijd schrijven,
/// inplannen, verplaatsen naar een andere mailbox, de afzender in contacten zetten of Claude laten analyseren.
struct PhoneMailAction: Identifiable {
    enum Kind {
        case task, time, plan, move, claude
        case contact(String)
        case sender(String)
    }

    let id = UUID()
    let kind: Kind
    let mail: PhoneMail
}

struct PhoneMailActionSheet: View {
    let action: PhoneMailAction

    var body: some View {
        switch action.kind {
        case .task: PhoneTaskSheet(mail: action.mail)
        case .time: PhoneTimeSheet(mail: action.mail)
        case .plan: PhonePlanSheet(mail: action.mail)
        case .move: PhoneMoveSheet(mail: action.mail)
        case .claude: PhoneClaudeSheet(mail: action.mail)
        case .contact(let from), .sender(let from): PhoneSenderSheet(mail: action.mail, from: from)
        }
    }
}

/// De kop van een blad: grote titel, rechts een bijschrift.
struct PhSheetHeader: View {
    let title: String
    var detail: String = ""

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title.uppercased()).font(Ph.poster(32)).foregroundStyle(Ph.ink)
            Spacer()
            if !detail.isEmpty { PhCaps(text: detail, size: 11) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }
}

/// Een invoerveld in een putje met inktrand.
struct PhInputField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhCaps(text: label)
            TextField("", text: $text)
                .font(Ph.text(15))
                .foregroundStyle(Ph.ink)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Rectangle().fill(Ph.card.shadow(.inner(color: Ph.ink.opacity(0.08), radius: 1.5, y: 2))))
                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
        }
    }
}

// MARK: - Taak

private struct PhoneTaskSheet: View {
    let mail: PhoneMail
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var title = ""
    @State private var column = BoardColumn.inbox.id
    @State private var archive = true

    var body: some View {
        let columns = BoardService.columns(in: context).filter { $0.id != BoardColumn.doneID }
        VStack(alignment: .leading, spacing: 14) {
            PhSheetHeader(title: "Taak", detail: "Uit mail · \(mail.item.senderDisplay)")
            VStack(alignment: .leading, spacing: 14) {
                PhInputField(label: "Titel", text: $title)
                PhCaps(text: "Kolom")
                PhSegmented(items: columns.map { .init(value: $0.id, title: $0.title) }, selection: $column, height: 40)
                Toggle(isOn: $archive) { Text("Mail archiveren").font(Ph.text(15)) }
                    .toggleStyle(PhToggleStyle())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .phCard()
            }
            .padding(.horizontal, 16)
            Spacer()
            Button("MAAK TAAK") { make(columns) }
                .buttonStyle(PhPrimaryStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { title = mail.item.subject }
    }

    private func make(_ columns: [BoardColumn]) {
        let target = columns.first { $0.id == column } ?? .inbox
        let sender = [mail.item.fromName, mail.item.fromAddress].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
        let card = BoardService.addCard(title: title, column: target, sender: sender, body: mail.item.snippet, in: context)
        card.mailThreadID = mail.item.threadID
        card.mailAccount = mail.account
        try? context.save()
        if archive {
            Task { _ = await PhoneGmail.shared.archive([(threadID: mail.item.threadID, account: mail.account)]) }
        }
        appState.showToast("Taak in \(target.title)")
        dismiss()
    }
}

// MARK: - Tijd

private struct PhoneTimeSheet: View {
    let mail: PhoneMail
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var client = ""
    @State private var performed = ""
    @State private var minutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhSheetHeader(title: "Tijd", detail: client)
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    TimerService.startSupport(client: client, caseTitle: mail.item.subject, performed: performed, in: context)
                    appState.showToast("Tijd loopt")
                    dismiss()
                } label: {
                    Label("START NU", systemImage: "play.fill")
                }
                .buttonStyle(PhPrimaryStyle(height: 64))
                PhInputField(label: "Klant", text: $client)
                PhInputField(label: "Omschrijving", text: $performed)
                PhCaps(text: "Of achteraf")
                PhSegmented(items: [15, 30, 45, 60, 90, 120].map { .init(value: $0, title: Self.label($0)) },
                            selection: $minutes, height: 40)
            }
            .padding(.horizontal, 16)
            Spacer()
            Button("SCHRIJF \(Self.label(minutes))") {
                TimerService.logSupport(client: client, caseTitle: mail.item.subject, performed: performed,
                                        minutes: minutes, in: context)
                appState.showToast("\(Self.label(minutes)) geschreven")
                dismiss()
            }
            .buttonStyle(PhInkStyle(height: 52))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onAppear {
            client = Self.client(of: mail)
        }
    }

    static func label(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }

    /// De klant bij deze mail: de bedrijfsnaam na een | in de afzender, anders het domein.
    static func client(of mail: PhoneMail) -> String {
        if let name = mail.item.fromName, let company = name.components(separatedBy: "|").dropFirst().first {
            let trimmed = company.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        let domain = (mail.item.fromAddress ?? "").split(separator: "@").last.map(String.init) ?? ""
        return domain.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
    }
}

// MARK: - Inplannen

private struct PhonePlanSheet: View {
    let mail: PhoneMail
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let calendar = CalendarService.shared

    @State private var title = ""
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var start = Date()
    @State private var minutes = 30
    @State private var error: String?

    private var days: [Date] {
        var result: [Date] = []
        var date = Calendar.current.startOfDay(for: Date())
        while result.count < 6 {
            if !Calendar.current.isDateInWeekend(date) { result.append(date) }
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhSheetHeader(title: "Inplannen", detail: "\(minutes) min")
            VStack(alignment: .leading, spacing: 14) {
                PhInputField(label: "Titel", text: $title)
                PhSegmented(items: days.map { .init(value: $0, title: Self.dayTitle($0)) }, selection: $day, height: 44)
                HStack {
                    PhCaps(text: "Begin")
                    Spacer()
                    DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Ph.ink)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .phCard()
                PhSegmented(items: [15, 30, 60, 90, 120].map { .init(value: $0, title: "\($0) min") },
                            selection: $minutes, height: 38)
                if let error { Text(error).font(Ph.text(13)).foregroundStyle(Ph.danger) }
            }
            .padding(.horizontal, 16)
            Spacer()
            Button("PLAN IN") { plan() }
                .buttonStyle(PhPrimaryStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .onAppear {
            title = "\(mail.item.senderDisplay): \(mail.item.subject)"
            let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0),
                                                 matchingPolicy: .nextTime) ?? Date()
            start = next
        }
        .task { if !calendar.hasAccess { await calendar.requestAccess() } }
    }

    static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Vandaag" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEEEE d"
        return formatter.string(from: date)
    }

    private func plan() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
        guard let begin = Calendar.current.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: day),
              let id = calendar.defaultTargetCalendarID(hiddenCalendarIDs: []) else {
            error = "Geen agenda om in te plannen"
            return
        }
        do {
            try calendar.createEvent(title: title, start: begin, end: begin.addingTimeInterval(Double(minutes) * 60),
                                     calendarID: id)
            appState.showToast("Ingepland")
            dismiss()
        } catch {
            self.error = "Inplannen mislukt"
        }
    }
}

// MARK: - Verplaatsen

private struct PhoneMoveSheet: View {
    let mail: PhoneMail
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let gmail = PhoneGmail.shared
    @State private var moving: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhSheetHeader(title: "Verplaats", detail: "Nu in \(gmail.displayName(mail.account))")
            VStack(spacing: 0) {
                ForEach(gmail.accounts.filter { $0 != mail.account }, id: \.self) { account in
                    Button {
                        move(to: account)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                PhCaps(text: gmail.displayName(account), size: 13, color: Ph.ink)
                                Text(account).font(Ph.text(12.5)).foregroundStyle(Ph.ink2)
                            }
                            Spacer()
                            if moving == account { ProgressView().tint(Ph.ink) }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .overlay(alignment: .bottom) { Rectangle().fill(Ph.hair).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(moving != nil)
                }
            }
            .phCard()
            .padding(.horizontal, 16)
            Spacer()
        }
    }

    private func move(to account: String) {
        moving = account
        Task {
            let ok = await gmail.move(threadID: mail.item.threadID, from: mail.account, to: account)
            moving = nil
            appState.showToast(ok ? "Verplaatst naar \(gmail.displayName(account))" : "Verplaatsen mislukt")
            if ok { dismiss() }
        }
    }
}

// MARK: - Afzender en contact

private struct PhoneSenderSheet: View {
    let mail: PhoneMail
    let from: String
    @Environment(\.dismiss) private var dismiss
    @State private var addingContact = false
    @State private var compose: PhoneComposeRequest?

    private var card: ContactCard { ContactCard.fromHeader(from) }

    var body: some View {
        let address = MailAddress.parse(from).valid.first
        VStack(alignment: .leading, spacing: 14) {
            PhSheetHeader(title: card.displayName.isEmpty ? (address?.address ?? "Afzender") : card.displayName)
            VStack(spacing: 0) {
                HStack {
                    Text(address?.address ?? from).font(Ph.text(15)).foregroundStyle(Ph.ink).textSelection(.enabled)
                    Spacer()
                    Button("KOPIEER") { UIPasteboard.general.string = address?.address ?? from }
                        .font(Ph.text(11, .semibold))
                        .foregroundStyle(Ph.ink2)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
            }
            .phCard()
            .padding(.horizontal, 16)
            HStack(spacing: 6) {
                Button("NIEUWE MAIL") {
                    compose = PhoneComposeRequest(mode: .new, account: mail.account, to: address?.address ?? "")
                }
                .buttonStyle(PhSecondaryStyle())
                Button("CONTACT") { addingContact = true }
                    .buttonStyle(PhPrimaryStyle(height: 48))
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .sheet(isPresented: $addingContact) {
            PhoneNewContact(card: card)
        }
        .sheet(item: $compose) { request in
            PhoneComposeView(request: request).presentationBackground(Ph.paper)
        }
    }
}

/// Het scherm Nieuw contact van iOS, ingevuld met wat er uit de mail bekend is.
struct PhoneNewContact: UIViewControllerRepresentable {
    let card: ContactCard
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        contact.givenName = card.givenName
        contact.familyName = card.familyName
        contact.organizationName = card.organization
        contact.jobTitle = card.jobTitle
        if !card.email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: card.email as NSString)]
        }
        var phones: [CNLabeledValue<CNPhoneNumber>] = []
        if !card.workPhone.isEmpty { phones.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: card.workPhone))) }
        if !card.mobilePhone.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: card.mobilePhone)))
        }
        contact.phoneNumbers = phones
        if !card.website.isEmpty {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelWork, value: card.website as NSString)]
        }
        let controller = CNContactViewController(forNewContact: contact)
        controller.contactStore = CNContactStore()
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            dismiss()
        }
    }
}
