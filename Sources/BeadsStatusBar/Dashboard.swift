import AppKit
import SwiftUI
import MarkdownUI

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listHasFocus: Bool
    @FocusState private var searchHasFocus: Bool
    @State private var selectedIssueKey: IssueKey?
    @State private var pinnedIssueKey: IssueKey?
    @State private var collapsedProjectIDs: Set<UUID> = []
    @State private var showDoltHealth = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if state.projects.isEmpty {
                onboarding
            } else {
                filterBar
                Divider()
                issueContent
            }

            Divider()
            footer
        }
        .frame(width: 440, height: 580)
        .background {
            ZStack {
                DashboardBackground()
                WindowTransparencyConfigurator()
                    .allowsHitTesting(false)
            }
        }
        .task { state.startPolling() }
        .sheet(isPresented: $showDoltHealth) {
            DoltHealthView()
                .environmentObject(state)
        }
        .onChange(of: state.selectedProjectID) { _, _ in
            Task { await state.checkDoltStatus() }
        }
        .onChange(of: visibleEntries.map(\.key)) { _, keys in
            if let selectedIssueKey, !keys.contains(selectedIssueKey) {
                self.selectedIssueKey = keys.first
            }
            if let pinnedIssueKey, !keys.contains(pinnedIssueKey) {
                self.pinnedIssueKey = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Beadle")
                    .font(.headline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showDoltHealth = true
            } label: {
                Image(systemName: "stethoscope")
            }
            .buttonStyle(.borderless)
            .help("Dolt health")
            .accessibilityLabel("Dolt health")

            ZStack {
                if state.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing beads")
                } else {
                    Button {
                        Task { await state.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                    .accessibilityLabel("Refresh beads")
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            ProjectFilterMenu(
                projects: state.projects,
                selection: $state.selectedProjectID,
                title: state.selectedProjectName
            )
            .frame(width: 132)

            FilterMenu(filters: $state.filters, options: state.availableFilterOptions)
                .frame(width: 56)

            SearchField(text: $state.searchText, isFocused: $searchHasFocus)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    @ViewBuilder
    private var issueContent: some View {
        Group {
            if state.isRefreshing && state.projectIssues.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading beads…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.filteredProjectIssues.isEmpty {
                unavailableContent
            } else {
                issueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ContentLayerBackground() }
    }

    private var issueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.filteredProjectIssues) { snapshot in
                        let isCollapsed = collapsedProjectIDs.contains(snapshot.project.id)
                        Section {
                            if snapshot.issues.isEmpty, let error = snapshot.error {
                                ProjectErrorView(message: error) {
                                    openAppSettings()
                                }
                            }

                            if !isCollapsed {
                                ForEach(snapshot.issues) { issue in
                                    let key = IssueKey(
                                        projectID: snapshot.project.id,
                                        issueID: issue.id
                                    )
                                    IssueRow(
                                        project: snapshot.project,
                                        issue: issue,
                                        detail: state.detail(for: key, fallback: issue),
                                        detailIsLoading: state.loadingDetails.contains(key),
                                        detailError: state.detailErrors[key],
                                        gitInfo: state.gitInfo(for: key),
                                        gitInfoIsLoading: state.gitInfoIsLoading(for: key),
                                        isSelected: selectedIssueKey == key,
                                        isPinned: pinnedIssueKey == key,
                                        onActivate: {
                                            listHasFocus = true
                                            selectedIssueKey = key
                                            pinnedIssueKey = pinnedIssueKey == key ? nil : key
                                            requestDetails(for: issue, in: snapshot.project)
                                        },
                                        onPreview: {
                                            requestDetails(for: issue, in: snapshot.project)
                                        }
                                    )
                                    .id(key)

                                    Divider()
                                        .padding(.leading, 42)
                                }
                            }
                        } header: {
                            ProjectHeader(
                                name: snapshot.project.name,
                                count: snapshot.issues.count,
                                error: snapshot.error,
                                doltFindingSummary: doltFindingSummary(for: snapshot.id),
                                isCollapsed: isCollapsed,
                                onToggle: {
                                    toggleCollapse(snapshot.project.id)
                                }
                            )
                        }
                    }
                }
            }
            .focusable()
            .focused($listHasFocus)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) {
                moveSelection(by: -1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.return) {
                guard let selectedIssueKey else { return .ignored }
                pinnedIssueKey = pinnedIssueKey == selectedIssueKey ? nil : selectedIssueKey
                if let entry = visibleEntries.first(where: { $0.key == selectedIssueKey }) {
                    requestDetails(for: entry.issue, in: entry.project)
                }
                return .handled
            }
            .onKeyPress(.escape) {
                guard pinnedIssueKey != nil else { return .ignored }
                pinnedIssueKey = nil
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "f")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                searchHasFocus = true
                return .handled
            }
        }
    }

    private var unavailableContent: some View {
        ContentUnavailableView {
            Label(unavailableTitle, systemImage: unavailableSymbol)
        } description: {
            Text(unavailableDescription)
        } actions: {
            if state.hasProjectErrors {
                Button("Settings…") { openAppSettings() }
            } else if !state.searchText.isEmpty {
                Button("Clear Search") { state.searchText = "" }
            }
        }
    }

    private var onboarding: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 5) {
                Text("Add your first Beads project")
                    .font(.headline)
                Text("Choose a repository with a .beads directory.\nThe app reads issues using your local bd CLI.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Choose Project…") { state.chooseAndAddProject() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                refreshStatus(at: context.date)
                Spacer()
                Button {
                    openAppSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")
                .accessibilityLabel("Settings")
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private func refreshStatus(at now: Date) -> some View {
        if state.hasProjectErrors {
            Button {
                showDoltHealth = true
            } label: {
                Label("Some projects unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Cached issues remain visible. Open Dolt health for per-project diagnosis.")
            .accessibilityLabel("Some projects unavailable. Open Dolt health.")
        } else if state.hasCriticalDoltFindings {
            Button {
                showDoltHealth = true
            } label: {
                Label("Dolt attention needed", systemImage: "stethoscope")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("A project's Dolt setup shows contamination or port-collision findings. Open Dolt health for details and fixes.")
            .accessibilityLabel("Dolt attention needed. Open Dolt health.")
        } else if let running = state.doltServerRunning {
            HStack(spacing: 4) {
                Image(systemName: running ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                    .foregroundStyle(running ? Color.green : Color.secondary)
                Text(running ? "Dolt running" : "Dolt stopped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .help(running
                  ? "The Dolt database server for this project is running."
                  : "The Dolt database server for this project is not running.")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundStyle(.tertiary)
                Text("Checking…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var summaryText: String {
        let count = state.openIssueCount
        return count == 1 ? "1 open issue" : "\(count) open issues"
    }

    private var unavailableTitle: String {
        state.hasProjectErrors ? "Can’t load beads" : "No active beads"
    }

    private var unavailableSymbol: String {
        state.hasProjectErrors ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var unavailableDescription: String {
        if state.hasProjectErrors {
            return "Check the project folder and bd executable in Settings."
        }
        return "Projects stay listed with a zero count. Closed issues are hidden until you enable Closed in the Status filter."
    }

    private var visibleEntries: [IssueEntry] {
        state.filteredProjectIssues.flatMap { snapshot -> [IssueEntry] in
            guard !collapsedProjectIDs.contains(snapshot.project.id) else { return [] }
            return snapshot.issues.map {
                IssueEntry(project: snapshot.project, issue: $0)
            }
        }
    }

    private func toggleCollapse(_ projectID: UUID) {
        if collapsedProjectIDs.contains(projectID) {
            collapsedProjectIDs.remove(projectID)
        } else {
            collapsedProjectIDs.insert(projectID)
        }
    }

    private func doltFindingSummary(for projectID: UUID) -> String? {
        guard let health = state.projectHealth.first(where: { $0.projectID == projectID }),
              !health.findings.isEmpty else { return nil }
        return health.findings.map(\.title).joined(separator: "\n")
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) {
        let entries = visibleEntries
        guard !entries.isEmpty else { return }

        let currentIndex = selectedIssueKey.flatMap { key in
            entries.firstIndex(where: { $0.key == key })
        }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + offset, 0), entries.count - 1)
        } else {
            nextIndex = offset < 0 ? entries.count - 1 : 0
        }

        let entry = entries[nextIndex]
        selectedIssueKey = entry.key
        if reduceMotion {
            proxy.scrollTo(entry.key, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(entry.key, anchor: .center)
            }
        }
    }

    private func requestDetails(for issue: BeadIssue, in project: ProjectConfiguration) {
        Task { await state.loadDetails(for: issue, in: project) }
        Task { await state.loadGitInfo(for: issue, in: project) }
    }

    private func openAppSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}

private struct IssueEntry: Identifiable {
    let project: ProjectConfiguration
    let issue: BeadIssue

    var key: IssueKey {
        IssueKey(projectID: project.id, issueID: issue.id)
    }

    var id: IssueKey { key }
}

private struct ProjectFilterMenu: View {
    let projects: [ProjectConfiguration]
    @Binding var selection: UUID?
    let title: String

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("All projects", systemImage: "checkmark")
                } else {
                    Text("All projects")
                }
            }
            Divider()
            ForEach(projects) { project in
                Button {
                    selection = project.id
                } label: {
                    if selection == project.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            FilterLabel(title: title, symbol: "folder", showsDisclosure: true)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Filter by project")
        .accessibilityLabel("Project filter, \(title)")
    }
}

private struct FilterMenu: View {
    @Binding var filters: IssueFilters
    let options: AppState.FilterOptions

    var body: some View {
        Menu {
            Section("Status") {
                ForEach(IssueStatus.allCases) { status in
                    toggle(
                        title: status.label,
                        isSelected: filters.statuses.contains(status),
                        symbol: status.symbol
                    ) {
                        if filters.statuses.contains(status) {
                            filters.statuses.remove(status)
                        } else {
                            filters.statuses.insert(status)
                        }
                    }
                }
                Text("Closed issues are hidden until selected")
            }
            Section("Priority") {
                ForEach(0...4, id: \.self) { priority in
                    toggle(title: priority.priorityLabel, isSelected: filters.priorities.contains(priority)) {
                        if filters.priorities.contains(priority) {
                            filters.priorities.remove(priority)
                        } else {
                            filters.priorities.insert(priority)
                        }
                    }
                }
            }
            if !options.types.isEmpty {
                Section("Type") {
                    ForEach(options.types, id: \.self) { type in
                        toggle(title: type.capitalized, isSelected: filters.types.contains(type)) {
                            if filters.types.contains(type) {
                                filters.types.remove(type)
                            } else {
                                filters.types.insert(type)
                            }
                        }
                    }
                }
            }
            if !options.assignees.isEmpty {
                Section("Assignee") {
                    ForEach(options.assignees, id: \.self) { assignee in
                        toggle(title: assignee, isSelected: filters.assignees.contains(assignee)) {
                            if filters.assignees.contains(assignee) {
                                filters.assignees.remove(assignee)
                            } else {
                                filters.assignees.insert(assignee)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Clear All") { filters.clear() }
                .disabled(filters.isEmpty)
        } label: {
            filterLabel
        }
        .menuStyle(.borderlessButton)
        .help("Filter issues")
        .accessibilityLabel(filters.isEmpty ? "Filter issues" : "Filter issues, \(filters.activeCount) active")
    }

    /// A single toggle row: shows a native checkmark when selected. Using `Toggle`
    /// (rather than a `Button` with a manual checkmark) is what makes macOS render
    /// the standard selected-state indicator inside a menu.
    @ViewBuilder
    private func toggle(title: String, isSelected: Bool, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in action() }
        )) {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
    }

    private var filterLabel: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(filters.isEmpty ? Color.secondary : Color.accentColor)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(.quaternary.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())

            if filters.activeCount > 0 {
                Text("\(filters.activeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 4, y: -3)
            }
        }
    }
}

private struct FilterLabel: View {
    let title: String
    let symbol: String
    let showsDisclosure: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(.quaternary.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(text.isEmpty ? 0 : 1)
            .allowsHitTesting(!text.isEmpty)
            .accessibilityHidden(text.isEmpty)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(.quaternary.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }
}

private struct ProjectHeader: View {
    let name: String
    let count: Int
    let error: String?
    let doltFindingSummary: String?
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 10)

                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(error)
                        .accessibilityLabel("Project unavailable: \(error)")
                } else if let doltFindingSummary {
                    Image(systemName: "bolt.trianglebadge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .help(doltFindingSummary)
                        .accessibilityLabel("Dolt finding: \(doltFindingSummary)")
                }
                Spacer()
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.thinMaterial)
        .accessibilityLabel("\(name) project, \(count) issues")
        .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
        .accessibilityHint("Press to \(isCollapsed ? "expand" : "collapse") this project")
    }
}

private struct ProjectErrorView: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Project unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("Settings…", action: openSettings)
                .buttonStyle(.link)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct IssueRow: View {
    let project: ProjectConfiguration
    let issue: BeadIssue
    let detail: BeadIssue
    let detailIsLoading: Bool
    let detailError: String?
    let gitInfo: IssueGitInfo?
    let gitInfoIsLoading: Bool
    let isSelected: Bool
    let isPinned: Bool
    let onActivate: () -> Void
    let onPreview: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowIsHovering = false
    @State private var panelIsHovering = false
    @State private var inspectorIsPresented = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        rowButton
            .background(rowBackground)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: rowIsHovering)
            .onHover(perform: handleRowHover)
            .popover(
                isPresented: $inspectorIsPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                inspector
            }
            .onChange(of: isPinned) { _, pinned in
                handlePinnedChange(pinned)
            }
            .onAppear {
                if isPinned { inspectorIsPresented = true }
            }
            .onDisappear { hoverTask?.cancel() }
            .contextMenu {
                rowContextMenu
            }
            .accessibilityLabel(issue.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Press to pin issue details. Use the context menu to copy the ID or title.")
    }

    private var rowButton: some View {
        Button(action: onActivate) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: issue.normalizedStatus.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(issue.normalizedStatus.color)
                    .frame(width: 18, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 7) {
                        Text(issue.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        PriorityBadge(priority: issue.priority)
                        if let assignee = issue.assignee, !assignee.isEmpty {
                            Label(assignee, systemImage: "person.crop.circle")
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }

                Image(systemName: isPinned ? "pin.fill" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary.opacity(0.65))
                    .frame(width: 14, height: 20)
                    .opacity(rowIsHovering || isSelected || isPinned ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var inspector: some View {
        IssueInspector(
            projectName: project.name,
            issue: detail,
            isLoading: detailIsLoading,
            error: detailError,
            gitInfo: gitInfo,
            gitInfoIsLoading: gitInfoIsLoading
        )
        .onHover(perform: handlePanelHover)
    }

    @ViewBuilder
    private var rowContextMenu: some View {
        Button("Copy issue ID") { copyToPasteboard(issue.id) }
        Button("Copy title") { copyToPasteboard(issue.title) }
        Divider()
        Button(isPinned ? "Unpin Details" : "Pin Details", action: onActivate)
    }

    private var rowBackground: some View {
        Group {
            if isSelected || isPinned {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isPinned ? 0.14 : 0.09))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            } else if rowIsHovering {
                Color.primary.opacity(0.045)
            } else {
                Color.clear
            }
        }
    }

    private var accessibilityValue: String {
        var values = [issue.normalizedStatus.label, "priority \(issue.priority)"]
        if let assignee = issue.assignee { values.append("assigned to \(assignee)") }
        values.append("project \(project.name)")
        return values.joined(separator: ", ")
    }

    private func handleRowHover(_ hovering: Bool) {
        rowIsHovering = hovering
        hoverTask?.cancel()

        if hovering {
            hoverTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(240))
                } catch {
                    return
                }
                guard rowIsHovering else { return }
                onPreview()
                inspectorIsPresented = true
            }
        } else if !isPinned {
            scheduleDismiss()
        }
    }

    private func handlePinnedChange(_ pinned: Bool) {
        if pinned {
            hoverTask?.cancel()
            inspectorIsPresented = true
            onPreview()
        } else if !rowIsHovering, !panelIsHovering {
            scheduleDismiss()
        }
    }

    private func handlePanelHover(_ hovering: Bool) {
        panelIsHovering = hovering
        if hovering {
            hoverTask?.cancel()
        } else if !isPinned {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 240))
            } catch {
                return
            }
            guard !rowIsHovering, !panelIsHovering, !isPinned else { return }
            inspectorIsPresented = false
        }
    }
}

