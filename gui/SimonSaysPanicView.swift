import SwiftUI

enum SimonDifficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"

    var gridSize: Int {
        switch self {
        case .easy: return 3
        case .medium: return 4
        case .hard: return 5
        }
    }

    var sequenceLength: Int {
        switch self {
        case .easy: return 5
        case .medium: return 7
        case .hard: return 10
        }
    }

    var displayName: String {
        switch self {
        case .easy: return "Easy (3\u{00D7}3, 5 steps)"
        case .medium: return "Medium (4\u{00D7}4, 7 steps)"
        case .hard: return "Hard (5\u{00D7}5, 10 steps)"
        }
    }
}

private let cellColors: [Color] = [
    Color(red: 0.90, green: 0.30, blue: 0.30),
    Color(red: 0.20, green: 0.60, blue: 0.86),
    Color(red: 0.30, green: 0.69, blue: 0.31),
    Color(red: 1.00, green: 0.76, blue: 0.03),
    Color(red: 0.61, green: 0.15, blue: 0.69),
    Color(red: 1.00, green: 0.60, blue: 0.00),
    Color(red: 0.00, green: 0.74, blue: 0.83),
    Color(red: 0.91, green: 0.46, blue: 0.67),
    Color(red: 0.47, green: 0.33, blue: 0.28),
]

enum SimonPhase {
    case watching
    case playing
    case wrong
    case won
}

@MainActor
class SimonGame: ObservableObject {
    let gridSize: Int
    let sequenceLength: Int
    @Published var sequence: [(Int, Int)] = []
    @Published var playerIndex: Int = 0
    @Published var phase: SimonPhase = .watching
    @Published var highlightedCell: (Int, Int)?

    private var playbackTask: Task<Void, Never>?

    init(difficulty: SimonDifficulty) {
        self.gridSize = difficulty.gridSize
        self.sequenceLength = difficulty.sequenceLength
        generateSequence()
        playSequence()
    }

    func generateSequence() {
        sequence = (0..<sequenceLength).map { _ in
            (Int.random(in: 0..<gridSize), Int.random(in: 0..<gridSize))
        }
    }

    func playSequence() {
        playbackTask?.cancel()
        phase = .watching
        highlightedCell = nil
        playbackTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            for position in sequence {
                guard !Task.isCancelled else { return }
                highlightedCell = position
                try? await Task.sleep(nanoseconds: 600_000_000)
                highlightedCell = nil
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard !Task.isCancelled else { return }
            phase = .playing
        }
    }

    func tap(row: Int, col: Int) {
        guard phase == .playing, playerIndex < sequence.count else { return }
        let expected = sequence[playerIndex]
        if row == expected.0 && col == expected.1 {
            highlightedCell = (row, col)
            playerIndex += 1
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                highlightedCell = nil
                if playerIndex == sequenceLength {
                    phase = .won
                }
            }
        } else {
            BlissSounds.playError()
            phase = .wrong
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                playerIndex = 0
                playSequence()
            }
        }
    }

    func reset(difficulty: SimonDifficulty) {
        playbackTask?.cancel()
        playerIndex = 0
        generateSequence()
        playSequence()
    }
}

enum SimonSaysChallenge {
    static let definition = PanicChallengeDefinition(
        id: "simon",
        displayName: "Simon Says",
        iconName: "circle.grid.3x3.fill",
        shortDescription: "Memorize and repeat a color sequence to unlock.",
        makeChallengeView: { onSuccess in
            AnyView(SimonSaysPanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(SimonSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(SimonWizardConfigView())
        }
    )
}

struct SimonSaysPanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        SimonSaysPanicView(difficulty: vm.simonDifficulty, onUnlock: onSuccess)
    }
}

struct SimonSaysPanicView: View {
    let difficulty: SimonDifficulty
    let onUnlock: () async -> Bool

    @StateObject private var game: SimonGame
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var resultText = ""

    init(difficulty: SimonDifficulty, onUnlock: @escaping () async -> Bool) {
        self.difficulty = difficulty
        self.onUnlock = onUnlock
        _game = StateObject(wrappedValue: SimonGame(difficulty: difficulty))
    }

    private let cellSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Simon Says")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(difficulty.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Group {
                    switch game.phase {
                    case .watching:
                        Text("Watch the sequence...")
                    case .playing:
                        Text("Your turn \u{2014} tap the cells in order")
                    case .wrong:
                        Text("Wrong! Watch again...")
                            .foregroundColor(.red)
                    case .won:
                        Text("Correct!")
                            .foregroundColor(.green)
                    }
                }
                .foregroundColor(game.phase == .watching ? .secondary : .primary)
                Spacer()
                Text("\(game.playerIndex)/\(game.sequenceLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(0..<game.gridSize, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<game.gridSize, id: \.self) { col in
                            cellView(row: row, col: col)
                        }
                    }
                }
            }

            HStack {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                    Text("Unlocking...")
                        .foregroundColor(.secondary)
                } else if !resultText.isEmpty {
                    Text(resultText)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if game.phase == .wrong || (game.phase == .watching && game.playerIndex == 0 && resultText.isEmpty) {
                    EmptyView()
                }
                Spacer()
                if game.phase == .wrong || game.phase == .playing {
                    Button("Restart") {
                        game.reset(difficulty: difficulty)
                        resultText = ""
                    }
                }
            }
            .frame(height: 28)
        }
        .onChange(of: game.phase) {
            if game.phase == .won {
                BlissSounds.playSuccess()
                submitUnlock()
            }
        }
    }

    private func colorForCell(row: Int, col: Int) -> Color {
        let index = (row * game.gridSize + col) % cellColors.count
        return cellColors[index]
    }

    private func isHighlighted(row: Int, col: Int) -> Bool {
        guard let h = game.highlightedCell else { return false }
        return h.0 == row && h.1 == col
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        let lit = isHighlighted(row: row, col: col)
        let baseColor = colorForCell(row: row, col: col)

        RoundedRectangle(cornerRadius: 8)
            .fill(baseColor.opacity(lit ? 1.0 : 0.3))
            .frame(width: cellSize, height: cellSize)
            .scaleEffect(lit ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: lit)
            .contentShape(Rectangle())
            .onTapGesture {
                game.tap(row: row, col: col)
            }
    }

    private func submitUnlock() {
        isSubmitting = true
        Task {
            let ok = await onUnlock()
            isSubmitting = false
            if ok {
                dismiss()
            } else {
                resultText = "Command failed \u{2014} try again."
            }
        }
    }
}

struct SimonSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
            Text("Grid size and sequence length")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.simonDifficulty },
                set: { vm.setSimonDifficulty($0) }
            )) {
                ForEach(SimonDifficulty.allCases, id: \.self) { difficulty in
                    Text(difficulty.displayName).tag(difficulty)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SimonWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Difficulty")
                    .font(.title2.weight(.semibold))
                Text("How challenging should the Simon Says sequence be?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(SimonDifficulty.allCases, id: \.self) { difficulty in
                    WizardOptionCard(
                        title: difficulty.rawValue.capitalized,
                        subtitle: difficulty.displayName,
                        selected: wizardState.simonDifficulty == difficulty
                    ) {
                        wizardState.simonDifficulty = difficulty
                    }
                }
            }
        }
    }
}
