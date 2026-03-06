    import Foundation
import SwiftUI

struct CFPanicTestCase: Codable {
    let input: String
    let output: String
}

struct CFPanicProblem: Codable, Identifiable {
    let id: String
    let title: String
    let statement: String
    let url: String
    let difficulty: String
    let input: String?
    let output: String?
    let tests: [CFPanicTestCase]
}

struct CFPanicLanguage: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let sourceFile: String
    let compile: [String]?
    let run: [String]
    let mainClass: String?
}

struct CFPanicLanguageFile: Codable {
    let languages: [CFPanicLanguage]
}

struct CFPanicJudgeResult {
    let passed: Bool
    let summary: String
}

struct CFPanicProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum CFPanicData {
    static func defaultLanguages() -> [CFPanicLanguage] {
        [
            CFPanicLanguage(
                id: "cpp17",
                displayName: "C++17 (clang++)",
                sourceFile: "main.cpp",
                compile: ["clang++", "-std=c++17", "-O2", "{source}", "-o", "{exe}"],
                run: ["{exe}"],
                mainClass: nil
            ),
            CFPanicLanguage(
                id: "python3",
                displayName: "Python 3",
                sourceFile: "solution.py",
                compile: nil,
                run: ["python3", "{source}"],
                mainClass: nil
            ),
            CFPanicLanguage(
                id: "java17",
                displayName: "Java 17",
                sourceFile: "Main.java",
                compile: ["javac", "{source}"],
                run: ["java", "-cp", ".", "{main_class}"],
                mainClass: "Main"
            )
        ]
    }

    static func loadLanguages() -> [CFPanicLanguage] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/panic_languages.json")
        guard let data = try? Data(contentsOf: path),
              let loaded = try? JSONDecoder().decode(CFPanicLanguageFile.self, from: data),
              !loaded.languages.isEmpty else {
            return defaultLanguages()
        }
        return loaded.languages
    }

    static func loadProblems() -> [CFPanicProblem] {
        for url in candidateProblemPaths() {
            guard let data = try? Data(contentsOf: url),
                  let loaded = try? JSONDecoder().decode([CFPanicProblem].self, from: data),
                  !loaded.isEmpty else {
                continue
            }
            return loaded
        }
        return []
    }

    private static func candidateProblemPaths() -> [URL] {
        var out: [URL] = []
        if let env = ProcessInfo.processInfo.environment["BLISS_CF_PROBLEMS"], !env.isEmpty {
            out.append(URL(fileURLWithPath: env))
        }
        out.append(URL(fileURLWithPath: "/usr/local/share/bliss/problems/codeforces.json"))
        out.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/bliss/problems/codeforces.json"))
        let bundleRoot = URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        out.append(bundleRoot.appendingPathComponent("problems/codeforces.json"))
        out.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("problems/codeforces.json"))
        return out
    }
}

enum CFPanicJudge {
    static func run(problem: CFPanicProblem, language: CFPanicLanguage, sourceCode: String) -> CFPanicJudgeResult {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("bliss_cf_\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return CFPanicJudgeResult(passed: false, summary: "Failed to create temp dir: \(error.localizedDescription)")
        }
        defer { try? fm.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent(language.sourceFile)
        do {
            try sourceCode.data(using: .utf8)?.write(to: sourceURL)
        } catch {
            return CFPanicJudgeResult(passed: false, summary: "Failed to write source: \(error.localizedDescription)")
        }

        let executableURL = tempDir.appendingPathComponent("solution_bin")
        if let compile = language.compile {
            let compileArgs = interpolate(
                compile,
                source: sourceURL.path,
                exe: executableURL.path,
                mainClass: language.mainClass ?? "Main"
            )
            let compileResult = runProcess(
                executable: compileArgs.first ?? "",
                arguments: Array(compileArgs.dropFirst()),
                workingDir: tempDir.path,
                stdin: nil,
                timeoutSeconds: 10
            )
            if compileResult.timedOut {
                return CFPanicJudgeResult(passed: false, summary: "Compilation timed out.")
            }
            if compileResult.exitCode != 0 {
                let message = compileResult.stderr.isEmpty ? compileResult.stdout : compileResult.stderr
                return CFPanicJudgeResult(passed: false, summary: "Compile failed:\n\(truncate(message, limit: 1000))")
            }
        }

        let runArgs = interpolate(
            language.run,
            source: sourceURL.path,
            exe: executableURL.path,
            mainClass: language.mainClass ?? "Main"
        )
        guard let executable = runArgs.first else {
            return CFPanicJudgeResult(passed: false, summary: "Invalid run command.")
        }

        for (index, test) in problem.tests.enumerated() {
            let result = runProcess(
                executable: executable,
                arguments: Array(runArgs.dropFirst()),
                workingDir: tempDir.path,
                stdin: test.input,
                timeoutSeconds: 4
            )
            if result.timedOut {
                return CFPanicJudgeResult(
                    passed: false,
                    summary: "Test \(index + 1) timed out."
                )
            }
            if result.exitCode != 0 {
                let error = result.stderr.isEmpty ? result.stdout : result.stderr
                return CFPanicJudgeResult(
                    passed: false,
                    summary: "Runtime error on test \(index + 1):\n\(truncate(error, limit: 1000))"
                )
            }
            let actual = normalize(result.stdout)
            let expected = normalize(test.output)
            if actual != expected {
                return CFPanicJudgeResult(
                    passed: false,
                    summary: """
                    Wrong answer on test \(index + 1)
                    expected:
                    \(truncate(expected, limit: 300))
                    got:
                    \(truncate(actual, limit: 300))
                    """
                )
            }
        }

        return CFPanicJudgeResult(passed: true, summary: "All tests passed (\(problem.tests.count)/\(problem.tests.count)).")
    }

    private static func interpolate(
        _ args: [String],
        source: String,
        exe: String,
        mainClass: String
    ) -> [String] {
        args.map { raw in
            raw.replacingOccurrences(of: "{source}", with: source)
                .replacingOccurrences(of: "{exe}", with: exe)
                .replacingOccurrences(of: "{main_class}", with: mainClass)
        }
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDir: String,
        stdin: String?,
        timeoutSeconds: TimeInterval
    ) -> CFPanicProcessResult {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if stdin != nil {
            process.standardInput = Pipe()
        }

        do {
            try process.run()
        } catch {
            return CFPanicProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: "Failed to run \(executable): \(error.localizedDescription)",
                timedOut: false
            )
        }

        if let stdin, let inPipe = process.standardInput as? Pipe {
            if let data = stdin.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            inPipe.fileHandleForWriting.closeFile()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CFPanicProcessResult(exitCode: process.terminationStatus, stdout: out, stderr: err, timedOut: timedOut)
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ s: String, limit: Int) -> String {
        if s.count <= limit {
            return s
        }
        return String(s.prefix(limit)) + "\n..."
    }
}

struct CodeforcesPanicView: View {
    let difficulty: CFPanicDifficulty
    let onUnlock: () async -> Bool

