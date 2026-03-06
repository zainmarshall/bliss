import SwiftUI
import UniformTypeIdentifiers

private enum DashboardTab: Hashable {
    case main
    case config
}

private enum ImportTarget {
    case app
    case browser
}

struct ContentView: View {
    @StateObject private var vm = BlissViewModel()
    @State private var panicQuote = "Focus is a practice, not a mood."
    @State private var importTarget: ImportTarget?
    @State private var selectedTab: DashboardTab = .main

    var body: some View {
        TabView(selection: $selectedTab) {
            mainTab
                .tabItem { Label("Main", systemImage: "timer") }
                .tag(DashboardTab.main)
            configTab
                .tabItem { Label("Config", systemImage: "slider.horizontal.3") }
                .tag(DashboardTab.config)
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear {
            vm.refreshAll()
            vm.startAutoRefresh()
        }
        .onDisappear {
            vm.stopAutoRefresh()
        }
        .sheet(isPresented: $vm.panicPresented) {
            PanicChallengeView(quote: panicQuote, mode: vm.panicMode, cfDifficulty: vm.cfDifficulty) {
                await vm.panicFromGUI()
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        importTarget = nil
                    }
                }
            ),
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            let target = importTarget
            importTarget = nil
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                switch target {
                case .app:
                    vm.addApp(path: url.path)
                case .browser:
                    vm.addBrowserFromAppPath(url.path)
                case .none:
                    break
                }
            case .failure(let error):
                if target == .browser {
                    vm.setManualError("Unable to read selected browser app: \(error.localizedDescription)")
                } else {
                    vm.setManualError("Unable to read selected app: \(error.localizedDescription)")
                }
            }
        }
    }

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
                    TextField("25", text: $vm.minutesInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Button("Start") { vm.startSession() }
                        .keyboardShortcut(.defaultAction)
                    Button("Panic") {
                        panicQuote = vm.randomQuote()
                        vm.panicPresented = true
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(20)
    }

    private var configTab: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack {
                        Text("Quote Length")
                        Picker(
                            "",
                            selection: Binding(
                                get: { vm.quoteLength },
                                set: { vm.setQuoteLength($0) }
                            )
                        ) {
                            Text("Short").tag("short")
                            Text("Medium").tag("medium")
                            Text("Long").tag("long")
                            Text("Huge").tag("huge")
                        }
                        .frame(width: 180)
                        .labelsHidden()

                        Divider().frame(height: 20)

                        Text("Panic Mode")
                        Picker(
                            "",
                            selection: Binding(
                                get: { vm.panicMode },
                                set: { vm.setPanicMode($0) }
                            )
                        ) {
                            Text("Typing").tag(PanicModeSetting.typing)
                            Text("Codeforces").tag(PanicModeSetting.codeforces)
                        }
                        .frame(width: 180)
                        .labelsHidden()

                        Divider().frame(height: 20)

                        Text("CF Difficulty")
                        Picker(
                            "",
                            selection: Binding(
                                get: { vm.cfDifficulty },
                                set: { vm.setCFDifficulty($0) }
                            )
                        ) {
                            Text("Easy").tag(CFPanicDifficulty.easy)
                            Text("Medium").tag(CFPanicDifficulty.medium)
                            Text("Hard").tag(CFPanicDifficulty.hard)
                        }
                        .frame(width: 140)
                        .labelsHidden()
                    }

                    HStack {
                        TextField("Add domain (example.com)", text: $vm.websiteInput)
                        Button("Add") { vm.addWebsite() }
                    }

                    GroupBox("Blocked Websites") {
                        VStack(alignment: .leading, spacing: 6) {
                            if vm.websites.isEmpty {
                                Text("No entries")
                            } else {
                                ForEach(vm.websites, id: \.self) { site in
                                    HStack {
                                        Text(site)
                                        Spacer()
                                        Button("Remove") { vm.removeWebsite(site) }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Blocked Apps") {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Add") { importTarget = .app }
                            if vm.apps.isEmpty {
                                Text("No entries")
                            } else {
                                ForEach(vm.apps) { app in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(app.name)
                                            if !app.path.isEmpty {
                                                Text(app.path)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            } else if !app.bundle.isEmpty {
                                                Text(app.bundle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Button("Remove") { vm.removeApp(app) }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Browsers") {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Add") { importTarget = .browser }
                            if vm.browsers.isEmpty {
                                Text("No entries")
                            } else {
                                ForEach(vm.browsers, id: \.self) { browser in
                                    HStack {
                                        Text(browser)
                                        Spacer()
                                        Button("Remove") { vm.removeBrowser(browser) }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .disabled(vm.isSessionActive)
                .opacity(vm.isSessionActive ? 0.4 : 1.0)
                .padding(20)
            }

            if vm.isSessionActive {
                Text("Config is locked while a session is active.")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
