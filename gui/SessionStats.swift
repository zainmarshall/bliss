import Foundation

struct SessionStats: Codable {
    var totalSessions: Int
    var totalFocusMinutes: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastSessionDate: String?
}

struct SessionLogEntry: Codable {
    let date: String      // yyyy-MM-dd
    let minutes: Int
    let startedAt: String // ISO8601 timestamp
}

enum SessionStatsManager {
    private static func statsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/stats.json")
    }

    private static func logURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/session_log.json")
    }

    private static func todayString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: Date())
    }

    private static func yesterdayString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return formatter.string(from: yesterday)
    }

    static func load() -> SessionStats {
        let url = statsURL()
        guard let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(SessionStats.self, from: data) else {
            return SessionStats(totalSessions: 0, totalFocusMinutes: 0, currentStreak: 0, longestStreak: 0, lastSessionDate: nil)
        }
        return stats
    }

    static func save(_ stats: SessionStats) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = statsURL()
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: url)
    }

    static func loadLog() -> [SessionLogEntry] {
        let url = logURL()
        guard let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode([SessionLogEntry].self, from: data) else {
            return []
        }
        return log
    }

    private static func saveLog(_ log: [SessionLogEntry]) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = logURL()
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: url)
    }

    /// Returns a dictionary of date string -> total focus minutes for that day.
    static func dailyMinutes() -> [String: Int] {
        let log = loadLog()
        var map: [String: Int] = [:]
        for entry in log {
            map[entry.date, default: 0] += entry.minutes
        }
        return map
    }

    static func recordSessionStart(minutes: Int) {
        var stats = load()
        stats.totalSessions += 1
        stats.totalFocusMinutes += minutes

        let today = todayString()
        let yesterday = yesterdayString()

        if let last = stats.lastSessionDate, last == today || last == yesterday {
            if last != today {
                stats.currentStreak += 1
            }
        } else {
            stats.currentStreak = 1
        }

        stats.longestStreak = max(stats.longestStreak, stats.currentStreak)
        stats.lastSessionDate = today
        save(stats)

        // Append to session log for heatmap
        let formatter = ISO8601DateFormatter()
        let entry = SessionLogEntry(
            date: today,
            minutes: minutes,
            startedAt: formatter.string(from: Date())
        )
        var log = loadLog()
        log.append(entry)
        saveLog(log)
    }

    static func recordPanic() {
    }
}
