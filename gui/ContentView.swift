import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = BlissViewModel()
    @State private var panicQuote = "Focus is a practice, not a mood."
    @State private var showingAppImporter = false
    @State private var showingBrowserImporter = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Status") {
                    Text(vm.statusText)
                    Text(vm.remainingText)
                    Text(vm.pfText)
                }

                Section("Start") {
                    TextField("Minutes", text: $vm.minutesInput)
                    Button("Start Session") { vm.startSession() }
                    Button("Panic") {
                        panicQuote = vm.randomQuote()
                        vm.panicPresented = true
                    }
                }

                Section("Quotes") {
                    Picker(
                        "Length",
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
                    .disabled(vm.isSessionActive)
                }
            }
            .navigationTitle("Bliss")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if vm.isSessionActive {
                    Text("Config is locked while a session is active.")
                        .font(.callout)
                        .foregroundColor(.orange)
                }

                HStack {
                    TextField("Add website", text: $vm.websiteInput)
                    Button("Add") { vm.addWebsite() }
                }
                .disabled(vm.isSessionActive)

                List {
                    Section("Blocked Websites") {
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

                    Section("Blocked Apps") {
                        Button("Add") { showingAppImporter = true }
                            .disabled(vm.isSessionActive)
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
                                        .disabled(vm.isSessionActive)
                                }
                            }
                        }
                    }

                    Section("Browsers") {
                        Button("Add") { showingBrowserImporter = true }
                            .disabled(vm.isSessionActive)

                        if vm.browsers.isEmpty {
                            Text("No entries")
                        } else {
                            ForEach(vm.browsers, id: \.self) { browser in
                                HStack {
                                    Text(browser)
                                    Spacer()
                                    Button("Remove") { vm.removeBrowser(browser) }
                                        .disabled(vm.isSessionActive)
                                }
                            }
                        }
                    }
                }

                Text(vm.output)
                    .font(.footnote.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(4)

                HStack {
                    Spacer()
                    Button("Refresh") { vm.refreshAll() }
                }
            }
            .padding()
            .navigationTitle("Dashboard")
        }
        .onAppear {
            vm.refreshAll()
            vm.startAutoRefresh()
        }
        .onDisappear {
            vm.stopAutoRefresh()
        }
        .sheet(isPresented: $vm.panicPresented) {
            PanicChallengeView(quote: panicQuote) {
                await vm.panicFromGUI()
            }
        }
        .fileImporter(
            isPresented: $showingAppImporter,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                vm.addApp(path: url.path)
            case .failure(let error):
                vm.setManualError("Unable to read selected app: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $showingBrowserImporter,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                vm.addBrowserFromAppPath(url.path)
            case .failure(let error):
                vm.setManualError("Unable to read selected browser app: \(error.localizedDescription)")
            }
        }
    }
}
