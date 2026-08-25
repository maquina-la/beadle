import Foundation

/// Port policy for Dolt servers managed through Beadle.
///
/// bd's default Dolt port is 3307 and every project without a pinned port
/// shares it. Whichever project starts its server first owns the port, and
/// every other project either fails with "database not found" or — worse —
/// has its database created inside the winning project's data directory.
/// Beadle therefore pins each project to a unique port above the default.
enum DoltPortPolicy {
    static let bdDefault = 3307
    static let lowerBound = 3310
    static let upperBound = 3400
}

/// The subset of `.beads/metadata.json` that matters for server health.
struct DoltMetadata: Equatable, Sendable {
    var host: String?
    var port: Int?
    var databaseName: String?
    var mode: String?

    var effectivePort: Int {
        port ?? DoltPortPolicy.bdDefault
    }

    var isLocalHost: Bool {
        guard let host, !host.isEmpty else { return true }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    static func load(atProjectPath projectPath: String) -> DoltMetadata? {
        let url = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".beads/metadata.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> DoltMetadata? {
        struct Raw: Decodable {
            let dolt_server_host: String?
            let dolt_server_port: Int?
            let dolt_database: String?
            let dolt_mode: String?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        return DoltMetadata(
            host: raw.dolt_server_host,
            port: raw.dolt_server_port,
            databaseName: raw.dolt_database,
            mode: raw.dolt_mode
        )
    }
}

/// One actionable diagnosis for a project's Dolt setup.
struct DoltFinding: Identifiable, Equatable, Sendable {
    enum Severity: Int, Comparable, Sendable {
        case critical = 0
        case warning = 1

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum Kind: Equatable, Sendable {
        case sharedPort(port: Int, otherProjects: [String])
        case unpinnedPort
        case foreignDatabases(names: [String])
        case databaseServedElsewhere(databaseName: String)
        case portCollisionError(port: Int?)
    }

    let kind: Kind
    let severity: Severity

    var id: String {
        switch kind {
        case .sharedPort(let port, _): return "shared-port-\(port)"
        case .unpinnedPort: return "unpinned-port"
        case .foreignDatabases(let names): return "foreign-databases-\(names.sorted().joined(separator: ","))"
        case .databaseServedElsewhere(let name): return "served-elsewhere-\(name)"
        case .portCollisionError(let port): return "collision-error-\(port.map(String.init) ?? "x")"
        }
    }

    var isAutoFixable: Bool {
        switch kind {
        case .unpinnedPort, .sharedPort, .portCollisionError:
            return true
        case .foreignDatabases, .databaseServedElsewhere:
            return false
        }
    }

    var symbolName: String {
        switch kind {
        case .foreignDatabases, .databaseServedElsewhere, .portCollisionError:
            return "exclamationmark.triangle.fill"
        case .sharedPort:
            return "arrow.triangle.2.circlepath"
        case .unpinnedPort:
            return "number.square"
        }
    }

    var title: String {
        switch kind {
        case .sharedPort(let port, _):
            return "Port \(port) is shared with another project"
        case .unpinnedPort:
            return "No pinned Dolt port"
        case .foreignDatabases(let names):
            return names.count == 1
                ? "Foreign database “\(names[0])” lives in this repository"
                : "Foreign databases live in this repository"
        case .databaseServedElsewhere(let name):
            return "Database “\(name)” is served from another repository"
        case .portCollisionError(let port):
            return port.map { "bd reached the wrong Dolt server on port \($0)" }
                ?? "bd reached the wrong Dolt server"
        }
    }

    var detail: String {
        switch kind {
        case .sharedPort(let port, let others):
            let names = others.map { "“\($0)”" }.joined(separator: ", ")
            return "This project and \(names) resolve to port \(port). Whichever server starts first wins it; the others connect to a server that cannot have their database. Pin a unique port for each project."
        case .unpinnedPort:
            return "Without a pinned port this project defaults to \(DoltPortPolicy.bdDefault), where it can collide with any other unpinned project's server. Pinning a unique port prevents both load failures and cross-repository data contamination."
        case .foreignDatabases:
            return "A project writing through a port collision stored its database here, so this repository's Dolt data directory serves another project's issues. Verify with that project's owner, then move or remove the foreign database directory."
        case .databaseServedElsewhere:
            return "bd loads issues successfully, but the database is not in this repository's .beads/dolt directory — another repository's server is serving it over a shared port. Its issues travel with that repository's backups, not this one."
        case .portCollisionError:
            return "The Dolt server on this project's port belongs to a different data directory. Beadle can pin a free port, start the correct server, and retry."
        }
    }
}

/// Health assessment for one project, produced by `DoltHealthEngine`.
struct DoltProjectHealth: Identifiable, Equatable, Sendable {
    let projectID: UUID
    let projectName: String
    let pinnedPort: Int?
    let effectivePort: Int
    let databaseName: String?
    let findings: [DoltFinding]

    var id: UUID { projectID }

    var highestSeverity: DoltFinding.Severity? {
        findings.map(\.severity).min()
    }

    var isHealthy: Bool {
        findings.allSatisfy { $0.severity != .critical }
    }
}

/// Pure rules that turn per-project observations into findings.
///
/// Observations (metadata contents, data directory listing, bd load result)
/// are gathered elsewhere; everything here is deterministic and testable.
enum DoltHealthEngine {
    struct Input: Sendable {
        let projectID: UUID
        let projectName: String
        let metadata: DoltMetadata?
        let dataDirDatabases: [String]
        let loadSucceeded: Bool
        let loadError: String?

        init(
            projectID: UUID,
            projectName: String,
            metadata: DoltMetadata?,
            dataDirDatabases: [String] = [],
            loadSucceeded: Bool = false,
            loadError: String? = nil
        ) {
            self.projectID = projectID
            self.projectName = projectName
            self.metadata = metadata
            self.dataDirDatabases = dataDirDatabases
            self.loadSucceeded = loadSucceeded
            self.loadError = loadError
        }
    }

    static func assess(_ inputs: [Input]) -> [DoltProjectHealth] {
        var portOwners: [Int: [String]] = [:]
        for input in inputs {
            let port = input.metadata?.effectivePort ?? DoltPortPolicy.bdDefault
            portOwners[port, default: []].append(input.projectName)
        }

        return inputs.map { input in
            var findings: [DoltFinding] = []
            let metadata = input.metadata
            let effectivePort = metadata?.effectivePort ?? DoltPortPolicy.bdDefault
            let databaseName = metadata?.databaseName

            if let owners = portOwners[effectivePort], owners.count > 1 {
                let others = owners.filter { $0 != input.projectName }.sorted()
                findings.append(
                    DoltFinding(
                        kind: .sharedPort(port: effectivePort, otherProjects: others),
                        severity: .critical
                    )
                )
            }

            if metadata?.port == nil {
                findings.append(DoltFinding(kind: .unpinnedPort, severity: .warning))
            }

            let ownName = databaseName ?? ""
            let foreign = input.dataDirDatabases
                .filter { $0 != ownName }
                .filter { !isQuarantineName($0) }
            if !foreign.isEmpty {
                findings.append(
                    DoltFinding(kind: .foreignDatabases(names: foreign.sorted()), severity: .critical)
                )
            }

            let quarantined = input.dataDirDatabases
                .filter { $0 != ownName }
                .filter { isQuarantineName($0) }
            if !quarantined.isEmpty {
                findings.append(
                    DoltFinding(
                        kind: .foreignDatabases(names: quarantined.sorted()),
                        severity: .warning
                    )
                )
            }

            if input.loadSucceeded,
               let databaseName,
               !databaseName.isEmpty,
               (metadata?.isLocalHost ?? true),
               !input.dataDirDatabases.contains(databaseName) {
                findings.append(
                    DoltFinding(
                        kind: .databaseServedElsewhere(databaseName: databaseName),
                        severity: .critical
                    )
                )
            }

            if let error = input.loadError, isPortCollisionMessage(error) {
                findings.append(
                    DoltFinding(
                        kind: .portCollisionError(port: collisionPort(in: error)),
                        severity: .critical
                    )
                )
            }

            return DoltProjectHealth(
                projectID: input.projectID,
                projectName: input.projectName,
                pinnedPort: metadata?.port,
                effectivePort: effectivePort,
                databaseName: databaseName,
                findings: findings.sorted { $0.severity < $1.severity }
            )
        }
    }

    /// bd's port-collision error: the server on the configured port serves a
    /// different data directory, so the database is "not found".
    static func isPortCollisionMessage(_ message: String) -> Bool {
        message.contains("not found on Dolt server")
    }

    static func collisionPort(in message: String) -> Int? {
        guard let range = message.range(of: #"at\s+(?:\d{1,3}\.){3}\d{1,3}:(\d+)"#, options: .regularExpression),
              let port = message[range].split(separator: ":").last.flatMap({ Int($0) }) else {
            return nil
        }
        return port
    }

    /// Names left behind by manual quarantine after a contamination incident,
    /// e.g. "vocal-stale-20260816-ours".
    static func isQuarantineName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("stale") || lowered.contains("quarantine")
    }
}

/// Lists database directories inside a project's `.beads/dolt` directory.
enum DoltDataDirectory {
    static func databaseNames(atProjectPath projectPath: String) -> [String] {
        let url = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".beads/dolt", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        return entries.compactMap { entry in
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { return nil }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            return name
        }
        .sorted()
    }
}

/// Picks a free port in Beadle's range, skipping ports other projects use.
enum DoltPortAllocator {
    static func allocatePort(
        takenPorts: Set<Int>,
        isPortFree: (Int) -> Bool = defaultIsPortFree
    ) -> Int? {
        var port = DoltPortPolicy.lowerBound
        while port <= DoltPortPolicy.upperBound {
            if !takenPorts.contains(port) && isPortFree(port) {
                return port
            }
            port += 1
        }
        return nil
    }

    /// True when nothing is listening on the loopback port. Binding without
    /// SO_REUSEADDR fails with EADDRINUSE when a listener exists.
    static func defaultIsPortFree(port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
