import Foundation

struct CommandResult {
    let code: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BlissCommand {
    static func executablePath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["BLISS_BIN"],
           FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }
        let devPath = "/Users/zain/Developer/bliss/build/bliss"
        if FileManager.default.isExecutableFile(atPath: devPath) {
            return devPath
        }
        let installed = "/usr/local/bin/bliss"
        if FileManager.default.isExecutableFile(atPath: installed) {
            return installed
        }
        return installed
    }

    static func run(_ args: [String]) -> CommandResult {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let selectedPath = executablePath()
        process.executableURL = URL(fileURLWithPath: selectedPath)
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(
                code: 127,
                stdout: "",
                stderr: "Failed to run bliss at \(selectedPath). Install or build Bliss first."
            )
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            code: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
