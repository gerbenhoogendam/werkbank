import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WerkbankCore

/// Voorkeuren › Klanten: de klantenlijst van Werkbank. Zoeken (ook op een woord midden in de naam), zelf een klant
/// toevoegen, naam en domein aanpassen, verwijderen en een .csv inlezen (nieuwe klanten erbij, bestaande aangevuld).
struct ClientsEditor: View {
    @Query(filter: #Predicate<Client> { !$0.isRemoved }, sort: \Client.name) private var clients: [Client]
    @State private var search = ""
    @State private var newName = ""
    @State private var newDomain = ""
    @State private var importing = false
    @State private var message: String?
    @FocusState private var newNameFocused: Bool

    private let directory = ClientDirectory.shared

    /// Zonder zoekterm alfabetisch; met zoekterm in de volgorde van de suggesties.
    private var shown: [Client] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return clients }
        let records = clients.map { ClientRecord(name: $0.name, details: $0.details, domains: $0.domains) }
        let found = ClientList.search(query, in: records, limit: 200)
        var rank: [String: Int] = [:]
        for (index, record) in found.enumerated() where rank[record.name] == nil { rank[record.name] = index }
        return clients.filter { rank[$0.name] != nil }.sorted { rank[$0.name, default: 0] < rank[$1.name, default: 0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addRow
                .padding(12)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Zoeken", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            List {
                ForEach(shown) { client in
                    ClientRow(client: client)
                }
            }
            .listStyle(.plain)

            Divider()
            HStack(spacing: 10) {
                Text("\(clients.count) klanten")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Importeer .csv…") { importing = true }
            }
            .font(.werk(size: 12))
            .padding(12)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result { Task { await importFile(url) } }
        }
        .task { await directory.refresh() }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Naam", text: $newName)
                .focused($newNameFocused)
                .onSubmit(add)
            TextField("Domein", text: $newDomain)
                .frame(maxWidth: 220)
                .onSubmit(add)
            Button("Voeg toe", action: add)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func add() {
        let name = newName
        let domain = newDomain
        Task {
            if await directory.add(name: name, domain: domain) {
                message = "Toegevoegd: \(name.trimmingCharacters(in: .whitespaces))"
                newName = ""
                newDomain = ""
                newNameFocused = true
            } else if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                message = "Staat er al in: \(name.trimmingCharacters(in: .whitespaces))"
            }
        }
    }

    private func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = CloudFile.text(data) else {
            message = "Kon \(url.lastPathComponent) niet lezen."
            return
        }
        let result = await directory.importCSV(text)
        message = "\(result.added) nieuw · \(result.updated) aangevuld · \(result.removed) weggelaten (failliet e.d.)"
    }
}

/// Eén klant: logo, naam en domeinen, ter plekke aan te passen (bewaren bij Return of als je het veld verlaat).
private struct ClientRow: View {
    let client: Client

    private enum Field { case name, domains }

    @State private var name = ""
    @State private var domains = ""
    @FocusState private var focus: Field?

    var body: some View {
        HStack(spacing: 10) {
            ClientLogo(name: client.name, size: 18)
                .frame(width: 20)
            TextField("Naam", text: $name)
                .focused($focus, equals: .name)
                .onSubmit(save)
            TextField("Domein", text: $domains)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 220)
                .focused($focus, equals: .domains)
                .onSubmit(save)
        }
        .textFieldStyle(.plain)
        .onAppear(perform: load)
        .onChange(of: client.name) { load() }
        .onChange(of: focus) { _, new in if new == nil { save() } }
        .contextMenu {
            Button("Verwijder", role: .destructive) { Task { await ClientDirectory.shared.delete(client) } }
        }
        #if os(iOS)
        .swipeActions {
            Button(role: .destructive) {
                Task { await ClientDirectory.shared.delete(client) }
            } label: { Label("Verwijder", systemImage: "trash") }
        }
        #endif
    }

    private func load() {
        name = client.name
        domains = client.domains.joined(separator: ", ")
    }

    private func save() {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDomains = ClientList.customDomains(in: domains)
        guard (!newName.isEmpty && newName != client.name) || newDomains != client.domains else {
            load()
            return
        }
        let text = domains
        Task { await ClientDirectory.shared.update(client, name: newName, domains: text) }
    }
}
