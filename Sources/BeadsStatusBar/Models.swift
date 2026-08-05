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

struct BeadIssue: Codable, Identifiable, Hashable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, assignee, owner
        case issueType = "issue_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dependencyCount = "dependency_count"
        case dependentCount = "dependent_count"
        case commentCount = "comment_count"
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
    }
}

enum IssueStatus: String, CaseIterable, Identifiable, Sendable {
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
}

struct ProjectIssues: Identifiable, Sendable {
    let project: ProjectConfiguration
    var issues: [BeadIssue]
    var error: String?

    var id: UUID { project.id }
}

enum IssueFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case inProgress
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .open: "Open"
        case .inProgress: "Active"
        case .blocked: "Blocked"
        }
    }

    func includes(_ issue: BeadIssue) -> Bool {
        switch self {
        case .all: issue.normalizedStatus != .closed
        case .open: issue.normalizedStatus == .open
        case .inProgress: issue.normalizedStatus == .inProgress
        case .blocked: issue.normalizedStatus == .blocked
        }
    }
}
