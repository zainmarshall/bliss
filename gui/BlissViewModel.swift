import Foundation

enum PanicModeSetting: String, CaseIterable {
    case typing = "typing"
    case codeforces = "codeforces"
}

enum CFPanicDifficulty: String, CaseIterable {
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
    @Published var panicMode: PanicModeSetting = .typing
    @Published var cfDifficulty: CFPanicDifficulty = .easy
    @Published var output = ""
    @Published var errorMessage: String?
    @Published var panicPresented = false
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
        syncCFDifficultyFromConfig()
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

    func setManualError(_ message: String) {
        errorMessage = message
    }

    func startSession() {
        runAction(["start", minutesInput], successRefresh: true)
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

    func removeWebsite(_ domain: String) {
        guard !isSessionActive else { return }
        runAction(["config", "website", "remove", domain], successRefresh: false) { [weak self] in
            self?.refreshWebsites()
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

    func setPanicMode(_ mode: PanicModeSetting) {
        guard !isSessionActive else { return }
        panicMode = mode
        savePanicModeToConfig()
    }

    func setCFDifficulty(_ difficulty: CFPanicDifficulty) {
        guard !isSessionActive else { return }
        cfDifficulty = difficulty
        saveCFDifficultyToConfig()
    }

    func panicFromGUI() async -> Bool {
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
        let preferred = URL(fileURLWithPath: "/usr/local/share/bliss/quotes/\(quoteLength).txt")
        if let loaded = loadRandomLine(from: preferred) {
            return loaded
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("quotes/\(quoteLength).txt")
        if let loaded = loadRandomLine(from: local) {
            return loaded
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

    private func syncPanicModeFromConfig() {
        let url = panicModeConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            panicMode = .typing
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        panicMode = PanicModeSetting(rawValue: value) ?? .typing
    }

    private func savePanicModeToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = panicModeConfigURL()
        try? (panicMode.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func panicModeConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/panic_mode.txt")
    }

    private func syncCFDifficultyFromConfig() {
        let url = cfDifficultyConfigURL()
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            cfDifficulty = .easy
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cfDifficulty = CFPanicDifficulty(rawValue: value) ?? .easy
    }

    private func saveCFDifficultyToConfig() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = cfDifficultyConfigURL()
        try? (cfDifficulty.rawValue + "\n").data(using: .utf8)?.write(to: url)
    }

    private func cfDifficultyConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/panic_difficulty.txt")
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
            return "Root helper is unavailable. Run: sudo bliss repair"
        }
        if output.contains("repair requires sudo") {
            return "This needs elevated permission. Run from Terminal with sudo."
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
}
