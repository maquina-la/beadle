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

    /// Branches whose short name references the issue ID as a whole token
    /// (case-insensitive), deduplicated across local and remote refs.
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

        var seen = Set<String>()
        var result: [IssueBranch] = []
        for ref in output.split(separator: "\n") {
            let name = String(ref).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, referencesIssueID(issueID, in: name) else { continue }
            guard seen.insert(name).inserted else { continue }
            result.append(
                IssueBranch(name: name, isCurrent: name == currentBranch)
            )
        }
        return result
    }

    /// Commits whose message references the issue ID anywhere (subject or
    /// body), newest first. `-i -F` makes git's own grep case-insensitive and
    /// literal; the boundary check then rejects IDs glued to longer IDs
    /// (bd-123 vs bd-1234) that a substring match would accept.
    private static func referencingCommits(
        issueID: String,
        git: String,
        project: ProjectConfiguration
    ) -> [IssueCommit] {
        guard let output = try? run(
            arguments: [
                "log",
                "--max-count=50",
                "--format=%H%x1f%h%x1f%s%x1f%cI%x1f%b%x1e",
                "--all",
                "-i",
                "-F",
                "--grep=\(issueID)"
            ],
            git: git,
            project: project
        ) else {
            return []
        }

        return parseCommitRecords(output)
            .filter { referencesIssueID(issueID, in: $0.message) }
            .map { IssueCommit(shortHash: $0.shortHash, subject: $0.subject, isoDate: $0.isoDate) }
    }

    // MARK: - Matching and parsing (internal for tests)

    /// A parsed `git log` record: the subject plus the full message used for
    /// reference matching.
    struct ParsedCommit: Equatable {
        let shortHash: String
        let subject: String
        let isoDate: String
        let message: String
    }

    /// Splits delimiter-separated `git log` output (fields joined with
    /// unit separators, records with record separators) into commits.
    static func parseCommitRecords(_ output: String) -> [ParsedCommit] {
        guard !output.isEmpty else { return [] }

        let rawRecords = output.split(separator: "\u{1e}", omittingEmptySubsequences: false)
        var commits: [ParsedCommit] = []
        for (index, rawRecord) in rawRecords.enumerated() {
            // The first record starts clean; later ones carry the newline
            // `git log` appends after each record.
            let record = index == 0
                ? String(rawRecord)
                : String(rawRecord).trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                .map { String($0) }
            guard fields.count >= 4 else { continue }

            let subject = fields[2]
            let body = fields.count >= 5 ? fields[4] : ""
            let message = body.isEmpty ? subject : subject + "\n" + body
            commits.append(
                ParsedCommit(
                    shortHash: fields[1],
                    subject: subject,
                    isoDate: fields[3],
                    message: message
                )
            )
        }
        return commits
    }

    /// True when `text` references `issueID` case-insensitively as a whole
    /// token: the ID must not be glued to another alphanumeric on either
    /// side, so bd-123 does not match bd-1234, while "Fixes bd-123." and
    /// "bd-123_fix" still do.
    static func referencesIssueID(_ issueID: String, in text: String) -> Bool {
        guard !issueID.isEmpty else { return false }
        let pattern = "(?i)(?<![a-zA-Z0-9])"
            + NSRegularExpression.escapedPattern(for: issueID)
            + "(?![a-zA-Z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.localizedCaseInsensitiveContains(issueID)
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
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
