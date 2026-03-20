import Foundation
import SwiftUI

enum CompetitiveChallenge {
    static let definition = PanicChallengeDefinition(
        id: "competitive",
        displayName: "Competitive Programming",
        iconName: "chevron.left.forwardslash.chevron.right",
        shortDescription: "Solve a CSES problem of your selected difficulty.",
        makeChallengeView: { onSuccess in
            AnyView(CompetitivePanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(CompetitiveSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(CompetitiveWizardConfigView())
        }
    )
}

struct CompetitivePanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        CompetitivePanicView(difficulty: vm.cpDifficulty, onUnlock: onSuccess)
    }
}

struct CompetitiveSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
            Text("CSES problem difficulty")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.cpDifficulty },
                set: { vm.setCPDifficulty($0) }
            )) {
                Text("Easy").tag(CPDifficulty.easy)
                Text("Medium").tag(CPDifficulty.medium)
                Text("Hard").tag(CPDifficulty.hard)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct CompetitiveWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Problem Difficulty")
                    .font(.title2.weight(.semibold))
                Text("How hard should the CSES problem be?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                WizardOptionCard(title: "Easy", subtitle: "Introductory & sorting problems", selected: wizardState.cpDifficulty == .easy) { wizardState.cpDifficulty = .easy }
                WizardOptionCard(title: "Medium", subtitle: "Dynamic programming & graphs", selected: wizardState.cpDifficulty == .medium) { wizardState.cpDifficulty = .medium }
                WizardOptionCard(title: "Hard", subtitle: "Advanced tree & math problems", selected: wizardState.cpDifficulty == .hard) { wizardState.cpDifficulty = .hard }
            }
        }
    }
}

struct CPPanicTestCase: Codable {
    let input: String
    let output: String
}

struct CPPanicProblem: Codable, Identifiable {
    let id: String
    let title: String
    let statement: String
    let url: String
    let difficulty: String
    let input: String?
    let output: String?
    let constraints: String?
    let tests: [CPPanicTestCase]
}

struct CPPanicLanguage: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let sourceFile: String
    let compile: [String]?
    let run: [String]
    let mainClass: String?
}

struct CPPanicLanguageFile: Codable {
    let languages: [CPPanicLanguage]
}

struct CPPanicJudgeResult {
    let passed: Bool
    let summary: String
}

struct CPPanicProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

// LaTex Render (it is prounced latex like the thing is gloves not lay-tec, fight me)

