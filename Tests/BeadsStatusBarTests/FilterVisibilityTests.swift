import Foundation
import Testing
@testable import BeadsStatusBar

struct FilterVisibilityTests {
    private func issue(
        id: String,
        title: String = "task",
        status: String = "open",
        labels: [String] = []
    ) -> BeadIssue {
        let labelsJSON = labels.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {"id":"\(id)","title":"\(title)","status":"\(status)","priority":2,"issue_type":"task","labels":[\(labelsJSON)]}
        """
        return try! JSONDecoder().decode(BeadIssue.self, from: Data(json.utf8))
    }

    private func snapshot(
        name: String,
        issues: [BeadIssue]
    ) -> ProjectIssues {
        ProjectIssues(
            project: ProjectConfiguration(name: name, path: "/tmp/\(name)"),
            issues: issues,
            error: nil
        )
    }

    @Test func closedIssuesAreHiddenWithoutAStatusFilter() {
        let filters = IssueFilters()
        #expect(!filters.matches(issue(id: "a-1", status: "closed")))
        #expect(filters.matches(issue(id: "a-2", status: "open")))
        #expect(filters.matches(issue(id: "a-3", status: "in_progress")))
    }

    @Test func enablingClosedRevealsClosedIssuesOnly() {
        var filters = IssueFilters()
        filters.statuses = [.closed]
        #expect(filters.matches(issue(id: "a-1", status: "closed")))
        #expect(!filters.matches(issue(id: "a-2", status: "open")))
    }

    @Test func selectingNonClosedStatusesKeepsClosedHidden() {
        var filters = IssueFilters()
        filters.statuses = [.open, .blocked]
        #expect(!filters.matches(issue(id: "a-1", status: "closed")))
        #expect(filters.matches(issue(id: "a-2", status: "blocked")))
    }

    @Test func clearingFiltersHidesClosedAgain() {
        var filters = IssueFilters()
        filters.statuses = [.closed]
        filters.clear()
        #expect(!filters.matches(issue(id: "a-1", status: "closed")))
    }

    @Test func searchAloneDoesNotRevealClosedIssues() {
        let snapshots = [
            snapshot(name: "alpha", issues: [
                issue(id: "a-1", title: "fix login", status: "open"),
                issue(id: "a-2", title: "fix logout", status: "closed"),
            ])
        ]

        let defaultResults = AppState.filteredSnapshots(
            snapshots,
            selectedProjectID: nil,
            filters: IssueFilters(),
            searchText: "fix"
        )
        #expect(defaultResults[0].issues.map(\.id) == ["a-1"])

        var closedEnabled = IssueFilters()
        closedEnabled.statuses = [.closed]
        let closedResults = AppState.filteredSnapshots(
            snapshots,
            selectedProjectID: nil,
            filters: closedEnabled,
            searchText: "fix"
        )
        #expect(closedResults[0].issues.map(\.id) == ["a-2"])
    }

    @Test func zeroMatchProjectsRemainListed() {
        let snapshots = [
            snapshot(name: "alpha", issues: [issue(id: "a-1", title: "port collision")]),
            snapshot(name: "beta", issues: [issue(id: "b-1", title: "unrelated")]),
        ]

        let results = AppState.filteredSnapshots(
            snapshots,
            selectedProjectID: nil,
            filters: IssueFilters(),
            searchText: "port collision"
        )

        #expect(results.count == 2)
        #expect(results[0].project.name == "alpha")
        #expect(results[0].issues.count == 1)
        #expect(results[1].project.name == "beta")
        #expect(results[1].issues.isEmpty)
    }

    @Test func allClosedProjectStillListedWithZeroCount() {
        let snapshots = [
            snapshot(name: "archive", issues: [
                issue(id: "a-1", status: "closed"),
                issue(id: "a-2", status: "closed"),
            ])
        ]

        let results = AppState.filteredSnapshots(
            snapshots,
            selectedProjectID: nil,
            filters: IssueFilters(),
            searchText: ""
        )

        #expect(results.count == 1)
        #expect(results[0].issues.isEmpty)
    }

    @Test func explicitProjectScopeStillHidesOtherProjects() {
        let alpha = snapshot(name: "alpha", issues: [issue(id: "a-1")])
        let beta = snapshot(name: "beta", issues: [issue(id: "b-1")])

        let results = AppState.filteredSnapshots(
            [alpha, beta],
            selectedProjectID: beta.project.id,
            filters: IssueFilters(),
            searchText: ""
        )

        #expect(results.count == 1)
        #expect(results[0].project.name == "beta")
    }
}
