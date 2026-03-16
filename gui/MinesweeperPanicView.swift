import SwiftUI

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

    var displayName: String {
        switch self {
        case .small: return "Small (8\u{00D7}8, 10 mines)"
        case .medium: return "Medium (12\u{00D7}12, 25 mines)"
        case .large: return "Large (16\u{00D7}16, 50 mines)"
        }
    }
}

enum MinesweeperChallenge {
    static let definition = PanicChallengeDefinition(
        id: "minesweeper",
        displayName: "Minesweeper",
        iconName: "square.grid.3x3.topleft.filled",
        shortDescription: "Win a game of Minesweeper to unlock.",
        makeChallengeView: { onSuccess in
            AnyView(MinesweeperPanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(MinesweeperSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(MinesweeperWizardConfigView())
        }
    )
}

struct MinesweeperPanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        MinesweeperPanicView(size: vm.minesweeperSize, onUnlock: onSuccess)
    }
}

// MARK: - Game Model

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

    private func placeMines(safeRow: Int, safeCol: Int) {
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

    private func computeAdjacent() {
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

// MARK: - View

struct MinesweeperPanicView: View {
    let size: MinesweeperSize
    let onUnlock: () async -> Bool

    @StateObject private var game: MinesweeperGame
    @State private var isSubmitting = false
    @State private var resultText = ""

    init(size: MinesweeperSize, onUnlock: @escaping () async -> Bool) {
        self.size = size
        self.onUnlock = onUnlock
        _game = StateObject(wrappedValue: MinesweeperGame(size: size))
    }

    private let cellSize: CGFloat = 28

    // Google Minesweeper-style palette
    private static let grassLight = Color(red: 0.667, green: 0.827, blue: 0.447)   // #AAD371
    private static let grassDark  = Color(red: 0.639, green: 0.804, blue: 0.416)    // #A3CD6A
    private static let dirtLight  = Color(red: 0.886, green: 0.827, blue: 0.725)    // #E2D3B9
    private static let dirtDark   = Color(red: 0.847, green: 0.784, blue: 0.675)    // #D8C8AC

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Minesweeper")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(size.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Left click to dig & right click to flag")
                    .foregroundColor(.secondary)
                Spacer()
                let flagCount = game.grid.flatMap { $0 }.filter(\.isFlagged).count
                Text("Flags: \(flagCount)/\(game.mineCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // Grid
            VStack(spacing: 0) {
                ForEach(0..<game.rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<game.cols, id: \.self) { col in
                            cellView(row: row, col: col)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Fixed-height status bar so layout doesn't jump
            HStack {
                if game.gameOver {
                    if game.won {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        }
                        Button("Unlock Session") {
                            submitUnlock()
                        }
                        .disabled(isSubmitting)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("You hit a mine!")
                            .foregroundColor(.red)
                        Spacer()
                        Button("Try Again") {
                            game.reset(size: size)
                            resultText = ""
                        }
                    }
                } else if !resultText.isEmpty {
                    Text(resultText)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
            }
            .frame(height: 28)
        }
    }

    private func grassColor(row: Int, col: Int) -> Color {
        (row + col) % 2 == 0 ? Self.grassLight : Self.grassDark
    }

    private func dirtColor(row: Int, col: Int) -> Color {
        (row + col) % 2 == 0 ? Self.dirtLight : Self.dirtDark
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        let cell = game.grid[row][col]
        ZStack {
            if cell.isRevealed {
                if cell.isMine {
                    Color.red.opacity(0.75)
                } else {
                    dirtColor(row: row, col: col)
                }

                if !cell.isMine && cell.adjacentMines > 0 {
                    Text("\(cell.adjacentMines)")
                        .font(.system(size: cellSize * 0.52, weight: .bold, design: .rounded))
                        .foregroundColor(numberColor(cell.adjacentMines))
                }
            } else {
                // Unrevealed — green grass checkerboard
                grassColor(row: row, col: col)

                if cell.isFlagged {
                    Image(systemName: "flag.fill")
                        .font(.system(size: cellSize * 0.4))
                        .foregroundColor(.red)
                }
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .onCellClick(
            left: {
                guard !game.gameOver, !cell.isRevealed else { return }
                game.reveal(row, col)
            },
            right: {
                guard !game.gameOver, !cell.isRevealed else { return }
                game.toggleFlag(row, col)
            }
        )
    }

    private func numberColor(_ n: Int) -> Color {
        switch n {
        case 1: return Color(red: 0.10, green: 0.46, blue: 0.82)  // blue
        case 2: return Color(red: 0.22, green: 0.56, blue: 0.24)  // green
        case 3: return Color(red: 0.83, green: 0.18, blue: 0.18)  // red
        case 4: return Color(red: 0.46, green: 0.16, blue: 0.71)  // purple
        case 5: return Color(red: 0.60, green: 0.34, blue: 0.14)  // brown
        case 6: return Color(red: 0.00, green: 0.60, blue: 0.60)  // teal
        case 7: return Color(red: 0.20, green: 0.20, blue: 0.20)  // dark gray
        case 8: return Color(red: 0.50, green: 0.50, blue: 0.50)  // gray
        default: return .primary
        }
    }

    private func submitUnlock() {
        isSubmitting = true
        Task {
            let ok = await onUnlock()
            isSubmitting = false
            if !ok {
                resultText = "Panic command failed. Session is still active."
            }
        }
    }
}

// Combined left+right click handler via NSView overlay
private struct CellClickModifier: ViewModifier {
    let left: () -> Void
    let right: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            CellClickOverlay(left: left, right: right)
        }
    }
}

private struct CellClickOverlay: NSViewRepresentable {
    let left: () -> Void
    let right: () -> Void

    func makeNSView(context: Context) -> CellClickNSView {
        let view = CellClickNSView()
        view.leftAction = left
        view.rightAction = right
        return view
    }

    func updateNSView(_ nsView: CellClickNSView, context: Context) {
        nsView.leftAction = left
        nsView.rightAction = right
    }
}

private class CellClickNSView: NSView {
    var leftAction: (() -> Void)?
    var rightAction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        leftAction?()
    }

    override func rightMouseDown(with event: NSEvent) {
        rightAction?()
    }
}

private extension View {
    func onCellClick(left: @escaping () -> Void, right: @escaping () -> Void) -> some View {
        modifier(CellClickModifier(left: left, right: right))
    }
}

// MARK: - Settings

struct MinesweeperSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grid Size")
                Text("Board dimensions and mine count")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { vm.minesweeperSize },
                set: { vm.setMinesweeperSize($0) }
            )) {
                ForEach(MinesweeperSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 250, alignment: .trailing)
        }
    }
}

// MARK: - Wizard Config

struct MinesweeperWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grid Size")
                    .font(.title2.weight(.semibold))
                Text("How large should the Minesweeper board be?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(MinesweeperSize.allCases, id: \.self) { size in
                    wizardOptionCard(
                        size.rawValue.capitalized,
                        subtitle: size.displayName,
                        selected: wizardState.minesweeperSize == size
                    ) {
                        wizardState.minesweeperSize = size
                    }
                }
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
