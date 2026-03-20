import Foundation
import SwiftUI


struct BlissProfile: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var websites: [String]
    var apps: [String]      // raw app entries
    var browsers: [String]
    var panicMode: String
    var quoteLength: String
    var colorName: String = "blue"

    static let availableColors: [(name: String, color: Color)] = [
        ("blue", .blue), ("purple", .purple), ("indigo", .indigo),
        ("pink", .pink), ("red", .red), ("orange", .orange),
        ("yellow", .yellow), ("green", .green), ("mint", .mint),
        ("cyan", .cyan), ("teal", .teal),
    ]

    var color: Color {
        Self.availableColors.first { $0.name == colorName }?.color ?? .blue
    }
}

extension BlissProfile {
    // Custom decoding so existing profiles without colorName still load
    enum CodingKeys: String, CodingKey {
        case name, websites, apps, browsers, panicMode, quoteLength, colorName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        websites = try c.decode([String].self, forKey: .websites)
        apps = try c.decode([String].self, forKey: .apps)
        browsers = try c.decode([String].self, forKey: .browsers)
        panicMode = try c.decode(String.self, forKey: .panicMode)
        quoteLength = try c.decode(String.self, forKey: .quoteLength)
        colorName = (try? c.decode(String.self, forKey: .colorName)) ?? "blue"
    }
}

