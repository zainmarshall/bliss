import SwiftUI

enum Game2048Difficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"

    var targetScore: Int {
        switch self {
        case .easy:   return 128
        case .medium: return 512
        case .hard:   return 2048
        }
    }

    var displayName: String {
        switch self {
        case .easy:   return "Reach 128"
        case .medium: return "Reach 512"
        case .hard:   return "Reach 2048"
        }
    }
}

enum Game2048Challenge {
    static let definition = PanicChallengeDefinition(
        id: "2048",
        displayName: "2048",
        iconName: "square.grid.2x2",
        shortDescription: "Reach the target tile to unlock.",
        makeChallengeView: { onSuccess in
            AnyView(Game2048PanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(Game2048SettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(Game2048WizardConfigView())
        }
    )
}

struct Game2048PanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        Game2048PanicView(difficulty: vm.game2048Difficulty, onUnlock: onSuccess)
    }
}

@MainActor
class Game2048Game: ObservableObject {
    let targetScore: Int
    @Published var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    @Published var score = 0
    @Published var won = false
    @Published var gameOver = false
    /// Tracks which cells were just spawned for pop-in animation
    @Published var justSpawned: Set<Int> = []
    /// Monotonically increasing generation counter to trigger tile identity changes on merge
    @Published var tileGeneration: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    private var generationCounter = 0

    init(targetScore: Int = 2048) {
        self.targetScore = targetScore
        spawnTile()
        spawnTile()
    }

    func reset() {
        grid = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        tileGeneration = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        generationCounter = 0
        score = 0
        won = false
        gameOver = false
        justSpawned = []
        spawnTile()
        spawnTile()
    }

    func move(_ direction: Direction) {
        guard !gameOver, !won else { return }

        let previous = grid
        switch direction {
        case .left:  slideLeft()
        case .right: slideRight()
        case .up:    slideUp()
        case .down:  slideDown()
        }

        // Bump generation for cells whose value changed (merged)
        for r in 0..<4 {
            for c in 0..<4 {
                if grid[r][c] != previous[r][c] && grid[r][c] != 0 {
                    generationCounter += 1
                    tileGeneration[r][c] = generationCounter
                }
            }
        }

        if grid != previous {
            spawnTile()
            if !hasMovesAvailable() {
                gameOver = true
            }
        }
    }

    enum Direction {
        case up, down, left, right
    }

    private func slideLeft() {
        for r in 0..<4 {
            let merged = mergeRow(grid[r])
            grid[r] = merged
        }
    }

    private func slideRight() {
        for r in 0..<4 {
            let merged = mergeRow(grid[r].reversed()).reversed()
            grid[r] = Array(merged)
        }
    }

    private func slideUp() {
        for c in 0..<4 {
            let col = (0..<4).map { grid[$0][c] }
            let merged = mergeRow(col)
            for r in 0..<4 { grid[r][c] = merged[r] }
        }
    }

    private func slideDown() {
        for c in 0..<4 {
            let col = (0..<4).map { grid[$0][c] }.reversed()
            let merged = mergeRow(Array(col)).reversed()
            let result = Array(merged)
            for r in 0..<4 { grid[r][c] = result[r] }
        }
    }

    private func mergeRow(_ row: [Int]) -> [Int] {
        let compact = row.filter { $0 != 0 }
        var result: [Int] = []
        var i = 0
        while i < compact.count {
            if i + 1 < compact.count && compact[i] == compact[i + 1] {
                let merged = compact[i] * 2
                result.append(merged)
                score += merged
                if merged >= targetScore { won = true }
                i += 2
            } else {
                result.append(compact[i])
                i += 1
            }
        }
        while result.count < 4 { result.append(0) }
        return result
    }

    private func spawnTile() {
        var empty: [(Int, Int)] = []
        for r in 0..<4 {
            for c in 0..<4 {
                if grid[r][c] == 0 { empty.append((r, c)) }
            }
        }
        guard let pos = empty.randomElement() else { return }
        grid[pos.0][pos.1] = Double.random(in: 0..<1) < 0.9 ? 2 : 4
        generationCounter += 1
        tileGeneration[pos.0][pos.1] = generationCounter
        let cellIndex = pos.0 * 4 + pos.1
        justSpawned.insert(cellIndex)
        // Clear the spawn flag after the animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.justSpawned.remove(cellIndex)
        }
    }

    private func hasMovesAvailable() -> Bool {
        for r in 0..<4 {
            for c in 0..<4 {
                if grid[r][c] == 0 { return true }
                if c + 1 < 4 && grid[r][c] == grid[r][c + 1] { return true }
                if r + 1 < 4 && grid[r][c] == grid[r + 1][c] { return true }
            }
        }
        return false
    }
}

