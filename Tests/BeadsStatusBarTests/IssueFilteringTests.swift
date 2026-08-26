import Foundation
import Testing
@testable import BeadsStatusBar

/// Filtering moved from a computed property that every view re-evaluated to a
/// value derived once per input change. These lock the behaviour that move had
/// to preserve, including the switch away from locale-aware substring search.
struct IssueFilteringTests {
    private func issue(
        id: String,
        title: String = "Title",
        description: String? = nil,
        status: String = "open",
        priority: Int = 2,
        issueType: String = "task",
        assignee: String? = nil,
        labels: [String] = []
    ) -> BeadIssue {
        var fields: [String: Any] = [
            "id": id,
            "title": title,
            "status": status,
            "priority": priority,
            "issue_type": issueType,
            "labels": labels,
        ]
        if let description { fields["description"] = description }
        if let assignee { fields["assignee"] = assignee }
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return try! JSONDecoder().decode(BeadIssue.self, from: data)
    }

    private func snapshot(_ name: String, _ issues: [BeadIssue]) -> ProjectIssues {
        ProjectIssues(
            project: ProjectConfiguration(name: name, path: "/tmp/\(name)"),
            issues: issues,
            error: nil
        )
    }

    private func filter(
        _ snapshots: [ProjectIssues],
        projectID: UUID? = nil,
        filters: IssueFilters = IssueFilters(),
        search: String = ""
    ) -> [ProjectIssues] {
        AppState.filteredSnapshots(
            snapshots,
            selectedProjectID: projectID,
            filters: filters,
            searchText: search
        )
    }

    @Test func searchMatchesEveryField() {
        let issues = [
            issue(id: "bd-1", title: "Fix the parser"),
            issue(id: "bd-2", description: "A **markdown** body mentioning telemetry"),
            issue(id: "bd-3", assignee: "Carlos Rivera"),
            issue(id: "bd-4", labels: ["infrastructure"]),
        ]
        let all = [snapshot("proj", issues)]

        #expect(filter(all, search: "parser").first?.issues.map(\.id) == ["bd-1"])
        #expect(filter(all, search: "telemetry").first?.issues.map(\.id) == ["bd-2"])
        #expect(filter(all, search: "carlos").first?.issues.map(\.id) == ["bd-3"])
        #expect(filter(all, search: "infrastructure").first?.issues.map(\.id) == ["bd-4"])
        #expect(filter(all, search: "bd-4").first?.issues.map(\.id) == ["bd-4"])
    }

    @Test func searchIsCaseInsensitive() {
        let all = [snapshot("proj", [issue(id: "bd-1", title: "Fix The PARSER")])]
        for term in ["parser", "PARSER", "PaRsEr", "fix the parser"] {
            #expect(filter(all, search: term).first?.issues.count == 1, "term: \(term)")
        }
        #expect(filter(all, search: "absent").first?.issues.isEmpty == true)
    }

    @Test func closedIssuesAreHiddenUntilExplicitlyRequested() {
        let all = [snapshot("proj", [
            issue(id: "bd-1", status: "open"),
            issue(id: "bd-2", status: "closed"),
        ])]

        #expect(filter(all).first?.issues.map(\.id) == ["bd-1"])

        var filters = IssueFilters()
        filters.statuses = [.closed]
        #expect(filter(all, filters: filters).first?.issues.map(\.id) == ["bd-2"])
    }

    @Test func projectsStayListedWhenFiltersMatchNothing() {
        let all = [
            snapshot("alpha", [issue(id: "bd-1", title: "alpha work")]),
            snapshot("beta", [issue(id: "bd-2", title: "beta work")]),
        ]
        let results = filter(all, search: "alpha")

        // Both projects survive; only the non-matching one empties out. The
        // header renders with a zero count rather than disappearing.
        #expect(results.count == 2)
        #expect(results[0].issues.count == 1)
        #expect(results[1].issues.isEmpty)
    }

    @Test func selectingAProjectDropsTheOthers() {
        let alpha = snapshot("alpha", [issue(id: "bd-1")])
        let beta = snapshot("beta", [issue(id: "bd-2")])
        let results = filter([alpha, beta], projectID: beta.id)

        #expect(results.count == 1)
        #expect(results.first?.issues.map(\.id) == ["bd-2"])
    }

    @Test func filtersCombineAsConjunction() {
        let issues = [
            issue(id: "bd-1", priority: 1, issueType: "bug", assignee: "carlos"),
            issue(id: "bd-2", priority: 1, issueType: "feature", assignee: "carlos"),
            issue(id: "bd-3", priority: 3, issueType: "bug", assignee: "carlos"),
            issue(id: "bd-4", priority: 1, issueType: "bug", assignee: "someone"),
        ]
        var filters = IssueFilters()
        filters.priorities = [1]
        filters.types = ["bug"]
        filters.assignees = ["carlos"]

        let results = filter([snapshot("proj", issues)], filters: filters)
        #expect(results.first?.issues.map(\.id) == ["bd-1"])
    }

    @Test func searchAndFiltersApplyTogether() {
        let issues = [
            issue(id: "bd-1", title: "parser crash", priority: 1),
            issue(id: "bd-2", title: "parser polish", priority: 3),
        ]
        var filters = IssueFilters()
        filters.priorities = [1]

        let results = filter([snapshot("proj", issues)], filters: filters, search: "parser")
        #expect(results.first?.issues.map(\.id) == ["bd-1"])
    }

    @Test func emptySearchMatchesEverythingOpen() {
        let all = [snapshot("proj", [issue(id: "bd-1"), issue(id: "bd-2")])]
        #expect(filter(all, search: "").first?.issues.count == 2)
    }
}
