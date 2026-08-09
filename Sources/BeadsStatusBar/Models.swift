import Foundation

struct ProjectConfiguration: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

struct IssueKey: Hashable, Identifiable, Sendable {
    let projectID: UUID
    let issueID: String

    var id: String { "\(projectID.uuidString):\(issueID)" }
}

struct BeadRelation: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let status: String?
    let dependencyType: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, type
        case issueID = "issue_id"
        case dependsOnID = "depends_on_id"
        case dependencyType = "dependency_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relationID = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .dependsOnID)
            ?? container.decodeIfPresent(String.self, forKey: .issueID)
            ?? "unknown"
        id = relationID
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? relationID
        status = try container.decodeIfPresent(String.self, forKey: .status)
        dependencyType = try container.decodeIfPresent(String.self, forKey: .dependencyType)
            ?? container.decodeIfPresent(String.self, forKey: .type)
    }
}

struct BeadIssue: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let priority: Int
    let issueType: String
    let assignee: String?
    let owner: String?
    let createdAt: String?
    let updatedAt: String?
    let dependencyCount: Int
    let dependentCount: Int
    let commentCount: Int
    let labels: [String]
    let dependencies: [BeadRelation]
    let dependents: [BeadRelation]
    let notes: String?
    let dueAt: String?
    let closedAt: String?
    let closeReason: String?

    var normalizedStatus: IssueStatus {
        IssueStatus(rawValue: status) ?? .open
    }

    var updatedDate: Date? {
        guard let updatedAt else { return nil }
        return ISO8601DateFormatter().date(from: updatedAt)
    }

    var createdDate: Date? {
        guard let createdAt else { return nil }
        return ISO8601DateFormatter().date(from: createdAt)
    }

    var dueDate: Date? {
        guard let dueAt else { return nil }
        return ISO8601DateFormatter().date(from: dueAt)
    }

    var closedDate: Date? {
        guard let closedAt else { return nil }
        return ISO8601DateFormatter().date(from: closedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, assignee, owner
        case issueType = "issue_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dependencyCount = "dependency_count"
        case dependentCount = "dependent_count"
        case commentCount = "comment_count"
        case labels, dependencies, dependents, notes
        case dueAt = "due_at"
        case closedAt = "closed_at"
        case closeReason = "close_reason"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "open"
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 2
        issueType = try container.decodeIfPresent(String.self, forKey: .issueType) ?? "task"
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        dependencyCount = try container.decodeIfPresent(Int.self, forKey: .dependencyCount) ?? 0
        dependentCount = try container.decodeIfPresent(Int.self, forKey: .dependentCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        dependencies = try container.decodeIfPresent([BeadRelation].self, forKey: .dependencies) ?? []
        dependents = try container.decodeIfPresent([BeadRelation].self, forKey: .dependents) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
        closeReason = try container.decodeIfPresent(String.self, forKey: .closeReason)
    }
}

enum IssueStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case open
    case inProgress = "in_progress"
    case blocked
    case deferred
    case closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .deferred: "Deferred"
        case .closed: "Closed"
        }
    }

    var symbol: String {
        switch self {
        case .open: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.octagon.fill"
        case .deferred: "pause.circle"
        case .closed: "checkmark.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .open: "secondary"
        case .inProgress: "blue"
        case .blocked: "red"
        case .deferred: "secondary"
        case .closed: "green"
        }
    }
}

struct ProjectIssues: Identifiable, Sendable {
    let project: ProjectConfiguration
    var issues: [BeadIssue]
    var error: String?

    var id: UUID { project.id }
}

struct IssueFilters: Codable, Equatable, Sendable {
    var statuses: Set<IssueStatus> = []
    var priorities: Set<Int> = []
    var types: Set<String> = []
    var assignees: Set<String> = []

    var isEmpty: Bool {
        statuses.isEmpty && priorities.isEmpty && types.isEmpty && assignees.isEmpty
    }

    /// Total number of selected values across every dimension. Drives the badge count.
    var activeCount: Int {
        statuses.count + priorities.count + types.count + assignees.count
    }

    /// Empty dimension = no constraint (matches all). Within a dimension = OR, across = AND.
    func matches(_ issue: BeadIssue) -> Bool {
        if !statuses.isEmpty, !statuses.contains(issue.normalizedStatus) { return false }
        if !priorities.isEmpty, !priorities.contains(issue.priority) { return false }
        if !types.isEmpty, !types.contains(issue.issueType) { return false }
        if !assignees.isEmpty {
            let assignee = issue.assignee ?? ""
            if assignee.isEmpty || !assignees.contains(assignee) { return false }
        }
        return true
    }

    mutating func clear() {
        statuses.removeAll()
        priorities.removeAll()
        types.removeAll()
        assignees.removeAll()
    }
}

extension Int {
    /// Human-readable label for a Beads priority value (0–4), per AGENTS.md.
    var priorityLabel: String {
        switch self {
        case 0: "P0 Critical"
        case 1: "P1 High"
        case 2: "P2 Medium"
        case 3: "P3 Low"
        case 4: "P4 Backlog"
        default: "P\(self)"
        }
    }
}

// MARK: - Git

/// Git information related to a specific issue, gathered on demand from the
/// project's working tree. `isGitRepository == false` means the project folder
/// is not inside a git repo (or git is unavailable); callers should hide the
/// section entirely in that case.
struct IssueGitInfo: Hashable, Sendable {
    var matchingBranches: [IssueBranch] = []
    var commits: [IssueCommit] = []
    var isGitRepository: Bool = false

    var isEmpty: Bool {
        matchingBranches.isEmpty && commits.isEmpty
    }
}

struct IssueBranch: Hashable, Sendable {
    let name: String
    let isCurrent: Bool
}

struct IssueCommit: Hashable, Sendable {
    let shortHash: String
    let subject: String
    let isoDate: String

    var date: Date? {
        ISO8601DateFormatter().date(from: isoDate)
    }
}
