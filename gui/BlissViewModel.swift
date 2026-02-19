import Foundation

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
    @Published var output = ""
    @Published var errorMessage: String?
    @Published var panicPresented = false
    @Published var isSessionActive = false

    private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                syncQuoteLengthFromConfig()
                await refreshStatusAsync()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshAll() {
        syncQuoteLengthFromConfig()
        Task {
            await refreshStatusAsync()
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
        guard !isSessionActive else {
            errorMessage = lockMessage()
            return
        }
        let domain = websiteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty else { return }
        runAction(["config", "website", "add", domain], successRefresh: false) { [weak self] in
            guard let self else { return }
            self.websiteInput = ""
            self.refreshWebsites()
        }
    }

    func removeWebsite(_ domain: String) {
        guard !isSessionActive else {
            errorMessage = lockMessage()
            return
        }
        runAction(["config", "website", "remove", domain], successRefresh: false) { [weak self] in
            self?.refreshWebsites()
        }
    }

    func addApp(path: String) {
        guard !isSessionActive else {
            errorMessage = lockMessage()
            return
        }
        runAction(["config", "app", "add", path], successRefresh: false) { [weak self] in
            self?.refreshApps()
        }
    }

    func removeApp(_ app: AppEntryModel) {
        guard !isSessionActive else {
            errorMessage = lockMessage()
            return
        }
        runAction(["config", "app", "remove", app.raw], successRefresh: false) { [weak self] in
            self?.refreshApps()
        }
    }

    func addBrowserFromAppPath(_ path: String) {
        guard !isSessionActive else {
            errorMessage = lockMessage()
            return
        }
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
        guard !isSessionActive else {
            errorMessage = lockMessage()
            return
        }
        runAction(["config", "browser", "remove", name], successRefresh: false) { [weak self] in
            self?.refreshBrowsers()
        }
    }

    func setQuoteLength(_ value: String) {
        guard !isSessionActive else {
            errorMessage = lockMessage()
            syncQuoteLengthFromConfig()
            return
        }
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

    private func refreshStatusAsync() async {
        let result = await Task.detached { BlissCommand.run(["status"]) }.value
        if result.code != 0 {
            statusText = "status: error"
            remainingText = "remaining: -"
            pfText = "pf table active: -"
            isSessionActive = false
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
            output = result.combinedOutput
            errorMessage = actionableMessage(from: result.combinedOutput)
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
            output = result.combinedOutput
            errorMessage = actionableMessage(from: result.combinedOutput)
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
