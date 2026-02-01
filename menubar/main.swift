import Cocoa

let endTimePath = "/var/db/bliss_end_time"

final class BlissStatusBar {
    private let statusItem: NSStatusItem
    private var timer: Timer?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Bliss --:--"
        statusItem.menu = buildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTitle()
        }
        updateTitle()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func readEndTime() -> Int64? {
        guard let data = try? String(contentsOfFile: endTimePath, encoding: .utf8) else {
            return nil
        }
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(trimmed)
    }

    private func formatRemaining(_ seconds: Int64) -> String {
        if seconds <= 0 { return "00:00" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func updateTitle() {
        guard let endTime = readEndTime() else {
            statusItem.button?.title = "Bliss --:--"
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        let remaining = max(0, endTime - now)
        statusItem.button?.title = "Bliss \(formatRemaining(remaining))"
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var statusApp: BlissStatusBar? = BlissStatusBar()
app.run()
