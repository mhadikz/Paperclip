import Foundation

/// Minimal test runner. XCTest is not available to Command Line Tools builds, and the
/// suite must run from `scripts/test.sh` on a machine without Xcode.
@MainActor
final class TestRunner {
    private struct Case {
        let name: String
        let body: @MainActor () async throws -> Void
    }

    private var cases: [Case] = []
    private var only: String?

    init(filter: String? = nil) {
        only = filter
    }

    func test(_ name: String, _ body: @escaping @MainActor () throws -> Void) {
        cases.append(Case(name: name, body: { try body() }))
    }

    func asyncTest(_ name: String, _ body: @escaping @MainActor () async throws -> Void) {
        cases.append(Case(name: name, body: body))
    }

    func run() async -> Int {
        var failed = 0
        var passed = 0
        let start = Date()
        for testCase in cases {
            if let only, !testCase.name.localizedCaseInsensitiveContains(only) { continue }
            do {
                try await testCase.body()
                passed += 1
                print("PASS  \(testCase.name)")
            } catch {
                failed += 1
                print("FAIL  \(testCase.name)\n      \(error)")
            }
        }
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        if failed == 0 {
            print("\n✅ \(passed) tests passed in \(elapsed)")
        } else {
            print("\n❌ \(failed) of \(passed + failed) tests failed in \(elapsed)")
        }
        return failed
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int
    var description: String { "\(message)  [\((file as NSString).lastPathComponent):\(line)]" }
}

func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) throws {
    if !condition { throw TestFailure(message: message, file: file, line: line) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) throws {
    if actual != expected {
        throw TestFailure(message: "\(message) expected \(expected), got \(actual)", file: file, line: line)
    }
}

func expectThrows(_ message: String, file: String = #fileID, line: Int = #line, _ body: () async throws -> Void) async throws {
    do {
        try await body()
    } catch {
        return
    }
    throw TestFailure(message: message, file: file, line: line)
}

enum TestDefaults {
    static let suite = "PaperclipTests"

    /// Empty `UserDefaults` domain shared by all tests; wiped on every call so nothing accumulates
    /// in `~/Library/Preferences`.
    static func fresh() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

enum TestTemp {
    /// Fresh directory under the system temp folder.
    static func directory(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperclipTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@main
struct PaperclipTestsMain {
    @MainActor
    static func main() async {
        let filter = CommandLine.arguments.dropFirst().first
        let runner = TestRunner(filter: filter)
        registerSensitiveContentTests(runner)
        registerModelTests(runner)
        registerHeuristicTests(runner)
        registerSearchTests(runner)
        registerPersistenceTests(runner)
        registerRepositoryTests(runner)
        registerCaptureTests(runner)
        registerPasteAndDeleteTests(runner)
        registerAITests(runner)
        registerViewModelTests(runner)
        let failed = await runner.run()
        exit(failed == 0 ? 0 : 1)
    }
}
