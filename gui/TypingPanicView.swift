import SwiftUI

enum TypingChallenge {
    static let definition = PanicChallengeDefinition(
        id: "typing",
        displayName: "Typing",
        iconName: "keyboard",
        shortDescription: "Type a quote with 95% accuracy.",
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

// Wrapper that loads a random quote from the view model
struct TypingPanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        TypingPanicView(quote: vm.randomQuote(), onSuccess: onSuccess)
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
        .onAppear { isInputFocused = true }
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

// Settings subsection for typing mode
struct TypingSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quote Length")
                Text("Length of text you must type accurately")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { vm.quoteLength },
                set: { vm.setQuoteLength($0) }
            )) {
                Text("Short").tag("short")
                Text("Medium").tag("medium")
                Text("Long").tag("long")
                Text("Huge").tag("huge")
            }
            .labelsHidden()
            .frame(width: 250, alignment: .trailing)
        }
    }
}

// Wizard config step for typing mode
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
                wizardOptionCard("Short", subtitle: "A sentence or two", selected: wizardState.quoteLength == "short") { wizardState.quoteLength = "short" }
                wizardOptionCard("Medium", subtitle: "A short paragraph", selected: wizardState.quoteLength == "medium") { wizardState.quoteLength = "medium" }
                wizardOptionCard("Long", subtitle: "A full paragraph", selected: wizardState.quoteLength == "long") { wizardState.quoteLength = "long" }
                wizardOptionCard("Huge", subtitle: "Multiple paragraphs", selected: wizardState.quoteLength == "huge") { wizardState.quoteLength = "huge" }
            }
        }
    }

    private func wizardOptionCard(_ title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: selected ? 2 : 1)
            )
            .background(
                selected ? Color.accentColor.opacity(0.05) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
