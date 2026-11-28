import Observation
import SwiftUI

/// Ongedaan maken na archiveren of afronden: een balk boven de tabbalk, zes seconden, met een lijn die krimpt (zoals
/// Verstuurd).
@MainActor
@Observable
final class PhoneUndo {
    static let shared = PhoneUndo()
    static let delay: TimeInterval = 6

    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
        let deadline: Date
        let undo: @MainActor () async -> Void
    }

    private(set) var pending: Item?
    @ObservationIgnored private var timer: Task<Void, Never>?

    func show(_ title: String, detail: String = "", icon: String = "archivebox",
              undo: @escaping @MainActor () async -> Void) {
        let item = Item(title: title, detail: detail, icon: icon, deadline: Date().addingTimeInterval(Self.delay),
                        undo: undo)
        withAnimation(.easeOut(duration: 0.2)) { pending = item }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled, self?.pending?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.pending = nil }
        }
    }

    func undo() {
        guard let item = pending else { return }
        timer?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
        Task { await item.undo() }
    }
}

/// De balk: wat er gebeurde, waarover, en ONGEDAAN MAKEN met de seconden.
struct PhoneUndoBar: View {
    let item: PhoneUndo.Item

    var body: some View {
        TimelineView(.animation) { timeline in
            let left = max(0, item.deadline.timeIntervalSince(timeline.date))
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ph.ink)
                        .frame(width: 30, height: 30)
                        .background(Ph.lime)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(Ph.text(14, .semibold)).foregroundStyle(Ph.paper)
                        if !item.detail.isEmpty {
                            Text(item.detail).font(Ph.text(12)).foregroundStyle(Color(hex: 0xB5B5AC)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Button {
                        PhoneUndo.shared.undo()
                    } label: {
                        HStack(spacing: 8) {
                            Text("ONGEDAAN MAKEN").tracking(1.4)
                            Text("\(Int(left.rounded(.up)))").monospacedDigit()
                        }
                        .font(Ph.text(11, .semibold))
                        .foregroundStyle(Ph.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Ph.lime.shadow(.inner(color: .white.opacity(0.6), radius: 0, y: 1)))
                        .shadow(color: .black.opacity(0.6), radius: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(hex: 0x3A3A36))
                        Rectangle().fill(Ph.lime)
                            .frame(width: geometry.size.width * CGFloat(left / PhoneUndo.delay))
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
            .background(Ph.ink)
            .shadow(color: .black.opacity(0.5), radius: 0, y: 2)
            .shadow(color: Ph.ink.opacity(0.32), radius: 12, y: 10)
        }
    }
}