enum MathRenderer {
    static func render(_ text: String) -> String {
        var result = text
        let subscriptMap: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
            "i": "ᵢ", "j": "ⱼ", "n": "ₙ", "k": "ₖ",
        ]
        let superscriptMap: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "n": "ⁿ", "i": "ⁱ",
        ]

        result = result.replacingOccurrences(
            of: #"_\{([^}]+)\}"#,
            with: "",
            options: .regularExpression
        )
        if let regex = try? NSRegularExpression(pattern: #"_\{([^}]+)\}"#) {
            var working = text
            let nsRange = NSRange(working.startIndex..., in: working)
            let matches = regex.matches(in: working, range: nsRange)
            for match in matches.reversed() {
                guard let contentRange = Range(match.range(at: 1), in: working),
                      let fullRange = Range(match.range, in: working) else { continue }
                let content = String(working[contentRange])
                let converted = content.map { subscriptMap[$0].map(String.init) ?? String($0) }.joined()
                working.replaceSubrange(fullRange, with: converted)
            }
            result = working
        }

        if let regex = try? NSRegularExpression(pattern: #"_([0-9a-z])"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange)
            for match in matches.reversed() {
                guard let charRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range, in: result) else { continue }
                let ch = result[charRange].first!
                let replacement = subscriptMap[ch].map(String.init) ?? "_\(ch)"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\^\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange)
            for match in matches.reversed() {
                guard let contentRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range, in: result) else { continue }
                let content = String(result[contentRange])
                let converted = content.map { superscriptMap[$0].map(String.init) ?? String($0) }.joined()
                result.replaceSubrange(fullRange, with: converted)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"\^([0-9a-z])"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange)
            for match in matches.reversed() {
                guard let charRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range, in: result) else { continue }
                let ch = result[charRange].first!
                let replacement = superscriptMap[ch].map(String.init) ?? "^\(ch)"
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        result = result.replacingOccurrences(of: "\\le ", with: "≤ ")
        result = result.replacingOccurrences(of: "\\le\n", with: "≤\n")
        result = result.replacingOccurrences(of: "\\ge ", with: "≥ ")
        result = result.replacingOccurrences(of: "\\ge\n", with: "≥\n")
        result = result.replacingOccurrences(of: "\\leq ", with: "≤ ")
        result = result.replacingOccurrences(of: "\\geq ", with: "≥ ")
        result = result.replacingOccurrences(of: "\\ne ", with: "≠ ")
        result = result.replacingOccurrences(of: "\\neq ", with: "≠ ")
        result = result.replacingOccurrences(of: "\\dots", with: "…")
        result = result.replacingOccurrences(of: "\\ldots", with: "…")
        result = result.replacingOccurrences(of: "\\cdot ", with: "· ")
        result = result.replacingOccurrences(of: "\\cdots", with: "⋯")
        result = result.replacingOccurrences(of: "\\times ", with: "× ")
        result = result.replacingOccurrences(of: "\\infty", with: "∞")
        result = result.replacingOccurrences(of: "\\sum", with: "∑")
        result = result.replacingOccurrences(of: "\\prod", with: "∏")
        result = result.replacingOccurrences(of: "\\sqrt", with: "√")
        result = result.replacingOccurrences(of: "\\pm ", with: "± ")
        result = result.replacingOccurrences(of: "\\in ", with: "∈ ")
        result = result.replacingOccurrences(of: "\\notin ", with: "∉ ")
        result = result.replacingOccurrences(of: "\\subset ", with: "⊂ ")
        result = result.replacingOccurrences(of: "\\subseteq ", with: "⊆ ")
        result = result.replacingOccurrences(of: "\\cup ", with: "∪ ")
        result = result.replacingOccurrences(of: "\\cap ", with: "∩ ")
        result = result.replacingOccurrences(of: "\\forall ", with: "∀ ")
        result = result.replacingOccurrences(of: "\\exists ", with: "∃ ")
        result = result.replacingOccurrences(of: "\\rightarrow ", with: "→ ")
        result = result.replacingOccurrences(of: "\\leftarrow ", with: "← ")
        result = result.replacingOccurrences(of: "\\lfloor ", with: "⌊")
        result = result.replacingOccurrences(of: "\\rfloor ", with: "⌋")
        result = result.replacingOccurrences(of: "\\lceil ", with: "⌈")
        result = result.replacingOccurrences(of: "\\rceil ", with: "⌉")
        result = result.replacingOccurrences(of: "\\bmod ", with: " mod ")
        result = result.replacingOccurrences(of: "\\mod ", with: " mod ")
        result = result.replacingOccurrences(of: "\\log ", with: "log ")
        result = result.replacingOccurrences(of: "\\min ", with: "min ")
        result = result.replacingOccurrences(of: "\\max ", with: "max ")
        result = result.replacingOccurrences(of: "\\gcd ", with: "gcd ")

        if let regex = try? NSRegularExpression(pattern: #"\\text\{([^}]*)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }
        if let regex = try? NSRegularExpression(pattern: #"\\(?:mathrm|mathit|mathbf)\{([^}]*)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        return result
    }
}

enum CPPanicData {
    static func defaultLanguages() -> [CPPanicLanguage] {
        [
            CPPanicLanguage(
                id: "cpp17",
                displayName: "C++17 (clang++)",
                sourceFile: "main.cpp",
                compile: ["clang++", "-std=c++17", "-O2", "{source}", "-o", "{exe}"],
                run: ["{exe}"],
                mainClass: nil
            ),
            CPPanicLanguage(
                id: "python3",
                displayName: "Python 3",
                sourceFile: "solution.py",
                compile: nil,
                run: ["python3", "{source}"],
                mainClass: nil
            ),
            CPPanicLanguage(
                id: "java17",
                displayName: "Java 17",
                sourceFile: "Main.java",
                compile: ["javac", "{source}"],
                run: ["java", "-cp", ".", "{main_class}"],
                mainClass: "Main"
            ),
            //holy tuff insane aura langauge who made this tuff ahh insane super cool auraful language?!
            CPPanicLanguage(
                id: "zenpp",
                displayName: "Zen++",
                sourceFile: "solution.zpp",
                compile: nil,
                run: ["/usr/local/bin/zenpp", "{source}"],
                mainClass: nil
            )
        ]
    }

