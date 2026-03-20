import SwiftUI

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

    var displayName: String {
        switch self {
        case .small: return "Small (5×5, 4 flows)"
        case .medium: return "Medium (7×7, 6 flows)"
        case .large: return "Large (9×9, 8 flows)"
        }
    }
}

enum PipesChallenge {
    static let definition = PanicChallengeDefinition(
        id: "pipes",
        displayName: "Pipes",
        iconName: "point.topleft.down.to.point.bottomright.curvepath",
        shortDescription: "Connect all flows to unlock.",
        makeChallengeView: { onSuccess in
            AnyView(PipesPanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(PipesSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(PipesWizardConfigView())
        }
    )
}

struct PipesPanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        PipesPanicView(size: vm.pipesSize, onUnlock: onSuccess)
    }
}

private let flowColors: [Color] = [
    Color(red: 0.90, green: 0.22, blue: 0.21),
    Color(red: 0.13, green: 0.59, blue: 0.95),
    Color(red: 0.30, green: 0.69, blue: 0.31),
    Color(red: 1.00, green: 0.60, blue: 0.00),
    Color(red: 0.61, green: 0.15, blue: 0.69),
    Color(red: 1.00, green: 0.92, blue: 0.23),
    Color(red: 0.47, green: 0.33, blue: 0.28),
    Color(red: 0.00, green: 0.74, blue: 0.83),
]

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

    init(size: PipesSize) {
        self.gridSize = size.gridSize
        self.flowCount = size.flowCount
        self.grid = Array(repeating: Array(repeating: PipesCell(), count: size.gridSize), count: size.gridSize)
        self.paths = Array(repeating: [], count: size.flowCount)
        generatePuzzle()
    }

    func reset(size: PipesSize) {
        grid = Array(repeating: Array(repeating: PipesCell(), count: size.gridSize), count: size.gridSize)
        paths = Array(repeating: [], count: size.flowCount)
        endpoints = []
        activeFlow = nil
        won = false
        generatePuzzle()
    }

    // Fill the entire grid with flowCount paths via randomised flood-fill partitioning +
    // Hamiltonian path search per region. Only endpoints are shown to the player.

    private func generatePuzzle() {
        for _ in 0..<200 {
            if tryGenerate() { return }
        }
        generateFallback()
    }

    private func generateFallback() {
        let n = gridSize
        grid = Array(repeating: Array(repeating: PipesCell(), count: n), count: n)
        endpoints = []
        paths = []
        // Simple horizontal snaking paths that fill the grid
        var row = 0
        var col = 0
        var fi = 0
        let cellsPerFlow = (n * n) / flowCount
        var currentPath: [(Int, Int)] = []
        var goingRight = true

        for _ in 0..<(n * n) {
            currentPath.append((row, col))
            grid[row][col] = PipesCell(flowIndex: fi, isEndpoint: false)

            if currentPath.count >= cellsPerFlow && fi < flowCount - 1 {
                let start = currentPath.first!
                let end = currentPath.last!
                grid[start.0][start.1] = PipesCell(flowIndex: fi, isEndpoint: true)
                grid[end.0][end.1] = PipesCell(flowIndex: fi, isEndpoint: true)
                endpoints.append([start, end])
                paths.append([])
                fi += 1
                currentPath = []
            }

            // snake through the grid
            if goingRight {
                if col + 1 < n { col += 1 }
                else { row += 1; goingRight = false }
            } else {
                if col - 1 >= 0 { col -= 1 }
                else { row += 1; goingRight = true }
            }
        }
        // finish last flow
        if !currentPath.isEmpty {
            let start = currentPath.first!
            let end = currentPath.last!
            grid[start.0][start.1] = PipesCell(flowIndex: fi, isEndpoint: true)
            grid[end.0][end.1] = PipesCell(flowIndex: fi, isEndpoint: true)
            endpoints.append([start, end])
            paths.append([])
        }
        // pad if needed
        while endpoints.count < flowCount {
            endpoints.append([(0, 0), (0, 0)])
            paths.append([])
        }
        activeFlow = nil
        won = false
    }

    private func tryGenerate() -> Bool {
        let n = gridSize
        let totalCells = n * n

        var owner = Array(repeating: Array(repeating: -1, count: n), count: n)
        let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]

        var seeds: [(Int, Int)] = []
        var taken = Set<Int>()
        for fi in 0..<flowCount {
            var attempts = 0
            while attempts < 500 {
                let r = Int.random(in: 0..<n), c = Int.random(in: 0..<n)
                let key = r * n + c
                if !taken.contains(key) {
                    taken.insert(key)
                    seeds.append((r, c))
                    owner[r][c] = fi
                    break
                }
                attempts += 1
            }
            if seeds.count <= fi { return false }
        }

        var frontiers: [[(Int, Int)]] = seeds.map { [($0.0, $0.1)] }
        var assigned = flowCount

        while assigned < totalCells {
            var grew = false
            for fi in 0..<flowCount {
                frontiers[fi].shuffle()
                var nextFrontier: [(Int, Int)] = []
                for cell in frontiers[fi] {
                    var neighbors: [(Int, Int)] = []
                    for d in dirs {
                        let nr = cell.0 + d.0, nc = cell.1 + d.1
                        if nr >= 0, nr < n, nc >= 0, nc < n, owner[nr][nc] == -1 {
                            neighbors.append((nr, nc))
                        }
                    }
                    neighbors.shuffle()
                    for nb in neighbors {
                        if owner[nb.0][nb.1] == -1 {
                            owner[nb.0][nb.1] = fi
                            assigned += 1
                            nextFrontier.append(nb)
                            grew = true
                        }
                    }
                    let stillActive = dirs.contains { d in
                        let nr = cell.0 + d.0, nc = cell.1 + d.1
                        return nr >= 0 && nr < n && nc >= 0 && nc < n && owner[nr][nc] == -1
                    }
                    if stillActive { nextFrontier.append(cell) }
                }
                frontiers[fi] = nextFrontier
            }
            if !grew { return false } // stuck
        }

        var regionCells: [[(Int, Int)]] = Array(repeating: [], count: flowCount)
        for r in 0..<n {
            for c in 0..<n {
                let fi = owner[r][c]
                if fi >= 0 { regionCells[fi].append((r, c)) }
            }
        }
        for fi in 0..<flowCount {
            guard regionCells[fi].count >= 2 else { return false }
        }

        var generatedEndpoints: [[(Int, Int)]] = []

        for fi in 0..<flowCount {
            let cells = regionCells[fi]
            let cellSet = Set(cells.map { $0.0 * n + $0.1 })

            var found: [(Int, Int)]?
            var startCandidates = cells.shuffled()
            if startCandidates.count > 8 { startCandidates = Array(startCandidates.prefix(8)) }

            for start in startCandidates {
                if let path = hamiltonianPath(start: start, cellSet: cellSet, count: cells.count, gridSize: n) {
                    found = path
                    break
                }
            }
            guard let path = found else { return false }
            generatedEndpoints.append([path.first!, path.last!])
        }

        grid = Array(repeating: Array(repeating: PipesCell(), count: n), count: n)
        endpoints = generatedEndpoints
        paths = Array(repeating: [], count: flowCount)

        for (i, eps) in endpoints.enumerated() {
            for ep in eps {
                grid[ep.0][ep.1] = PipesCell(flowIndex: i, isEndpoint: true)
            }
        }

        activeFlow = nil
        won = false
        return true
    }

    private func hamiltonianPath(start: (Int, Int), cellSet: Set<Int>, count: Int, gridSize n: Int) -> [(Int, Int)]? {
        let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var path: [(Int, Int)] = [start]
        var visited = Set<Int>([start.0 * n + start.1])
        // Iterative max attempts to avoid deep recursion on large regions
        var backtrackBudget = count * count * 4

        func dfs() -> Bool {
            if path.count == count { return true }
            if backtrackBudget <= 0 { return false }
            let cur = path.last!
            // Sort neighbors by fewest onward moves (Warnsdorff's heuristic)
            var neighbors: [(Int, Int, Int)] = [] // (r, c, degree)
            for d in dirs {
                let nr = cur.0 + d.0, nc = cur.1 + d.1
                guard nr >= 0, nr < n, nc >= 0, nc < n else { continue }
                let key = nr * n + nc
                guard cellSet.contains(key), !visited.contains(key) else { continue }
                var deg = 0
                for d2 in dirs {
                    let nnr = nr + d2.0, nnc = nc + d2.1
                    guard nnr >= 0, nnr < n, nnc >= 0, nnc < n else { continue }
                    let nkey = nnr * n + nnc
                    if cellSet.contains(nkey) && !visited.contains(nkey) { deg += 1 }
                }
                neighbors.append((nr, nc, deg))
            }
            neighbors.sort { $0.2 < $1.2 }

            for (nr, nc, _) in neighbors {
                let key = nr * n + nc
                path.append((nr, nc))
                visited.insert(key)
                if dfs() { return true }
                path.removeLast()
                visited.remove(key)
                backtrackBudget -= 1
                if backtrackBudget <= 0 { return false }
            }
            return false
        }

        return dfs() ? path : nil
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

    private func isPathComplete(_ fi: Int) -> Bool {
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

    private func extendPath(fi: Int, row: Int, col: Int) {
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

    private func clearPath(_ fi: Int) {
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

    private func checkWin() {
        for fi in 0..<flowCount {
            guard paths[fi].count >= 2 else { return }
            let first = paths[fi].first!
            let last = paths[fi].last!
            let ep0 = endpoints[fi][0]
            let ep1 = endpoints[fi][1]
            let startsAtEndpoint = (first == ep0 || first == ep1)
            let endsAtEndpoint = (last == ep0 || last == ep1)
            let differentEndpoints = !(first == last)
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

private func == (_ lhs: (Int, Int), _ rhs: (Int, Int)) -> Bool {
    lhs.0 == rhs.0 && lhs.1 == rhs.1
}

struct PipesPanicView: View {
    let size: PipesSize
    let onUnlock: () async -> Bool

    @StateObject private var game: PipesGame
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var resultText = ""

    init(size: PipesSize, onUnlock: @escaping () async -> Bool) {
        self.size = size
        self.onUnlock = onUnlock
        _game = StateObject(wrappedValue: PipesGame(size: size))
    }

    private let cellSize: CGFloat = 44

    private static let bgDark = Color(red: 0.12, green: 0.12, blue: 0.14)
    private static let bgLight = Color(red: 0.15, green: 0.15, blue: 0.17)
    private static let gridLine = Color.white.opacity(0.08)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Pipes")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(size.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Draw paths connecting matching colored dots")
                    .foregroundColor(.secondary)
                Spacer()
                let completed = game.paths.enumerated().filter { fi, path in
                    guard path.count >= 2, fi < game.endpoints.count, game.endpoints[fi].count >= 2 else { return false }
                    let first = path.first!
                    let last = path.last!
                    let ep0 = game.endpoints[fi][0]
                    let ep1 = game.endpoints[fi][1]
                    return (first == ep0 || first == ep1) && (last == ep0 || last == ep1) && !(first == last)
                }.count
                Text("Flows: \(completed)/\(game.flowCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            let totalSize = cellSize * CGFloat(game.gridSize)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Self.bgDark)

                VStack(spacing: 0) {
                    ForEach(0..<game.gridSize, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<game.gridSize, id: \.self) { col in
                                cellView(row: row, col: col)
                            }
                        }
                    }
                }

                ForEach(0..<game.flowCount, id: \.self) { fi in
                    PipesPathShape(path: game.paths[fi], cellSize: cellSize)
                        .stroke(flowColors[fi % flowColors.count], style: StrokeStyle(lineWidth: cellSize * 0.35, lineCap: .round, lineJoin: .round))
                        .opacity(0.85)
                }
            }
            .frame(width: totalSize, height: totalSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let col = Int(value.location.x / cellSize)
                        let row = Int(value.location.y / cellSize)
                        game.handleDrag(row: row, col: col)
                    }
                    .onEnded { _ in
                        game.endDrag()
                    }
            )

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
                if !game.won {
                    Button("New Puzzle") {
                        game.reset(size: size)
                        resultText = ""
                    }
                }
            }
            .frame(height: 28)
        }
        .onChange(of: game.won) {
            if game.won {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    submitUnlock()
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(row: Int, col: Int) -> some View {
        let cell = game.grid[row][col]
        ZStack {
            Rectangle()
                .fill((row + col) % 2 == 0 ? Self.bgDark : Self.bgLight)
                .overlay(
                    Rectangle()
                        .stroke(Self.gridLine, lineWidth: 0.5)
                )

            if cell.isEndpoint, let fi = cell.flowIndex {
                Circle()
                    .fill(flowColors[fi % flowColors.count])
                    .frame(width: cellSize * 0.6, height: cellSize * 0.6)
            }
        }
        .frame(width: cellSize, height: cellSize)
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

struct PipesPathShape: Shape {
    let path: [(Int, Int)]
    let cellSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard path.count >= 2 else { return p }
        let half = cellSize / 2
        p.move(to: CGPoint(
            x: CGFloat(path[0].1) * cellSize + half,
            y: CGFloat(path[0].0) * cellSize + half
        ))
        for i in 1..<path.count {
            p.addLine(to: CGPoint(
                x: CGFloat(path[i].1) * cellSize + half,
                y: CGFloat(path[i].0) * cellSize + half
            ))
        }
        return p
    }
}

struct PipesSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grid Size")
            Text("Board dimensions and flow count")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.pipesSize },
                set: { vm.setPipesSize($0) }
            )) {
                ForEach(PipesSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct PipesWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grid Size")
                    .font(.title2.weight(.semibold))
                Text("How large should the Pipes board be?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(PipesSize.allCases, id: \.self) { size in
                    WizardOptionCard(
                        title: size.rawValue.capitalized,
                        subtitle: size.displayName,
                        selected: wizardState.pipesSize == size
                    ) {
                        wizardState.pipesSize = size
                    }
                }
            }
        }
    }
}
