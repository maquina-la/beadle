import Foundation

struct IssueEvent: Decodable, Sendable {
    let seq: Int64
    let op: String
    let issueID: String
    let issue: BeadIssue?

    enum CodingKeys: String, CodingKey {
        case seq, op, issue
        case issueID = "issue_id"
    }

    static func decode(_ data: Data, since: Int64) throws -> [IssueEvent] {
        var cursor = since
        return try data.split(separator: 10).filter { !$0.allSatisfy { $0 == 13 || $0 == 32 } }.map { line in
            let event = try JSONDecoder().decode(IssueEvent.self, from: Data(line))
            guard event.seq > cursor, (since == 0 || event.seq == cursor + 1), !event.issueID.isEmpty,
                  ["create", "update", "close", "delete", "dep_add", "dep_remove", "comment"].contains(event.op),
                  event.issue == nil || event.issue?.id == event.issueID,
                  event.issue != nil || ["delete", "dep_remove"].contains(event.op) else {
                throw BeadsClientError.invalidResponse("Invalid or unordered event journal record.")
            }
            cursor = event.seq
            return event
        }
    }
}

/// Checkpoints are session-local and belong to one project/executable pair.
/// Reconciliation catches changes that never pass through the journal (pull,
/// SQL, branch switches and replacing a clone at the same path).
struct IssueJournal: Sendable {
    static let reconciliationInterval: TimeInterval = 300
    let source: String
    let issues: [BeadIssue]
    let checkpoint: Int64?
    let baselineAt: Date

    static func refresh(
        previous: IssueJournal?, source: String, forceBaseline: Bool, now: Date = Date(),
        readEvents: (Int64) async throws -> [IssueEvent],
        readIssues: () async throws -> [BeadIssue],
        readDetail: (String) async throws -> BeadIssue
    ) async throws -> IssueJournal {
        if !forceBaseline, let previous, previous.source == source,
           now.timeIntervalSince(previous.baselineAt) < reconciliationInterval,
           let checkpoint = previous.checkpoint {
            do {
                let events = try await readEvents(checkpoint)
                guard !events.isEmpty else { return previous }
                // Dependency edges and deletion change counts/relations on other
                // beads. Their row-only snapshots cannot reconstruct that graph.
                if !events.contains(where: { ["dep_add", "dep_remove", "delete"].contains($0.op) }) {
                    var issues = previous.issues
                    for event in events {
                        guard var issue = event.issue else {
                            throw BeadsClientError.invalidResponse("Missing event issue.")
                        }
                        if event.op == "create" || event.op == "comment" {
                            let blocked = issue.isBlocked
                            issue = try await readDetail(event.issueID)
                            issue.isBlocked = blocked
                        } else if let old = issues.first(where: { $0.id == issue.id }) {
                            if old.issueType != issue.issueType {
                                let blocked = issue.isBlocked
                                issue = try await readDetail(event.issueID)
                                issue.isBlocked = blocked
                            }
                            // Journal snapshots omit graph and comment data.
                            issue.dependencyCount = old.dependencyCount
                            issue.dependentCount = old.dependentCount
                            issue.commentCount = old.commentCount
                            issue.dependencies = old.dependencies
                            issue.dependents = old.dependents
                        } else {
                            let blocked = issue.isBlocked
                            issue = try await readDetail(event.issueID)
                            issue.isBlocked = blocked
                        }
                        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
                            issues[index] = issue
                        } else {
                            issues.append(issue)
                        }
                    }
                    issues.sort {
                        if $0.priority != $1.priority { return $0.priority < $1.priority }
                        return ($0.createdAt ?? "") > ($1.createdAt ?? "")
                    }
                    return IssueJournal(source: source, issues: issues,
                                        checkpoint: events.last?.seq ?? checkpoint,
                                        baselineAt: previous.baselineAt)
                }
            } catch {
                // Unsupported/disabled journals, truncation, malformed records,
                // and failed targeted reads all recover from current state.
            }
        }
        // Capture BEFORE reading the snapshot. Mutations racing the full read
        // remain after this cursor and will be replayed on the next refresh.
        let checkpoint: Int64?
        do {
            checkpoint = try await readEvents(0).last?.seq ?? 0
        } catch BeadsClientError.journalTruncated(let head) {
            checkpoint = head
        } catch {
            checkpoint = nil
        }
        let issues = try await readIssues()
        return IssueJournal(source: source, issues: issues,
                            checkpoint: checkpoint, baselineAt: now)
    }
}
