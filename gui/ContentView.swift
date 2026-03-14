import SwiftUI
import UniformTypeIdentifiers

private enum DashboardTab: Hashable {
    case main, settings
}

private enum ImportTarget {
    case app, browser
}

private enum SetupStep: Int, CaseIterable {
    case welcome, websites, apps, browsers, panicMode, panicConfig, ready
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
    @State private var panicQuote = "Focus is a practice, not a mood." // fallback
    @State private var importTarget: ImportTarget?
    @State private var pendingImportTarget: ImportTarget?
    @State private var selectedTab: DashboardTab = .main
    @State private var uninstallChallengePresented = false
    @State private var showUninstallConfirm = false

    // Setup wizard
    @State private var showSetupWizard = false
    @State private var setupStep: SetupStep = .welcome
    @State private var setupWebsiteInput = ""
    @State private var setupWebsites: [String] = []
    @State private var setupPanicMode: PanicModeSetting = .typing
    @State private var setupQuoteLength: String = "medium"
    @State private var setupCPDifficulty: CPDifficulty = .easy

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
                    panicQuote = vm.randomQuote()
                    vm.panicPresented = true
                }
            }
        }
        .sheet(isPresented: $vm.panicPresented) {
            PanicChallengeView(quote: panicQuote, mode: vm.panicMode, cpDifficulty: vm.cpDifficulty) {
                await vm.panicFromGUI()
            }
        }
        .sheet(isPresented: $uninstallChallengePresented) {
            PanicChallengeView(quote: panicQuote, mode: vm.panicMode, cpDifficulty: vm.cpDifficulty) {
                vm.runUninstall()
                return true
            }
        }
        .onChange(of: importTarget) { newValue in
            if newValue != nil { pendingImportTarget = newValue }
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
                Button("") { selectedTab = .settings }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                Button("") { triggerPanic() }
                    .keyboardShortcut("e", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        VStack(spacing: 0) {
            // Manual tab bar
            HStack(spacing: 0) {
                tabBarButton("Session", icon: "timer", tab: .main)
                tabBarButton("Settings", icon: "gear", tab: .settings)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider().padding(.top, 4)

            // Only render the active tab
            if selectedTab == .main {
                mainTab
            } else {
                settingsTab
            }
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

    private var mainTab: some View {
        VStack {
            Spacer()
            VStack(alignment: .center, spacing: 14) {
                Text("Bliss")
                    .font(.title.weight(.semibold))
                Text(vm.statusText.replacingOccurrences(of: "status: ", with: "").capitalized)
                    .foregroundColor(vm.isSessionActive ? .green : .secondary)
                Text(vm.remainingText.replacingOccurrences(of: "remaining: ", with: ""))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 10) {
                    if !vm.isSessionActive {
                        TextField("25", text: $vm.minutesInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .onSubmit { if selectedTab == .main { vm.startSession() } }
                        Button("Start") { vm.startSession() }
                    } else {
                        Button("Panic") {
                            panicQuote = vm.randomQuote()
                            vm.panicPresented = true
                        }
                        .foregroundColor(.red)
                    }
                }

                if !vm.isSessionActive {
                    Text("\u{2318}Return to start \u{00B7} \u{2318}E to panic")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        ZStack {
            Form {
                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }

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
                            Text("Typing").tag(PanicModeSetting.typing)
                            Text("Competitive Programming").tag(PanicModeSetting.competitive)
                        }
                        .labelsHidden()
                        .frame(width: 250, alignment: .trailing)
                    }

                    if vm.panicMode == .typing {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quote Length")
                                Text("Length of text you must type accurately")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { vm.quoteLength },
                                set: { vm.setQuoteLength($0) }
                            )) {
                                Text("Short").tag("short")
                                Text("Medium").tag("medium")
                                Text("Long").tag("long")
                                Text("Huge").tag("huge")
                            }
                            .labelsHidden()
                            .frame(width: 250, alignment: .trailing)
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Difficulty")
                                Text("CSES problem difficulty")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { vm.cpDifficulty },
                                set: { vm.setCPDifficulty($0) }
                            )) {
                                Text("Easy").tag(CPDifficulty.easy)
                                Text("Medium").tag(CPDifficulty.medium)
                                Text("Hard").tag(CPDifficulty.hard)
                            }
                            .labelsHidden()
                            .frame(width: 250, alignment: .trailing)
                        }
                    }
                } header: {
                    Label("Panic Challenge", systemImage: "bolt.shield")
                }

                Section {
                    if vm.websites.isEmpty {
                        Text("No blocked websites")
                            .foregroundColor(.secondary)
                    }
                    ForEach(vm.websites, id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button { vm.removeWebsite(site) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("example.com", text: $vm.websiteInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { vm.addWebsite() }
                        Button("Add") { vm.addWebsite() }
                    }
                } header: {
                    Label("Blocked Websites", systemImage: "globe")
                }

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

                Section {
                    shortcutRow("Session tab", shortcut: "\u{2318}1")
                    shortcutRow("Settings tab", shortcut: "\u{2318}2  or  \u{2318},")
                    shortcutRow("Start session", shortcut: "\u{2318}Return")
                    shortcutRow("End session (panic)", shortcut: "\u{2318}E")
                } header: {
                    Label("Keyboard Shortcuts", systemImage: "keyboard")
                }

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
                panicQuote = vm.randomQuote()
                uninstallChallengePresented = true
            }
        } message: {
            Text("Complete a panic challenge to uninstall. This removes all Bliss components.")
        }
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        }
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
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                TextField("example.com", text: $setupWebsiteInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addSetupWebsite() }
                Button("Add") { addSetupWebsite() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Popular distractions")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(
                        ["youtube.com", "twitter.com", "reddit.com", "instagram.com",
                         "tiktok.com", "facebook.com", "netflix.com"],
                        id: \.self
                    ) { site in
                        if !setupWebsites.contains(site) {
                            Button(site) { setupWebsites.append(site) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
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
                wizardModeCard(
                    .typing,
                    icon: "keyboard",
                    title: "Typing Test",
                    description: "Type a quote with 95% accuracy."
                )
                wizardModeCard(
                    .competitive,
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Competitive Programming",
                    description: "Solve a CSES problem of your selected difficulty."
                )
            }
        }
    }

    private var wizardPanicConfig: some View {
        VStack(alignment: .leading, spacing: 16) {
            if setupPanicMode == .typing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quote Length")
                        .font(.title2.weight(.semibold))
                    Text("How long should the typing challenge quote be?")
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    wizardOptionCard("Short", subtitle: "A sentence or two", selected: setupQuoteLength == "short") { setupQuoteLength = "short" }
                    wizardOptionCard("Medium", subtitle: "A short paragraph", selected: setupQuoteLength == "medium") { setupQuoteLength = "medium" }
                    wizardOptionCard("Long", subtitle: "A full paragraph", selected: setupQuoteLength == "long") { setupQuoteLength = "long" }
                    wizardOptionCard("Huge", subtitle: "Multiple paragraphs", selected: setupQuoteLength == "huge") { setupQuoteLength = "huge" }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Problem Difficulty")
                        .font(.title2.weight(.semibold))
                    Text("How hard should the CSES problem be?")
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    wizardOptionCard("Easy", subtitle: "Introductory & sorting problems", selected: setupCPDifficulty == .easy) { setupCPDifficulty = .easy }
                    wizardOptionCard("Medium", subtitle: "Dynamic programming & graphs", selected: setupCPDifficulty == .medium) { setupCPDifficulty = .medium }
                    wizardOptionCard("Hard", subtitle: "Advanced tree & math problems", selected: setupCPDifficulty == .hard) { setupCPDifficulty = .hard }
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

    private func wizardModeCard(
        _ mode: PanicModeSetting,
        icon: String,
        title: String,
        description: String
    ) -> some View {
        let selected = setupPanicMode == mode
        return Button {
            setupPanicMode = mode
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundColor(selected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(description)
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
                Label(
                    setupPanicMode == .typing
                        ? "Typing test \u{2014} \(setupQuoteLength) quotes"
                        : "Competitive programming \u{2014} \(setupCPDifficulty == .easy ? "easy" : setupCPDifficulty == .medium ? "medium" : "hard") difficulty",
                    systemImage: setupPanicMode == .typing
                        ? "keyboard"
                        : "chevron.left.forwardslash.chevron.right"
                )
            }
            .foregroundColor(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func triggerPanic() {
        if vm.isSessionActive {
            panicQuote = vm.randomQuote()
            vm.panicPresented = true
        }
    }

    private func addSetupWebsite() {
        let domain = setupWebsiteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty, !setupWebsites.contains(domain) else { return }
        setupWebsites.append(domain)
        setupWebsiteInput = ""
    }

    private func finishSetup() {
        vm.setPanicMode(setupPanicMode)
        if setupPanicMode == .typing {
            vm.setQuoteLength(setupQuoteLength)
        } else {
            vm.setCPDifficulty(setupCPDifficulty)
        }
        for site in setupWebsites where !vm.websites.contains(site) {
            vm.addWebsite(domain: site)
        }
        vm.completeSetup()
        withAnimation(.easeInOut(duration: 0.3)) {
            showSetupWizard = false
        }
        vm.refreshAll()
    }
}
