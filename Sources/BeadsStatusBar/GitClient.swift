import Foundation

/// Reads git information related to a specific issue from a project's working
/// tree. All commands are read-only and run with the project folder as the
/// working directory. Failures are non-fatal: a non-git project (or a missing
/// `git` binary) yields `IssueGitInfo(isGitRepository: false)`.
struct GitClient: Sendable {

    /// Gather branch and commit information referencing `issueID` within the
    /// given project's repository.
    static func gitInfo(
        forIssue issueID: String,
        in project: ProjectConfiguration
    ) async -> IssueGitInfo {
        await Task.detached(priority: .userInitiated) {
            gitInfoSynchronously(forIssue: issueID, in: project)
        }.value
    }

    // MARK: - Internals

    private static func gitInfoSynchronously(
        forIssue issueID: String,
        in project: ProjectConfiguration
    ) -> IssueGitInfo {
        var empty = IssueGitInfo()
        guard let git = resolveGit() else { return empty }

        // Not a git repo (or folder missing) → hide the section entirely.
        guard
            let isRepo = try? run(
                arguments: ["rev-parse", "--is-inside-work-tree"],
                git: git,
                project: project
            ),
            isRepo.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else {
            return empty
        }
        empty.isGitRepository = true

        let currentBranch = (try? run(
            arguments: ["branch", "--show-current"],
            git: git,
            project: project
        ))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        let branches = matchingBranches(
            issueID: issueID,
            currentBranch: currentBranch,
            git: git,
            project: project
        )
        let commits = referencingCommits(
            issueID: issueID,
            git: git,
            project: project
        )

        return IssueGitInfo(
            matchingBranches: branches,
            commits: commits,
            isGitRepository: true
        )
    }

    /// Branches whose short name contains the issue ID (case-insensitive),
    /// deduplicated across local and remote refs.
    private static func matchingBranches(
        issueID: String,
        currentBranch: String?,
        git: String,
        project: ProjectConfiguration
    ) -> [IssueBranch] {
        guard let output = try? run(
            arguments: [
                "for-each-ref",
                "--format=%(refname:short)",
                "refs/heads",
                "refs/remotes"
            ],
            git: git,
            project: project
        ) else {
            return []
        }

        let needle = issueID.lowercased()
        var seen = Set<String>()
        var result: [IssueBranch] = []
        for ref in output.split(separator: "\n") {
            let name = String(ref).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.lowercased().contains(needle) else { continue }
            guard seen.insert(name).inserted else { continue }
            result.append(
                IssueBranch(name: name, isCurrent: name == currentBranch)
            )
        }
        return result
    }

    /// Recent commits whose message references the issue ID, newest first.
    /// `--grep` defaults to fixed-string matching, but we re-confirm the ID
    /// appears in each subject to avoid false positives from regex
    /// metacharacters.
    private static func referencingCommits(
        issueID: String,
        git: String,
        project: ProjectConfiguration
    ) -> [IssueCommit] {
        guard let output = try? run(
            arguments: [
                "log",
                "--max-count=50",
                "--format=%H%n%h%n%s%n%cI%n%",
                "--all",
                "--grep=\(issueID)"
            ],
            git: git,
            project: project
        ) else {
            return []
        }

        let needle = issueID.lowercased()
        var commits: [IssueCommit] = []
        // Each record is four lines (hash, shortHash, subject, date) followed by
        // a record terminator line containing "%".
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var index = 0
        while index + 4 <= lines.count {
            let terminatorLine = lines[index + 4]
            guard terminatorLine.trimmingCharacters(in: .whitespacesAndNewlines) == "%" else {
                index += 1
                continue
            }
            let shortHash = String(lines[index + 1])
            let subject = String(lines[index + 2])
            let date = String(lines[index + 3])
            defer { index += 5 }

            guard subject.lowercased().contains(needle) else { continue }
            commits.append(
                IssueCommit(shortHash: shortHash, subject: subject, isoDate: date)
            )
        }
        return commits
    }

    // MARK: - Process execution

    /// Runs `git` with the given arguments in the project's working directory
    /// and returns trimmed stdout on success. Throws on non-zero exit.
    private static func run(
        arguments: [String],
        git: String,
        project: ProjectConfiguration
    ) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: project.path) else {
            throw GitError.projectMissing(project.path)
        }

        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("beads-status-bar-git-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: captureDirectory) }

        let outputURL = captureDirectory.appendingPathComponent("out.txt")
        let errorURL = captureDirectory.appendingPathComponent("err.txt")
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.currentDirectoryURL = URL(fileURLWithPath: project.path, isDirectory: true)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()

        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.commandFailed(
                message?.isEmpty == false
                    ? message!
                    : "git exited with status \(process.terminationStatus)."
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private static func resolveGit() -> String? {
        let fileManager = FileManager.default
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }
}

private enum GitError: LocalizedError {
    case projectMissing(String)
    case launchFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectMissing(let path):
            "The project folder no longer exists: \(path)"
        case .launchFailed(let message):
            message
        case .commandFailed(let message):
            message
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
