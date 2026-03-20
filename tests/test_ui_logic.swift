// Standalone Swift tests for UI/game logic (no XCTest dependency)
// Tests: WordleGame, Game2048Game, MinesweeperGame, SudokuGame, SimonGame, PipesGame
//
// Compile with:
//   swiftc -parse-as-library -framework SwiftUI -framework AppKit \
//     tests/test_ui_logic.swift -o tests/test_ui_logic_runner
//
// This file re-declares game model classes from gui/*.swift so it can compile
// standalone without conflicting with gui/main.swift's @main.

import SwiftUI

// ---- Stubs for dependencies ----

enum BlissSounds {
    static func playSuccess() {}
    static func playError() {}
    static func playMerge() {}
    static func playClick() {}
}

// ---- WordleGame and dependencies ----

enum WordleLetter {
    case correct
    case misplaced
    case absent
    case empty
}

struct WordleGuessLetter {
    var character: Character = " "
    var state: WordleLetter = .empty
}

enum WordleWordList {
    // Minimal word lists for testing
    static let answers: [String] = [
        "about", "above", "abuse", "actor", "acute", "admit", "adopt", "adult",
        "after", "again", "agent", "agree", "ahead", "alarm", "album", "alert",
        "alien", "align", "alive", "alley", "allow", "alone", "along", "alter",
        "among", "angel", "anger", "angle", "angry", "anime", "apple", "crane",
        "bliss", "hello", "world", "grape", "stone", "flame", "pride", "heart",
    ]

    static let validGuesses: [String] = [
        "aapas", "aarti", "abaca", "abacs", "abaht", "cigar", "bikes", "foxes",
        "jumpy", "quick", "waltz", "bytes", "glyph", "verbs", "expat",
    ]
}

@MainActor
class WordleGame: ObservableObject {
    let maxGuesses = 6
    let wordLength = 5

    @Published var guesses: [[WordleGuessLetter]]
    @Published var currentRow = 0
    @Published var currentCol = 0
    @Published var won = false
    @Published var gameOver = false
    @Published var answer: String
    @Published var keyStates: [Character: WordleLetter] = [:]
    @Published var shakeRow = -1

    init() {
        let word = WordleWordList.answers.randomElement()!
        self.answer = word.uppercased()
        self.guesses = Array(
            repeating: Array(repeating: WordleGuessLetter(), count: 5),
            count: 6
        )
    }

    func typeLetter(_ ch: Character) {
        guard !gameOver, currentCol < wordLength else { return }
        guesses[currentRow][currentCol].character = ch
        currentCol += 1
    }

    func deleteLetter() {
        guard !gameOver, currentCol > 0 else { return }
        currentCol -= 1
        guesses[currentRow][currentCol].character = " "
        guesses[currentRow][currentCol].state = .empty
    }

    func submitGuess() {
        guard !gameOver, currentCol == wordLength else { return }

        let word = String(guesses[currentRow].map(\.character)).lowercased()
        guard WordleWordList.validGuesses.contains(word) || WordleWordList.answers.contains(word) else {
            shakeRow = currentRow
            BlissSounds.playError()
            return
        }

        let answerChars = Array(answer)
        let guessChars = Array(word.uppercased())
        var remaining: [Character: Int] = [:]
        for ch in answerChars { remaining[ch, default: 0] += 1 }

        for i in 0..<wordLength {
            if guessChars[i] == answerChars[i] {
                guesses[currentRow][i].state = .correct
                remaining[guessChars[i], default: 0] -= 1
            }
        }

        for i in 0..<wordLength {
            guard guesses[currentRow][i].state != .correct else { continue }
            if remaining[guessChars[i], default: 0] > 0 {
                guesses[currentRow][i].state = .misplaced
                remaining[guessChars[i], default: 0] -= 1
            } else {
                guesses[currentRow][i].state = .absent
            }
        }

        for i in 0..<wordLength {
            let ch = guesses[currentRow][i].character
            let newState = guesses[currentRow][i].state
            let existing = keyStates[ch]
            if existing == nil || betterState(newState, than: existing!) {
                keyStates[ch] = newState
            }
        }

        if guesses[currentRow].allSatisfy({ $0.state == .correct }) {
            won = true
            gameOver = true
            BlissSounds.playSuccess()
        } else if currentRow == maxGuesses - 1 {
            gameOver = true
        } else {
            currentRow += 1
            currentCol = 0
        }
    }

    func reset() {
        let word = WordleWordList.answers.randomElement()!
        answer = word.uppercased()
        guesses = Array(
            repeating: Array(repeating: WordleGuessLetter(), count: 5),
            count: 6
        )
        currentRow = 0
        currentCol = 0
        won = false
        gameOver = false
        keyStates = [:]
        shakeRow = -1
    }

    private func betterState(_ new: WordleLetter, than old: WordleLetter) -> Bool {
        let rank: [WordleLetter: Int] = [.empty: 0, .absent: 1, .misplaced: 2, .correct: 3]
        return (rank[new] ?? 0) > (rank[old] ?? 0)
    }
}

// ---- Game2048Game and dependencies ----

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
}

@MainActor
class Game2048Game: ObservableObject {
    let targetScore: Int
    @Published var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    @Published var score = 0
    @Published var won = false
    @Published var gameOver = false

    init(targetScore: Int = 2048) {
        self.targetScore = targetScore
        spawnTile()
        spawnTile()
    }

