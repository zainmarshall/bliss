// Standalone Swift tests for GUI logic (no XCTest dependency)
// Tests: MathRenderer, problem loading, judge normalization, config parsing

import Foundation

// Redeclare types from GUI sources that depend on SwiftUI and can't be compiled standalone.

enum PanicModeSetting: String, CaseIterable {
    case typing = "typing"
    case competitive = "competitive"
}

enum CPDifficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
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

enum CPPanicData {
    static func defaultLanguages() -> [CPPanicLanguage] {
        [
            CPPanicLanguage(id: "cpp17", displayName: "C++17 (clang++)", sourceFile: "main.cpp",
                compile: ["clang++", "-std=c++17", "-O2", "{source}", "-o", "{exe}"], run: ["{exe}"], mainClass: nil),
            CPPanicLanguage(id: "python3", displayName: "Python 3", sourceFile: "solution.py",
                compile: nil, run: ["python3", "{source}"], mainClass: nil),
            CPPanicLanguage(id: "java17", displayName: "Java 17", sourceFile: "Main.java",
                compile: ["javac", "{source}"], run: ["java", "-cp", ".", "{main_class}"], mainClass: "Main"),
        ]
    }
}

// Copy of MathRenderer from CodeforcesPanic.swift for testing
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

var testsRun = 0
var testsPassed = 0

