import Foundation

enum BeadsClientError: LocalizedError {
    case executableNotFound
    case projectMissing(String)
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
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

    private static func loadIssuesSynchronously(
        for project: ProjectConfiguration,
        configuredExecutable: String?
    ) throws -> [BeadIssue] {
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
        process.arguments = [
            "list", "--json", "--limit", "0", "--no-pager",
            "--readonly", "--sandbox"
        ]
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

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BeadsClientError.commandFailed(
                message?.isEmpty == false ? message! : "bd exited with status \(process.terminationStatus)."
            )
        }

        do {
            return try JSONDecoder().decode([BeadIssue].self, from: outputData)
        } catch {
            throw BeadsClientError.invalidResponse(error.localizedDescription)
        }
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
