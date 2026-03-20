import SwiftUI

enum SudokuDifficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"

    var clues: Int {
        switch self {
        case .easy: return 30
        case .medium: return 25
        case .hard: return 20
        }
    }

    var displayName: String {
        switch self {
        case .easy: return "Easy (30 clues)"
        case .medium: return "Medium (25 clues)"
        case .hard: return "Hard (20 clues)"
        }
    }
}

enum SudokuChallenge {
    static let definition = PanicChallengeDefinition(
        id: "sudoku",
        displayName: "Sudoku",
        iconName: "number.square",
        shortDescription: "Solve a Sudoku puzzle to unlock.",
        makeChallengeView: { onSuccess in
            AnyView(SudokuPanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(SudokuSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(SudokuWizardConfigView())
        }
    )
}

struct SudokuPanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        SudokuPanicView(difficulty: vm.sudokuDifficulty, onUnlock: onSuccess)
    }
}

@MainActor
class SudokuGame: ObservableObject {
    let difficulty: SudokuDifficulty

    @Published var board: [[Int]]
    @Published var solution: [[Int]]
    @Published var fixed: [[Bool]]
    @Published var selected: (row: Int, col: Int)?
    @Published var won = false

    init(difficulty: SudokuDifficulty) {
        self.difficulty = difficulty
        self.board = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        self.solution = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        self.fixed = Array(repeating: Array(repeating: false, count: 9), count: 9)
        generatePuzzle()
    }

    func place(_ number: Int) {
        guard let sel = selected, !fixed[sel.row][sel.col], !won else { return }
        board[sel.row][sel.col] = number
        checkWin()
    }

    func clear() {
        guard let sel = selected, !fixed[sel.row][sel.col], !won else { return }
        board[sel.row][sel.col] = 0
    }

    func reset() {
        won = false
        selected = nil
        generatePuzzle()
    }

    func hasConflict(row: Int, col: Int) -> Bool {
        let value = board[row][col]
        guard value != 0 else { return false }

        for c in 0..<9 where c != col && board[row][c] == value { return true }
        for r in 0..<9 where r != row && board[r][col] == value { return true }

        let boxR = (row / 3) * 3
        let boxC = (col / 3) * 3
        for r in boxR..<boxR+3 {
            for c in boxC..<boxC+3 {
                if r != row || c != col {
                    if board[r][c] == value { return true }
                }
            }
        }
        return false
    }

    private func checkWin() {
        for r in 0..<9 {
            for c in 0..<9 {
                if board[r][c] != solution[r][c] { return }
            }
        }
        won = true
        BlissSounds.playSuccess()
    }

    private func generatePuzzle() {
        var grid = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        _ = fillBoard(&grid, pos: 0)
        solution = grid
        board = grid

        var positions = (0..<81).map { ($0 / 9, $0 % 9) }
        positions.shuffle()

        let toRemove = 81 - difficulty.clues
        for i in 0..<toRemove {
            let (r, c) = positions[i]
            board[r][c] = 0
        }

        fixed = (0..<9).map { r in
            (0..<9).map { c in board[r][c] != 0 }
        }
    }

    private func fillBoard(_ grid: inout [[Int]], pos: Int) -> Bool {
        if pos == 81 { return true }
        let row = pos / 9
        let col = pos % 9

        var numbers = Array(1...9)
        numbers.shuffle()

        for num in numbers {
            if isValid(grid, row: row, col: col, num: num) {
                grid[row][col] = num
                if fillBoard(&grid, pos: pos + 1) { return true }
                grid[row][col] = 0
            }
        }
        return false
    }

    private func isValid(_ grid: [[Int]], row: Int, col: Int, num: Int) -> Bool {
        for c in 0..<9 where grid[row][c] == num { return false }
        for r in 0..<9 where grid[r][col] == num { return false }

        let boxR = (row / 3) * 3
        let boxC = (col / 3) * 3
        for r in boxR..<boxR+3 {
            for c in boxC..<boxC+3 {
                if grid[r][c] == num { return false }
            }
        }
        return true
    }
}

struct SudokuPanicView: View {
    let difficulty: SudokuDifficulty
    let onUnlock: () async -> Bool

    @StateObject private var game: SudokuGame
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var resultText = ""

    init(difficulty: SudokuDifficulty, onUnlock: @escaping () async -> Bool) {
        self.difficulty = difficulty
        self.onUnlock = onUnlock
        _game = StateObject(wrappedValue: SudokuGame(difficulty: difficulty))
    }

    private let cellSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sudoku")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(difficulty.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Click a cell, then type 1\u{2013}9. Backspace to clear.")
                    .foregroundColor(.secondary)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { col in
                            cellView(row: row, col: col)
                                .border(Color.black.opacity(0.15), width: 0.5)
                                .overlay(alignment: .trailing) {
                                    if col == 2 || col == 5 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.4))
                                            .frame(width: 1.5)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if row == 2 || row == 5 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.4))
                                            .frame(height: 1.5)
                                    }
                                }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.4), lineWidth: 2)
            )
            .focusable()
            .onKeyPress { keyPress in
                if let digit = Int(keyPress.characters), (1...9).contains(digit) {
                    game.place(digit)
                    return .handled
                }
                if keyPress.key == .delete {
                    game.clear()
                    return .handled
                }
                return .ignored
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
                }
                Spacer()
                Button("New Puzzle") {
                    game.reset()
                    resultText = ""
                }
            }
            .frame(height: 28)
        }
        .onChange(of: game.won) {
            if game.won { submitUnlock() }
        }
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        let value = game.board[row][col]
        let isSelected = game.selected?.row == row && game.selected?.col == col
        let conflict = game.hasConflict(row: row, col: col)

        ZStack {
            if isSelected {
                Color.accentColor.opacity(0.15)
            } else {
                Color.clear
            }

            if value != 0 {
                Text("\(value)")
                    .font(.system(size: cellSize * 0.5, weight: game.fixed[row][col] ? .bold : .regular, design: .rounded))
                    .foregroundColor(conflict ? .red : .primary)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !game.won else { return }
            game.selected = (row, col)
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

struct SudokuSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
            Text("Number of pre-filled clues")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.sudokuDifficulty },
                set: { vm.setSudokuDifficulty($0) }
            )) {
                ForEach(SudokuDifficulty.allCases, id: \.self) { diff in
                    Text(diff.displayName).tag(diff)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SudokuWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Difficulty")
                    .font(.title2.weight(.semibold))
                Text("How many clues should the Sudoku puzzle start with?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(SudokuDifficulty.allCases, id: \.self) { diff in
                    WizardOptionCard(
                        title: diff.rawValue.capitalized,
                        subtitle: diff.displayName,
                        selected: wizardState.sudokuDifficulty == diff
                    ) {
                        wizardState.sudokuDifficulty = diff
                    }
                }
            }
        }
    }
}
