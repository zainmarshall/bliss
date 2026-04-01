import SwiftUI

@main
struct BlissApp: App {
    @NSApplicationDelegateAdaptor(BlissAppDelegate.self) var appDelegate
    @StateObject private var menuBarTimer = MenuBarTimer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(menuBarTimer)
        } label: {
            Text(menuBarTimer.menuBarLabel)
        }
    }
}

// MARK: - App Delegate

class BlissAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shouldReallyQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        BlissNotifications.requestPermission()
        // Delay slightly so SwiftUI has time to create windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows where window.level == .normal {
                window.delegate = self
            }
        }
    }

    /// Intercept red X / Cmd+W: hide instead of close to preserve SwiftUI view hierarchy
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        let hasVisibleMain = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
        if !hasVisibleMain {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    /// Keep the app running when the last window is closed (menubar stays alive)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Intercept Cmd-Q: just hide the main window(s) instead of quitting
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if BlissAppDelegate.shouldReallyQuit {
            return .terminateNow
        }
        // Hide regular windows instead of closing, so they can be re-shown
        for window in sender.windows where window.level == .normal && window.isVisible {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }
}

extension Notification.Name {
    static let blissGlobalHotkey = Notification.Name("blissGlobalHotkey")
    static let blissOpenWindow = Notification.Name("blissOpenWindow")
    static let blissMenuStart = Notification.Name("blissMenuStart")
    static let blissMenuPanic = Notification.Name("blissMenuPanic")
    static let blissMenuSettings = Notification.Name("blissMenuSettings")
}

// MARK: - Menubar Timer

@MainActor
class MenuBarTimer: ObservableObject {
    @Published var title: String = "Bliss"
    @Published var isSessionActive: Bool = false

    /// Label shown in the menubar
    var menuBarLabel: String {
        if isSessionActive, let range = title.range(of: #"\d{2}:\d{2}:\d{2}"#, options: .regularExpression) {
            return "Bliss \(title[range])"
        }
        return "Bliss"
    }

    private var timer: Timer?
    private let endTimePath = "/var/db/bliss_end_time"

    init() {
        updateTitle()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTitle()
            }
        }
    }

    private func updateTitle() {
        guard let endTime = readEndTime() else {
            title = "Bliss"
            isSessionActive = false
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        let remaining = max(0, endTime - now)
        if remaining > 0 {
            isSessionActive = true
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            let secs = remaining % 60
            title = String(format: "Bliss %02d:%02d:%02d", hours, minutes, secs)
        } else {
            title = "Bliss"
            isSessionActive = false
        }
    }

    private func readEndTime() -> Int64? {
        guard let data = try? String(contentsOfFile: endTimePath, encoding: .utf8) else {
            return nil
        }
        return Int64(data.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Menubar Dropdown View

struct MenuBarView: View {
    @EnvironmentObject var timer: MenuBarTimer

    var body: some View {
        if timer.isSessionActive {
            Text(timer.title)
        } else {
            Text("No active session")
        }

        Divider()

        Button("Open Bliss") {
            openDashboard()
        }
        .keyboardShortcut("o")

        if timer.isSessionActive {
            Button("Panic") {
                openDashboard()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .blissMenuPanic, object: nil)
                }
            }
            .keyboardShortcut("p")
        } else {
            Button("Start Session") {
                openDashboard()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .blissMenuStart, object: nil)
                }
            }
            .keyboardShortcut("s")
        }

        Button("Settings") {
            openDashboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .blissMenuSettings, object: nil)
            }
        }

        Divider()

        Button("Quit Bliss") {
            BlissAppDelegate.shouldReallyQuit = true
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openDashboard() {
        NSApp.setActivationPolicy(.regular)
        // Bring back any normal window — even if hidden via orderOut
        for window in NSApp.windows where window.level == .normal {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .blissOpenWindow, object: nil)
    }
}
