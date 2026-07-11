// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0
//
// Test suite - entry point
// Validates the app's protocol/model/transport layers against a live ecmsim.
// Run via ./run-tests.sh (which starts its own simulator on a dedicated port,
// sandboxes HOME so backups don't touch your real Documents, and cleans up).

import Foundation

@main
struct ECMSimTestSuite {
    @MainActor
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let host = env["ECMSIM_HOST"] ?? "127.0.0.1"
        let port = UInt16(env["ECMSIM_PORT"] ?? "") ?? 6299

        guard DatabaseManager.shared.open() else {
            print("FATAL: could not open ecmdroid.db (must sit next to the test binary)")
            exit(2)
        }
        PDU.setProtocol(.stock)

        let runner = TestRunner()
        print("Unit tests:")
        await runUnitTests(runner)
        print("Integration tests (ecmsim @ \(host):\(port)):")
        await runIntegrationTests(runner, host: host, port: port)
        exit(runner.finish())
    }
}
