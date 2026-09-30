import Foundation
import Testing
@testable import BeadsStatusBar

struct IssueJournalTests {
    private let now = Date(timeIntervalSince1970: 1000)

    private func issue(_ json: String) throws -> BeadIssue {
        try JSONDecoder().decode(BeadIssue.self, from: Data(json.utf8))
    }

    private func events(_ json: String, since: Int64 = 0) throws -> [IssueEvent] {
        try IssueEvent.decode(Data(json.utf8), since: since)
    }

    private func previous(_ issues: [BeadIssue] = [], checkpoint: Int64? = 10) -> IssueJournal {
        IssueJournal(source: "project/bd", issues: issues, checkpoint: checkpoint, baselineAt: now)
    }

    @Test func quietProjectAvoidsSnapshotAndDetailReads() async throws {
        let state = try await IssueJournal.refresh(
            previous: previous(), source: "project/bd", forceBaseline: false, now: now,
            readEvents: { #expect($0 == 10); return [] },
            readIssues: { Issue.record("Unexpected full snapshot"); return [] },
            readDetail: { _ in throw BeadsClientError.invalidResponse("Unexpected detail") }
        )
        #expect(state.checkpoint == 10)
    }

    @Test func baselineCapturesCursorBeforeSnapshotAndReplaysRacingWrite() async throws {
        var order: [String] = []
        let old = try issue(#"{"id":"a","title":"old"}"#)
        let baseline = try await IssueJournal.refresh(
            previous: nil, source: "project/bd", forceBaseline: false, now: now,
            readEvents: { since in
                order.append("cursor"); #expect(since == 0)
                return try events(#"{"seq":10,"op":"update","issue_id":"a","issue":{"id":"a","title":"old"}}"#)
            },
            readIssues: { order.append("snapshot"); return [old] },
            readDetail: { _ in old }
        )
        #expect(order == ["cursor", "snapshot"])
        let state = try await IssueJournal.refresh(
            previous: baseline, source: "project/bd", forceBaseline: false, now: now,
            readEvents: { since in
                #expect(since == 10)
                return try events(#"{"seq":11,"op":"update","issue_id":"a","issue":{"id":"a","title":"racing write"}}"#, since: since)
            },
            readIssues: { Issue.record("Unexpected snapshot"); return [] },
            readDetail: { _ in old }
        )
        #expect(state.issues.first?.title == "racing write")
        #expect(state.checkpoint == 11)
    }

    @Test func replayPreservesGraphAndClearsMissingBlockedFlag() async throws {
        let old = try issue(#"{"id":"a","title":"old","is_blocked":true,"dependency_count":2,"dependent_count":3,"comment_count":4,"dependencies":[{"id":"b","title":"B"}]}"#)
        let state = try await IssueJournal.refresh(
            previous: previous([old]), source: "project/bd", forceBaseline: false, now: now,
            readEvents: { try events(#"{"seq":11,"op":"update","issue_id":"a","issue":{"id":"a","title":"new"}}"#, since: $0) },
            readIssues: { Issue.record("Unexpected snapshot"); return [] },
            readDetail: { _ in old }
        )
        let new = try #require(state.issues.first)
        #expect(old.normalizedStatus == .blocked)
        #expect(new.normalizedStatus == .open)
        #expect(new.dependencyCount == 2 && new.dependentCount == 3 && new.commentCount == 4)
        #expect(new.dependencies == old.dependencies)
        #expect(try issue(#"{"id":"a","title":"a","is_blocked":true,"status":"closed"}"#).normalizedStatus == .closed)
        #expect(try issue(#"{"id":"a","title":"a","is_blocked":true,"status":"in_progress"}"#).normalizedStatus == .inProgress)
    }

    @Test func createsAndCommentsReadCurrentDetails() async throws {
        let full = try issue(#"{"id":"a","title":"a","comment_count":1,"dependency_count":2}"#)
        for op in ["create", "comment"] {
            var details = 0
            let state = try await IssueJournal.refresh(
                previous: previous(), source: "project/bd", forceBaseline: false, now: now,
                readEvents: { try events("{\"seq\":11,\"op\":\"\(op)\",\"issue_id\":\"a\",\"issue\":{\"id\":\"a\",\"title\":\"a\"}}", since: $0) },
                readIssues: { Issue.record("Unexpected snapshot"); return [] },
                readDetail: { id in #expect(id == "a"); details += 1; return full }
            )
            #expect(details == 1 && state.issues == [full] && state.checkpoint == 11)
        }
    }

    @Test func graphChangesAndDeletionRebuildInsteadOfDroppingCounts() async throws {
        for op in ["delete", "dep_add", "dep_remove"] {
            var reads = 0
            let state = try await IssueJournal.refresh(
                previous: previous([try issue(#"{"id":"a","title":"a"}"#)]), source: "project/bd", forceBaseline: false, now: now,
                readEvents: { since in
                    try events("{\"seq\":11,\"op\":\"\(op)\",\"issue_id\":\"a\",\"issue\":\(op == "dep_add" ? "{\"id\":\"a\",\"title\":\"a\"}" : "null")}", since: since)
                },
                readIssues: { reads += 1; return [] }, readDetail: { _ in throw BeadsClientError.journalDisabled }
            )
            #expect(reads == 1 && state.issues.isEmpty && state.checkpoint == 11)
        }
    }

    @Test func truncationUsesHeadCapturedBeforeRebuild() async throws {
        var reads: [Int64] = []
        let state = try await IssueJournal.refresh(
            previous: previous(), source: "project/bd", forceBaseline: false, now: now,
            readEvents: { reads.append($0); throw BeadsClientError.journalTruncated(100) },
            readIssues: { #expect(reads == [10, 0]); return [] },
            readDetail: { _ in throw BeadsClientError.journalDisabled }
        )
        #expect(state.checkpoint == 100)
    }

    @Test func disabledUnsupportedAndMalformedFeedsFallBack() async throws {
        for error in [BeadsClientError.journalDisabled, .commandFailed("unknown command events"), .invalidResponse("bad JSON")] {
            var snapshots = 0
            let state = try await IssueJournal.refresh(
                previous: previous(), source: "project/bd", forceBaseline: false, now: now,
                readEvents: { _ in throw error }, readIssues: { snapshots += 1; return [] },
                readDetail: { _ in throw error }
            )
            #expect(snapshots == 1 && state.checkpoint == nil)
        }
    }

    @Test func failedBatchDoesNotMutatePreviousState() async throws {
        let old = try issue(#"{"id":"a","title":"old"}"#)
        let state = previous([old])
        await #expect(throws: BeadsClientError.self) {
            _ = try await IssueJournal.refresh(
                previous: state, source: "project/bd", forceBaseline: false, now: now,
                readEvents: { try events(#"{"seq":11,"op":"update","issue_id":"a","issue":{"id":"a","title":"new"}}"# + "\n" + #"{"seq":12,"op":"create","issue_id":"b","issue":{"id":"b","title":"B"}}"#, since: $0) },
                readIssues: { throw BeadsClientError.commandFailed("offline") },
                readDetail: { _ in throw BeadsClientError.commandFailed("offline") }
            )
        }
        #expect(state.checkpoint == 10 && state.issues == [old])
    }

    @Test func manualReconciliationAndSourceChangesResetCursors() async throws {
        for (source, forced, date) in [("project/bd", true, now), ("other/bd", false, now), ("project/new-bd", false, now), ("project/bd", false, now.addingTimeInterval(300))] {
            var reads: [Int64] = []
            let state = try await IssueJournal.refresh(
                previous: previous(), source: source, forceBaseline: forced, now: date,
                readEvents: { reads.append($0); return [] }, readIssues: { [] },
                readDetail: { _ in throw BeadsClientError.journalDisabled }
            )
            #expect(reads == [0] && state.checkpoint == 0 && state.baselineAt == date)
        }
    }

    @Test func separateProjectsKeepIndependentCheckpoints() async throws {
        for cursor: Int64 in [10, 200] {
            let state = try await IssueJournal.refresh(
                previous: previous(checkpoint: cursor), source: "project/bd", forceBaseline: false, now: now,
                readEvents: { #expect($0 == cursor); return [] }, readIssues: { [] },
                readDetail: { _ in throw BeadsClientError.journalDisabled }
            )
            #expect(state.checkpoint == cursor)
        }
    }

    @Test func parserRejectsMalformedUnknownMismatchedAndUnorderedRecords() {
        for json in ["garbage", #"{"seq":11,"op":"surprise","issue_id":"a","issue":null}"#, #"{"seq":11,"op":"update","issue_id":"a","issue":{"id":"b","title":"B"}}"#, #"{"seq":10,"op":"delete","issue_id":"a","issue":null}"#, #"{"seq":12,"op":"delete","issue_id":"a","issue":null}"#] {
            #expect(throws: (any Error).self) { try events(json, since: 10) }
        }
    }
}
