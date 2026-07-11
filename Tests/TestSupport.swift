// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0
//
// Test suite - shared test runner.
// Run via ./run-tests.sh in the project root. Not part of the app target;
// compiled for macOS together with the app's transport/protocol/model sources.

import Foundation

@MainActor
final class TestRunner {
    private(set) var passed = 0
    private(set) var failed = 0
    private var failures: [String] = []
    private var currentTest = ""
    private var currentFailed = false

    func test(_ name: String, _ body: @MainActor () async throws -> Void) async {
        currentTest = name
        currentFailed = false
        do {
            try await body()
        } catch {
            record("unexpectedly threw: \(error.localizedDescription)")
        }
        if currentFailed {
            failed += 1
            print("  ✗ \(name)")
        } else {
            passed += 1
            print("  ✓ \(name)")
        }
    }

    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition {
            record("\(message) (line \(line))")
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
        if actual != expected {
            record("\(message): expected \(expected), got \(actual) (line \(line))")
        }
    }

    /// Runs `body` expecting it to throw; returns the error (or records a failure).
    @discardableResult
    func expectThrows(_ label: String, line: Int = #line, _ body: @MainActor () async throws -> Void) async -> Error? {
        do {
            try await body()
            record("\(label): expected an error but none was thrown (line \(line))")
            return nil
        } catch {
            return error
        }
    }

    private func record(_ message: String) {
        failures.append("\(currentTest): \(message)")
        currentFailed = true
        print("    FAIL: \(message)")
    }

    /// Prints the summary and returns the process exit code.
    func finish() -> Int32 {
        print("")
        if failures.isEmpty {
            print("ALL \(passed) TESTS PASSED")
            return 0
        }
        print("\(passed) passed, \(failed) FAILED:")
        for f in failures {
            print("  - \(f)")
        }
        return 1
    }
}

func sleepMs(_ ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
}
