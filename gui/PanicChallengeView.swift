import SwiftUI

struct PanicChallengeView: View {
    let quote: String
    let mode: PanicModeSetting
    let cpDifficulty: CPDifficulty
    let onSuccess: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var typed = ""
    @State private var submitted = false
    @State private var isSubmitting = false
    @State private var commandError: String?

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

            if mode == .typing {
                typingView
                    .padding(20)
            } else {
                CompetitivePanicView(difficulty: cpDifficulty, onUnlock: {
                    let ok = await onSuccess()
                    if ok {
                        dismiss()
                    }
                    return ok
                })
                .padding(20)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, maxWidth: 920, minHeight: 560, idealHeight: 700, maxHeight: .infinity)
        .onAppear { isInputFocused = true }
    }

    private var typingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type with at least 95% accuracy to unlock.")
                .foregroundColor(.secondary)

            Text(renderedPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .onTapGesture { isInputFocused = true }

            ProgressView(value: accuracy / 100.0)
                .tint(accuracy >= 95 ? .green : .orange)
            Text("Accuracy: \(Int(accuracy.rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(accuracy >= 95 ? .green : .secondary)

            if submitted && accuracy < 95 {
                Text("Challenge failed. Keep typing until you hit 95%.")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            if let commandError {
                Text(commandError)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            TextField("", text: $typed)
                .textFieldStyle(.plain)
                .foregroundColor(.clear)
                .accentColor(.clear)
                .focused($isInputFocused)
                .onChange(of: typed) { newValue in
                    typed = sanitize(newValue)
                }
                .frame(height: 1)
                .opacity(0.02)

            HStack {
                Spacer()
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Submit") {
                    Task {
                        submitted = true
                        commandError = nil
                        guard accuracy >= 95 else { return }
                        isSubmitting = true
                        let ok = await onSuccess()
                        isSubmitting = false
                        if ok {
                            dismiss()
                        } else {
                            commandError = "Panic command failed. Session is still active."
                        }
                    }
                }
                .disabled(isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var accuracy: Double {
        let prompt = Array(quote)
        let input = Array(typed)
        guard !prompt.isEmpty else { return 0 }
        var correct = 0
        for index in 0..<min(prompt.count, input.count) where prompt[index] == input[index] {
            correct += 1
        }
        return (Double(correct) / Double(prompt.count)) * 100.0
    }

    private var renderedPrompt: AttributedString {
        var output = AttributedString()
        let promptChars = Array(quote)
        let typedChars = Array(typed)
        for index in 0..<promptChars.count {
            var piece = AttributedString(String(promptChars[index]))
            if index < typedChars.count {
                piece.foregroundColor = typedChars[index] == promptChars[index] ? .green : .red
            } else {
                piece.foregroundColor = .secondary
            }
            output += piece
        }
        return output
    }

    private func sanitize(_ value: String) -> String {
        let maxCount = Array(quote).count
        let filtered = value.filter { $0 == " " || ($0 >= "!" && $0 <= "~") }
        if filtered.count <= maxCount {
            return filtered
        }
        return String(filtered.prefix(maxCount))
    }
}
