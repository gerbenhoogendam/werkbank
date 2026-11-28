import SwiftUI

/// Een handeling achter een geveegde rij.
struct PhSwipeAction: Identifiable {
    let id: String
    let symbol: String
    let label: String
    var primary = false
    let run: () -> Void
}

/// Vegen over een rij, in de stijl van de app: vierkante knoppen (wit, of limoen voor de eerste) met een inktrand en
/// het zwarte balkje eronder, alleen een icoon. iOS tekent eigen veegknoppen als rondjes; daarom doet de app het zelf.
/// Naar links vegen toont `trailing` rechts, naar rechts vegen `leading` links. Helemaal doorvegen doet de eerste.
/// Er staat er één tegelijk open (`openID`); een tik op een open rij sluit hem.
struct PhSwipeRow<Content: View>: View {
    let id: String
    @Binding var openID: String?
    var background: Color = Ph.card
    let leading: [PhSwipeAction]
    let trailing: [PhSwipeAction]
    /// Helemaal doorvegen voert de eerste uit (uit voor iets als verwijderen).
    var fullLeading = true
    var fullTrailing = true
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var start: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var width: CGFloat = 390

    private let size: CGFloat = 52
    private let gap: CGFloat = 8
    private let edge: CGFloat = 12

    private func reveal(_ count: Int) -> CGFloat {
        count == 0 ? 0 : edge * 2 + CGFloat(count) * size + CGFloat(count - 1) * gap
    }

    var body: some View {
        ZStack {
            HStack(spacing: gap) {
                if offset > 0 { ForEach(leading) { button($0) } }
                Spacer(minLength: 0)
                if offset < 0 { ForEach(Array(trailing.reversed())) { button($0) } }
            }
            .padding(.horizontal, edge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ph.paper)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background)
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    if offset != 0 { close() } else { onTap() }
                }
        }
        .background(GeometryReader { proxy in Color.clear.onAppear { width = proxy.size.width } })
        .clipped()
        .simultaneousGesture(drag)
        .onChange(of: openID) { _, open in
            if open != id, offset != 0 { withAnimation(.easeOut(duration: 0.2)) { offset = 0 } }
        }
        .accessibilityActions {
            ForEach(Array((leading + trailing).enumerated()), id: \.offset) { _, action in
                Button(action.label) { action.run() }
            }
        }
    }

    private func button(_ action: PhSwipeAction) -> some View {
        Button {
            close()
            action.run()
        } label: {
            Image(systemName: action.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Ph.ink)
                .frame(width: size, height: size - 4)
                .background(action.primary ? Ph.lime : Ph.card)
                .overlay(Rectangle().strokeBorder(Ph.ink, lineWidth: 2))
                .background(Rectangle().fill(Ph.ink).offset(y: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if horizontal == nil {
                    horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3
                    start = offset
                    if horizontal == true { openID = id }
                }
                guard horizontal == true else { return }
                var next = start + value.translation.width
                if leading.isEmpty { next = min(0, next) }
                if trailing.isEmpty { next = max(0, next) }
                offset = next
            }
            .onEnded { value in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                let predicted = start + value.predictedEndTranslation.width
                let full = width * 0.6
                withAnimation(.easeOut(duration: 0.2)) {
                    if fullTrailing, offset < -full || predicted < -width, let first = trailing.first {
                        offset = 0
                        first.run()
                    } else if fullLeading, offset > full || predicted > width, let first = leading.first {
                        offset = 0
                        first.run()
                    } else if offset < -reveal(trailing.count) / 2 {
                        offset = -reveal(trailing.count)
                    } else if offset > reveal(leading.count) / 2 {
                        offset = reveal(leading.count)
                    } else {
                        offset = 0
                    }
                }
                if offset == 0, openID == id { openID = nil }
            }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
        if openID == id { openID = nil }
    }
}
