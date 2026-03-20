import SwiftUI
import UniformTypeIdentifiers

private let websitePresets: [(name: String, icon: String, sites: [String])] = [
    ("Social Media", "person.2.fill", ["youtube.com", "twitter.com", "x.com", "reddit.com", "instagram.com", "tiktok.com", "facebook.com", "snapchat.com", "linkedin.com", "threads.net", "tumblr.com", "pinterest.com", "discord.com"]),
    ("Entertainment", "tv.fill", ["netflix.com", "hulu.com", "disneyplus.com", "twitch.tv", "crunchyroll.com", "max.com", "primevideo.com", "spotify.com"]),
    ("News", "newspaper.fill", ["cnn.com", "foxnews.com", "bbc.com", "nytimes.com", "washingtonpost.com", "news.google.com", "apple.news"]),
    ("Gaming", "gamecontroller.fill", ["store.steampowered.com", "epicgames.com", "roblox.com", "chess.com", "lichess.org"]),
    ("Shopping", "cart.fill", ["amazon.com", "ebay.com", "etsy.com", "walmart.com", "target.com"]),
]

private enum DashboardTab: Hashable {
    case main, schedule, stats, settings
}

private enum ImportTarget {
    case app, browser
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case profiles = "Configs"
    case panicChallenge = "Panic Challenge"
    case blockedWebsites = "Blocked Websites"
    case blockedApps = "Blocked Apps"
    case browsers = "Browsers"
    case troubleshooting = "Troubleshooting"
    case uninstall = "Uninstall"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .profiles: return "folder"
        case .panicChallenge: return "bolt.shield"
        case .blockedWebsites: return "globe"
        case .blockedApps: return "app.badge"
        case .browsers: return "safari"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .uninstall: return "trash"
        }
    }
}

private enum ActiveSheet: Identifiable {
    case panic, uninstall
    var id: Self { self }
}

private enum SetupStep: Int, CaseIterable {
    case welcome, websites, apps, browsers, panicMode, panicConfig, ready
}

class SetupWizardState: ObservableObject {
    @Published var panicMode: String = "typing"
    @Published var quoteLength: String = "medium"
    @Published var cpDifficulty: CPDifficulty = .easy
    @Published var minesweeperSize: MinesweeperSize = .small
    @Published var pipesSize: PipesSize = .small
    @Published var sudokuDifficulty: SudokuDifficulty = .easy
    @Published var simonDifficulty: SimonDifficulty = .easy
    @Published var game2048Difficulty: Game2048Difficulty = .easy
    @Published var wordleDifficulty: WordleDifficulty = .easy
}

private struct HideSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

// flow

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), offsets)
    }
}

// app icon for the thing to look cool

private func appIcon(for path: String, size: CGFloat = 20) -> some View {
    Group {
        if !path.isEmpty,
           let icon = NSWorkspace.shared.icon(forFile: path) as NSImage? {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
        }
    }
}

private func browserIcon(for name: String, size: CGFloat = 20) -> some View {
    Group {
        let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID(for: name))?.path
            ?? "/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: appPath) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "safari")
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
        }
    }
}

private func browserBundleID(for name: String) -> String {
    switch name.lowercased() {
    case "safari": return "com.apple.Safari"
    case "chrome", "google chrome": return "com.google.Chrome"
    case "firefox": return "org.mozilla.firefox"
    case "brave browser", "brave": return "com.brave.Browser"
    case "arc": return "company.thebrowser.Browser"
    case "edge", "microsoft edge": return "com.microsoft.edgemac"
    case "opera": return "com.operasoftware.Opera"
    case "vivaldi": return "com.vivaldi.Vivaldi"
    default: return ""
    }
}

// view

struct ContentView: View {
    @StateObject private var vm = BlissViewModel()
    @State private var importTarget: ImportTarget?
    @State private var pendingImportTarget: ImportTarget?
    @State private var selectedTab: DashboardTab = .main
    @State private var showUninstallConfirm = false
    @State private var selectedSettingsSection: SettingsSection = .profiles
    @State private var activeSheet: ActiveSheet?
    @State private var newConfigName = ""
    @State private var showNewConfigField = false
    @State private var timerPulse = false

