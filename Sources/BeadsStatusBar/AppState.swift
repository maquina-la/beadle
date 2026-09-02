import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [ProjectConfiguration]
    @Published private(set) var projectIssues: [ProjectIssues] = [] {
        didSet { recomputeDerivedIssueState() }
    }

    /// Filtering used to be a computed property, which meant every view that
    /// read it re-filtered and re-searched the whole corpus: four or five full
    /// passes per render, and a fresh pass on every keystroke. These are
    /// derived once per input change instead.
    @Published private(set) var filteredProjectIssues: [ProjectIssues] = []
    @Published private(set) var availableFilterOptions = FilterOptions()
    @Published private(set) var openIssueCount = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRefreshAttempt: Date?
    @Published private(set) var doltServerRunning: Bool?
    @Published private(set) var projectHealth: [DoltProjectHealth] = []
    @Published private(set) var repairNotes: [UUID: RepairNote] = [:]
    @Published private(set) var issueDetails: [IssueKey: BeadIssue] = [:]
    @Published private(set) var loadingDetails: Set<IssueKey> = []
    @Published private(set) var detailErrors: [IssueKey: String] = [:]
    @Published private(set) var issueGitInfo: [IssueKey: IssueGitInfo] = [:]
    @Published private(set) var loadingGitInfo: Set<IssueKey> = []
    @Published var selectedProjectID: UUID? {
        didSet { recomputeDerivedIssueState() }
    }
    @Published var filters = IssueFilters() {
        didSet { recomputeFilteredIssues() }
    }
    @Published var searchText = "" {
        didSet { recomputeFilteredIssues() }
    }
    @Published var configuredExecutable: String {
        didSet { defaults.set(configuredExecutable, forKey: Keys.executable) }
    }

    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var activeOpenPanel: NSOpenPanel?

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults
            ?? UserDefaults(suiteName: Self.preferencesSuiteName)
            ?? .standard
        self.defaults = defaults
        configuredExecutable = defaults.string(forKey: Keys.executable) ?? ""

        if let data = defaults.data(forKey: Keys.projects),
           let stored = try? JSONDecoder().decode([ProjectConfiguration].self, from: data) {
            projects = stored
        } else {
            projects = []
        }
    }

    var visibleIssueCount: Int {
        filteredProjectIssues.reduce(0) { $0 + $1.issues.count }
    }

    /// Recomputes everything derived from the issue set. Filter options and the
    /// open count depend only on the loaded issues and the project scope; the
    /// filtered list additionally depends on the filters and the search text.
    private func recomputeDerivedIssueState() {
        var types = Set<String>()
        var assignees = Set<String>()
        var openCount = 0
        for snapshot in projectIssues {
            let inScope = selectedProjectID == nil || selectedProjectID == snapshot.id
            for issue in snapshot.issues {
                if issue.normalizedStatus != .closed { openCount += 1 }
                guard inScope else { continue }
                types.insert(issue.issueType)
                if let assignee = issue.assignee, !assignee.isEmpty {
                    assignees.insert(assignee)
                }
            }
        }
        openIssueCount = openCount
        availableFilterOptions = FilterOptions(
            types: types.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            assignees: assignees.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
        recomputeFilteredIssues()
    }

    private func recomputeFilteredIssues() {
        filteredProjectIssues = Self.filteredSnapshots(
            projectIssues,
            selectedProjectID: selectedProjectID,
            filters: filters,
            searchText: searchText
        )
    }

    var hasProjectErrors: Bool {
        projectIssues.contains { $0.error != nil }
    }

    var selectedProjectName: String {
        guard let selectedProjectID,
              let project = projects.first(where: { $0.id == selectedProjectID }) else {
            return "All projects"
        }
        return project.name
    }

    var resolvedExecutablePath: String? {
        BeadsClient.resolveExecutable(
            configuredExecutable: configuredExecutable.isEmpty ? nil : configuredExecutable
        )
    }

    /// Projects stay visible even when the current filters match zero of
    /// their issues (the header renders with a zero count); only the explicit
    /// single-project scope removes the other projects.
    nonisolated static func filteredSnapshots(
        _ snapshots: [ProjectIssues],
        selectedProjectID: UUID?,
        filters: IssueFilters,
        searchText: String
    ) -> [ProjectIssues] {
        snapshots.compactMap { snapshot in
            guard selectedProjectID == nil || selectedProjectID == snapshot.id else { return nil }
            let issues = snapshot.issues.filter { issue in
                guard filters.matches(issue) else { return false }
                guard !searchText.isEmpty else { return true }
                return matchesSearch(issue, text: searchText)
            }
            return ProjectIssues(project: snapshot.project, issues: issues, error: snapshot.error)
        }
    }

    /// Case-insensitive, but deliberately not *localized*: the locale-aware
    /// variants normalize as they scan, which is a real cost over full
    /// markdown descriptions on every keystroke. Matching semantics for the
    /// text people actually type are the same.
    nonisolated static func matchesSearch(_ issue: BeadIssue, text: String) -> Bool {
        issue.title.containsCaseInsensitive(text)
            || issue.id.containsCaseInsensitive(text)
            || issue.assignee?.containsCaseInsensitive(text) == true
            || issue.description?.containsCaseInsensitive(text) == true
            || issue.labels.contains { $0.containsCaseInsensitive(text) }
    }

    /// Distinct Type/Assignee values present in the currently-scoped issues, for the filter menu.
    struct FilterOptions: Equatable, Sendable {
        var types: [String] = []
        var assignees: [String] = []
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                await self?.checkDoltStatus()
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    struct RepairNote: Equatable, Sendable {
        let message: String
        let isError: Bool
    }

    private struct RefreshOutcome {
        let snapshot: ProjectIssues
        let healthInput: DoltHealthEngine.Input
    }

    /// Ports Beadle handed out this session, so concurrent repairs never
    /// allocate the same port before the pin lands in metadata.json.
    private var allocatedRepairPorts: Set<Int> = []

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        lastRefreshAttempt = Date()
        let currentProjects = projects
        let previousSnapshots = Dictionary(uniqueKeysWithValues: projectIssues.map { ($0.id, $0) })
        let executable = configuredExecutable.isEmpty ? nil : configuredExecutable
        var outcomes: [RefreshOutcome] = []

        await withTaskGroup(of: RefreshOutcome.self) { group in
            for (index, project) in currentProjects.enumerated() {
                // Stagger cold starts: simultaneous bd processes race to bind
                // the default Dolt port when no server is running yet.
                let stagger = Duration.seconds(Double(index) * 0.2)
                group.addTask { [weak self] in
                    if stagger > .zero {
                        try? await Task.sleep(for: stagger)
                    }
                    return await Self.refreshProject(
                        project,
                        executable: executable,
                        previousIssues: previousSnapshots[project.id]?.issues ?? [],
                        repair: { error in
                            guard BeadsClient.isPortCollisionError(error) else { return nil }
                            return await self?.repairDoltServer(for: project, executable: executable)
                        }
                    )
                }
            }

            for await outcome in group {
                outcomes.append(outcome)
            }
        }

        let results = outcomes.map(\.snapshot)
        projectIssues = results.sorted {
            $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
        }
        projectHealth = DoltHealthEngine.assess(outcomes.map(\.healthInput))
        let currentIssues = Dictionary(
            uniqueKeysWithValues: results.flatMap { snapshot in
                snapshot.issues.map {
                    (IssueKey(projectID: snapshot.id, issueID: $0.id), $0)
                }
            }
        )
        issueDetails = issueDetails.filter { key, detail in
            guard let current = currentIssues[key] else { return false }
            return current.updatedAt == detail.updatedAt
        }
        issueGitInfo = issueGitInfo.filter { key, _ in currentIssues[key] != nil }
        if results.contains(where: { $0.error == nil }) {
            lastRefresh = Date()
        }
    }

    private static func refreshProject(
        _ project: ProjectConfiguration,
        executable: String?,
        previousIssues: [BeadIssue],
        repair: (Error) async -> Int?
    ) async -> RefreshOutcome {
        do {
            let issues = try await BeadsClient.loadIssues(for: project, configuredExecutable: executable)
            let input = await healthInput(for: project, loadSucceeded: true, loadError: nil)
            return RefreshOutcome(
                snapshot: ProjectIssues(project: project, issues: issues, error: nil),
                healthInput: input
            )
        } catch {
            if let port = await repair(error) {
                if let issues = try? await BeadsClient.loadIssues(for: project, configuredExecutable: executable) {
                    let input = await healthInput(for: project, loadSucceeded: true, loadError: nil)
                    return RefreshOutcome(
                        snapshot: ProjectIssues(project: project, issues: issues, error: nil),
                        healthInput: input
                    )
                }
                _ = port // repair ran but the retry still failed; fall through with the original error
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let input = await healthInput(for: project, loadSucceeded: false, loadError: message)
            return RefreshOutcome(
                snapshot: ProjectIssues(project: project, issues: previousIssues, error: message),
                healthInput: input
            )
        }
    }

    private static func healthInput(
        for project: ProjectConfiguration,
        loadSucceeded: Bool,
        loadError: String?
    ) async -> DoltHealthEngine.Input {
        await Task.detached(priority: .utility) {
            DoltHealthEngine.Input(
                projectID: project.id,
                projectName: project.name,
                projectPath: project.path,
                metadata: DoltMetadata.load(atProjectPath: project.path),
                dataDirDatabases: DoltDataDirectory.databaseNames(atProjectPath: project.path),
                loadSucceeded: loadSucceeded,
                loadError: loadError
            )
        }.value
    }

    var hasCriticalDoltFindings: Bool {
        projectHealth.contains { !$0.isHealthy }
    }

    /// Pins a free Dolt port and starts the server. Serialized on the main
    /// actor so concurrent repairs pick distinct ports.
    @discardableResult
    private func repairDoltServer(
        for project: ProjectConfiguration,
        executable: String?
    ) async -> Int? {
        let taken = await Self.pinnedPorts(for: projects).union(allocatedRepairPorts)
        do {
            let port = try await BeadsClient.repairDoltServer(
                for: project,
                configuredExecutable: executable,
                takenPorts: taken
            )
            allocatedRepairPorts.insert(port)
            repairNotes[project.id] = RepairNote(
                message: "Pinned Dolt port \(port) and started the server.",
                isError: false
            )
            return port
        } catch {
            repairNotes[project.id] = RepairNote(
                message: "Repair failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)",
                isError: true
            )
            return nil
        }
    }

    /// User-triggered fix from the health view: pin a unique port, start the
    /// server, and refresh the project.
    func applyPortFix(for projectID: UUID) async {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        let executable = configuredExecutable.isEmpty ? nil : configuredExecutable
        if await repairDoltServer(for: project, executable: executable) != nil {
            await refresh()
        }
    }

    private static func pinnedPorts(for projects: [ProjectConfiguration]) async -> Set<Int> {
        await Task.detached(priority: .utility) {
            Set(projects.compactMap { DoltMetadata.load(atProjectPath: $0.path)?.port })
        }.value
    }

    func checkDoltStatus() async {
        let project = projects.first { $0.id == selectedProjectID } ?? projects.first
        guard let project else {
            doltServerRunning = nil
            return
        }

        let executable = configuredExecutable.isEmpty ? nil : configuredExecutable
        let running = await BeadsClient.doltServerRunning(
            for: project,
            configuredExecutable: executable
        )
        doltServerRunning = running
    }

    func detail(for key: IssueKey, fallback: BeadIssue) -> BeadIssue {
        issueDetails[key] ?? fallback
    }

    func loadDetails(for issue: BeadIssue, in project: ProjectConfiguration) async {
        let key = IssueKey(projectID: project.id, issueID: issue.id)
        guard issueDetails[key] == nil, !loadingDetails.contains(key) else { return }

        loadingDetails.insert(key)
        detailErrors[key] = nil
        defer { loadingDetails.remove(key) }

        do {
            let executable = configuredExecutable.isEmpty ? nil : configuredExecutable
            issueDetails[key] = try await BeadsClient.loadIssueDetails(
                issueID: issue.id,
                for: project,
                configuredExecutable: executable
            )
        } catch {
            detailErrors[key] = error.localizedDescription
        }
    }

    func gitInfo(for key: IssueKey) -> IssueGitInfo? {
        issueGitInfo[key]
    }

    func gitInfoIsLoading(for key: IssueKey) -> Bool {
        loadingGitInfo.contains(key)
    }

    func loadGitInfo(for issue: BeadIssue, in project: ProjectConfiguration) async {
        let key = IssueKey(projectID: project.id, issueID: issue.id)
        guard issueGitInfo[key] == nil, !loadingGitInfo.contains(key) else { return }

        loadingGitInfo.insert(key)
        defer { loadingGitInfo.remove(key) }

        issueGitInfo[key] = await GitClient.gitInfo(forIssue: issue.id, in: project)
    }

    func chooseAndAddProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Beads project"
        panel.message = "Choose a folder containing a .beads directory."
        panel.prompt = "Add Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        present(panel) { [weak self] url in
            self?.addProject(at: url)
        }
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose the bd executable"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        present(panel) { [weak self] url in
            guard let self else { return }
            self.configuredExecutable = url.path
            Task { await self.refresh() }
        }
    }

    func addProject(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard !projects.contains(where: { $0.path == standardizedURL.path }) else { return }

        projects.append(
            ProjectConfiguration(
                name: standardizedURL.lastPathComponent,
                path: standardizedURL.path
            )
        )
        persistProjects()
        Task { await refresh() }
    }

    func renameProject(id: UUID, name: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = name
        persistProjects()
    }

    func removeProject(id: UUID) {
        projects.removeAll { $0.id == id }
        projectIssues.removeAll { $0.id == id }
        issueDetails = issueDetails.filter { $0.key.projectID != id }
        detailErrors = detailErrors.filter { $0.key.projectID != id }
        issueGitInfo = issueGitInfo.filter { $0.key.projectID != id }
        if selectedProjectID == id { selectedProjectID = nil }
        persistProjects()
    }

    private func persistProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            defaults.set(data, forKey: Keys.projects)
        }
    }

    private func present(_ panel: NSOpenPanel, onChoose: @escaping (URL) -> Void) {
        activeOpenPanel?.cancel(nil)
        activeOpenPanel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.level = .floating
        panel.center()
        panel.begin { [weak self, weak panel] response in
            Task { @MainActor in
                defer { self?.activeOpenPanel = nil }
                guard response == .OK, let url = panel?.url else { return }
                onChoose(url)
            }
        }
        panel.orderFrontRegardless()
    }

    private enum Keys {
        static let projects = "projects"
        static let executable = "bdExecutablePath"
    }

    private static let preferencesSuiteName = "la.maquina.BeadsStatusBar"
}

private extension StringProtocol {
    func containsCaseInsensitive(_ other: some StringProtocol) -> Bool {
        range(of: other, options: .caseInsensitive) != nil
    }
}
