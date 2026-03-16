import SwiftUI

struct PanicChallengeView: View {
    let mode: String
    let onSuccess: () async -> Bool

    @EnvironmentObject var vm: BlissViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Panic Challenge")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            Divider()

            if let challenge = PanicChallengeRegistry.find(mode) {
                challenge.makeChallengeView(onSuccess)
                    .environmentObject(vm)
                    .padding(20)
            } else {
                // Fallback to typing if mode not found
                TypingPanicView(quote: vm.randomQuote(), onSuccess: onSuccess)
                    .padding(20)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, maxWidth: 920, minHeight: 560, idealHeight: 700, maxHeight: .infinity)
    }
}
