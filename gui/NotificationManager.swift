import UserNotifications

enum BlissNotifications {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sessionStarted(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Focus session started"
        content.body = "\(minutes) minutes of deep work. You've got this."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "bliss-start", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleFiveMinWarning(totalSeconds: Int) {
        let delay = totalSeconds - 300
        guard delay > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "5 minutes remaining"
        content.body = "Almost there. Finish strong."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(delay), repeats: false)
        let request = UNNotificationRequest(identifier: "bliss-5min", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleSessionEnd(totalSeconds: Int) {
        guard totalSeconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Session complete"
        content.body = "Nice work. Take a break."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(totalSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: "bliss-end", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
