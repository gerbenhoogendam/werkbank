import AppKit
import SwiftUI

/// Veeg met twee vingers op het trackpad over een rij: naar links en naar rechts, elk met een eigen actie.
///
/// Bewust geen `List` + `.swipeActions`: een List neemt het slepen van de rij over, waardoor een mail niet meer
/// naar het board gesleept kon worden. Hier blijft de rij gewoon een view in een ScrollView (slepen en klikken
/// werken dus als vanouds) en vangen we alleen horizontale scrollwiel-gebeurtenissen van het trackpad op.
/// Een muis heeft geen horizontale veeg; daarvoor blijven de knoppen.
struct SwipeAction {
    let systemImage: String
    let title: String
    let color: Color
    let perform: () -> Void
}

private let swipeThreshold: CGFloat = 90
private let swipeMax: CGFloat = 140

struct TrackpadSwipe: ViewModifier {
    /// Veeg naar rechts.
    let leading: SwipeAction
    /// Veeg naar links.
    let trailing: SwipeAction

    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(offset != 0 ? ThingsColor.backgroundSidebar : Color.clear)
            .offset(x: offset)
            .background(alignment: offset > 0 ? .leading : .trailing) { reveal }
            .background(SwipeCatcher(
                onChange: { offset = $0 },
                onEnd: { final in
                    let action: SwipeAction? = final >= swipeThreshold ? leading : (final <= -swipeThreshold ? trailing : nil)
                    withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
                    action?.perform()
                }
            ))
            .clipped()
    }

    @ViewBuilder private var reveal: some View {
        if offset != 0 {
            let action = offset > 0 ? leading : trailing
            let progress = min(abs(offset) / swipeThreshold, 1)
            ZStack(alignment: offset > 0 ? .leading : .trailing) {
                Rectangle().fill(action.color.opacity(0.25 + 0.75 * progress))
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(progress >= 1 ? 1.15 : 0.9)
                    .padding(.horizontal, 14)
            }
            .frame(width: abs(offset))
            .frame(maxHeight: .infinity)
        }
    }
}

extension View {
    func trackpadSwipe(leading: SwipeAction, trailing: SwipeAction) -> some View {
        modifier(TrackpadSwipe(leading: leading, trailing: trailing))
    }
}

/// Onzichtbare view die scrollwiel-gebeurtenissen met twee vingers boven zichzelf volgt.
private struct SwipeCatcher: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class CatcherView: NSView {
        var onChange: ((CGFloat) -> Void)?
        var onEnd: ((CGFloat) -> Void)?

        private var monitor: Any?
        private var tracking = false
        private var swallowMomentum = false
        private var accumulated: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // nooit klikken of slepen onderscheppen

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Let op: `self?.handle(event) ?? event` zou een bewust ingeslikte gebeurtenis (nil) terugzetten.
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.hasPreciseScrollingDeltas, event.window === window else { return event }

            // Uitlooptijd na het loslaten van een veeg die wij afhandelden: niet laten doorscrollen.
            if swallowMomentum {
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swallowMomentum = false }
                if !event.momentumPhase.isEmpty { return nil }
                swallowMomentum = false
            }

            if event.phase.contains(.began) {
                let point = convert(event.locationInWindow, from: nil)
                let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                tracking = bounds.contains(point) && horizontal
                accumulated = 0
            }
            guard tracking else { return event }

            // De vinger beweegt mee, ook als "natuurlijk scrollen" uit staat.
            let fingerDelta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            accumulated = max(-swipeMax, min(swipeMax, accumulated + fingerDelta))
            onChange?(accumulated)

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                tracking = false
                swallowMomentum = true
                onEnd?(accumulated)
                accumulated = 0
            }
            return nil
        }
    }
}
