import SwiftData
import SwiftUI

/// Wat de gebruiker met de kolommen van het board wil doen; de sleutel is `ColumnRecord.key`.
enum ColumnRequest: Equatable {
    case add
    case rename(String)
    case delete(String)
    case icon(String)
}

/// Dialogen om een kolom toe te voegen, te hernoemen, te verwijderen en van icoon en kleur te veranderen. Gedeeld door macOS en iOS:
/// de view zet een `ColumnRequest`, deze modifier toont het bijbehorende dialoog en voert het uit.
struct ColumnManagement: ViewModifier {
    @Binding var request: ColumnRequest?

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var name = ""
    /// Het verzoek dat getoond wordt; `request` wordt al leeg gezet zodra het dialoog sluit, ook vóór de knopactie.
    @State private var active: ColumnRequest?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, new in
                guard let new else { return }
                active = new
                switch new {
                case .add:
                    name = ""
                case .rename(let key):
                    name = record(for: key)?.title ?? ""
                case .delete, .icon:
                    break
                }
            }
            .sheet(isPresented: iconSheetBinding) {
                if case .icon(let key)? = request, let record = record(for: key) {
                    ColumnIconPicker(record: record)
                    #if os(iOS)
                        .presentationDetents([.large])
                    #endif
                }
            }
            .alert(isAddRequest ? "Nieuwe kolom" : "Kolom hernoemen", isPresented: nameAlertBinding) {
                TextField("Naam", text: $name)
                Button("Annuleer", role: .cancel) {}
                Button(isAddRequest ? "Voeg toe" : "Bewaar") { commitName() }
            }
            .confirmationDialog(deleteTitle, isPresented: deleteDialogBinding, titleVisibility: .visible) {
                Button("Verwijder kolom", role: .destructive) { commitDelete() }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
    }

    // MARK: Bindings

    private var nameAlertBinding: Binding<Bool> {
        Binding(
            get: {
                switch request {
                case .add?, .rename?: return true
                default:              return false
                }
            },
            set: { if !$0 { request = nil } }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: {
                if case .delete? = request { return true }
                return false
            },
            set: { if !$0 { request = nil } }
        )
    }

    private var iconSheetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .icon? = request { return true }
                return false
            },
            set: { if !$0 { request = nil } }
        )
    }

    private var isAddRequest: Bool { active == .add }

    // MARK: Uitvoeren

    private func record(for key: String) -> ColumnRecord? {
        BoardService.columnRecords(in: context).first { $0.key == key }
    }

    private func commitName() {
        switch active {
        case .add?:
            if let record = BoardService.addColumn(title: name, in: context) {
                appState.showToast("Kolom \(record.title) toegevoegd")
            }
        case .rename(let key)?:
            if let record = record(for: key) { BoardService.renameColumn(record, to: name, in: context) }
        default:
            break
        }
    }

    private var deleteTitle: String {
        guard case .delete(let key)? = active, let record = record(for: key) else { return "Kolom verwijderen?" }
        return "Kolom \(record.title) verwijderen?"
    }

    private var deleteMessage: String {
        guard case .delete(let key)? = active, let record = record(for: key) else { return "" }
        let count = BoardService.allCards(in: context).filter { $0.columnRaw == key }.count
        let destination = BoardService.columnRecords(in: context).first { $0.key != key }?.title ?? ""
        switch count {
        case 0:  return "De kolom is leeg."
        case 1:  return "De kaart in deze kolom gaat naar \(destination)."
        default: return "De \(count) kaarten in deze kolom gaan naar \(destination)."
        }
    }

    private func commitDelete() {
        guard case .delete(let key)? = active, let record = record(for: key) else { return }
        let title = record.title
        guard let result = BoardService.deleteColumn(record, in: context) else { return }
        appState.showToast(result.moved > 0
            ? "Kolom \(title) verwijderd; \(result.moved) naar \(result.destination)"
            : "Kolom \(title) verwijderd")
    }
}

extension View {
    func columnManagement(_ request: Binding<ColumnRequest?>) -> some View {
        modifier(ColumnManagement(request: request))
    }
}