    @State private var problems: [CFPanicProblem] = []
    @State private var languages: [CFPanicLanguage] = []
    @State private var selectedLanguageID = ""
    @State private var code = ""
    @State private var resultText = ""
    @State private var testsPassed = false
    @State private var isRunning = false
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codeforces Panic")
                .font(.title3.weight(.semibold))

            if filteredProblems.isEmpty || languages.isEmpty {
                Text("Problem bank or language presets not found.")
                    .foregroundColor(.red)
                Text("Expected: /usr/local/share/bliss/problems/codeforces.json")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Text("Problem").font(.callout.weight(.semibold))
                    Spacer()
                    Text(difficulty.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let problem = selectedProblem, let language = selectedLanguage {
                    HStack {
                        Text("\(problem.id) \(problem.title)")
                            .font(.headline)
                        Spacer()
                        Picker("Language", selection: $selectedLanguageID) {
                            ForEach(languages) { lang in
                                Text(lang.displayName).tag(lang.id)
                            }
                        }
                        .frame(width: 220)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.caption.weight(.semibold))
                            Text(problem.statement)
                                .textSelection(.enabled)
                                .font(.system(.body, design: .monospaced))

                            if let input = problem.input {
                                Text("Input")
                                    .font(.caption.weight(.semibold))
                                    .padding(.top, 6)
                                Text(input)
                                    .textSelection(.enabled)
                                    .font(.system(.body, design: .monospaced))
                            }

                            if let output = problem.output {
                                Text("Output")
                                    .font(.caption.weight(.semibold))
                                    .padding(.top, 6)
                                Text(output)
                                    .textSelection(.enabled)
                                    .font(.system(.body, design: .monospaced))
                            }

                            Text(problem.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 170)
                    .padding(8)
                    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                    TextEditor(text: $code)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 220)
                        .border(.gray.opacity(0.3))
                        .onChange(of: selectedLanguageID) { _, _ in
                            testsPassed = false
                            code = ""
                        }

                    HStack {
                        Button("Run Tests") {
                            runTests(problem: problem, language: language)
                        }
                        .disabled(isRunning || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Submit Panic") {
                            submitPanic()
                        }
                        .disabled(isSubmitting || !testsPassed)

                        if isRunning || isSubmitting {
                            ProgressView().controlSize(.small)
                        }
                    }

                    Text(resultText)
                        .font(.footnote.monospaced())
                        .foregroundColor(testsPassed ? .green : .secondary)
                        .lineLimit(8)
                }
            }
        }
        .onAppear {
            problems = CFPanicData.loadProblems()
            languages = CFPanicData.loadLanguages()
            selectedLanguageID = languages.first?.id ?? ""
            pickRandomProblem()
        }
        .onChange(of: difficulty) { _, _ in
            pickRandomProblem()
        }
    }

    private var selectedProblem: CFPanicProblem? {
        if let current = currentProblem {
            return current
        }
        return filteredProblems.randomElement()
    }

    private var selectedLanguage: CFPanicLanguage? {
        languages.first(where: { $0.id == selectedLanguageID })
    }

    private var filteredProblems: [CFPanicProblem] {
        let matches = problems.filter { $0.difficulty.lowercased() == difficulty.rawValue }
        return matches.isEmpty ? problems : matches
    }

    @State private var currentProblem: CFPanicProblem?

    private func pickRandomProblem() {
        currentProblem = filteredProblems.randomElement()
        testsPassed = false
        code = ""
        resultText = ""
    }

    private func runTests(problem: CFPanicProblem, language: CFPanicLanguage) {
        testsPassed = false
        isRunning = true
        resultText = "Running tests..."
        let source = code
        Task {
            let result = await Task.detached { CFPanicJudge.run(problem: problem, language: language, sourceCode: source) }.value
            await MainActor.run {
                isRunning = false
                testsPassed = result.passed
                resultText = result.summary
            }
        }
    }

    private func submitPanic() {
        isSubmitting = true
        Task {
            let unlocked = await onUnlock()
            await MainActor.run {
                isSubmitting = false
                if !unlocked {
                    testsPassed = false
                    resultText = "Panic command failed. Session is still active."
                }
            }
        }
    }
}
