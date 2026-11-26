import SwiftUI

struct MailHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhHeader(eyebrow: "12 ONGELEZEN", title: "Mail")
            Spacer()
        }
        .padding(.top, 8)
        .phScreen()
    }
}