    static func loadLanguages() -> [CPPanicLanguage] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bliss/panic_languages.json")
        guard let data = try? Data(contentsOf: path),
              let loaded = try? JSONDecoder().decode(CPPanicLanguageFile.self, from: data),
              !loaded.languages.isEmpty else {
            return defaultLanguages()
        }
        return loaded.languages
    }

    static func loadProblems() -> [CPPanicProblem] {
        for url in candidateProblemPaths() {
            guard let data = try? Data(contentsOf: url),
                  let loaded = try? JSONDecoder().decode([CPPanicProblem].self, from: data),
                  !loaded.isEmpty else {
                continue
            }
            return loaded
        }
        return []
    }

    private static func candidateProblemPaths() -> [URL] {
        let fileName = "problems.json"
        var out: [URL] = []

        // Env var override
        if let env = ProcessInfo.processInfo.environment["BLISS_PROBLEMS"], !env.isEmpty {
            out.append(URL(fileURLWithPath: env))
        }
        // Legacy env var
        if let env = ProcessInfo.processInfo.environment["BLISS_CF_PROBLEMS"], !env.isEmpty {
            out.append(URL(fileURLWithPath: env))
        }

        // Installed location
        out.append(URL(fileURLWithPath: "/usr/local/share/bliss/problems/\(fileName)"))
        out.append(URL(fileURLWithPath: "/usr/local/share/bliss/problems/codeforces.json"))

        // User config
        let home = FileManager.default.homeDirectoryForCurrentUser
        out.append(home.appendingPathComponent(".config/bliss/problems/\(fileName)"))
        out.append(home.appendingPathComponent(".config/bliss/problems/codeforces.json"))

        // Current working directory fallback
        out.append(URL(fileURLWithPath: "problems/\(fileName)"))
        out.append(URL(fileURLWithPath: "problems/codeforces.json"))

        // Bundle-relative (3 levels up from executable inside .app bundle)
        let bundleRoot = URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        out.append(bundleRoot.appendingPathComponent("problems/\(fileName)"))
        out.append(bundleRoot.appendingPathComponent("problems/codeforces.json"))

        // CWD
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        out.append(cwd.appendingPathComponent("problems/\(fileName)"))
        out.append(cwd.appendingPathComponent("problems/codeforces.json"))

        return out
    }
}