func check(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    testsRun += 1
    if condition {
        testsPassed += 1
    } else {
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    testsRun += 1
    if a == b {
        testsPassed += 1
    } else {
        print("  FAIL: got \"\(a)\" expected \"\(b)\" \(message) (\(file):\(line))")
    }
}

// ---- MathRenderer tests ----

func testMathRendererBasicSymbols() {
    print("test: math_renderer_basic_symbols")
    let result = MathRenderer.render("1 \\le n \\le 10^5")
    check(result.contains("≤"), "should convert \\le to ≤")
    check(result.contains("⁵"), "should convert ^5 to superscript")
}

func testMathRendererSubscripts() {
    print("test: math_renderer_subscripts")
    let result = MathRenderer.render("a_1,a_2,\\dots,a_n")
    check(result.contains("₁"), "should convert _1 to subscript")
    check(result.contains("₂"), "should convert _2 to subscript")
    check(result.contains("ₙ"), "should convert _n to subscript")
    check(result.contains("…"), "should convert \\dots to ellipsis")
}

func testMathRendererBracedSuperscript() {
    print("test: math_renderer_braced_superscript")
    let result = MathRenderer.render("2 \\cdot 10^{5}")
    check(result.contains("·"), "should convert \\cdot to ·")
    check(result.contains("⁵"), "should convert ^{5} to superscript")
}

func testMathRendererComparisons() {
    print("test: math_renderer_comparisons")
    assertEqual(MathRenderer.render("\\ge "), "≥ ")
    assertEqual(MathRenderer.render("\\ne "), "≠ ")
    assertEqual(MathRenderer.render("\\leq "), "≤ ")
    assertEqual(MathRenderer.render("\\geq "), "≥ ")
}

func testMathRendererArrowsAndSets() {
    print("test: math_renderer_arrows_and_sets")
    check(MathRenderer.render("\\rightarrow ").contains("→"))
    check(MathRenderer.render("\\leftarrow ").contains("←"))
    check(MathRenderer.render("\\in ").contains("∈"))
    check(MathRenderer.render("\\infty").contains("∞"))
}

func testMathRendererTextCommand() {
    print("test: math_renderer_text_command")
    let result = MathRenderer.render("\\text{hello}")
    assertEqual(result, "hello")
}

func testMathRendererFloorCeil() {
    print("test: math_renderer_floor_ceil")
    let result = MathRenderer.render("\\lfloor x \\rfloor ")
    check(result.contains("⌊"), "should have floor left")
    check(result.contains("⌋"), "should have floor right")
}

func testMathRendererPlainTextPassthrough() {
    print("test: math_renderer_plain_text")
    let input = "Given an array of n integers"
    assertEqual(MathRenderer.render(input), input, "plain text should pass through unchanged")
}

// ---- CPPanicProblem JSON decoding tests ----

func testProblemDecoding() {
    print("test: problem_json_decoding")
    let json = """
    [{
        "id": "cses-1640",
        "title": "Sum of Two Values",
        "url": "https://cses.fi/problemset/task/1640",
        "difficulty": "easy",
        "statement": "Find two values whose sum is x.",
        "input": "First line has n and x.",
        "output": "Print two integers.",
        "constraints": "1 \\\\le n \\\\le 10^5",
        "tests": [{"input": "4 8\\n2 7 5 1\\n", "output": "2 4\\n"}]
    }]
    """.data(using: .utf8)!

    let problems = try? JSONDecoder().decode([CPPanicProblem].self, from: json)
    check(problems != nil, "should decode problem JSON")
    assertEqual(problems?.count ?? 0, 1)
    assertEqual(problems?[0].title ?? "", "Sum of Two Values")
    assertEqual(problems?[0].difficulty ?? "", "easy")
    check(problems?[0].constraints != nil, "should have constraints field")
    assertEqual(problems?[0].tests.count ?? 0, 1)
}

func testProblemDecodingWithoutOptionalFields() {
    print("test: problem_decoding_without_optionals")
    let json = """
    [{
        "id": "test-1",
        "title": "Test",
        "url": "https://example.com",
        "difficulty": "easy",
        "statement": "Do something.",
        "tests": []
    }]
    """.data(using: .utf8)!

    let problems = try? JSONDecoder().decode([CPPanicProblem].self, from: json)
    check(problems != nil, "should decode without optional fields")
    check(problems?[0].input == nil, "input should be nil")
    check(problems?[0].output == nil, "output should be nil")
    check(problems?[0].constraints == nil, "constraints should be nil")
}

// ---- Language decoding tests ----

func testLanguageDecoding() {
    print("test: language_json_decoding")
    let json = """
    {
        "languages": [{
            "id": "cpp17",
            "displayName": "C++17",
            "sourceFile": "main.cpp",
            "compile": ["clang++", "-std=c++17", "{source}", "-o", "{exe}"],
            "run": ["{exe}"],
            "mainClass": null
        }]
    }
    """.data(using: .utf8)!

    let file = try? JSONDecoder().decode(CPPanicLanguageFile.self, from: json)
    check(file != nil, "should decode language JSON")
    assertEqual(file?.languages.count ?? 0, 1)
    assertEqual(file?.languages[0].id ?? "", "cpp17")
    check(file?.languages[0].compile != nil, "should have compile command")
    check(file?.languages[0].mainClass == nil, "mainClass should be nil for C++")
}

// ---- Default languages tests ----

func testDefaultLanguages() {
    print("test: default_languages")
    let langs = CPPanicData.defaultLanguages()
    check(langs.count >= 3, "should have at least 3 default languages")

    let ids = langs.map { $0.id }
    check(ids.contains("cpp17"), "should include C++17")
    check(ids.contains("python3"), "should include Python 3")
    check(ids.contains("java17"), "should include Java 17")

    // C++ should have compile step
    let cpp = langs.first { $0.id == "cpp17" }!
    check(cpp.compile != nil, "C++ should have compile command")

    // Python should not have compile step
    let py = langs.first { $0.id == "python3" }!
    check(py.compile == nil, "Python should not have compile command")
}

// ---- Problem filtering tests ----

func testProblemFiltering() {
    print("test: problem_filtering_by_difficulty")
    let problems = [
        makeProblem(id: "1", difficulty: "easy"),
        makeProblem(id: "2", difficulty: "easy"),
        makeProblem(id: "3", difficulty: "medium"),
        makeProblem(id: "4", difficulty: "hard"),
    ]

    let easy = problems.filter { $0.difficulty.lowercased() == "easy" }
    assertEqual(easy.count, 2)

    let medium = problems.filter { $0.difficulty.lowercased() == "medium" }
    assertEqual(medium.count, 1)

    let hard = problems.filter { $0.difficulty.lowercased() == "hard" }
    assertEqual(hard.count, 1)

    // Unknown difficulty should return empty (app falls back to all)
    let expert = problems.filter { $0.difficulty.lowercased() == "expert" }
    assertEqual(expert.count, 0)
}

func makeProblem(id: String, difficulty: String) -> CPPanicProblem {
    CPPanicProblem(
        id: id, title: "P\(id)", statement: "stmt",
        url: "https://example.com", difficulty: difficulty,
        input: nil, output: nil, constraints: nil,
        tests: []
    )
}

// ---- PanicModeSetting tests ----

func testPanicModeSettingRawValues() {
    print("test: panic_mode_raw_values")
    assertEqual(PanicModeSetting.typing.rawValue, "typing")
    assertEqual(PanicModeSetting.competitive.rawValue, "competitive")
    check(PanicModeSetting(rawValue: "codeforces") == nil, "old value should not parse directly")
    check(PanicModeSetting(rawValue: "competitive") == .competitive)
}

func testCPDifficultyRawValues() {
    print("test: cp_difficulty_raw_values")
    assertEqual(CPDifficulty.easy.rawValue, "easy")
    assertEqual(CPDifficulty.medium.rawValue, "medium")
    assertEqual(CPDifficulty.hard.rawValue, "hard")
}

// ---- Entry point ----

@main
struct TestRunner {
    static func main() {
        print("\n=== bliss Swift unit tests ===\n")

        testMathRendererBasicSymbols()
        testMathRendererSubscripts()
        testMathRendererBracedSuperscript()
        testMathRendererComparisons()
        testMathRendererArrowsAndSets()
        testMathRendererTextCommand()
        testMathRendererFloorCeil()
        testMathRendererPlainTextPassthrough()
        testProblemDecoding()
        testProblemDecodingWithoutOptionalFields()
        testLanguageDecoding()
        testDefaultLanguages()
        testProblemFiltering()
        testPanicModeSettingRawValues()
        testCPDifficultyRawValues()

        print("\n\(testsPassed)/\(testsRun) assertions passed")
        if testsPassed == testsRun {
            print("ALL TESTS PASSED")
            exit(0)
        } else {
            print("SOME TESTS FAILED")
            exit(1)
        }
    }
}
