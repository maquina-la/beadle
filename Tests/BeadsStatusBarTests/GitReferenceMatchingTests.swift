import Foundation
import Testing
@testable import BeadsStatusBar

struct GitReferenceMatchingTests {
    @Test func idMatchesAsWholeToken() {
        #expect(GitClient.referencesIssueID("bd-123", in: "Fixes bd-123."))
        #expect(GitClient.referencesIssueID("bd-123", in: "FIXES BD-123!"))
        #expect(GitClient.referencesIssueID("bd-123", in: "branch bd-123_fix rebased"))
        #expect(GitClient.referencesIssueID("bd-123", in: "prefix/bd-123"))
        #expect(GitClient.referencesIssueID("bd-123", in: "bd-123"))
    }

    @Test func longerIDsDoNotMatchShorterID() {
        #expect(!GitClient.referencesIssueID("bd-123", in: "fix bd-1234 regression"))
        #expect(!GitClient.referencesIssueID("bd-123", in: "bd-12345"))
        #expect(!GitClient.referencesIssueID("bd-123", in: "starts abd-123 here"))
        #expect(!GitClient.referencesIssueID("bd-123", in: "nothing relevant"))
    }

    @Test func regexMetacharactersInIDsAreLiteral() {
        #expect(GitClient.referencesIssueID("maquina.la-1", in: "fix maquina.la-1"))
        #expect(!GitClient.referencesIssueID("maquina.la-1", in: "maquinaXla-1"))
    }

    @Test func parserHandlesRecordsWithBodiesAndEmptySubjects() {
        let output = [
            "fullhash1\u{1f}hash1\u{1f}feat: subject one\u{1f}2026-08-20T10:00:00-06:00\u{1f}Body mentions bd-123.\n\nFixes bd-123.\u{1e}",
            "\nfullhash2\u{1f}hash2\u{1f}\u{1f}2026-08-21T10:00:00-06:00\u{1f}\u{1e}",
            "\n",
        ].joined()

        let commits = GitClient.parseCommitRecords(output)

        #expect(commits.count == 2)
        #expect(commits[0].shortHash == "hash1")
        #expect(commits[0].subject == "feat: subject one")
        #expect(commits[0].message.contains("Fixes bd-123."))
        #expect(GitClient.referencesIssueID("bd-123", in: commits[0].message))

        // Empty subject: the record must still parse instead of desyncing.
        #expect(commits[1].shortHash == "hash2")
        #expect(commits[1].subject.isEmpty)
        #expect(commits[1].message.isEmpty)
    }

    @Test func bodyOnlyReferenceSurvivesFiltering() {
        // The regression behind this fix: IDs commonly live in the body, so
        // matching must run against subject + body, not the subject alone.
        let output = "h1\u{1f}h1\u{1f}feat: surface git info per issue\u{1f}2026-08-20T10:00:00-06:00\u{1f}Implements beads-status-bar-88n.\u{1e}\n"
        let commits = GitClient.parseCommitRecords(output)

        let subjectMatch = commits.contains {
            GitClient.referencesIssueID("beads-status-bar-88n", in: $0.subject)
        }
        let messageMatch = commits.contains {
            GitClient.referencesIssueID("beads-status-bar-88n", in: $0.message)
        }
        #expect(!subjectMatch)
        #expect(messageMatch)
    }

    @Test func parserHandlesEmptyInput() {
        #expect(GitClient.parseCommitRecords("").isEmpty)
    }
}