// judgeman - liek Higuruma from jjk ykyk
enum CPPanicJudge {
    static func run(problem: CPPanicProblem, language: CPPanicLanguage, sourceCode: String) -> CPPanicJudgeResult {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("bliss_cp_\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return CPPanicJudgeResult(passed: false, summary: "Failed to create temp dir: \(error.localizedDescription)")
        }
        defer { try? fm.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent(language.sourceFile)
        do {
            try sourceCode.data(using: .utf8)?.write(to: sourceURL)
        } catch {
            return CPPanicJudgeResult(passed: false, summary: "Failed to write source: \(error.localizedDescription)")
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
                return CPPanicJudgeResult(passed: false, summary: "Compilation timed out.")
            }
            if compileResult.exitCode != 0 {
                let message = compileResult.stderr.isEmpty ? compileResult.stdout : compileResult.stderr
                return CPPanicJudgeResult(passed: false, summary: "Compile failed:\n\(truncate(message, limit: 1000))")
            }
        }

        let runArgs = interpolate(
            language.run,
            source: sourceURL.path,
            exe: executableURL.path,
            mainClass: language.mainClass ?? "Main"
        )
        guard let executable = runArgs.first else {
            return CPPanicJudgeResult(passed: false, summary: "Invalid run command.")
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
                return CPPanicJudgeResult(
                    passed: false,
                    summary: "Test \(index + 1) timed out."
                )
            }
            if result.exitCode != 0 {
                let error = result.stderr.isEmpty ? result.stdout : result.stderr
                return CPPanicJudgeResult(
                    passed: false,
                    summary: "Runtime error on test \(index + 1):\n\(truncate(error, limit: 1000))"
                )
            }
            let actual = normalize(result.stdout)
            let expected = normalize(test.output)
            if actual != expected {
                return CPPanicJudgeResult(
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

        return CPPanicJudgeResult(passed: true, summary: "All tests passed (\(problem.tests.count)/\(problem.tests.count)).")
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
    ) -> CPPanicProcessResult {
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
        let inPipe = stdin != nil ? Pipe() : nil
        if inPipe != nil { process.standardInput = inPipe }

        do {
            try process.run()
        } catch {
            return CPPanicProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: "Failed to run \(executable): \(error.localizedDescription)",
                timedOut: false
            )
        }

        if let inPipe, let data = stdin?.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
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
        return CPPanicProcessResult(exitCode: process.terminationStatus, stdout: out, stderr: err, timedOut: timedOut)
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

struct CompetitivePanicView: View {
    let difficulty: CPDifficulty
    let onUnlock: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var problems: [CPPanicProblem] = []
    @State private var languages: [CPPanicLanguage] = []
    @State private var selectedLanguageID = ""
    @State private var code = ""
    @State private var resultText = ""
    @State private var testsPassed = false
    @State private var isRunning = false
    @State private var isSubmitting = false
    @State private var currentProblem: CPPanicProblem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Competitive Programming Panic")
                    .font(.title3.weight(.semibold))

                if filteredProblems.isEmpty || languages.isEmpty {
                    errorSection
                } else if let problem = selectedProblem, let language = selectedLanguage {
                    problemHeader(problem)
                    problemDescription(problem)
                    codeEditor
                    controlBar(problem: problem, language: language)
                }
            }
        }
        .onAppear {
            problems = CPPanicData.loadProblems()
            languages = CPPanicData.loadLanguages()
            selectedLanguageID = languages.first?.id ?? ""
            pickRandomProblem()
        }
        .onChange(of: difficulty) {
            pickRandomProblem()
        }
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Problem bank or language presets not found.")
                .foregroundColor(.red)
            Text("Looked in:")
                .font(.caption).foregroundColor(.secondary)
            Text("  /usr/local/share/bliss/problems/problems.json")
                .font(.caption).foregroundColor(.secondary)
            Text("  ~/.config/bliss/problems/problems.json")
                .font(.caption).foregroundColor(.secondary)
            if !problems.isEmpty {
                Text("Loaded \(problems.count) problems, but none match difficulty \"\(difficulty.rawValue)\".")
                    .font(.caption).foregroundColor(.orange)
            }
            if languages.isEmpty {
                Text("No language presets loaded. Check panic_languages.json or defaults.")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    private func problemHeader(_ problem: CPPanicProblem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Problem").font(.callout.weight(.semibold))
                Spacer()
                Text(difficulty.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("\(problem.id) \u{2014} \(problem.title)")
                    .font(.headline)
                Spacer()
                Picker("Language", selection: $selectedLanguageID) {
                    ForEach(languages) { lang in
                        Text(lang.displayName).tag(lang.id)
                    }
                }
                .frame(width: 220)
            }
        }
    }

    private func problemDescription(_ problem: CPPanicProblem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.caption.weight(.semibold))
                Text(MathRenderer.render(problem.statement))
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))

                if let input = problem.input {
                    Text("Input")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)
                    Text(MathRenderer.render(input))
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }

                if let output = problem.output {
                    Text("Output")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)
                    Text(MathRenderer.render(output))
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }

                if let constraints = problem.constraints {
                    Text("Constraints")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)
                    Text(MathRenderer.render(constraints))
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }

                if !problem.tests.isEmpty {
                    Text("Examples")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)
                    ForEach(Array(problem.tests.enumerated()), id: \.offset) { idx, test in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Input \(idx + 1)").font(.caption2.weight(.medium))
                                Text(test.input.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Output \(idx + 1)").font(.caption2.weight(.medium))
                                Text(test.output.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(6)
                        .background(.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                    }
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
    }

    private var codeEditor: some View {
        TextEditor(text: $code)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15))
            )
            .frame(height: 240)
            .onChange(of: selectedLanguageID) {
                testsPassed = false
                code = ""
            }
    }

    private func controlBar(problem: CPPanicProblem, language: CPPanicLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private var selectedProblem: CPPanicProblem? { currentProblem }

    private var selectedLanguage: CPPanicLanguage? {
        languages.first(where: { $0.id == selectedLanguageID })
    }

    private var filteredProblems: [CPPanicProblem] {
        let matches = problems.filter { $0.difficulty.lowercased() == difficulty.rawValue }
        return matches.isEmpty ? problems : matches
    }

    private func pickRandomProblem() {
        currentProblem = filteredProblems.randomElement()
        testsPassed = false
        code = ""
        resultText = ""
    }

    private func runTests(problem: CPPanicProblem, language: CPPanicLanguage) {
        testsPassed = false
        isRunning = true
        resultText = "Running tests..."
        let source = code
        Task {
            let result = await Task.detached { CPPanicJudge.run(problem: problem, language: language, sourceCode: source) }.value
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
                if unlocked {
                    dismiss()
                } else {
                    testsPassed = false
                    resultText = "Command failed — try again."
                }
            }
        }
    }
}
