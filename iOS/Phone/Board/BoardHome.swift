import SwiftUI

struct BoardHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhHeader(eyebrow: "TO DO", title: "Board")
            Spacer()
        }
        .padding(.top, 8)
        .phScreen()
    }
}