enum BlissProfileManager {
    private static func profilesDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/profiles", isDirectory: true)
    }

    private static func activeURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/active_profile.txt")
    }

    static func listProfiles() -> [BlissProfile] {
        let dir = profilesDir()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> BlissProfile? in
                guard let data = try? Data(contentsOf: url),
                      let p = try? JSONDecoder().decode(BlissProfile.self, from: data) else { return nil }
                return p
            }
            .sorted { $0.name < $1.name }
    }

    static func save(_ profile: BlissProfile) {
        let dir = profilesDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(profile.name).json")
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: url)
    }

    static func delete(name: String) {
        let url = profilesDir().appendingPathComponent("\(name).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func activeProfileName() -> String? {
        guard let raw = try? String(contentsOf: activeURL(), encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setActiveProfile(_ name: String?) {
        let url = activeURL()
        if let name = name {
            try? (name + "\n").data(using: .utf8)?.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func ensureDefaultConfig() {
        guard listProfiles().isEmpty else { return }
        let defaultProfile = BlissProfile(
            name: "Default",
            websites: ["youtube.com", "twitter.com", "reddit.com", "instagram.com", "tiktok.com", "facebook.com"],
            apps: [],
            browsers: [],
            panicMode: "typing",
            quoteLength: "medium"
        )
        save(defaultProfile)
    }
}

enum CPDifficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
}

struct AppEntryModel: Identifiable, Hashable {
    let raw: String
    let name: String
    let bundle: String
    let path: String

    var id: String { raw }
}

@MainActor
final class BlissViewModel: ObservableObject {
    @Published var statusText = "status: unknown"
    @Published var remainingText = "remaining: -"
    @Published var pfText = "pf table active: -"
    @Published var minutesInput = "25"
    @Published var websites: [String] = []
    @Published var apps: [AppEntryModel] = []
    @Published var browsers: [String] = []
    @Published var websiteInput = ""
    @Published var quoteLength = "medium"
    @Published var panicMode: String = "typing"
    @Published var cpDifficulty: CPDifficulty = .easy
    @Published var minesweeperSize: MinesweeperSize = .small
    @Published var pipesSize: PipesSize = .small
    @Published var sudokuDifficulty: SudokuDifficulty = .easy
    @Published var simonDifficulty: SimonDifficulty = .easy
    @Published var game2048Difficulty: Game2048Difficulty = .easy
    @Published var wordleDifficulty: WordleDifficulty = .easy
    @Published var stats = SessionStats(totalSessions: 0, totalFocusMinutes: 0, currentStreak: 0, longestStreak: 0, lastSessionDate: nil)
    @Published var dailyMinutes: [String: Int] = [:]
    @Published var profiles: [BlissProfile] = []
    @Published var activeProfileName: String?
    @Published var schedules: [BlissScheduleEntry] = []
    private var lastTriggeredScheduleID: UUID?
    private var lastTriggeredMinute: Int = -1

    var currentChallenge: PanicChallengeDefinition? {
        PanicChallengeRegistry.find(panicMode)
    }
    @Published var output = ""
    @Published var errorMessage: String?
    @Published var dismissSheets = false
    @Published var isSessionActive = false
    @Published var endTimeEpoch: Int64?

    private var refreshTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
        tickerTask?.cancel()
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                syncQuoteLengthFromConfig()
                await refreshStatusAsync()
                checkScheduledSessions()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        startTicker()
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        tickerTask?.cancel()
        tickerTask = nil
    }

    func refreshAll() {
        syncQuoteLengthFromConfig()
        syncPanicModeFromConfig()
        syncCPDifficultyFromConfig()
        syncMinesweeperSizeFromConfig()
        syncPipesSizeFromConfig()
        syncSudokuDifficultyFromConfig()
        syncSimonDifficultyFromConfig()
        syncGame2048DifficultyFromConfig()
        syncWordleDifficultyFromConfig()

        stats = SessionStatsManager.load()
        dailyMinutes = SessionStatsManager.dailyMinutes()
        loadProfiles()
        schedules = BlissScheduleManager.load()
        Task {
            await refreshStatusAsync()
            if isSessionActive {
                return
            }
            await refreshWebsitesAsync()
            await refreshAppsAsync()
            await refreshBrowsersAsync()
        }
    }

    var isSetupComplete: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/setup_complete").path
        return FileManager.default.fileExists(atPath: path)
    }

    func completeSetup() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/setup_complete")
        try? "1\n".data(using: .utf8)?.write(to: url)
        BlissProfileManager.ensureDefaultConfig()
    }

    func setManualError(_ message: String) {
        errorMessage = message
    }

    /// Total seconds for the session. Set by the timer UI; falls back to minutesInput * 60.
    var totalSecondsInput: Int?

    func startSession() {
        let totalSecs: Int
        if let s = totalSecondsInput, s > 0 {
            totalSecs = s
        } else {
            totalSecs = (Int(minutesInput) ?? 25) * 60
        }
        let displayMins = (totalSecs + 59) / 60
        runAction(["start", "\(totalSecs)", "--seconds"], successRefresh: true) { [weak self] in
            BlissNotifications.sessionStarted(minutes: displayMins)
            BlissNotifications.scheduleFiveMinWarning(totalSeconds: totalSecs)
            BlissNotifications.scheduleSessionEnd(totalSeconds: totalSecs)
            SessionStatsManager.recordSessionStart(minutes: displayMins)
            self?.stats = SessionStatsManager.load()
            self?.dailyMinutes = SessionStatsManager.dailyMinutes()
        }
        totalSecondsInput = nil
    }

    func addWebsite() {
        guard !isSessionActive else { return }
        let domain = websiteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else { return }
        runAction(["config", "website", "add", domain], successRefresh: false) { [weak self] in
            guard let self else { return }
            self.websiteInput = ""
            self.refreshWebsites()
        }
    }

    func addWebsite(domain: String) {
        guard !isSessionActive else { return }
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runAction(["config", "website", "add", trimmed], successRefresh: false) { [weak self] in
            self?.refreshWebsites()
        }
    }

    /// Add multiple websites serially to avoid file write races.
    func addWebsites(_ domains: [String]) {
        guard !isSessionActive else { return }
        let toAdd = domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !websites.contains($0) }
        guard !toAdd.isEmpty else { return }
        Task {
            for domain in toAdd {
                let result = await Task.detached { BlissCommand.run(["config", "website", "add", domain]) }.value
                if result.code != 0 {
                    errorMessage = actionableMessage(from: result.combinedOutput)
                    break
                }
            }
            errorMessage = nil
            await refreshWebsitesAsync()
        }
    }

    func removeWebsite(_ domain: String) {
        guard !isSessionActive else { return }
        runAction(["config", "website", "remove", domain], successRefresh: false) { [weak self] in
            self?.refreshWebsites()
        }
    }

    /// Remove multiple websites serially.
    func removeWebsites(_ domains: [String]) {
        guard !isSessionActive else { return }
        let toRemove = domains.filter { websites.contains($0) }
        guard !toRemove.isEmpty else { return }
        Task {
            for domain in toRemove {
                let _ = await Task.detached { BlissCommand.run(["config", "website", "remove", domain]) }.value
            }
            errorMessage = nil
            await refreshWebsitesAsync()
        }
    }

    func addApp(path: String) {
        guard !isSessionActive else { return }
        runAction(["config", "app", "add", path], successRefresh: false) { [weak self] in
            self?.refreshApps()
        }
    }

    func removeApp(_ app: AppEntryModel) {
        guard !isSessionActive else { return }
        runAction(["config", "app", "remove", app.raw], successRefresh: false) { [weak self] in
            self?.refreshApps()
        }
    }

    func addBrowserFromAppPath(_ path: String) {
        guard !isSessionActive else { return }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if name.isEmpty {
            errorMessage = "Invalid app path for browser selection."
            return
        }
        runAction(["config", "browser", "add", name], successRefresh: false) { [weak self] in
            self?.refreshBrowsers()
        }
    }

    func removeBrowser(_ name: String) {
        guard !isSessionActive else { return }
        runAction(["config", "browser", "remove", name], successRefresh: false) { [weak self] in
            self?.refreshBrowsers()
        }
    }

    func setQuoteLength(_ value: String) {
        guard !isSessionActive else { return }
        Task {
            let result = await Task.detached { BlissCommand.run(["config", "quotes", value]) }.value
            output = result.combinedOutput
            if result.code == 0 {
                errorMessage = nil
                syncQuoteLengthFromConfig()
                return
            }
            errorMessage = actionableMessage(from: result.combinedOutput)
            syncQuoteLengthFromConfig()
        }
    }

    func setPanicMode(_ mode: String) {
        guard !isSessionActive else { return }
        panicMode = mode
        savePanicModeToConfig()
    }

    func setCPDifficulty(_ difficulty: CPDifficulty) {
        guard !isSessionActive else { return }
        cpDifficulty = difficulty
        saveCPDifficultyToConfig()
    }

    func panicFromGUI() async -> Bool {
        BlissNotifications.cancelAll()
        let result = await Task.detached { BlissCommand.run(["panic", "--skip-challenge"]) }.value
        output = result.combinedOutput
        if result.code == 0 {
            errorMessage = nil
            refreshAll()
            return true
        }
        errorMessage = actionableMessage(from: result.combinedOutput)
        return false
    }

    func randomQuote() -> String {
        let bundleQuotes = Bundle.main.bundlePath + "/Contents/Resources/quotes/\(quoteLength).txt"
        let candidates = [
            bundleQuotes,
            "/usr/local/share/bliss/quotes/\(quoteLength).txt",
            "/Users/zain/Developer/bliss/quotes/\(quoteLength).txt",
            FileManager.default.currentDirectoryPath + "/quotes/\(quoteLength).txt",
        ]
        for path in candidates {
            if let loaded = loadRandomLine(from: URL(fileURLWithPath: path)) {
                return loaded
            }
        }
        return "Focus is a practice, not a mood."
    }

    private func loadRandomLine(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = content
            .split(separator: "\n")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.randomElement()
    }

    private func syncQuoteLengthFromConfig() {
        let result = BlissCommand.run(["config", "quotes", "get"])
        guard result.code == 0 else {
            quoteLength = "medium"
            return
        }
        let line = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix("quotes:") }) ?? ""
        let value = line.replacingOccurrences(of: "quotes:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "short", "medium", "long", "huge":
            quoteLength = value
        default:
            quoteLength = "medium"
        }
    }

    func setMinesweeperSize(_ size: MinesweeperSize) {
        guard !isSessionActive else { return }
        minesweeperSize = size
        saveMinesweeperSizeToConfig()
    }

    private func syncPanicModeFromConfig() {
        let url = panicModeConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            panicMode = "typing"
            return
        }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "codeforces" { value = "competitive" }
        // Validate against registry; fall back to typing
        if PanicChallengeRegistry.find(value) != nil {
            panicMode = value
        } else {
            panicMode = "typing"
        }
    }

    private func savePanicModeToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = panicModeConfigURL()
        try? (panicMode + "\n").data(using: .utf8)?.write(to: url)
    }

    private func panicModeConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/panic_mode.txt")
    }

    private func syncCPDifficultyFromConfig() {
        let url = cpDifficultyConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            cpDifficulty = .easy
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cpDifficulty = CPDifficulty(rawValue: value) ?? .easy
    }

    private func saveCPDifficultyToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = cpDifficultyConfigURL()
        try? (cpDifficulty.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func cpDifficultyConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/panic_difficulty.txt")
    }

    private func syncMinesweeperSizeFromConfig() {
        let url = minesweeperSizeConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            minesweeperSize = .small
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        minesweeperSize = MinesweeperSize(rawValue: value) ?? .small
    }

    private func saveMinesweeperSizeToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = minesweeperSizeConfigURL()
        try? (minesweeperSize.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func minesweeperSizeConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/minesweeper_size.txt")
    }

    func setPipesSize(_ size: PipesSize) {
        guard !isSessionActive else { return }
        pipesSize = size
        savePipesSizeToConfig()
    }

    private func syncPipesSizeFromConfig() {
        let url = pipesSizeConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            pipesSize = .small
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pipesSize = PipesSize(rawValue: value) ?? .small
    }

    private func savePipesSizeToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = pipesSizeConfigURL()
        try? (pipesSize.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func pipesSizeConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/pipes_size.txt")
    }

    func setSudokuDifficulty(_ difficulty: SudokuDifficulty) {
        guard !isSessionActive else { return }
        sudokuDifficulty = difficulty
        saveSudokuDifficultyToConfig()
    }

    private func syncSudokuDifficultyFromConfig() {
        let url = sudokuDifficultyConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            sudokuDifficulty = .easy
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        sudokuDifficulty = SudokuDifficulty(rawValue: value) ?? .easy
    }

    private func saveSudokuDifficultyToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = sudokuDifficultyConfigURL()
        try? (sudokuDifficulty.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func sudokuDifficultyConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/sudoku_difficulty.txt")
    }

    func setSimonDifficulty(_ difficulty: SimonDifficulty) {
        guard !isSessionActive else { return }
        simonDifficulty = difficulty
        saveSimonDifficultyToConfig()
    }

    private func syncSimonDifficultyFromConfig() {
        let url = simonDifficultyConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            simonDifficulty = .easy
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        simonDifficulty = SimonDifficulty(rawValue: value) ?? .easy
    }

    private func saveSimonDifficultyToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = simonDifficultyConfigURL()
        try? (simonDifficulty.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func simonDifficultyConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/simon_difficulty.txt")
    }

    func setGame2048Difficulty(_ difficulty: Game2048Difficulty) {
        guard !isSessionActive else { return }
        game2048Difficulty = difficulty
        saveGame2048DifficultyToConfig()
    }

    private func syncGame2048DifficultyFromConfig() {
        let url = game2048DifficultyConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            game2048Difficulty = .easy
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        game2048Difficulty = Game2048Difficulty(rawValue: value) ?? .easy
    }

    private func saveGame2048DifficultyToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = game2048DifficultyConfigURL()
        try? (game2048Difficulty.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func game2048DifficultyConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/game2048_difficulty.txt")
    }

    func setWordleDifficulty(_ difficulty: WordleDifficulty) {
        guard !isSessionActive else { return }
        wordleDifficulty = difficulty
        saveWordleDifficultyToConfig()
    }

    private func syncWordleDifficultyFromConfig() {
        let url = wordleDifficultyConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            wordleDifficulty = .easy
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        wordleDifficulty = WordleDifficulty(rawValue: value) ?? .easy
    }

    private func saveWordleDifficultyToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = wordleDifficultyConfigURL()
        try? (wordleDifficulty.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func wordleDifficultyConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/wordle_difficulty.txt")
    }

    private func refreshStatusAsync() async {
        let result = await Task.detached { BlissCommand.run(["status"]) }.value
        if result.code != 0 {
            statusText = "status: error"
            remainingText = "remaining: -"
            pfText = "pf table active: -"
            isSessionActive = false
            endTimeEpoch = nil
            output = result.combinedOutput
            errorMessage = actionableMessage(from: result.combinedOutput)
            return
        }
        let lines = result.stdout.split(separator: "\n").map(String.init)
        statusText = lines.first(where: { $0.hasPrefix("status:") }) ?? "status: unknown"
        remainingText = lines.first(where: { $0.hasPrefix("remaining:") }) ?? "remaining: -"
        pfText = lines.first(where: { $0.hasPrefix("pf table active:") }) ?? "pf table active: unknown"
        isSessionActive = (statusText == "status: running")
        errorMessage = nil

        if let endLine = lines.first(where: { $0.hasPrefix("ends at (epoch):") }) {
            let raw = endLine.replacingOccurrences(of: "ends at (epoch):", with: "")
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            endTimeEpoch = Int64(trimmed)
        } else {
            endTimeEpoch = nil
        }
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    updateRemainingFromEpoch()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateRemainingFromEpoch() {
        guard let end = endTimeEpoch else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let remaining = max(0, end - now)
        let minutes = remaining / 60
        let seconds = remaining % 60
        remainingText = "remaining: \(minutes)m \(String(format: "%02d", seconds))s"
        if remaining <= 0 && isSessionActive {
            isSessionActive = false
            endTimeEpoch = nil
            dismissSheets = true
            statusText = "status: idle"
            remainingText = "remaining: -"
            BlissNotifications.cancelAll()
            refreshAll()
        }
    }

    private func refreshWebsitesAsync() async {
        let result = await Task.detached { BlissCommand.run(["config", "website", "list"]) }.value
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "no entries" }
        websites = lines
    }

    private func refreshAppsAsync() async {
        let result = await Task.detached { BlissCommand.run(["config", "app", "list", "--raw"]) }.value
        if result.code != 0 {
            let out = result.combinedOutput
            if out.contains("config is locked while a session is active") {
                return
            }
            output = out
            errorMessage = actionableMessage(from: out)
            return
        }
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "no entries" }
        apps = lines.map(parseAppEntry)
    }

    private func refreshBrowsersAsync() async {
        let result = await Task.detached { BlissCommand.run(["config", "browser", "list"]) }.value
        if result.code != 0 {
            let out = result.combinedOutput
            if out.contains("config is locked while a session is active") {
                return
            }
            output = out
            errorMessage = actionableMessage(from: out)
            return
        }
        browsers = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "no entries" }
    }

    private func parseAppEntry(_ line: String) -> AppEntryModel {
        if let bar = line.firstIndex(of: "|") {
            let name = String(line[..<bar])
            let rest = line[line.index(after: bar)...]
            var bundle = ""
            var path = ""
            for chunk in rest.split(separator: "|") {
                if chunk.hasPrefix("bundle=") {
                    bundle = String(chunk.dropFirst("bundle=".count))
                } else if chunk.hasPrefix("path=") {
                    path = String(chunk.dropFirst("path=".count))
                }
            }
            return AppEntryModel(raw: line, name: name, bundle: bundle, path: path)
        }
        return AppEntryModel(raw: line, name: line, bundle: "", path: "")
    }

    private func runAction(
        _ args: [String],
        successRefresh: Bool,
        onSuccess: (() -> Void)? = nil
    ) {
        Task {
            let result = await Task.detached { BlissCommand.run(args) }.value
            output = result.combinedOutput
            if result.code == 0 {
                errorMessage = nil
                onSuccess?()
                if successRefresh {
                    refreshAll()
                }
                return
            }
            errorMessage = actionableMessage(from: result.combinedOutput)
        }
    }

    private func lockMessage() -> String {
        "Config is locked during an active session. Use panic or wait for timer end."
    }

    private func actionableMessage(from output: String) -> String? {
        if output.contains("Failed to run bliss") {
            return "Bliss CLI not found at \(BlissCommand.executablePath()). Install or build Bliss first."
        }
        if output.contains("unable to reach bliss root helper") {
            return "Root helper is unavailable. Run in Terminal: sudo \(BlissCommand.executablePath()) repair"
        }
        if output.contains("repair requires sudo") {
            return "This needs elevated permission. Run in Terminal: sudo \(BlissCommand.executablePath()) repair"
        }
        if output.contains("config is locked while a session is active") {
            return lockMessage()
        }
        if output.contains("session already running") {
            return "A session is already running. Use panic or wait for it to finish."
        }
        if output.contains("invalid minutes") {
            return "Minutes must be a number between 1 and 1440."
        }
        if output.contains("app not found") {
            return "Selected app is no longer in config. Refresh and try again."
        }
        if output.isEmpty {
            return nil
        }
        return "Command failed. See details below."
    }

    private func refreshWebsites() {
        Task { await refreshWebsitesAsync() }
    }

    private func refreshApps() {
        Task { await refreshAppsAsync() }
    }

    private func refreshBrowsers() {
        Task { await refreshBrowsersAsync() }
    }


    // MARK: - Profiles

    func loadProfiles() {
        profiles = BlissProfileManager.listProfiles()
        if profiles.isEmpty {
            BlissProfileManager.ensureDefaultConfig()
            profiles = BlissProfileManager.listProfiles()
        }
        activeProfileName = BlissProfileManager.activeProfileName()
    }

    func saveCurrentAsProfile(name: String, colorName: String = "blue") {
        guard !isSessionActive else { return }
        let profile = BlissProfile(
            name: name,
            websites: websites,
            apps: apps.map { $0.raw },
            browsers: browsers,
            panicMode: panicMode,
            quoteLength: quoteLength,
            colorName: colorName
        )
        BlissProfileManager.save(profile)
        loadProfiles()
    }

    func setProfileColor(name: String, colorName: String) {
        guard var profile = profiles.first(where: { $0.name == name }) else { return }
        profile.colorName = colorName
        BlissProfileManager.save(profile)
        loadProfiles()
    }

    func applyProfile(_ profile: BlissProfile) {
        guard !isSessionActive else { return }

        // Clear current websites and add profile ones
        for site in websites {
            runAction(["config", "website", "remove", site], successRefresh: false, onSuccess: nil)
        }
        for site in profile.websites {
            runAction(["config", "website", "add", site], successRefresh: false, onSuccess: nil)
        }

        // Clear current apps and add profile ones
        for app in apps {
            runAction(["config", "app", "remove", app.raw], successRefresh: false, onSuccess: nil)
        }
        for raw in profile.apps {
            runAction(["config", "app", "add", raw], successRefresh: false, onSuccess: nil)
        }

        // Clear current browsers and add profile ones
        for b in browsers {
            runAction(["config", "browser", "remove", b], successRefresh: false, onSuccess: nil)
        }
        for b in profile.browsers {
            runAction(["config", "browser", "add", b], successRefresh: false, onSuccess: nil)
        }

        setPanicMode(profile.panicMode)
        setQuoteLength(profile.quoteLength)

        BlissProfileManager.setActiveProfile(profile.name)
        activeProfileName = profile.name

        // Refresh after a delay to let commands finish
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            refreshAll()
        }
    }

    func deleteProfile(name: String) {
        BlissProfileManager.delete(name: name)
        if activeProfileName == name {
            BlissProfileManager.setActiveProfile(nil)
            activeProfileName = nil
        }
        loadProfiles()
    }

    func deleteProfileAndSchedules(name: String) {
        // Remove schedules referencing this config
        var current = BlissScheduleManager.load()
        current.removeAll { $0.configName == name }
        BlissScheduleManager.save(current)
        schedules = current
        deleteProfile(name: name)
    }

    // MARK: - Schedules

    func addSchedule(_ entry: BlissScheduleEntry) {
        var current = BlissScheduleManager.load()
        current.append(entry)
        BlissScheduleManager.save(current)
        schedules = current
    }

    func updateSchedule(_ entry: BlissScheduleEntry) {
        var current = BlissScheduleManager.load()
        if let idx = current.firstIndex(where: { $0.id == entry.id }) {
            current[idx] = entry
        }
        BlissScheduleManager.save(current)
        schedules = current
    }

    func deleteSchedule(id: UUID) {
        var current = BlissScheduleManager.load()
        current.removeAll { $0.id == id }
        BlissScheduleManager.save(current)
        schedules = current
    }

    private func checkScheduledSessions() {
        guard !isSessionActive else { return }

        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)  // 1=Sun
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)

        for entry in schedules where entry.enabled {
            guard entry.days.contains(weekday),
                  entry.hour == hour,
                  entry.minute == minute else { continue }

            // Prevent double-fire within same minute
            if lastTriggeredScheduleID == entry.id && lastTriggeredMinute == minute {
                continue
            }

            // Find and apply the config
            if let profile = profiles.first(where: { $0.name == entry.configName }) {
                applyProfile(profile)
            }
            minutesInput = "\(entry.durationMinutes)"
            startSession()
            lastTriggeredScheduleID = entry.id
            lastTriggeredMinute = minute
            break
        }
    }

    func runRepair() {
        Task {
            let blissPath = BlissCommand.executablePath()
            let result = await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = [
                    "-e",
                    "do shell script \"\(blissPath) repair\" with administrator privileges"
                ]
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    return CommandResult(code: 127, stdout: "", stderr: error.localizedDescription)
                }
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CommandResult(code: process.terminationStatus, stdout: out, stderr: err)
            }.value
            if result.code == 0 {
                errorMessage = nil
                output = "Repair complete."
                refreshAll()
            } else {
                errorMessage = "Repair failed: \(result.combinedOutput)"
            }
        }
    }

    func runUninstall() async -> Bool {
        // Build candidate paths. The CLI binary is often a symlink
        // (e.g. /usr/local/bin/bliss -> /Users/.../bliss/build/bliss),
        // so resolve the symlink to find the source tree.
        let rawPath = BlissCommand.executablePath()
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: rawPath)) ?? rawPath
        let scriptPaths = [
            "/usr/local/share/bliss/uninstall.sh",
            URL(fileURLWithPath: resolvedPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/uninstall.sh").path,
            URL(fileURLWithPath: rawPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/uninstall.sh").path,
        ]
        for path in scriptPaths {
            if FileManager.default.fileExists(atPath: path) {
                let result = await Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = [
                        "-e",
                        "do shell script \"/bin/bash '\(path)'\" with administrator privileges"
                    ]
                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    do {
                        try process.run()
                        process.waitUntilExit()
                    } catch {
                        return CommandResult(code: 127, stdout: "", stderr: error.localizedDescription)
                    }
                    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    return CommandResult(code: process.terminationStatus, stdout: out, stderr: err)
                }.value
                if result.code == 0 {
                    errorMessage = nil
                    output = "Uninstall complete."
                    return true
                } else {
                    errorMessage = "Uninstall failed: \(result.combinedOutput)"
                    return false
                }
            }
        }
        errorMessage = "Uninstall script not found."
        return false
    }
}