    /// Deduplicated website list for display: if both "example.com" and
    /// "www.example.com" exist, only show "example.com".
    private var displayWebsites: [String] {
        let set = Set(vm.websites)
        return vm.websites.filter { site in
            if site.hasPrefix("www.") {
                let base = String(site.dropFirst(4))
                return !set.contains(base)
            }
            return true
        }
    }

    /// Remove a website and its www. counterpart from the backend.
    private func removeWebsiteAndWWW(_ domain: String) {
        vm.removeWebsite(domain)
        let counterpart = domain.hasPrefix("www.")
            ? String(domain.dropFirst(4))
            : "www.\(domain)"
        if vm.websites.contains(counterpart) {
            vm.removeWebsite(counterpart)
        }
    }

    // Setup wizard
    @State private var showSetupWizard = false
    @State private var setupStep: SetupStep = .welcome
    @State private var setupWebsiteInput = ""
    @State private var setupWebsites: [String] = []
    @StateObject private var wizardState = SetupWizardState()

    var body: some View {
        Group {
            if showSetupWizard {
                setupWizardOverlay
            } else {
                tabContent
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .animation(.easeInOut(duration: 0.3), value: showSetupWizard)
        .onAppear {
            vm.refreshAll()
            vm.startAutoRefresh()
            if !vm.isSetupComplete {
                showSetupWizard = true
            }
        }
        .onDisappear { vm.stopAutoRefresh() }
        .onOpenURL { url in
            guard url.scheme == "bliss" else { return }
            if url.host == "panic" {
                selectedTab = .main
                if vm.isSessionActive {
                    activeSheet = .panic
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .panic:
                PanicChallengeView(mode: vm.panicMode) {
                    await vm.panicFromGUI()
                }
                .environmentObject(vm)
            case .uninstall:
                PanicChallengeView(mode: vm.panicMode) {
                    await vm.runUninstall()
                }
                .environmentObject(vm)
            }
        }
        .onChange(of: importTarget) {
            if importTarget != nil { pendingImportTarget = importTarget }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importTarget != nil },
                set: { if !$0 { importTarget = nil } }
            ),
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            let target = pendingImportTarget
            pendingImportTarget = nil
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let path = url.resolvingSymlinksInPath().path
                switch target {
                case .app: vm.addApp(path: path)
                case .browser: vm.addBrowserFromAppPath(path)
                case .none: break
                }
            case .failure(let error):
                vm.setManualError("Unable to read selected app: \(error.localizedDescription)")
            }
        }
        // Keyboard shortcuts
        .background {
            Group {
                Button("") { selectedTab = .main }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = .schedule }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = .stats }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedTab = .settings }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selectedTab = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                Button("") { triggerPanic() }
                    .keyboardShortcut("e", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .blissGlobalHotkey)) { _ in
            selectedTab = .main
        }
        .onReceive(NotificationCenter.default.publisher(for: .blissMenuStart)) { _ in
            selectedTab = .main
            if !vm.isSessionActive { vm.startSession() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blissMenuPanic)) { _ in
            selectedTab = .main
            if vm.isSessionActive { activeSheet = .panic }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blissMenuSettings)) { _ in
            selectedTab = .settings
        }
        .onChange(of: vm.dismissSheets) {
            if vm.dismissSheets {
                activeSheet = nil
                vm.dismissSheets = false
            }
        }
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        VStack(spacing: 0) {
            // Manual tab bar - fixed height, never stretches
            HStack(spacing: 0) {
                tabBarButton("Session", icon: "timer", tab: .main)
                tabBarButton("Schedule", icon: "calendar", tab: .schedule)
                tabBarButton("Statistics", icon: "chart.bar.fill", tab: .stats)
                tabBarButton("Settings", icon: "gear", tab: .settings)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            // Content area takes all remaining space
            ZStack {
                switch selectedTab {
                case .main:
                    mainTab
                case .schedule:
                    ScheduleView()
                        .environmentObject(vm)
                case .stats:
                    statsTab
                case .settings:
                    settingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tabBarButton(_ title: String, icon: String, tab: DashboardTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.body.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .background(
                    selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session Tab

    /// Raw digits the user has typed (right-to-left entry, max 6 digits for H:MM:SS)
    @State private var timerDigits: [Int] = []

    /// The 6 digit slots: [H, M tens, M ones, S tens, S ones], but we display as H:MM:SS
    /// Slots: 0=H tens, 1=H ones, 2=M tens, 3=M ones, 4=S tens, 5=S ones — but hours cap at ~24
    /// Simpler: 6 raw slots filled right-to-left
    private var timerSlots: [Int?] {
        var slots: [Int?] = [nil, nil, nil, nil, nil, nil]
        let count = timerDigits.count
        for (i, digit) in timerDigits.enumerated() {
            let slotIndex = 6 - count + i
            if slotIndex >= 0 && slotIndex < 6 {
                slots[slotIndex] = digit
            }
        }
        return slots
    }

    /// Total seconds from the current digit entry
    private var timerTotalSeconds: Int {
        let s = timerSlots
        let hh = (s[0] ?? 0) * 10 + (s[1] ?? 0)
        let mm = (s[2] ?? 0) * 10 + (s[3] ?? 0)
        let ss = (s[4] ?? 0) * 10 + (s[5] ?? 0)
        return hh * 3600 + mm * 60 + ss
    }

    private var mainTab: some View {
        VStack {
            if let error = vm.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") { vm.errorMessage = nil }
                        .buttonStyle(.borderless)
                        .foregroundColor(.white.opacity(0.8))
                }
                .font(.callout)
                .foregroundColor(.white)
                .padding(12)
                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            Spacer()
            VStack(alignment: .center, spacing: 14) {
                Text("Bliss")
                    .font(.title.weight(.semibold))
                Text(vm.statusText.replacingOccurrences(of: "status: ", with: "").capitalized)
                    .foregroundColor(vm.isSessionActive ? .green : .secondary)

                if vm.isSessionActive {
                    // Active countdown
                    Text(vm.remainingText.replacingOccurrences(of: "remaining: ", with: ""))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.3), value: vm.remainingText)
                        .foregroundColor(isLastMinute ? .orange : .primary)
                        .opacity(isLastMinute ? (timerPulse ? 1.0 : 0.6) : 1.0)
                        .animation(isLastMinute ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: timerPulse)
                        .onChange(of: isLastMinute) {
                            if isLastMinute { timerPulse = true }
                            else { timerPulse = false }
                        }
                } else {
                    // Editable timer: right-to-left digit entry
                    timerInputView
                }

                if !vm.isSessionActive {
                    Button("Start") {
                        commitTimerInput()
                        vm.startSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Panic") {
                        activeSheet = .panic
                    }
                    .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(20)
    }

    @State private var timerIsFocused = true

    private var timerInputView: some View {
        let slots = timerSlots
        let hasInput = !timerDigits.isEmpty
        let grey = Color.secondary.opacity(0.3)
        let showCursor = timerIsFocused && timerDigits.count < 6

        return ZStack {
            HStack(spacing: 0) {
                // H
                timerChar(slots[0].map { "\($0)" } ?? "-", filled: slots[0] != nil, grey: grey, isCursor: false)
                timerChar(slots[1].map { "\($0)" } ?? "-", filled: slots[1] != nil, grey: grey, isCursor: false)
                Text(":")
                    .foregroundColor(hasInput ? .primary.opacity(0.5) : grey)
                // MM
                timerChar(slots[2].map { "\($0)" } ?? "-", filled: slots[2] != nil, grey: grey, isCursor: false)
                timerChar(slots[3].map { "\($0)" } ?? "-", filled: slots[3] != nil, grey: grey, isCursor: false)
                Text(":")
                    .foregroundColor(hasInput ? .primary.opacity(0.5) : grey)
                // SS
                timerChar(slots[4].map { "\($0)" } ?? "-", filled: slots[4] != nil, grey: grey, isCursor: false)
                timerChar(slots[5].map { "\($0)" } ?? "-", filled: slots[5] != nil, grey: grey, isCursor: showCursor)
            }
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
            .allowsHitTesting(false)

            // Full-size key catcher overlay
            TimerKeyCatcher(
                onDigit: { d in
                    if timerDigits.count < 6 {
                        timerDigits.append(d)
                        vm.totalSecondsInput = timerTotalSeconds
                    }
                },
                onDelete: {
                    if !timerDigits.isEmpty {
                        timerDigits.removeLast()
                        vm.totalSecondsInput = timerDigits.isEmpty ? nil : timerTotalSeconds
                    }
                },
                onSubmit: {
                    commitTimerInput()
                    vm.startSession()
                },
                onFocusChange: { focused in
                    timerIsFocused = focused
                }
            )
            .frame(maxWidth: 380, maxHeight: 70)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func timerChar(_ ch: String, filled: Bool, grey: Color, isCursor: Bool) -> some View {
        Text(ch)
            .foregroundColor(filled ? .primary : grey)
            .padding(.horizontal, 1)
            .background(
                Group {
                    if isCursor {
                        BlinkingCursor()
                    }
                }
            )
    }

    private func commitTimerInput() {
        if timerDigits.isEmpty { return }
        let secs = timerTotalSeconds
        if secs > 0 {
            vm.totalSecondsInput = secs
        }
    }

    /// True when an active session has less than 60 seconds remaining
    private var isLastMinute: Bool {
        guard vm.isSessionActive else { return false }
        let text = vm.remainingText
        // Format: "remaining: Xm YYs"
        if text.contains("m") {
            let parts = text.components(separatedBy: "m")
            if let minuteStr = parts.first?.components(separatedBy: " ").last,
               let minutes = Int(minuteStr) {
                return minutes == 0
            }
        }
        return false
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 90, height: 64)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Statistics Tab

    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary cards
                HStack(spacing: 12) {
                    statCard(value: "\(vm.stats.totalSessions)", label: "Sessions")
                    statCard(value: String(format: "%.1f", Double(vm.stats.totalFocusMinutes) / 60.0), label: "Hours")
                    statCard(value: "\(vm.stats.currentStreak)", label: "Streak")
                    statCard(value: "\(vm.stats.longestStreak)", label: "Best Streak")
                }
                .frame(maxWidth: .infinity)

                // Activity heatmap
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(.headline)
                    ActivityHeatmap(dailyMinutes: vm.dailyMinutes)
                }

                // Session history
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Sessions")
                        .font(.headline)
                    let log = SessionStatsManager.loadLog().suffix(20).reversed()
                    if log.isEmpty {
                        Text("No sessions recorded yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(Array(log), id: \.startedAt) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatLogDate(entry.date))
                                        .font(.callout.weight(.medium))
                                    Text(formatLogTime(entry.startedAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(entry.minutes)m")
                                    .font(.callout.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }

    private func formatLogDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }

    private func formatLogTime(_ isoStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoStr) else { return "" }
        let display = DateFormatter()
        display.timeStyle = .short
        return display.string(from: date)
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        ZStack {
            HStack(spacing: 0) {
                List(SettingsSection.allCases, selection: $selectedSettingsSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .padding(.top, 8)
                .frame(width: 200)
                .modifier(HideSidebarToggle())

                Divider()

                settingsDetailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .focusEffectDisabled()
            .disabled(vm.isSessionActive)
            .opacity(vm.isSessionActive ? 0.5 : 1.0)

            if vm.isSessionActive {
                Text("Settings are locked during an active session")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Uninstall Bliss?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                activeSheet = .uninstall
            }
        } message: {
            Text("Complete a panic challenge to uninstall. This removes all Bliss components.")
        }
    }

    @ViewBuilder
    private var settingsDetailPane: some View {
        switch selectedSettingsSection {
        case .profiles:
            settingsProfiles
        case .panicChallenge:
            settingsPanicChallenge
        case .blockedWebsites:
            settingsBlockedWebsites
        case .blockedApps:
            settingsBlockedApps
        case .browsers:
            settingsBrowsers
        case .troubleshooting:
            settingsTroubleshooting
        case .uninstall:
            settingsUninstall
        }
    }

    @State private var showDeleteConfigAlert = false
    @State private var configToDelete: String?
    @State private var schedulesUsingConfig: Int = 0

    private var settingsProfiles: some View {
        Form {
            if let error = vm.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            }
            Section {
                if vm.profiles.isEmpty && !showNewConfigField {
                    HStack {
                        Text("Save your current settings as a config for quick switching")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Save Config") { showNewConfigField = true }
                            .controlSize(.small)
                    }
                } else {
                    ForEach(vm.profiles) { profile in
                        HStack(spacing: 10) {
                            // Color picker dot
                            colorPickerDot(profile: profile)

                            Image(systemName: profile.name == vm.activeProfileName ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(profile.name == vm.activeProfileName ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name).font(.callout.weight(.medium))
                                Text("\(profile.websites.count) sites, \(profile.apps.count) apps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if profile.name != vm.activeProfileName {
                                Button("Apply") { vm.applyProfile(profile) }
                                    .controlSize(.small)
                            }
                            Button {
                                let count = vm.schedules.filter { $0.configName == profile.name }.count
                                if count > 0 {
                                    configToDelete = profile.name
                                    schedulesUsingConfig = count
                                    showDeleteConfigAlert = true
                                } else {
                                    vm.deleteProfile(name: profile.name)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if showNewConfigField {
                        HStack {
                            TextField("Config name", text: $newConfigName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { saveNewConfig() }
                            Button("Save") { saveNewConfig() }
                                .disabled(newConfigName.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Cancel") {
                                showNewConfigField = false
                                newConfigName = ""
                            }
                        }
                    } else {
                        Button("Save Current Config") { showNewConfigField = true }
                            .controlSize(.small)
                    }
                }
            } header: {
                Label("Configs", systemImage: "folder.fill")
            }
        }
        .formStyle(.grouped)
        .alert("Delete Config?", isPresented: $showDeleteConfigAlert) {
            Button("Cancel", role: .cancel) { configToDelete = nil }
            Button("Delete", role: .destructive) {
                if let name = configToDelete {
                    vm.deleteProfileAndSchedules(name: name)
                    configToDelete = nil
                }
            }
        } message: {
            Text("This config is used by \(schedulesUsingConfig) schedule(s). Deleting it will also remove those schedules.")
        }
    }

    private var settingsPanicChallenge: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mode")
                        Text("Challenge type to end a session early")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { vm.panicMode },
                        set: { vm.setPanicMode($0) }
                    )) {
                        ForEach(PanicChallengeRegistry.all) { challenge in
                            Text(challenge.displayName).tag(challenge.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250, alignment: .trailing)
                }

                // Show the selected challenge's settings subsection
                if let challenge = vm.currentChallenge,
                   let makeSettings = challenge.makeSettingsView {
                    makeSettings(vm)
                }
            } header: {
                Label("Panic Challenge", systemImage: "bolt.shield")
            }
        }
        .formStyle(.grouped)
    }

    private var settingsBlockedWebsites: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    TextField("Add website (e.g. youtube.com)", text: $vm.websiteInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { vm.addWebsite() }
                }
                FlowLayout(spacing: 6) {
                    ForEach(websitePresets, id: \.name) { preset in
                        let allAdded = preset.sites.allSatisfy { vm.websites.contains($0) }
                        Button {
                            if allAdded {
                                vm.removeWebsites(preset.sites)
                            } else {
                                vm.addWebsites(preset.sites)
                            }
                        } label: {
                            Label(preset.name, systemImage: allAdded ? "checkmark.circle.fill" : preset.icon)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(allAdded ? .green : nil)
                    }
                }
            } header: {
                Label("Blocked Websites", systemImage: "globe")
            }

            Section {
                if vm.websites.isEmpty {
                    Text("No blocked websites")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(displayWebsites, id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button { removeWebsiteAndWWW(site) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var settingsBlockedApps: some View {
        Form {
            Section {
                if vm.apps.isEmpty {
                    Text("No blocked apps")
                        .foregroundColor(.secondary)
                }
                ForEach(vm.apps) { app in
                    HStack(spacing: 10) {
                        appIcon(for: app.path, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Group {
                                if !app.path.isEmpty {
                                    Text(app.path)
                                } else if !app.bundle.isEmpty {
                                    Text(app.bundle)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                        Spacer()
                        Button { vm.removeApp(app) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add App\u{2026}") { importTarget = .app }
            } header: {
                HStack(spacing: 4) {
                    Label("Blocked Apps", systemImage: "app.dashed")
                    Text("\u{2014} killed during sessions")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var settingsBrowsers: some View {
        Form {
            Section {
                if vm.browsers.isEmpty {
                    Text("No browsers configured")
                        .foregroundColor(.secondary)
                }
                ForEach(vm.browsers, id: \.self) { browser in
                    HStack(spacing: 10) {
                        browserIcon(for: browser, size: 28)
                        Text(browser)
                        Spacer()
                        Button { vm.removeBrowser(browser) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Browser\u{2026}") { importTarget = .browser }
            } header: {
                Label("Browsers", systemImage: "safari")
            } footer: {
                Text("Browsers are restarted when a session starts to flush DNS caches and active connections, ensuring blocked websites can\u{2019}t be reached through cached sessions.")
            }
        }
        .formStyle(.grouped)
    }

    private var settingsTroubleshooting: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repair Bliss")
                        Text("Fixes stuck blocks, restores the root helper, and flushes all state")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Run Repair") { vm.runRepair() }
                }
            } header: {
                Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
            }
        }
        .formStyle(.grouped)
    }

    private var settingsUninstall: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Button("Uninstall Bliss\u{2026}") { showUninstallConfirm = true }
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Setup Wizard

    private var setupWizardOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch setupStep {
                    case .welcome: wizardWelcome
                    case .websites: wizardWebsites
                    case .apps: wizardApps
                    case .browsers: wizardBrowsers
                    case .panicMode: wizardPanicMode
                    case .panicConfig: wizardPanicConfig
                    case .ready: wizardReady
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: 300)

                Divider()

                HStack {
                    HStack(spacing: 8) {
                        ForEach(SetupStep.allCases, id: \.rawValue) { step in
                            Circle()
                                .fill(step == setupStep ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    Spacer()
                    if setupStep != .welcome {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                setupStep = SetupStep(rawValue: setupStep.rawValue - 1)!
                            }
                        }
                    }
                    if setupStep == .websites || setupStep == .apps || setupStep == .browsers {
                        Button("Skip") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                setupStep = SetupStep(rawValue: setupStep.rawValue + 1)!
                            }
                        }
                    }
                    Button(setupStep == .ready ? "Get Started" : "Continue") {
                        if setupStep == .ready {
                            finishSetup()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                setupStep = SetupStep(rawValue: setupStep.rawValue + 1)!
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .frame(width: 520)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        }
        .transition(.opacity)
    }

    private var wizardWelcome: some View {
        VStack(spacing: 16) {
            Text("Welcome to Bliss")
                .font(.title.weight(.bold))
            Text("Bliss locks your Mac into focus mode by blocking distracting websites and apps. To end a session early, you must complete a challenge \u{2014} making it hard to give in to impulse.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)
        }
    }

    private var wizardWebsites: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Block Distracting Websites")
                    .font(.title2.weight(.semibold))
                Text("These sites will be unreachable during focus sessions.")
                    .foregroundColor(.secondary)
            }

            if !setupWebsites.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(setupWebsites.enumerated()), id: \.element) { index, site in
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(site)
                                Spacer()
                                Button { setupWebsites.removeAll { $0 == site } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            if index < setupWebsites.count - 1 {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                TextField("example.com", text: $setupWebsiteInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addSetupWebsite() }
                Button("Add") { addSetupWebsite() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preset packs")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(websitePresets, id: \.name) { preset in
                        let allAdded = preset.sites.allSatisfy { setupWebsites.contains($0) }
                        Button {
                            if allAdded {
                                setupWebsites.removeAll { preset.sites.contains($0) }
                            } else {
                                for site in preset.sites where !setupWebsites.contains(site) {
                                    setupWebsites.append(site)
                                }
                            }
                        } label: {
                            Label(preset.name, systemImage: allAdded ? "checkmark.circle.fill" : preset.icon)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(allAdded ? .green : nil)
                    }
                }
            }
        }
    }

    private var wizardApps: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Block Apps")
                    .font(.title2.weight(.semibold))
                Text("These apps will be force-quit whenever a focus session is active.")
                    .foregroundColor(.secondary)
            }

            if !vm.apps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(vm.apps.enumerated()), id: \.element.id) { index, app in
                        HStack(spacing: 10) {
                            appIcon(for: app.path, size: 24)
                            Text(app.name)
                            Spacer()
                            Button { vm.removeApp(app) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if index < vm.apps.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Button("Add App\u{2026}") { importTarget = .app }
        }
    }

    private var wizardBrowsers: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browsers")
                    .font(.title2.weight(.semibold))
                Text("Browsers are restarted when a session starts to flush DNS caches and active connections, ensuring blocked websites can\u{2019}t be reached through cached sessions.")
                    .foregroundColor(.secondary)
            }

            if !vm.browsers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(vm.browsers.enumerated()), id: \.element) { index, browser in
                        HStack(spacing: 10) {
                            browserIcon(for: browser, size: 24)
                            Text(browser)
                            Spacer()
                            Button { vm.removeBrowser(browser) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if index < vm.browsers.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Button("Add Browser\u{2026}") { importTarget = .browser }
        }
    }

    private var wizardPanicMode: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Your Challenge")
                    .font(.title2.weight(.semibold))
                Text("This is what you'll need to complete to end a session early.")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(PanicChallengeRegistry.all) { challenge in
                    wizardModeCard(challenge)
                }
            }
        }
    }

    private var wizardPanicConfig: some View {
        Group {
            if let challenge = PanicChallengeRegistry.find(wizardState.panicMode),
               let makeConfig = challenge.makeWizardConfigView {
                makeConfig()
                    .environmentObject(wizardState)
            } else {
                VStack(spacing: 16) {
                    Text("No additional configuration needed.")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func wizardModeCard(_ challenge: PanicChallengeDefinition) -> some View {
        let selected = wizardState.panicMode == challenge.id
        return Button {
            wizardState.panicMode = challenge.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: challenge.iconName)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundColor(selected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.displayName).font(.callout.weight(.medium))
                    Text(challenge.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: selected ? 2 : 1)
            )
            .background(
                selected ? Color.accentColor.opacity(0.05) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var wizardReady: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("You\u{2019}re All Set")
                .font(.title.weight(.bold))
            Text("Start a focus session anytime from the Session tab.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                if !setupWebsites.isEmpty {
                    Label(
                        "\(setupWebsites.count) website\(setupWebsites.count == 1 ? "" : "s") to block",
                        systemImage: "globe"
                    )
                }
                if !vm.apps.isEmpty {
                    Label(
                        "\(vm.apps.count) app\(vm.apps.count == 1 ? "" : "s") to block",
                        systemImage: "app.dashed"
                    )
                }
                if !vm.browsers.isEmpty {
                    Label(
                        "\(vm.browsers.count) browser\(vm.browsers.count == 1 ? "" : "s") to restart",
                        systemImage: "safari"
                    )
                }
                if let challenge = PanicChallengeRegistry.find(wizardState.panicMode) {
                    Label(
                        "\(challenge.displayName) challenge",
                        systemImage: challenge.iconName
                    )
                }
            }
            .foregroundColor(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func triggerPanic() {
        if vm.isSessionActive {
            activeSheet = .panic
        }
    }

    @State private var colorPickerOpenFor: String?

    private func colorPickerDot(profile: BlissProfile) -> some View {
        let isOpen = Binding<Bool>(
            get: { colorPickerOpenFor == profile.name },
            set: { if !$0 { colorPickerOpenFor = nil } }
        )
        return Button {
            colorPickerOpenFor = colorPickerOpenFor == profile.name ? nil : profile.name
        } label: {
            Circle()
                .fill(profile.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: isOpen, arrowEdge: .leading) {
            VStack(spacing: 6) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28))], spacing: 6) {
                    ForEach(BlissProfile.availableColors, id: \.name) { option in
                        Button {
                            vm.setProfileColor(name: profile.name, colorName: option.name)
                            colorPickerOpenFor = nil
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 24, height: 24)
                                if option.name == profile.colorName {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .frame(width: 160)
        }
    }

    private func saveNewConfig() {
        let name = newConfigName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        vm.saveCurrentAsProfile(name: name)
        newConfigName = ""
        showNewConfigField = false
    }

    private func addSetupWebsite() {
        let domain = setupWebsiteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty, !setupWebsites.contains(domain) else { return }
        setupWebsites.append(domain)
        setupWebsiteInput = ""
    }

    private func finishSetup() {
        vm.setPanicMode(wizardState.panicMode)
        switch wizardState.panicMode {
        case "typing":      vm.setQuoteLength(wizardState.quoteLength)
        case "competitive": vm.setCPDifficulty(wizardState.cpDifficulty)
        case "minesweeper": vm.setMinesweeperSize(wizardState.minesweeperSize)
        case "pipes":       vm.setPipesSize(wizardState.pipesSize)
        case "sudoku":      vm.setSudokuDifficulty(wizardState.sudokuDifficulty)
        case "simon":       vm.setSimonDifficulty(wizardState.simonDifficulty)
        case "2048":        vm.setGame2048Difficulty(wizardState.game2048Difficulty)
        case "wordle":      vm.setWordleDifficulty(wizardState.wordleDifficulty)
        default:            break
        }
        vm.completeSetup()
        // Add websites serially to avoid config file write races, then refresh
        let sitesToAdd = setupWebsites.filter { !vm.websites.contains($0) }
        if !sitesToAdd.isEmpty {
            vm.addWebsites(sitesToAdd)
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            showSetupWizard = false
        }
        // Delay refresh to let serial website adds finish
        Task {
            try? await Task.sleep(nanoseconds: UInt64(sitesToAdd.count) * 300_000_000 + 500_000_000)
            vm.refreshAll()
        }
    }
}

// MARK: - Activity Heatmap

struct ActivityHeatmap: View {
    let dailyMinutes: [String: Int]

    private let columns = 52
    private let rows = 7
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3
    private let dayLabels = ["", "Mon", "", "Wed", "", "Fri", ""]

    private func dateString(for date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }

    private func colorForMinutes(_ minutes: Int) -> Color {
        if minutes == 0 { return Color.white.opacity(0.06) }
        if minutes < 30 { return Color.green.opacity(0.25) }
        if minutes < 60 { return Color.green.opacity(0.45) }
        if minutes < 120 { return Color.green.opacity(0.65) }
        return Color.green.opacity(0.85)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 0) {
                // Day labels
                VStack(alignment: .trailing, spacing: cellSpacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        Text(dayLabels[row])
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .frame(width: 28)

                // Grid
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: cellSpacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<rows, id: \.self) { row in
                                    let daysAgo = (columns - 1 - col) * 7 + (6 - row)
                                    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
                                    let key = dateString(for: date)
                                    let mins = dailyMinutes[key] ?? 0
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(colorForMinutes(mins))
                                        .frame(width: cellSize, height: cellSize)
                                        .help(mins > 0 ? "\(key): \(mins)m" : key)
                                }
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 9)).foregroundColor(.secondary)
                ForEach([0, 15, 45, 90, 150], id: \.self) { mins in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForMinutes(mins))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More").font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(visible ? 0.15 : 0))
            .frame(width: 34, height: 52)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - Timer Key Catcher

struct TimerKeyCatcher: NSViewRepresentable {
    var onDigit: (Int) -> Void
    var onDelete: () -> Void
    var onSubmit: () -> Void
    var onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> TimerKeyView {
        let view = TimerKeyView()
        view.callbacks = (onDigit, onDelete, onSubmit, onFocusChange)
        return view
    }

    func updateNSView(_ nsView: TimerKeyView, context: Context) {
        nsView.callbacks = (onDigit, onDelete, onSubmit, onFocusChange)
    }
}

class TimerKeyView: NSView {
    var callbacks: (
        onDigit: (Int) -> Void,
        onDelete: () -> Void,
        onSubmit: () -> Void,
        onFocusChange: (Bool) -> Void
    )?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Auto-focus when the view appears
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        callbacks?.onFocusChange(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        callbacks?.onFocusChange(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { return }
        // Ignore if any modifier keys are held (Cmd, Ctrl, etc.)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        for ch in chars {
            if let d = ch.wholeNumberValue {
                callbacks?.onDigit(d)
            } else if ch == "\r" || ch == "\n" {
                callbacks?.onSubmit()
            } else if ch == "\u{7F}" { // backspace
                callbacks?.onDelete()
            }
            // All other keys are silently ignored
        }
    }
}

