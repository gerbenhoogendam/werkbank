import SwiftUI

struct AgendaHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhHeader(eyebrow: "WEEK", title: "Agenda")
            Spacer()
        }
        .padding(.top, 8)
        .phScreen()
    }
}
