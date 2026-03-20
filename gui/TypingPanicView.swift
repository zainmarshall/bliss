import SwiftUI

enum TypingChallenge {
    static let definition = PanicChallengeDefinition(
        id: "typing",
        displayName: "Typing",
        iconName: "keyboard",
        shortDescription: "Type a quote with 100% accuracy.",
        makeChallengeView: { onSuccess in
            AnyView(TypingPanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(TypingSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(TypingWizardConfigView())
        }
    )
}

// Wrapper that loads a random quote from the view model (once, on appear)
struct TypingPanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel
    @State private var quote: String?

    var body: some View {
        Group {
            if let quote {
                TypingPanicView(quote: quote, onSuccess: onSuccess)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if quote == nil {
                quote = vm.randomQuote()
            }
        }
    }
}

struct TypingPanicView: View {
    let quote: String
    let onSuccess: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var typed = ""
    @State private var submitted = false
    @State private var isSubmitting = false
    @State private var commandError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type the quote below with 100% accuracy to unlock.")
                .foregroundColor(.secondary)

            Text(renderedPrompt)
                .font(.system(size: 18, design: .monospaced))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .onTapGesture { isInputFocused = true }

            ProgressView(value: progress)
                .tint(accuracy >= 100 ? .green : .accentColor)
            Text("\(typed.count) / \(quote.count) characters")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)

            if submitted && accuracy < 100 {
                Text("Not quite right. Fix any errors and keep going.")
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
                .onChange(of: typed) {
                    typed = sanitize(typed)
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
                        guard accuracy >= 100 else { return }
                        isSubmitting = true
                        let ok = await onSuccess()
                        isSubmitting = false
                        if ok {
                            dismiss()
                        } else {
                            commandError = "Command failed \u{2014} try again."
                        }
                    }
                }
                .disabled(isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { isInputFocused = true }
    }

    /// Fraction of quote typed so far (for progress bar)
    private var progress: Double {
        guard !quote.isEmpty else { return 0 }
        return Double(typed.count) / Double(quote.count)
    }

    private var accuracy: Double {
        let prompt = Array(quote)
        let input = Array(typed)
        guard !prompt.isEmpty else { return 0 }
        guard input.count >= prompt.count else { return 0 }
        var correct = 0
        for index in 0..<prompt.count where prompt[index] == input[index] {
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
                if typedChars[index] == promptChars[index] {
                    piece.foregroundColor = .green
                } else {
                    // Wrong character: show the expected char in red with underline
                    piece.foregroundColor = .red
                    piece.underlineStyle = .single
                    piece.underlineColor = .red
                }
            } else {
                piece.foregroundColor = .secondary
            }
            output += piece
        }

        // Extra typed characters beyond the quote length: show as red insertions
        if typedChars.count > promptChars.count {
            for index in promptChars.count..<typedChars.count {
                var extra = AttributedString(String(typedChars[index]))
                extra.foregroundColor = .red
                extra.backgroundColor = .red.opacity(0.15)
                output += extra
            }
        }

        // MonkeyType-style: if the character at cursor position is a space error,
        // show a visible red marker for wrong spaces within the typed range
        // (This is handled above by showing the expected char underlined in red,
        // which makes space errors visible since the space char gets a red underline)

        return output
    }

    private func sanitize(_ value: String) -> String {
        // Allow typing beyond quote length so extra chars show as red
        let maxCount = Array(quote).count + 20
        let filtered = value.filter { $0 == " " || ($0 >= "!" && $0 <= "~") }
        if filtered.count <= maxCount {
            return filtered
        }
        return String(filtered.prefix(maxCount))
    }
}

struct TypingSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quote Length")
            Text("Length of text you must type accurately")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.quoteLength },
                set: { vm.setQuoteLength($0) }
            )) {
                Text("Short").tag("short")
                Text("Medium").tag("medium")
                Text("Long").tag("long")
                Text("Huge").tag("huge")
            }
            .pickerStyle(.segmented)
        }
    }
}

struct TypingWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quote Length")
                    .font(.title2.weight(.semibold))
                Text("How long should the typing challenge quote be?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                WizardOptionCard(title: "Short", subtitle: "A sentence or two", selected: wizardState.quoteLength == "short") { wizardState.quoteLength = "short" }
                WizardOptionCard(title: "Medium", subtitle: "A short paragraph", selected: wizardState.quoteLength == "medium") { wizardState.quoteLength = "medium" }
                WizardOptionCard(title: "Long", subtitle: "A full paragraph", selected: wizardState.quoteLength == "long") { wizardState.quoteLength = "long" }
                WizardOptionCard(title: "Huge", subtitle: "Multiple paragraphs", selected: wizardState.quoteLength == "huge") { wizardState.quoteLength = "huge" }
            }
        }
    }
}
