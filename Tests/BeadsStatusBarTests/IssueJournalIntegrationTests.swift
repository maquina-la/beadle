import Foundation
import Testing
@testable import BeadsStatusBar

/// Run explicitly with BEADLE_TEST_BD pointing at a Beads 1.3+ executable.
/// All mutations are confined to a disposable embedded workspace.
struct IssueJournalIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BEADLE_TEST_BD"] != nil))
    func realCLIJournalLifecycle() async throws {
        let executable = try #require(ProcessInfo.processInfo.environment["BEADLE_TEST_BD"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beadle-journal-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func run(_ arguments: [String], git: Bool = false) throws -> Data {
            let output = directory.appendingPathComponent("test-stdout")
            let errors = directory.appendingPathComponent("test-stderr")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            FileManager.default.createFile(atPath: errors.path, contents: nil)
            let stdout = try FileHandle(forWritingTo: output)
            let stderr = try FileHandle(forWritingTo: errors)
            defer { try? stdout.close(); try? stderr.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: git ? "/usr/bin/git" : executable)
            process.currentDirectoryURL = directory
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            var environment = ProcessInfo.processInfo.environment
            environment["BD_METRICS"] = "0"
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw BeadsClientError.commandFailed(String(decoding: try Data(contentsOf: errors), as: UTF8.self))
            }
            return try Data(contentsOf: output)
        }

        _ = try run(["init", "-q"], git: true)
        _ = try run(["init", "--non-interactive", "--prefix", "test", "--skip-hooks", "--skip-agents"])
        _ = try run(["config", "set", "events-journal", "true"])
        let created = try JSONDecoder().decode(BeadIssue.self, from: run(["create", "First", "--json"]))
        let project = ProjectConfiguration(name: "test", path: directory.path)
        var state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                        previous: nil, forceBaseline: false)
        #expect(state.checkpoint == 1 && state.issues.map(\.id) == [created.id])
        let quiet = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                       previous: state, forceBaseline: false)
        #expect(quiet.checkpoint == state.checkpoint && quiet.issues == state.issues)

        _ = try run(["update", created.id, "--title", "Updated", "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: state, forceBaseline: false)
        #expect(state.issues.first?.title == "Updated" && state.checkpoint == 2)
        _ = try run(["comments", "add", created.id, "A comment", "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: state, forceBaseline: false)
        #expect(state.issues.first?.commentCount == 1)

        let second = try JSONDecoder().decode(BeadIssue.self, from: run(["create", "Second", "--json"]))
        _ = try run(["dep", "add", second.id, created.id, "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: state, forceBaseline: false)
        #expect(state.issues.first { $0.id == second.id }?.dependencyCount == 1)
        #expect(state.issues.first { $0.id == second.id }?.normalizedStatus == .blocked)
        #expect(state.issues.first { $0.id == created.id }?.dependentCount == 1)
        _ = try run(["close", created.id, "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: state, forceBaseline: false)
        #expect(state.issues.first { $0.id == created.id }?.normalizedStatus == .closed)
        #expect(state.issues.first { $0.id == second.id }?.normalizedStatus == .open)

        _ = try run(["delete", second.id, "--force", "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: state, forceBaseline: false)
        #expect(state.issues.map(\.id) == [created.id])
        // Prune past an old cursor and verify rebuilding uses the CLI's
        // structured truncation head, rather than stalling on the old cursor.
        _ = try run(["config", "set", "events-journal-retain-days", "0"])
        _ = try run(["config", "set", "events-journal-retain-rows", "0"])
        _ = try run(["events", "prune", "--before", "100000", "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: quiet, forceBaseline: false)
        #expect(state.issues.first?.title == "Updated")
        #expect(state.issues.first?.normalizedStatus == .closed)
        #expect(try #require(state.checkpoint) > 1)
        _ = try run(["config", "set", "events-journal", "false"])
        _ = try run(["update", created.id, "--title", "Unjournaled", "--json"])
        state = try await BeadsClient.refreshIssues(for: project, configuredExecutable: executable,
                                                    previous: state, forceBaseline: false)
        #expect(state.checkpoint == nil && state.issues.first?.title == "Unjournaled")
    }
}
