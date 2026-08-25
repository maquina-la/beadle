import Foundation
import Testing
@testable import BeadsStatusBar

struct DoltHealthEngineTests {
    private func makeInput(
        name: String,
        host: String? = nil,
        port: Int? = nil,
        database: String? = nil,
        dataDirDatabases: [String] = [],
        loadSucceeded: Bool = false,
        loadError: String? = nil
    ) -> DoltHealthEngine.Input {
        DoltHealthEngine.Input(
            projectID: UUID(),
            projectName: name,
            metadata: DoltMetadata(host: host, port: port, databaseName: database ?? "db_\(name)", mode: "server"),
            dataDirDatabases: dataDirDatabases,
            loadSucceeded: loadSucceeded,
            loadError: loadError
        )
    }

    @Test func sharedDefaultPortIsCriticalForEveryProjectOnIt() {
        let health = DoltHealthEngine.assess([
            makeInput(name: "alpha", port: nil),
            makeInput(name: "beta", port: nil),
            makeInput(name: "gamma", port: 3312),
        ])

        let alpha = health.first { $0.projectName == "alpha" }
        let beta = health.first { $0.projectName == "beta" }
        let gamma = health.first { $0.projectName == "gamma" }

        guard case .sharedPort(let port, let others)? = alpha?.findings.first?.kind else {
            Issue.record("alpha should report a shared-port finding")
            return
        }
        #expect(port == 3307)
        #expect(others == ["beta"])
        #expect(beta?.findings.contains { $0.severity == .critical } == true)
        #expect(gamma?.findings.allSatisfy { $0.severity != .critical } == true)
    }

    @Test func unpinnedPortIsAWarning() {
        let health = DoltHealthEngine.assess([makeInput(name: "solo", port: nil)])
        #expect(health[0].findings.contains { finding in
            finding.kind == .unpinnedPort && finding.severity == .warning
        })
    }

    @Test func foreignDatabaseIsCriticalButQuarantineIsWarning() {
        let health = DoltHealthEngine.assess([
            makeInput(name: "host", port: 3310, database: "host", dataDirDatabases: ["host", "guest", "other-stale-20260816"]),
        ])

        let foreign = health[0].findings.first { $0.kind == .foreignDatabases(names: ["guest"]) }
        let quarantined = health[0].findings.first { $0.kind == .foreignDatabases(names: ["other-stale-20260816"]) }

        #expect(foreign?.severity == .critical)
        #expect(quarantined?.severity == .warning)
    }

    @Test func databaseServedElsewhereWhenLoadSucceedsButDataDirLacksIt() {
        let health = DoltHealthEngine.assess([
            makeInput(name: "wf", port: 3307, database: "wf", dataDirDatabases: ["somethingelse"], loadSucceeded: true),
        ])

        #expect(health[0].findings.contains { finding in
            finding.kind == .databaseServedElsewhere(databaseName: "wf")
                && finding.severity == .critical
        })
    }

    @Test func remoteHostDoesNotTriggerServedElsewhere() {
        let health = DoltHealthEngine.assess([
            makeInput(name: "shared", host: "192.168.1.10", port: 3307, database: "shared", dataDirDatabases: [], loadSucceeded: true),
        ])

        #expect(!health[0].findings.contains { finding in
            if case .databaseServedElsewhere = finding.kind { return true }
            return false
        })
    }

    @Test func portCollisionErrorMatchesBdMessageAndExtractsPort() {
        let message = """
        Error: failed to open database: database "beads_status_bar" not found on Dolt server at 127.0.0.1:3307
        """
        #expect(DoltHealthEngine.isPortCollisionMessage(message))
        #expect(DoltHealthEngine.collisionPort(in: message) == 3307)
        #expect(!DoltHealthEngine.isPortCollisionMessage("bd exited with status 1"))
        #expect(DoltHealthEngine.collisionPort(in: "no port here") == nil)

        #expect(BeadsClient.isPortCollisionError(BeadsClientError.commandFailed(message)))
        #expect(!BeadsClient.isPortCollisionError(BeadsClientError.commandFailed("other failure")))
    }

    @Test func metadataDecoding() {
        let json = """
        {"database":"dolt","backend":"dolt","dolt_mode":"server","dolt_server_host":"127.0.0.1","dolt_server_port":3312,"dolt_database":"vocal"}
        """
        let metadata = DoltMetadata.decode(Data(json.utf8))
        #expect(metadata?.port == 3312)
        #expect(metadata?.databaseName == "vocal")
        #expect(metadata?.effectivePort == 3312)
        #expect(metadata?.isLocalHost == true)

        let unpinned = DoltMetadata.decode(Data("{\"dolt_database\":\"x\"}".utf8))
        #expect(unpinned?.effectivePort == 3307)
    }

    @Test func portAllocatorSkipsTakenAndBusyPorts() {
        let busy: Set<Int> = [3310, 3312]
        let allocated = DoltPortAllocator.allocatePort(
            takenPorts: [3311],
            isPortFree: { !busy.contains($0) }
        )
        #expect(allocated == 3313)

        let everythingBusy = Set(DoltPortPolicy.lowerBound...DoltPortPolicy.upperBound)
        #expect(DoltPortAllocator.allocatePort(
            takenPorts: [],
            isPortFree: { !everythingBusy.contains($0) }
        ) == nil)
    }

    @Test func healthyProjectHasNoFindings() {
        let health = DoltHealthEngine.assess([
            makeInput(name: "clean", port: 3315, database: "clean", dataDirDatabases: ["clean"], loadSucceeded: true),
        ])
        #expect(health[0].findings.isEmpty)
        #expect(health[0].isHealthy)
        #expect(health[0].highestSeverity == nil)
    }
}
