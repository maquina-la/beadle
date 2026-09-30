import Foundation

enum BeadsClientError: LocalizedError {
    case executableNotFound
    case projectMissing(String)
    case commandFailed(String)
    case invalidResponse(String)
    case journalTruncated(Int64)
    case journalDisabled

    var errorDescription: String? {
        switch self {
        case .journalTruncated:
            "The event journal checkpoint has expired."
        case .journalDisabled:
            "The event journal is disabled."
        case .executableNotFound:
            "Could not find the bd executable. Install Beads or set its path in Settings."
        case .projectMissing(let path):
            "The project folder no longer exists: \(path)"
        case .commandFailed(let message):
            message
        case .invalidResponse(let message):
            "Could not read bd output: \(message)"
        }
    }
}

struct BeadsClient: Sendable {
    static func loadIssues(
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) async throws -> [BeadIssue] {
        try await Task.detached(priority: .userInitiated) {
            try loadIssuesSynchronously(
                for: project,
                configuredExecutable: configuredExecutable
            )
        }.value
    }

    static func refreshIssues(
        for project: ProjectConfiguration, configuredExecutable: String?,
        previous: IssueJournal?, forceBaseline: Bool
    ) async throws -> IssueJournal {
        let executable = resolveExecutable(configuredExecutable: configuredExecutable) ?? ""
        return try await IssueJournal.refresh(
            previous: previous, source: project.path + "\n" + executable,
            forceBaseline: forceBaseline,
            readEvents: { since in
                try await Task.detached(priority: .utility) {
                    let data = try runSynchronously(
                        arguments: ["events", "tail", "--since", String(since), "--json",
                                    "--readonly", "--sandbox"],
                        project: project, configuredExecutable: configuredExecutable
                    )
                    return try IssueEvent.decode(data, since: since)
                }.value
            },
            readIssues: { try await loadIssues(for: project, configuredExecutable: configuredExecutable) },
            readDetail: { id in
                try await Task.detached(priority: .utility) {
                    // Use list's projection and visibility rules, rather than
                    // show (which also returns hidden infrastructure issues).
                    let data = try runSynchronously(
                        arguments: ["list", "--id=\(id)", "--all", "--json", "--limit", "0",
                                    "--no-pager", "--readonly", "--sandbox"],
                        project: project, configuredExecutable: configuredExecutable
                    )
                    guard let row = try JSONDecoder().decode([BeadIssue].self, from: data).first,
                          row.id == id else {
                        throw BeadsClientError.invalidResponse("Changed issue is no longer visible.")
                    }
                    return row
                }.value
            }
        )
    }

    static func loadIssueDetails(
        issueID: String,
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) async throws -> BeadIssue {
        try await Task.detached(priority: .userInitiated) {
            let data = try runSynchronously(
                arguments: [
                    "show", "--id=\(issueID)", "--json",
                    "--readonly", "--sandbox"
                ],
                project: project,
                configuredExecutable: configuredExecutable
            )

            do {
                guard let issue = try JSONDecoder().decode([BeadIssue].self, from: data).first else {
                    throw BeadsClientError.invalidResponse("bd returned no issue details.")
                }
                return issue
            } catch let error as BeadsClientError {
                throw error
            } catch {
                throw BeadsClientError.invalidResponse(error.localizedDescription)
            }
        }.value
    }

    private static func loadIssuesSynchronously(
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) throws -> [BeadIssue] {
        let outputData = try runSynchronously(
            arguments: [
                "list", "--all", "--json", "--limit", "0", "--no-pager",
                "--readonly", "--sandbox"
            ],
            project: project,
            configuredExecutable: configuredExecutable
        )

        // bd list's projection omits is_blocked even in 1.3. Read the
        // authoritative readiness projection when rebuilding the baseline.
        let blockedData = try runSynchronously(
            arguments: ["blocked", "--json", "--readonly", "--sandbox"],
            project: project, configuredExecutable: configuredExecutable
        )
        do {
            let blocked = Set(try JSONDecoder().decode([BlockedIssue].self, from: blockedData).map(\.id))
            return try JSONDecoder().decode([BeadIssue].self, from: outputData).map { row in
                var issue = row
                issue.isBlocked = blocked.contains(issue.id)
                return issue
            }
        } catch {
            throw BeadsClientError.invalidResponse(error.localizedDescription)
        }
    }

