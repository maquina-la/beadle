import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [ProjectConfiguration]
    @Published private(set) var projectIssues: [ProjectIssues] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRefreshAttempt: Date?
    @Published private(set) var issueDetails: [IssueKey: BeadIssue] = [:]
    @Published private(set) var loadingDetails: Set<IssueKey> = []
    @Published private(set) var detailErrors: [IssueKey: String] = [:]
    @Published var selectedProjectID: UUID?
    @Published var filter: IssueFilter = .all
    @Published var searchText = ""
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

    var openIssueCount: Int {
        projectIssues.flatMap(\.issues).filter { $0.normalizedStatus != .closed }.count
    }

    var visibleIssueCount: Int {
        filteredProjectIssues.reduce(0) { $0 + $1.issues.count }
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

    var filteredProjectIssues: [ProjectIssues] {
        projectIssues.compactMap { snapshot in
            guard selectedProjectID == nil || selectedProjectID == snapshot.id else { return nil }
            let issues = snapshot.issues.filter { issue in
                guard filter.includes(issue) else { return false }
                guard !searchText.isEmpty else { return true }
                return issue.title.localizedCaseInsensitiveContains(searchText)
                    || issue.id.localizedCaseInsensitiveContains(searchText)
                    || issue.assignee?.localizedCaseInsensitiveContains(searchText) == true
                    || issue.description?.localizedCaseInsensitiveContains(searchText) == true
                    || issue.labels.contains(where: {
                        $0.localizedCaseInsensitiveContains(searchText)
                    })
            }
            guard !issues.isEmpty || snapshot.error != nil else { return nil }
            return ProjectIssues(project: snapshot.project, issues: issues, error: snapshot.error)
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
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

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        lastRefreshAttempt = Date()
        let currentProjects = projects
        let previousSnapshots = Dictionary(uniqueKeysWithValues: projectIssues.map { ($0.id, $0) })
        let executable = configuredExecutable.isEmpty ? nil : configuredExecutable
        var results: [ProjectIssues] = []

        await withTaskGroup(of: ProjectIssues.self) { group in
            for project in currentProjects {
                group.addTask {
                    do {
                        let issues = try await BeadsClient.loadIssues(
                            for: project,
                            configuredExecutable: executable
                        )
                        return ProjectIssues(project: project, issues: issues, error: nil)
                    } catch {
                        let cachedIssues = previousSnapshots[project.id]?.issues ?? []
                        return ProjectIssues(project: project, issues: cachedIssues, error: error.localizedDescription)
                    }
                }
            }

            for await result in group {
                results.append(result)
            }
        }

        projectIssues = results.sorted {
            $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
        }
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
        if results.contains(where: { $0.error == nil }) {
            lastRefresh = Date()
        }
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

    private static let preferencesSuiteName = "im.carlosrivera.BeadsStatusBar"
}
