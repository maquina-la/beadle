import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var projects: [ProjectConfiguration]
    @Published private(set) var projectIssues: [ProjectIssues] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published var selectedProjectID: UUID?
    @Published var filter: IssueFilter = .all
    @Published var searchText = ""
    @Published var configuredExecutable: String {
        didSet { defaults.set(configuredExecutable, forKey: Keys.executable) }
    }

    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
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

    var filteredProjectIssues: [ProjectIssues] {
        projectIssues.compactMap { snapshot in
            guard selectedProjectID == nil || selectedProjectID == snapshot.id else { return nil }
            let issues = snapshot.issues.filter { issue in
                guard filter.includes(issue) else { return false }
                guard !searchText.isEmpty else { return true }
                return issue.title.localizedCaseInsensitiveContains(searchText)
                    || issue.id.localizedCaseInsensitiveContains(searchText)
                    || issue.assignee?.localizedCaseInsensitiveContains(searchText) == true
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

        let currentProjects = projects
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
                        return ProjectIssues(
                            project: project,
                            issues: [],
                            error: error.localizedDescription
                        )
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
        lastRefresh = Date()
    }

    func chooseAndAddProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Beads project"
        panel.message = "Choose a folder containing a .beads directory."
        panel.prompt = "Add Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addProject(at: url)
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
        if selectedProjectID == id { selectedProjectID = nil }
        persistProjects()
    }

    private func persistProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            defaults.set(data, forKey: Keys.projects)
        }
    }

    private enum Keys {
        static let projects = "projects"
        static let executable = "bdExecutablePath"
    }
}