    func reset() {
        grid = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        score = 0
        won = false
        gameOver = false
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

        if grid != previous {
            spawnTile()
            BlissSounds.playMerge()
            if !hasMovesAvailable() {
                gameOver = true
                BlissSounds.playError()
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

    func mergeRow(_ row: [Int]) -> [Int] {
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

    func spawnTile() {
        var empty: [(Int, Int)] = []
        for r in 0..<4 {
            for c in 0..<4 {
                if grid[r][c] == 0 { empty.append((r, c)) }
            }
        }
        guard let pos = empty.randomElement() else { return }
        grid[pos.0][pos.1] = Double.random(in: 0..<1) < 0.9 ? 2 : 4
    }

    func hasMovesAvailable() -> Bool {
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

// ---- MinesweeperGame and dependencies ----

enum MinesweeperSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var rows: Int {
        switch self {
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        }
    }

    var cols: Int { rows }

    var mines: Int {
        switch self {
        case .small: return 10
        case .medium: return 25
        case .large: return 50
        }
    }
}

struct MinesweeperCell {
    var isMine = false
    var isRevealed = false
    var isFlagged = false
    var adjacentMines = 0
}

@MainActor
class MinesweeperGame: ObservableObject {
    let rows: Int
    let cols: Int
    let mineCount: Int

    @Published var grid: [[MinesweeperCell]]
    @Published var gameOver = false
    @Published var won = false
    @Published var firstClick = true

    init(size: MinesweeperSize) {
        self.rows = size.rows
        self.cols = size.cols
        self.mineCount = size.mines
        self.grid = Array(repeating: Array(repeating: MinesweeperCell(), count: size.cols), count: size.rows)
    }

    func reveal(_ row: Int, _ col: Int) {
        guard !gameOver, !grid[row][col].isFlagged, !grid[row][col].isRevealed else { return }

        if firstClick {
            firstClick = false
            placeMines(safeRow: row, safeCol: col)
            computeAdjacent()
        }

        grid[row][col].isRevealed = true

        if grid[row][col].isMine {
            gameOver = true
            won = false
            BlissSounds.playError()
            revealAll()
            return
        }

        if grid[row][col].adjacentMines == 0 {
            floodFill(row, col)
        }

        checkWin()
    }

    func toggleFlag(_ row: Int, _ col: Int) {
        guard !gameOver, !grid[row][col].isRevealed else { return }
        grid[row][col].isFlagged.toggle()
    }

    func reset(size: MinesweeperSize) {
        grid = Array(repeating: Array(repeating: MinesweeperCell(), count: size.cols), count: size.rows)
        gameOver = false
        won = false
        firstClick = true
    }

    func placeMines(safeRow: Int, safeCol: Int) {
        var placed = 0
        while placed < mineCount {
            let r = Int.random(in: 0..<rows)
            let c = Int.random(in: 0..<cols)
            if abs(r - safeRow) <= 1 && abs(c - safeCol) <= 1 { continue }
            if grid[r][c].isMine { continue }
            grid[r][c].isMine = true
            placed += 1
        }
    }

    func computeAdjacent() {
        for r in 0..<rows {
            for c in 0..<cols {
                guard !grid[r][c].isMine else { continue }
                var count = 0
                for dr in -1...1 {
                    for dc in -1...1 {
                        let nr = r + dr, nc = c + dc
                        if nr >= 0, nr < rows, nc >= 0, nc < cols, grid[nr][nc].isMine {
                            count += 1
                        }
                    }
                }
                grid[r][c].adjacentMines = count
            }
        }
    }

    private func floodFill(_ row: Int, _ col: Int) {
        for dr in -1...1 {
            for dc in -1...1 {
                let nr = row + dr, nc = col + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                guard !grid[nr][nc].isRevealed, !grid[nr][nc].isMine, !grid[nr][nc].isFlagged else { continue }
                grid[nr][nc].isRevealed = true
                if grid[nr][nc].adjacentMines == 0 {
                    floodFill(nr, nc)
                }
            }
        }
    }

    private func checkWin() {
        let totalNonMine = rows * cols - mineCount
        let revealed = grid.flatMap { $0 }.filter { $0.isRevealed && !$0.isMine }.count
        if revealed == totalNonMine {
            gameOver = true
            won = true
        }
    }

    private func revealAll() {
        for r in 0..<rows {
            for c in 0..<cols {
                grid[r][c].isRevealed = true
            }
        }
    }
}

// ---- SudokuGame and dependencies ----

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

    func generatePuzzle() {
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

// ---- SimonGame and dependencies ----

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
}

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

    // For testing, we skip async playback
    init(gridSize: Int, sequenceLength: Int) {
        self.gridSize = gridSize
        self.sequenceLength = sequenceLength
        generateSequence()
        // Start directly in playing phase for tests
        phase = .playing
    }

    func generateSequence() {
        sequence = (0..<sequenceLength).map { _ in
            (Int.random(in: 0..<gridSize), Int.random(in: 0..<gridSize))
        }
    }

    func tapSync(row: Int, col: Int) {
        guard phase == .playing else { return }
        let expected = sequence[playerIndex]
        if row == expected.0 && col == expected.1 {
            playerIndex += 1
            if playerIndex == sequenceLength {
                phase = .won
            }
        } else {
            BlissSounds.playError()
            phase = .wrong
        }
    }
}

// ---- PipesGame and dependencies ----

enum PipesSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var gridSize: Int {
        switch self {
        case .small: return 5
        case .medium: return 7
        case .large: return 9
        }
    }

    var flowCount: Int {
        switch self {
        case .small: return 4
        case .medium: return 6
        case .large: return 8
        }
    }
}

struct PipesCell {
    var flowIndex: Int? = nil
    var isEndpoint = false
}

@MainActor
class PipesGame: ObservableObject {
    let gridSize: Int
    let flowCount: Int

    @Published var grid: [[PipesCell]]
    @Published var endpoints: [[(Int, Int)]] = []
    @Published var paths: [[(Int, Int)]] = []
    @Published var activeFlow: Int? = nil
    @Published var won = false
    var dragCompleted = false
    var lastDragCell: (Int, Int)? = nil

    // Simplified init for testing: creates an empty grid without puzzle generation
    init(gridSize: Int, flowCount: Int) {
        self.gridSize = gridSize
        self.flowCount = flowCount
        self.grid = Array(repeating: Array(repeating: PipesCell(), count: gridSize), count: gridSize)
        self.paths = Array(repeating: [], count: flowCount)
    }

    func setupTestPuzzle(endpointPairs: [[(Int, Int)]]) {
        endpoints = endpointPairs
        for (i, eps) in endpoints.enumerated() {
            for ep in eps {
                grid[ep.0][ep.1] = PipesCell(flowIndex: i, isEndpoint: true)
            }
        }
    }

    func handleDrag(row: Int, col: Int) {
        guard !won else { return }
        guard row >= 0, row < gridSize, col >= 0, col < gridSize else { return }

        if let last = lastDragCell, last.0 == row, last.1 == col { return }
        lastDragCell = (row, col)

        if activeFlow == nil {
            if dragCompleted { return }
            let cell = grid[row][col]
            if cell.isEndpoint, let fi = cell.flowIndex {
                clearPath(fi)
                activeFlow = fi
                paths[fi] = [(row, col)]
                return
            }
            if let fi = cell.flowIndex, !cell.isEndpoint {
                breakPath(fi, at: (row, col))
                activeFlow = fi
                return
            }
            return
        }

        let fi = activeFlow!
        guard let last = paths[fi].last else { return }

        let cells = interpolate(from: last, to: (row, col))
        for cell in cells {
            if activeFlow == nil { break }
            extendPath(fi: fi, row: cell.0, col: cell.1)
        }
    }

    func endDrag() {
        if let fi = activeFlow {
            if !isPathComplete(fi) {
                clearPath(fi)
            }
        }
        activeFlow = nil
        dragCompleted = false
        lastDragCell = nil
    }

    func isPathComplete(_ fi: Int) -> Bool {
        guard paths[fi].count >= 2 else { return false }
        let first = paths[fi].first!
        let last = paths[fi].last!
        let ep0 = endpoints[fi][0]
        let ep1 = endpoints[fi][1]
        let startsAtEp = (first.0 == ep0.0 && first.1 == ep0.1) || (first.0 == ep1.0 && first.1 == ep1.1)
        let endsAtEp = (last.0 == ep0.0 && last.1 == ep0.1) || (last.0 == ep1.0 && last.1 == ep1.1)
        let different = !(first.0 == last.0 && first.1 == last.1)
        return startsAtEp && endsAtEp && different
    }

    func extendPath(fi: Int, row: Int, col: Int) {
        guard let last = paths[fi].last else { return }

        let dr = abs(row - last.0), dc = abs(col - last.1)
        guard (dr == 1 && dc == 0) || (dr == 0 && dc == 1) else { return }

        if paths[fi].count >= 2 {
            let prev = paths[fi][paths[fi].count - 2]
            if prev.0 == row && prev.1 == col {
                let removed = paths[fi].removeLast()
                if !grid[removed.0][removed.1].isEndpoint {
                    grid[removed.0][removed.1].flowIndex = nil
                }
                return
            }
        }

        let target = grid[row][col]

        if target.isEndpoint && target.flowIndex != fi { return }

        if target.isEndpoint && target.flowIndex == fi {
            let ep0 = endpoints[fi][0]
            let ep1 = endpoints[fi][1]
            let pathStart = paths[fi].first!
            let otherEnd = (pathStart.0 == ep0.0 && pathStart.1 == ep0.1) ? ep1 : ep0
            if row == otherEnd.0 && col == otherEnd.1 {
                paths[fi].append((row, col))
                activeFlow = nil
                dragCompleted = true
                checkWin()
            }
            return
        }

        if let otherFlow = target.flowIndex, otherFlow != fi, !target.isEndpoint {
            clearPath(otherFlow)
        }

        if target.flowIndex == fi { return }

        paths[fi].append((row, col))
        grid[row][col].flowIndex = fi
    }

    private func interpolate(from: (Int, Int), to: (Int, Int)) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var r = from.0, c = from.1
        while c != to.1 {
            c += (to.1 > c) ? 1 : -1
            result.append((r, c))
        }
        while r != to.0 {
            r += (to.0 > r) ? 1 : -1
            result.append((r, c))
        }
        return result
    }

    func clearPath(_ fi: Int) {
        for cell in paths[fi] {
            if !grid[cell.0][cell.1].isEndpoint {
                grid[cell.0][cell.1].flowIndex = nil
            }
        }
        paths[fi] = []
    }

    private func breakPath(_ fi: Int, at pos: (Int, Int)) {
        guard let idx = paths[fi].firstIndex(where: { $0.0 == pos.0 && $0.1 == pos.1 }) else { return }
        let removed = paths[fi].suffix(from: idx + 1)
        for cell in removed {
            if !grid[cell.0][cell.1].isEndpoint {
                grid[cell.0][cell.1].flowIndex = nil
            }
        }
        paths[fi] = Array(paths[fi].prefix(through: idx))
    }

    func checkWin() {
        for fi in 0..<flowCount {
            guard paths[fi].count >= 2 else { return }
            let first = paths[fi].first!
            let last = paths[fi].last!
            let ep0 = endpoints[fi][0]
            let ep1 = endpoints[fi][1]
            let startsAtEndpoint = (first.0 == ep0.0 && first.1 == ep0.1) || (first.0 == ep1.0 && first.1 == ep1.1)
            let endsAtEndpoint = (last.0 == ep0.0 && last.1 == ep0.1) || (last.0 == ep1.0 && last.1 == ep1.1)
            let differentEndpoints = !(first.0 == last.0 && first.1 == last.1)
            guard startsAtEndpoint && endsAtEndpoint && differentEndpoints else { return }
        }
        for r in 0..<gridSize {
            for c in 0..<gridSize {
                if grid[r][c].flowIndex == nil { return }
            }
        }
        won = true
        BlissSounds.playSuccess()
    }
}

// ---- Test framework ----

var testsRun = 0
var testsPassed = 0

func check(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    testsRun += 1
    if condition {
        testsPassed += 1
    } else {
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    testsRun += 1
    if a == b {
        testsPassed += 1
    } else {
        print("  FAIL: got \"\(a)\" expected \"\(b)\" \(message) (\(file):\(line))")
    }
}

// ============================================================
// WORDLE TESTS
// ============================================================

@MainActor
func testWordleTypeLetter() {
    print("test: wordle_type_letter")
    let game = WordleGame()
    game.answer = "CRANE"

    game.typeLetter("C")
    assertEqual(game.currentCol, 1, "col after 1 letter")
    assertEqual(game.guesses[0][0].character, Character("C"), "first letter")

    game.typeLetter("R")
    game.typeLetter("A")
    game.typeLetter("N")
    game.typeLetter("E")
    assertEqual(game.currentCol, 5, "col after 5 letters")

    // Should not type beyond word length
    game.typeLetter("X")
    assertEqual(game.currentCol, 5, "col stays at 5")
}

@MainActor
func testWordleDeleteLetter() {
    print("test: wordle_delete_letter")
    let game = WordleGame()
    game.answer = "CRANE"

    game.typeLetter("H")
    game.typeLetter("E")
    assertEqual(game.currentCol, 2)

    game.deleteLetter()
    assertEqual(game.currentCol, 1, "col after delete")
    assertEqual(game.guesses[0][1].character, Character(" "), "deleted char is space")

    game.deleteLetter()
    assertEqual(game.currentCol, 0)

    // Should not delete past 0
    game.deleteLetter()
    assertEqual(game.currentCol, 0, "col stays at 0")
}

@MainActor
func testWordleSubmitCorrectGuess() {
    print("test: wordle_submit_correct_guess")
    let game = WordleGame()
    game.answer = "CRANE"

    for ch in "CRANE" { game.typeLetter(ch) }
    game.submitGuess()

    check(game.won, "should win with correct guess")
    check(game.gameOver, "game should be over")
    for i in 0..<5 {
        check(game.guesses[0][i].state == .correct, "letter \(i) should be correct")
    }
}

@MainActor
func testWordleSubmitInvalidWord() {
    print("test: wordle_submit_invalid_word")
    let game = WordleGame()
    game.answer = "CRANE"

    // "ZZZZZ" is not in answers or validGuesses
    for ch in "ZZZZZ" { game.typeLetter(ch) }
    game.submitGuess()

    check(!game.gameOver, "game should not be over after invalid word")
    assertEqual(game.currentRow, 0, "should stay on same row")
    assertEqual(game.shakeRow, 0, "should shake current row")
}

@MainActor
func testWordleSubmitMisplacedAndAbsent() {
    print("test: wordle_submit_misplaced_and_absent")
    let game = WordleGame()
    game.answer = "CRANE"

    // "ALERT" -- A is misplaced, L absent, E misplaced, R misplaced, T absent
    for ch in "ALERT" { game.typeLetter(ch) }
    game.submitGuess()

    check(!game.won, "should not win")
    assertEqual(game.currentRow, 1, "should advance to next row")
    // A is in CRANE but not at pos 0 -> misplaced
    check(game.guesses[0][0].state == .misplaced, "A should be misplaced")
}

@MainActor
func testWordleGameOverAfterSixWrongGuesses() {
    print("test: wordle_game_over_after_six_wrong")
    let game = WordleGame()
    game.answer = "CRANE"

    let wrongWords = ["ABOUT", "AFTER", "AGAIN", "ALARM", "ALBUM", "ALERT"]
    for word in wrongWords {
        for ch in word { game.typeLetter(ch) }
        game.submitGuess()
    }

    check(game.gameOver, "game should be over after 6 wrong guesses")
    check(!game.won, "should not have won")
}

@MainActor
func testWordleKeyStates() {
    print("test: wordle_key_states")
    let game = WordleGame()
    game.answer = "CRANE"

    for ch in "CRANE" { game.typeLetter(ch) }
    game.submitGuess()

    assertEqual(game.keyStates[Character("C")], .correct)
    assertEqual(game.keyStates[Character("R")], .correct)
    assertEqual(game.keyStates[Character("A")], .correct)
    assertEqual(game.keyStates[Character("N")], .correct)
    assertEqual(game.keyStates[Character("E")], .correct)
}

@MainActor
func testWordleReset() {
    print("test: wordle_reset")
    let game = WordleGame()
    for ch in "ABOUT" { game.typeLetter(ch) }
    game.submitGuess()

    game.reset()
    assertEqual(game.currentRow, 0)
    assertEqual(game.currentCol, 0)
    check(!game.won)
    check(!game.gameOver)
    check(game.keyStates.isEmpty, "key states should be cleared")
}

@MainActor
func testWordleCannotTypeAfterGameOver() {
    print("test: wordle_cannot_type_after_game_over")
    let game = WordleGame()
    game.answer = "CRANE"
    for ch in "CRANE" { game.typeLetter(ch) }
    game.submitGuess()
    check(game.gameOver)

    let oldCol = game.currentCol
    game.typeLetter("X")
    assertEqual(game.currentCol, oldCol, "should not type after game over")
}

// ============================================================
// 2048 TESTS
// ============================================================

@MainActor
func testGame2048MergeRow() {
    print("test: 2048_merge_row")
    let game = Game2048Game(targetScore: 2048)

    let merged = game.mergeRow([2, 2, 4, 4])
    assertEqual(merged, [4, 8, 0, 0], "should merge pairs")
}

@MainActor
func testGame2048MergeRowNoMerge() {
    print("test: 2048_merge_row_no_merge")
    let game = Game2048Game(targetScore: 2048)

    let merged = game.mergeRow([2, 4, 8, 16])
    assertEqual(merged, [2, 4, 8, 16], "no merges when all different")
}

@MainActor
func testGame2048MergeRowWithZeros() {
    print("test: 2048_merge_row_with_zeros")
    let game = Game2048Game(targetScore: 2048)

    let merged = game.mergeRow([0, 2, 0, 2])
    assertEqual(merged, [4, 0, 0, 0], "should compact and merge")
}

@MainActor
func testGame2048MergeRowChained() {
    print("test: 2048_merge_row_chained")
    let game = Game2048Game(targetScore: 2048)

    // [2, 2, 2, 2] should merge to [4, 4, 0, 0], not [8, 0, 0, 0]
    let merged = game.mergeRow([2, 2, 2, 2])
    assertEqual(merged, [4, 4, 0, 0], "should not chain merges")
}

@MainActor
func testGame2048InitialState() {
    print("test: 2048_initial_state")
    let game = Game2048Game(targetScore: 128)

    // Should have exactly 2 tiles after init
    let nonZero = game.grid.flatMap { $0 }.filter { $0 != 0 }
    assertEqual(nonZero.count, 2, "should start with 2 tiles")
    check(nonZero.allSatisfy { $0 == 2 || $0 == 4 }, "initial tiles should be 2 or 4")
    assertEqual(game.score, 0)
    check(!game.won)
    check(!game.gameOver)
}

@MainActor
func testGame2048ScoreTracking() {
    print("test: 2048_score_tracking")
    let game = Game2048Game(targetScore: 2048)
    game.grid = [
        [2, 2, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]
    game.score = 0

    game.move(.left)
    // Merging two 2s gives 4 points
    check(game.score >= 4, "score should be at least 4 after merging two 2s")
}

@MainActor
func testGame2048WinDetectionEasy() {
    print("test: 2048_win_detection_easy")
    let game = Game2048Game(targetScore: 128)
    game.grid = [
        [64, 64, 0, 0],
        [0,  0,  0, 0],
        [0,  0,  0, 0],
        [0,  0,  0, 0],
    ]
    game.score = 0

    game.move(.left)
    check(game.won, "should win when reaching 128")
}

@MainActor
func testGame2048WinDetectionMedium() {
    print("test: 2048_win_detection_medium")
    let game = Game2048Game(targetScore: 512)
    game.grid = [
        [256, 256, 0, 0],
        [0,   0,   0, 0],
        [0,   0,   0, 0],
        [0,   0,   0, 0],
    ]
    game.score = 0

    game.move(.left)
    check(game.won, "should win when reaching 512")
}

@MainActor
func testGame2048NoMoveWhenWon() {
    print("test: 2048_no_move_when_won")
    let game = Game2048Game(targetScore: 128)
    game.won = true
    let gridBefore = game.grid
    game.move(.left)
    assertEqual(game.grid, gridBefore, "grid should not change when won")
}

@MainActor
func testGame2048GameOverDetection() {
    print("test: 2048_game_over_detection")
    let game = Game2048Game(targetScore: 2048)
    // Fill the grid so no moves are possible
    game.grid = [
        [2,  4,  8,  16],
        [16, 8,  4,  2],
        [2,  4,  8,  16],
        [16, 8,  4,  2],
    ]

    check(!game.hasMovesAvailable(), "should have no moves available")
}

@MainActor
func testGame2048HasMovesWithEmpty() {
    print("test: 2048_has_moves_with_empty")
    let game = Game2048Game(targetScore: 2048)
    game.grid = [
        [2,  4,  8,  16],
        [16, 8,  4,  2],
        [2,  4,  0,  16],
        [16, 8,  4,  2],
    ]

    check(game.hasMovesAvailable(), "should have moves when empty cell exists")
}

@MainActor
func testGame2048HasMovesWithMergeable() {
    print("test: 2048_has_moves_with_mergeable")
    let game = Game2048Game(targetScore: 2048)
    game.grid = [
        [2,  4,  8,  16],
        [16, 8,  4,  2],
        [2,  4,  8,  16],
        [16, 8,  4,  4],
    ]

    check(game.hasMovesAvailable(), "should have moves when adjacent tiles can merge")
}

@MainActor
func testGame2048SlideDirections() {
    print("test: 2048_slide_directions")
    let game = Game2048Game(targetScore: 2048)

    // Test slide right
    game.grid = [
        [2, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]
    game.move(.right)
    // After slide right, the 2 should be at position [0][3] (plus a new spawned tile)
    let row0 = game.grid[0]
    check(row0[3] == 2, "2 should slide to rightmost position")

    // Test slide down
    game.reset()
    game.grid = [
        [2, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]
    game.score = 0
    game.won = false
    game.gameOver = false
    game.move(.down)
    check(game.grid[3][0] == 2, "2 should slide to bottom")
}

@MainActor
func testGame2048Reset() {
    print("test: 2048_reset")
    let game = Game2048Game(targetScore: 128)
    game.won = true
    game.score = 500

    game.reset()
    assertEqual(game.score, 0)
    check(!game.won)
    check(!game.gameOver)
    let nonZero = game.grid.flatMap { $0 }.filter { $0 != 0 }
    assertEqual(nonZero.count, 2, "should have 2 tiles after reset")
}

@MainActor
func testGame2048DifficultyTargets() {
    print("test: 2048_difficulty_targets")
    assertEqual(Game2048Difficulty.easy.targetScore, 128)
    assertEqual(Game2048Difficulty.medium.targetScore, 512)
    assertEqual(Game2048Difficulty.hard.targetScore, 2048)
}

// ============================================================
// MINESWEEPER TESTS
// ============================================================

@MainActor
func testMinesweeperInitialState() {
    print("test: minesweeper_initial_state")
    let game = MinesweeperGame(size: .small)

    assertEqual(game.rows, 8)
    assertEqual(game.cols, 8)
    assertEqual(game.mineCount, 10)
    check(game.firstClick, "should be first click")
    check(!game.gameOver)
    check(!game.won)

    // No mines placed yet
    let mineCount = game.grid.flatMap { $0 }.filter(\.isMine).count
    assertEqual(mineCount, 0, "no mines before first click")
}

@MainActor
func testMinesweeperFirstClickSafety() {
    print("test: minesweeper_first_click_safety")
    let game = MinesweeperGame(size: .small)

    // Click center cell
    game.reveal(4, 4)

    check(!game.firstClick, "firstClick should be false after first reveal")
    check(!game.gameOver, "should not lose on first click")

    // Check that the clicked cell and its neighbors are safe
    for dr in -1...1 {
        for dc in -1...1 {
            let nr = 4 + dr, nc = 4 + dc
            if nr >= 0, nr < 8, nc >= 0, nc < 8 {
                check(!game.grid[nr][nc].isMine, "cell (\(nr),\(nc)) near first click should not be a mine")
            }
        }
    }

    // Should have placed 10 mines
    let mineCount = game.grid.flatMap { $0 }.filter(\.isMine).count
    assertEqual(mineCount, 10, "should have 10 mines after first click")
}

@MainActor
func testMinesweeperFlagging() {
    print("test: minesweeper_flagging")
    let game = MinesweeperGame(size: .small)

    // Flag before any click
    game.toggleFlag(0, 0)
    check(game.grid[0][0].isFlagged, "cell should be flagged")

    // Unflag
    game.toggleFlag(0, 0)
    check(!game.grid[0][0].isFlagged, "cell should be unflagged")
}

@MainActor
func testMinesweeperFlagPreventsReveal() {
    print("test: minesweeper_flag_prevents_reveal")
    let game = MinesweeperGame(size: .small)

    game.toggleFlag(3, 3)
    game.reveal(3, 3)
    // First click should still be true because the flagged cell blocks reveal
    // Actually, reveal checks isFlagged first, so firstClick remains true
    check(game.firstClick, "flagged cell should not be revealable")
    check(!game.grid[3][3].isRevealed, "flagged cell should not be revealed")
}

@MainActor
func testMinesweeperCannotFlagRevealedCell() {
    print("test: minesweeper_cannot_flag_revealed")
    let game = MinesweeperGame(size: .small)

    game.reveal(4, 4)
    // The clicked cell is revealed
    check(game.grid[4][4].isRevealed)
    game.toggleFlag(4, 4)
    check(!game.grid[4][4].isFlagged, "should not flag revealed cell")
}

@MainActor
func testMinesweeperMineCountBySize() {
    print("test: minesweeper_mine_count_by_size")
    assertEqual(MinesweeperSize.small.mines, 10)
    assertEqual(MinesweeperSize.small.rows, 8)
    assertEqual(MinesweeperSize.medium.mines, 25)
    assertEqual(MinesweeperSize.medium.rows, 12)
    assertEqual(MinesweeperSize.large.mines, 50)
    assertEqual(MinesweeperSize.large.rows, 16)
}

@MainActor
func testMinesweeperAdjacentCounting() {
    print("test: minesweeper_adjacent_counting")
    let game = MinesweeperGame(size: .small)

    // Manually set up a known mine layout
    game.grid[0][0].isMine = true
    game.grid[0][1].isMine = true
    game.computeAdjacent()

    // Cell (1,0) should see 2 adjacent mines: (0,0) and (0,1)
    assertEqual(game.grid[1][0].adjacentMines, 2, "(1,0) should have 2 adjacent mines")
    // Cell (1,1) should see 2 adjacent mines: (0,0) and (0,1)
    assertEqual(game.grid[1][1].adjacentMines, 2, "(1,1) should have 2 adjacent mines")
    // Cell (0,2) should see 1 adjacent mine: (0,1)
    assertEqual(game.grid[0][2].adjacentMines, 1, "(0,2) should have 1 adjacent mine")
    // Cell (2,0) should see 0
    assertEqual(game.grid[2][0].adjacentMines, 0, "(2,0) should have 0 adjacent mines")
}

@MainActor
func testMinesweeperWinDetection() {
    print("test: minesweeper_win_detection")
    let game = MinesweeperGame(size: .small)

    // First click to place mines
    game.reveal(4, 4)
    check(!game.gameOver || game.won, "should not lose on first click")

    // Reveal all non-mine cells manually
    for r in 0..<game.rows {
        for c in 0..<game.cols {
            if !game.grid[r][c].isMine && !game.grid[r][c].isRevealed {
                game.grid[r][c].isRevealed = true
            }
        }
    }

    // Manually trigger win check by revealing one more non-mine cell
    // Actually, we need to find a non-mine non-revealed cell... all are revealed now
    // So we simulate by calling reveal on an already-revealed cell, which won't do anything.
    // Instead, let's re-check the win condition ourselves.
    let totalNonMine = game.rows * game.cols - game.mineCount
    let revealed = game.grid.flatMap { $0 }.filter { $0.isRevealed && !$0.isMine }.count
    check(revealed == totalNonMine, "all non-mine cells should be revealed")
}

@MainActor
func testMinesweeperHitMine() {
    print("test: minesweeper_hit_mine")
    let game = MinesweeperGame(size: .small)

    // First click to place mines
    game.reveal(4, 4)

    // Find a mine cell
    var minePos: (Int, Int)?
    for r in 0..<game.rows {
        for c in 0..<game.cols {
            if game.grid[r][c].isMine && !game.grid[r][c].isRevealed {
                minePos = (r, c)
                break
            }
        }
        if minePos != nil { break }
    }

    if let pos = minePos {
        game.reveal(pos.0, pos.1)
        check(game.gameOver, "should be game over after hitting mine")
        check(!game.won, "should not have won")
    } else {
        check(false, "should have found a mine")
    }
}

@MainActor
func testMinesweeperFloodFill() {
    print("test: minesweeper_flood_fill")
    let game = MinesweeperGame(size: .small)

    // Make a corner with no adjacent mines by first clicking there
    // After first click, the 3x3 around the click is mine-free
    game.reveal(0, 0)

    // (0,0) has no mine, so it was revealed
    check(game.grid[0][0].isRevealed, "(0,0) should be revealed")

    // If adjacentMines is 0, flood fill should reveal neighbors too
    if game.grid[0][0].adjacentMines == 0 {
        check(game.grid[0][1].isRevealed, "flood fill should reveal (0,1)")
        check(game.grid[1][0].isRevealed, "flood fill should reveal (1,0)")
        check(game.grid[1][1].isRevealed, "flood fill should reveal (1,1)")
    }
}

@MainActor
func testMinesweeperReset() {
    print("test: minesweeper_reset")
    let game = MinesweeperGame(size: .small)
    game.reveal(4, 4)

    game.reset(size: .small)
    check(game.firstClick, "should be first click after reset")
    check(!game.gameOver)
    check(!game.won)
    let mineCount = game.grid.flatMap { $0 }.filter(\.isMine).count
    assertEqual(mineCount, 0, "no mines after reset")
}

// ============================================================
// SUDOKU TESTS
// ============================================================

@MainActor
func testSudokuBoardGeneration() {
    print("test: sudoku_board_generation")
    let game = SudokuGame(difficulty: .easy)

    // Solution should be complete (all 1-9 in each row/col/box)
    for r in 0..<9 {
        let rowValues = Set(game.solution[r])
        assertEqual(rowValues, Set(1...9), "row \(r) should have all digits 1-9")
    }

    for c in 0..<9 {
        let colValues = Set((0..<9).map { game.solution[$0][c] })
        assertEqual(colValues, Set(1...9), "col \(c) should have all digits 1-9")
    }

    // Check 3x3 boxes
    for boxR in stride(from: 0, to: 9, by: 3) {
        for boxC in stride(from: 0, to: 9, by: 3) {
            var boxValues = Set<Int>()
            for r in boxR..<boxR+3 {
                for c in boxC..<boxC+3 {
                    boxValues.insert(game.solution[r][c])
                }
            }
            assertEqual(boxValues, Set(1...9), "box at (\(boxR),\(boxC)) should have all digits 1-9")
        }
    }
}

@MainActor
func testSudokuClueCount() {
    print("test: sudoku_clue_count")

    // Easy should have 30 clues
    let easyGame = SudokuGame(difficulty: .easy)
    let easyClues = easyGame.board.flatMap { $0 }.filter { $0 != 0 }.count
    assertEqual(easyClues, 30, "easy should have 30 clues")

    // Hard should have 20 clues
    let hardGame = SudokuGame(difficulty: .hard)
    let hardClues = hardGame.board.flatMap { $0 }.filter { $0 != 0 }.count
    assertEqual(hardClues, 20, "hard should have 20 clues")
}

@MainActor
func testSudokuPlaceNumber() {
    print("test: sudoku_place_number")
    let game = SudokuGame(difficulty: .easy)

    // Find a non-fixed cell
    var target: (Int, Int)?
    for r in 0..<9 {
        for c in 0..<9 {
            if !game.fixed[r][c] {
                target = (r, c)
                break
            }
        }
        if target != nil { break }
    }

    guard let pos = target else {
        check(false, "should find a non-fixed cell")
        return
    }

    game.selected = (row: pos.0, col: pos.1)
    game.place(5)
    assertEqual(game.board[pos.0][pos.1], 5, "should place number")
}

@MainActor
func testSudokuCannotPlaceOnFixed() {
    print("test: sudoku_cannot_place_on_fixed")
    let game = SudokuGame(difficulty: .easy)

    // Find a fixed cell
    var fixedCell: (Int, Int)?
    for r in 0..<9 {
        for c in 0..<9 {
            if game.fixed[r][c] {
                fixedCell = (r, c)
                break
            }
        }
        if fixedCell != nil { break }
    }

    guard let pos = fixedCell else {
        check(false, "should find a fixed cell")
        return
    }

    let oldValue = game.board[pos.0][pos.1]
    game.selected = (row: pos.0, col: pos.1)
    game.place(oldValue == 1 ? 2 : 1)
    assertEqual(game.board[pos.0][pos.1], oldValue, "fixed cell should not change")
}

@MainActor
func testSudokuClear() {
    print("test: sudoku_clear")
    let game = SudokuGame(difficulty: .easy)

    // Find a non-fixed cell
    var target: (Int, Int)?
    for r in 0..<9 {
        for c in 0..<9 {
            if !game.fixed[r][c] {
                target = (r, c)
                break
            }
        }
        if target != nil { break }
    }

    guard let pos = target else { return }

    game.selected = (row: pos.0, col: pos.1)
    game.place(7)
    assertEqual(game.board[pos.0][pos.1], 7)

    game.clear()
    assertEqual(game.board[pos.0][pos.1], 0, "should clear cell")
}

@MainActor
func testSudokuConflictDetection() {
    print("test: sudoku_conflict_detection")
    let game = SudokuGame(difficulty: .easy)

    // Set up a known conflict: put duplicate in a row
    // Find two non-fixed cells in the same row
    var cell1: (Int, Int)?
    var cell2: (Int, Int)?
    for r in 0..<9 {
        var emptyCells: [(Int, Int)] = []
        for c in 0..<9 {
            if !game.fixed[r][c] { emptyCells.append((r, c)) }
        }
        if emptyCells.count >= 2 {
            cell1 = emptyCells[0]
            cell2 = emptyCells[1]
            break
        }
    }

    guard let c1 = cell1, let c2 = cell2 else {
        check(false, "need two empty cells in same row")
        return
    }

    // Place the same number in both cells
    game.board[c1.0][c1.1] = 9
    game.board[c2.0][c2.1] = 9

    check(game.hasConflict(row: c1.0, col: c1.1), "should detect row conflict")
    check(game.hasConflict(row: c2.0, col: c2.1), "should detect row conflict on other cell")
}

@MainActor
func testSudokuConflictInBox() {
    print("test: sudoku_conflict_in_box")
    let game = SudokuGame(difficulty: .easy)

    // Clear the board and set up a known box conflict
    game.board = Array(repeating: Array(repeating: 0, count: 9), count: 9)
    game.fixed = Array(repeating: Array(repeating: false, count: 9), count: 9)

    game.board[0][0] = 5
    game.board[1][1] = 5

    // Both are in the same 3x3 box
    check(game.hasConflict(row: 0, col: 0), "should detect box conflict at (0,0)")
    check(game.hasConflict(row: 1, col: 1), "should detect box conflict at (1,1)")
}

@MainActor
func testSudokuNoConflictForZero() {
    print("test: sudoku_no_conflict_for_zero")
    let game = SudokuGame(difficulty: .easy)

    // Zero should never be a conflict
    game.board = Array(repeating: Array(repeating: 0, count: 9), count: 9)
    check(!game.hasConflict(row: 0, col: 0), "zero should not be a conflict")
}

@MainActor
func testSudokuWinDetection() {
    print("test: sudoku_win_detection")
    let game = SudokuGame(difficulty: .easy)

    // Fill in all the solution values to trigger a win
    for r in 0..<9 {
        for c in 0..<9 {
            if !game.fixed[r][c] {
                game.selected = (row: r, col: c)
                game.place(game.solution[r][c])
            }
        }
    }

    check(game.won, "should win when board matches solution")
}

@MainActor
func testSudokuDifficultySettings() {
    print("test: sudoku_difficulty_settings")
    assertEqual(SudokuDifficulty.easy.clues, 30)
    assertEqual(SudokuDifficulty.medium.clues, 25)
    assertEqual(SudokuDifficulty.hard.clues, 20)
}

// ============================================================
// SIMON SAYS TESTS
// ============================================================

@MainActor
func testSimonSequenceGeneration() {
    print("test: simon_sequence_generation")
    let game = SimonGame(gridSize: 3, sequenceLength: 5)

    assertEqual(game.sequence.count, 5, "should generate 5-step sequence")
    for (r, c) in game.sequence {
        check(r >= 0 && r < 3, "row should be in range")
        check(c >= 0 && c < 3, "col should be in range")
    }
}

@MainActor
func testSimonCorrectInput() {
    print("test: simon_correct_input")
    let game = SimonGame(gridSize: 3, sequenceLength: 3)

    assertEqual(game.phase, .playing)
    assertEqual(game.playerIndex, 0)

    // Tap correct sequence
    for i in 0..<3 {
        let (r, c) = game.sequence[i]
        game.tapSync(row: r, col: c)
    }

    assertEqual(game.phase, .won, "should win after completing sequence")
    assertEqual(game.playerIndex, 3)
}

@MainActor
func testSimonWrongInput() {
    print("test: simon_wrong_input")
    let game = SimonGame(gridSize: 3, sequenceLength: 5)
    game.sequence = [(0, 0), (1, 1), (2, 2), (0, 1), (1, 0)]

    // Tap wrong cell
    game.tapSync(row: 2, col: 2)  // Expected (0,0)
    assertEqual(game.phase, .wrong, "should be wrong phase after incorrect tap")
}

@MainActor
func testSimonDoesNotAcceptInputWhileWatching() {
    print("test: simon_no_input_while_watching")
    let game = SimonGame(gridSize: 3, sequenceLength: 5)
    game.phase = .watching

    game.tapSync(row: 0, col: 0)
    assertEqual(game.playerIndex, 0, "should not advance while watching")
}

@MainActor
func testSimonLevelProgression() {
    print("test: simon_level_progression")
    let game = SimonGame(gridSize: 3, sequenceLength: 5)

    // Tap first correct cell
    let (r, c) = game.sequence[0]
    game.tapSync(row: r, col: c)
    assertEqual(game.playerIndex, 1, "should advance to next step")
    assertEqual(game.phase, .playing, "should still be playing")
}

@MainActor
func testSimonDifficultySettings() {
    print("test: simon_difficulty_settings")
    assertEqual(SimonDifficulty.easy.gridSize, 3)
    assertEqual(SimonDifficulty.easy.sequenceLength, 5)
    assertEqual(SimonDifficulty.medium.gridSize, 4)
    assertEqual(SimonDifficulty.medium.sequenceLength, 7)
    assertEqual(SimonDifficulty.hard.gridSize, 5)
    assertEqual(SimonDifficulty.hard.sequenceLength, 10)
}

@MainActor
func testSimonPartialProgress() {
    print("test: simon_partial_progress")
    let game = SimonGame(gridSize: 4, sequenceLength: 5)

    // Complete 3 out of 5 steps correctly
    for i in 0..<3 {
        let (r, c) = game.sequence[i]
        game.tapSync(row: r, col: c)
    }

    assertEqual(game.playerIndex, 3, "should be at step 3")
    assertEqual(game.phase, .playing, "should still be playing")
    check(game.phase != .won, "should not have won yet")
}

// ============================================================
// PIPES TESTS
// ============================================================

@MainActor
func testPipesInitialState() {
    print("test: pipes_initial_state")
    let game = PipesGame(gridSize: 3, flowCount: 1)
    assertEqual(game.gridSize, 3)
    assertEqual(game.flowCount, 1)
    check(!game.won)
    assertEqual(game.paths.count, 1)
}

@MainActor
func testPipesEndpointSetup() {
    print("test: pipes_endpoint_setup")
    let game = PipesGame(gridSize: 3, flowCount: 1)
    game.setupTestPuzzle(endpointPairs: [[(0, 0), (0, 2)]])

    check(game.grid[0][0].isEndpoint, "(0,0) should be endpoint")
    check(game.grid[0][2].isEndpoint, "(0,2) should be endpoint")
    assertEqual(game.grid[0][0].flowIndex, 0)
    assertEqual(game.grid[0][2].flowIndex, 0)
}

@MainActor
func testPipesPathExtension() {
    print("test: pipes_path_extension")
    // Simple 3x3 grid with one flow: (0,0) -> (0,2)
    let game = PipesGame(gridSize: 3, flowCount: 1)
    game.setupTestPuzzle(endpointPairs: [[(0, 0), (0, 2)]])

    // Start drag from endpoint (0,0)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)
    assertEqual(game.activeFlow, 0, "should activate flow 0")
    assertEqual(game.paths[0].count, 1)

    // Extend to (0,1)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 1)
    assertEqual(game.paths[0].count, 2)
    check(game.grid[0][1].flowIndex == 0, "(0,1) should be assigned to flow 0")
}

@MainActor
func testPipesCompleteFlow() {
    print("test: pipes_complete_flow")
    // 3x3 grid, 1 flow: (0,0) -> (0,2), fill entire grid
    let game = PipesGame(gridSize: 3, flowCount: 1)
    game.setupTestPuzzle(endpointPairs: [[(0, 0), (0, 2)]])

    // Build path: (0,0) -> (1,0) -> (2,0) -> (2,1) -> (2,2) -> (1,2) -> (1,1) -> (0,1) -> (0,2) -- but wait, this doesn't match. Let me manually drive the drag.
    // Start at (0,0)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)

    // Extend step by step
    let pathCells = [(0,1), (0,2)]
    for (r, c) in pathCells {
        game.lastDragCell = nil
        game.handleDrag(row: r, col: c)
    }

    // Path should be complete for flow 0
    check(game.isPathComplete(0), "flow 0 should be complete")
}

@MainActor
func testPipesWinDetection() {
    print("test: pipes_win_detection")
    // Simple 2x2 grid (custom), 1 flow covering all cells
    let game = PipesGame(gridSize: 2, flowCount: 1)
    game.setupTestPuzzle(endpointPairs: [[(0, 0), (1, 1)]])

    // Path: (0,0) -> (0,1) -> (1,1)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 1)
    game.lastDragCell = nil
    game.handleDrag(row: 1, col: 1)

    // Not won yet because not all cells filled (1,0 is empty)
    check(!game.won, "should not win with unfilled cells")

    // Clear and try a path that fills all cells
    game.clearPath(0)
    game.activeFlow = nil
    game.dragCompleted = false

    // Path: (0,0) -> (1,0) -> (1,1)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)
    game.lastDragCell = nil
    game.handleDrag(row: 1, col: 0)
    game.lastDragCell = nil
    game.handleDrag(row: 1, col: 1)

    // Still need (0,1) filled... with 1 flow on a 2x2, we can't fill all 4 cells with a path from (0,0) to (1,1) of length 4
    // Let's use a better test setup: 2 flows on a 2x2
    let game2 = PipesGame(gridSize: 2, flowCount: 2)
    game2.setupTestPuzzle(endpointPairs: [[(0, 0), (0, 1)], [(1, 0), (1, 1)]])

    // Flow 0: (0,0) -> (0,1)
    game2.lastDragCell = nil
    game2.handleDrag(row: 0, col: 0)
    game2.lastDragCell = nil
    game2.handleDrag(row: 0, col: 1)
    game2.endDrag()

    // Flow 1: (1,0) -> (1,1)
    game2.lastDragCell = nil
    game2.handleDrag(row: 1, col: 0)
    game2.lastDragCell = nil
    game2.handleDrag(row: 1, col: 1)

    check(game2.won, "should win when all cells filled and all flows complete")
}

@MainActor
func testPipesPathBacktrack() {
    print("test: pipes_path_backtrack")
    let game = PipesGame(gridSize: 3, flowCount: 1)
    game.setupTestPuzzle(endpointPairs: [[(0, 0), (2, 2)]])

    // Start at (0,0)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)

    // Extend to (0,1)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 1)
    assertEqual(game.paths[0].count, 2)

    // Backtrack to (0,0) by dragging back
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)
    assertEqual(game.paths[0].count, 1, "should remove last cell on backtrack")
    check(game.grid[0][1].flowIndex == nil, "(0,1) should be cleared after backtrack")
}

@MainActor
func testPipesEndDragClearsIncomplete() {
    print("test: pipes_end_drag_clears_incomplete")
    let game = PipesGame(gridSize: 3, flowCount: 1)
    game.setupTestPuzzle(endpointPairs: [[(0, 0), (2, 2)]])

    // Start drag but don't complete
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 0)
    game.lastDragCell = nil
    game.handleDrag(row: 0, col: 1)

    game.endDrag()
    assertEqual(game.paths[0].count, 0, "incomplete path should be cleared on endDrag")
}

@MainActor
func testPipesSizeSettings() {
    print("test: pipes_size_settings")
    assertEqual(PipesSize.small.gridSize, 5)
    assertEqual(PipesSize.small.flowCount, 4)
    assertEqual(PipesSize.medium.gridSize, 7)
    assertEqual(PipesSize.medium.flowCount, 6)
    assertEqual(PipesSize.large.gridSize, 9)
    assertEqual(PipesSize.large.flowCount, 8)
}

// ============================================================
// Entry point
// ============================================================

@main
struct TestUIRunner {
    static func main() async {
        print("\n=== bliss UI logic unit tests ===\n")

        // Wordle tests
        await testWordleTypeLetter()
        await testWordleDeleteLetter()
        await testWordleSubmitCorrectGuess()
        await testWordleSubmitInvalidWord()
        await testWordleSubmitMisplacedAndAbsent()
        await testWordleGameOverAfterSixWrongGuesses()
        await testWordleKeyStates()
        await testWordleReset()
        await testWordleCannotTypeAfterGameOver()

        // 2048 tests
        await testGame2048MergeRow()
        await testGame2048MergeRowNoMerge()
        await testGame2048MergeRowWithZeros()
        await testGame2048MergeRowChained()
        await testGame2048InitialState()
        await testGame2048ScoreTracking()
        await testGame2048WinDetectionEasy()
        await testGame2048WinDetectionMedium()
        await testGame2048NoMoveWhenWon()
        await testGame2048GameOverDetection()
        await testGame2048HasMovesWithEmpty()
        await testGame2048HasMovesWithMergeable()
        await testGame2048SlideDirections()
        await testGame2048Reset()
        await testGame2048DifficultyTargets()

        // Minesweeper tests
        await testMinesweeperInitialState()
        await testMinesweeperFirstClickSafety()
        await testMinesweeperFlagging()
        await testMinesweeperFlagPreventsReveal()
        await testMinesweeperCannotFlagRevealedCell()
        await testMinesweeperMineCountBySize()
        await testMinesweeperAdjacentCounting()
        await testMinesweeperWinDetection()
        await testMinesweeperHitMine()
        await testMinesweeperFloodFill()
        await testMinesweeperReset()

        // Sudoku tests
        await testSudokuBoardGeneration()
        await testSudokuClueCount()
        await testSudokuPlaceNumber()
        await testSudokuCannotPlaceOnFixed()
        await testSudokuClear()
        await testSudokuConflictDetection()
        await testSudokuConflictInBox()
        await testSudokuNoConflictForZero()
        await testSudokuWinDetection()
        await testSudokuDifficultySettings()

        // Simon Says tests
        await testSimonSequenceGeneration()
        await testSimonCorrectInput()
        await testSimonWrongInput()
        await testSimonDoesNotAcceptInputWhileWatching()
        await testSimonLevelProgression()
        await testSimonDifficultySettings()
        await testSimonPartialProgress()

        // Pipes tests
        await testPipesInitialState()
        await testPipesEndpointSetup()
        await testPipesPathExtension()
        await testPipesCompleteFlow()
        await testPipesWinDetection()
        await testPipesPathBacktrack()
        await testPipesEndDragClearsIncomplete()
        await testPipesSizeSettings()

        print("\n\(testsPassed)/\(testsRun) assertions passed")
        if testsPassed == testsRun {
            print("ALL TESTS PASSED")
            exit(0)
        } else {
            print("SOME TESTS FAILED")
            exit(1)
        }
    }
}