    private struct BlockedIssue: Decodable {
        let id: String
    }

    private static func runSynchronously(
        arguments: [String],
        project: ProjectConfiguration,
        configuredExecutable: String?
    ) throws -> Data {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: project.path) else {
            throw BeadsClientError.projectMissing(project.path)
        }

        guard let executable = resolveExecutable(configuredExecutable: configuredExecutable) else {
            throw BeadsClientError.executableNotFound
        }

        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("beads-status-bar-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: captureDirectory) }

        let outputURL = captureDirectory.appendingPathComponent("stdout.json")
        let errorURL = captureDirectory.appendingPathComponent("stderr.txt")
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = URL(fileURLWithPath: project.path, isDirectory: true)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            throw BeadsClientError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()
        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)

        if arguments.first == "events" {
            // bd serves historic rows with exit 0 even when journaling is off.
            // Its stderr notice is essential: an empty success alone is unsafe.
            if String(data: errorData, encoding: .utf8)?.contains("events journal is disabled") == true {
                throw BeadsClientError.journalDisabled
            }
            if let failure = try? JSONDecoder().decode(JournalFailure.self, from: outputData),
               failure.code == "events_journal_truncated", let head = failure.head, head >= 0 {
                throw BeadsClientError.journalTruncated(head)
            }
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsClientError.commandFailed(
                message?.isEmpty == false ? message! : "bd exited with status \(process.terminationStatus)."
            )
        }

        return outputData
    }

    private struct JournalFailure: Decodable {
        let code: String
        let head: Int64?
    }

    /// True when bd failed because the configured Dolt port belongs to a
    /// server serving a different data directory.
    static func isPortCollisionError(_ error: Error) -> Bool {
        guard case BeadsClientError.commandFailed(let message) = error else { return false }
        return DoltHealthEngine.isPortCollisionMessage(message)
    }

    /// Pins `bd dolt set port` for the project. This writes the project's
    /// gitignored `.beads/metadata.json`, so it must not run with --readonly.
    static func pinDoltPort(
        _ port: Int,
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try runSynchronously(
                arguments: ["dolt", "set", "port", String(port)],
                project: project,
                configuredExecutable: configuredExecutable
            )
        }.value
    }

    static func startDoltServer(
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try runSynchronously(
                arguments: ["dolt", "start"],
                project: project,
                configuredExecutable: configuredExecutable
            )
        }.value
    }

    /// Pins a free port outside `takenPorts`, starts the project's Dolt
    /// server on it, and returns the chosen port.
    static func repairDoltServer(
        for project: ProjectConfiguration,
        configuredExecutable: String?,
        takenPorts: Set<Int>
    ) async throws -> Int {
        guard let port = DoltPortAllocator.allocatePort(takenPorts: takenPorts) else {
            throw BeadsClientError.commandFailed(
                "No free Dolt port in \(DoltPortPolicy.lowerBound)–\(DoltPortPolicy.upperBound)."
            )
        }
        try await pinDoltPort(port, for: project, configuredExecutable: configuredExecutable)
        try await startDoltServer(for: project, configuredExecutable: configuredExecutable)
        return port
    }

    static func doltServerRunning(
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) async -> Bool? {
        let data: Data?
        do {
            data = try await Task.detached(priority: .utility) {
                try runSynchronously(
                    arguments: ["dolt", "status", "--json", "--readonly", "--sandbox"],
                    project: project,
                    configuredExecutable: configuredExecutable
                )
            }.value
        } catch {
            return nil
        }

        guard let data,
              let status = try? JSONDecoder().decode(DoltStatus.self, from: data) else {
            return nil
        }
        return status.running
    }

    private struct DoltStatus: Decodable {
        let running: Bool
    }

    static func resolveExecutable(configuredExecutable: String?) -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            configuredExecutable,
            "/opt/homebrew/bin/bd",
            "/usr/local/bin/bd",
            "\(home)/.local/bin/bd",
            "\(home)/go/bin/bd"
        ].compactMap { $0 }

        return candidates.first {
            fileManager.isExecutableFile(atPath: $0)
        }
    }
}
