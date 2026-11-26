import SwiftUI

struct TijdHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhHeader(eyebrow: "VANDAAG", title: "Tijd")
            Spacer()
        }
        .padding(.top, 8)
        .phScreen()
    }
}