struct Game2048PanicView: View {
    let difficulty: Game2048Difficulty
    let onUnlock: () async -> Bool

    @StateObject private var game: Game2048Game
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var isSubmitting = false
    @State private var resultText = ""

    private let tileSize: CGFloat = 70
    private let tileSpacing: CGFloat = 8

    init(difficulty: Game2048Difficulty, onUnlock: @escaping () async -> Bool) {
        self.difficulty = difficulty
        self.onUnlock = onUnlock
        _game = StateObject(wrappedValue: Game2048Game(targetScore: difficulty.targetScore))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("2048")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Goal: \(difficulty.targetScore)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Score: \(game.score)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.score)
            }

            Text("Use arrow keys to slide tiles")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            let boardSize = tileSize * 4 + tileSpacing * 5
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: 0xbbada0))

                VStack(spacing: tileSpacing) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: tileSpacing) {
                            ForEach(0..<4, id: \.self) { col in
                                let cellIndex = row * 4 + col
                                let isNew = game.justSpawned.contains(cellIndex)
                                tileView(value: game.grid[row][col])
                                    .scaleEffect(isNew ? 0.8 : 1.0)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: game.tileGeneration[row][col])
                                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isNew)
                            }
                        }
                    }
                }
                .padding(tileSpacing)
            }
            .frame(width: boardSize, height: boardSize)

            HStack {
                if game.won {
                    Text("You reached \(difficulty.targetScore)!")
                        .foregroundColor(.green)
                        .font(.callout.weight(.semibold))
                } else if game.gameOver {
                    Text("Game Over")
                        .foregroundColor(.red)
                    Spacer()
                    Button("Try Again") {
                        game.reset()
                        resultText = ""
                    }
                }
                if isSubmitting {
                    ProgressView().controlSize(.small)
                    Text("Unlocking...")
                        .foregroundColor(.secondary)
                } else if !resultText.isEmpty {
                    Text(resultText)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
            }
            .frame(height: 28)
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) { game.move(.up); return .handled }
        .onKeyPress(.downArrow) { game.move(.down); return .handled }
        .onKeyPress(.leftArrow) { game.move(.left); return .handled }
        .onKeyPress(.rightArrow) { game.move(.right); return .handled }
        .onAppear { isFocused = true }
        .onChange(of: game.won) {
            if game.won {
                BlissSounds.playSuccess()
                submitUnlock()
            }
        }
    }

    @ViewBuilder
    private func tileView(value: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tileColor(value))

            if value > 0 {
                Text("\(value)")
                    .font(.system(size: tileFontSize(value), weight: .bold, design: .rounded))
                    .foregroundColor(value <= 4 ? Color(hex: 0x776e65) : .white)
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    private func tileFontSize(_ value: Int) -> CGFloat {
        switch value {
        case 0..<100: return 28
        case 100..<1000: return 22
        default: return 18
        }
    }

    private func tileColor(_ value: Int) -> Color {
        switch value {
        case 0:    return Color(hex: 0xcdc1b4)
        case 2:    return Color(hex: 0xeee4da)
        case 4:    return Color(hex: 0xede0c8)
        case 8:    return Color(hex: 0xf2b179)
        case 16:   return Color(hex: 0xf59563)
        case 32:   return Color(hex: 0xf67c5f)
        case 64:   return Color(hex: 0xf65e3b)
        case 128:  return Color(hex: 0xedcf72)
        case 256:  return Color(hex: 0xedcc61)
        case 512:  return Color(hex: 0xedc850)
        case 1024: return Color(hex: 0xedc53f)
        case 2048: return Color(hex: 0xedc22e)
        default:   return Color(hex: 0x3c3a32)
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
                resultText = "Command failed — try again."
            }
        }
    }
}

struct Game2048SettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
            Text("Score target to reach")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.game2048Difficulty },
                set: { vm.setGame2048Difficulty($0) }
            )) {
                ForEach(Game2048Difficulty.allCases, id: \.self) { diff in
                    Text(diff.displayName).tag(diff)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct Game2048WizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Difficulty")
                    .font(.title2.weight(.semibold))
                Text("What score do you need to reach to unlock?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(Game2048Difficulty.allCases, id: \.self) { diff in
                    WizardOptionCard(
                        title: diff.rawValue.capitalized,
                        subtitle: diff.displayName,
                        selected: wizardState.game2048Difficulty == diff
                    ) {
                        wizardState.game2048Difficulty = diff
                    }
                }
            }
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