private struct IssueInspector: View {
    let projectName: String
    let issue: BeadIssue
    let isLoading: Bool
    let error: String?
    let gitInfo: IssueGitInfo?
    let gitInfoIsLoading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                inspectorHeader
                Divider()
                description
                properties

                if showGitSection {
                    gitSection
                }

                if !issue.labels.isEmpty {
                    labels
                }

                if !issue.dependencies.isEmpty {
                    RelationshipSection(title: "Dependencies", relations: issue.dependencies)
                }

                if !issue.dependents.isEmpty {
                    RelationshipSection(title: "Dependents", relations: issue.dependents)
                }

                if let closeReason = issue.closeReason, !closeReason.isEmpty {
                    InspectorTextSection(title: "Closure", text: closeReason)
                }

                if let notes = issue.notes, !notes.isEmpty {
                    InspectorTextSection(title: "Notes", text: notes)
                }

                if isLoading {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Loading relationships…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                dates
            }
            .padding(16)
        }
        .frame(width: 360, alignment: .leading)
        .frame(maxHeight: 510, alignment: .top)
    }

    /// Show the Git section once we know it's a git repo, or while we're still
    /// loading. Hide it entirely for non-git projects to avoid noise.
    private var showGitSection: Bool {
        if gitInfoIsLoading { return true }
        return gitInfo?.isGitRepository == true
    }

    private var inspectorHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.normalizedStatus.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(issue.normalizedStatus.color)
                .frame(width: 20, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(issue.id)
                        .font(.caption.monospaced())
                    PriorityBadge(priority: issue.priority)
                    Text(issue.issueType.capitalized)
                    Text(projectName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                copyToPasteboard(issue.id)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy issue ID")
            .accessibilityLabel("Copy issue ID")
        }
    }

    @ViewBuilder
    private var description: some View {
        if let text = issue.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            MarkdownSection(text: text, font: .body)
        } else {
            Text("No description")
                .font(.body)
                .italic()
                .foregroundStyle(.tertiary)
        }
    }

    private var properties: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
            GridRow {
                DetailLabel(
                    title: issue.normalizedStatus.label,
                    symbol: issue.normalizedStatus.symbol,
                    color: issue.normalizedStatus.color
                )
                if let person = issue.assignee ?? issue.owner, !person.isEmpty {
                    DetailLabel(title: person, symbol: "person.crop.circle")
                }
            }
            GridRow {
                DetailLabel(
                    title: "\(issue.commentCount) comments",
                    symbol: "bubble.left"
                )
                if let due = issue.dueDate {
                    DetailLabel(title: due.formatted(date: .abbreviated, time: .omitted), symbol: "calendar")
                }
            }
        }
    }

    @ViewBuilder
    private var gitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionTitle(title: "Git")

            if gitInfoIsLoading || gitInfo == nil {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Loading git info…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let info = gitInfo {
                gitBranches(in: info)
                gitCommits(in: info)
            }
        }
    }

    @ViewBuilder
    private func gitBranches(in info: IssueGitInfo) -> some View {
        if info.matchingBranches.isEmpty {
            Text("No matching branch")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(info.matchingBranches, id: \.name) { branch in
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(branch.name)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if branch.isCurrent {
                            Text("current")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gitCommits(in info: IssueGitInfo) -> some View {
        if info.commits.isEmpty {
            Text("No commits reference this issue")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(info.commits.prefix(10).enumerated()), id: \.offset) { _, commit in
                    HStack(alignment: .top, spacing: 7) {
                        Text(commit.shortHash)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(commit.subject)
                                .font(.caption)
                                .lineLimit(2)
                            if let date = commit.date {
                                Text(date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button {
                            copyToPasteboard(commit.shortHash)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy commit hash")
                        .accessibilityLabel("Copy commit hash")
                    }
                }
                if info.commits.count > 10 {
                    Text("+\(info.commits.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionTitle(title: "Labels", count: issue.labels.count)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(issue.labels, id: \.self) { label in
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let created = issue.createdDate {
                Text("Created \(created, style: .date)")
            }
            if let updated = issue.updatedDate {
                Text("Updated \(updated, style: .relative) ago")
            }
            if let closed = issue.closedDate {
                Text("Closed \(closed, style: .relative) ago")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}

private struct RelationshipSection: View {
    let title: String
    let relations: [BeadRelation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionTitle(title: title, count: relations.count)
            ForEach(relations) { relation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: relationStatus(relation).symbol)
                        .foregroundStyle(relationStatus(relation).color)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(relation.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(relation.id)
                                .font(.caption2.monospaced())
                            if let type = relation.dependencyType {
                                Text(type.replacingOccurrences(of: "-", with: " "))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func relationStatus(_ relation: BeadRelation) -> IssueStatus {
        relation.status.flatMap(IssueStatus.init(rawValue:)) ?? .open
    }
}

private struct InspectorTextSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            InspectorSectionTitle(title: title)
            MarkdownSection(text: text, font: .caption)
        }
    }
}

private struct InspectorSectionTitle: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
            if let count { Text("\(count)") }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
}

private struct DetailLabel: View {
    let title: String
    let symbol: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(priority <= 1 ? Color.orange : Color.secondary)
            .accessibilityLabel("Priority \(priority)")
    }
}

private struct DashboardBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.72)
        }
    }
}

private struct ContentLayerBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(contrast == .increased ? 0.62 : 0.3)
                Color(nsColor: .controlBackgroundColor)
                    .opacity(contrast == .increased ? 0.38 : 0.12)
            }
        }
    }
}

private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TransparentWindowProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TransparentWindowProbeView)?.configureWindow()
    }
}

private final class TransparentWindowProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.invalidateShadow()
    }
}

private extension IssueStatus {
    var color: Color {
        switch self {
        case .open: .secondary
        case .inProgress: .blue
        case .blocked: .red
        case .deferred: .orange
        case .closed: .green
        }
    }
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
