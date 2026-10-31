import SwiftUI
import WerkbankCore

/// Een genummerde klik (stip) of kader op het venster of de screenshot.
struct FeedbackMarkView: View {
    let mark: FeedbackMark
    let size: CGSize
    let color: Color

    var body: some View {
        let x = CGFloat(mark.x) * size.width
        let y = CGFloat(mark.y) * size.height
        if mark.kind == .click {
            ZStack {
                Circle().strokeBorder(color.opacity(0.5), lineWidth: 6).frame(width: 34, height: 34)
                Circle().fill(color).frame(width: 22, height: 22)
                Text("\(mark.number)")
                    .font(.werk(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .position(x: x, y: y)
            .allowsHitTesting(false)
        } else {
            let width = CGFloat(mark.width) * size.width
            let height = CGFloat(mark.height) * size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(color.opacity(0.08))
                Rectangle().strokeBorder(color, lineWidth: 2.5)
                Text("\(mark.number)")
                    .font(.werk(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(color))
                    .offset(x: -11, y: -11)
            }
            .frame(width: width, height: height)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
        }
    }
}
