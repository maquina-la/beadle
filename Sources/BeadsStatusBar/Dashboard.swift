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
            .frame(maxWidth: .infinity)

            StatusFilterMenu(selection: $state.filter)
                .frame(width: 112)

            SearchField(text: $state.searchText, isFocused: $searchHasFocus)
                .frame(width: 132)
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
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(state.filteredProjectIssues) { snapshot in
                        Section {
                            if snapshot.issues.isEmpty, let error = snapshot.error {
                                ProjectErrorView(message: error) {
                                    openAppSettings()
                                }
                            }

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
                        } header: {
                            ProjectHeader(
                                name: snapshot.project.name,
                                count: snapshot.issues.count,
                                error: snapshot.error
                            )
                        }
                    }
                }
            }
            .focusable()
            .focused($listHasFocus)
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
                Button("Settings…") { openAppSettings() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(",", modifiers: .command)
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
            Label("Some projects unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Cached issues remain visible. Open Settings to check project and CLI paths.")
        } else if let lastRefresh = state.lastRefresh {
            let isStale = now.timeIntervalSince(lastRefresh) > 60
            Label {
                Text("Updated \(lastRefresh, style: .relative) ago")
            } icon: {
                Image(systemName: isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
            }
            .foregroundStyle(isStale ? Color.orange : Color.secondary.opacity(0.68))
        } else {
            Text("Not updated yet")
                .foregroundStyle(.tertiary)
        }
    }

    private var summaryText: String {
        let count = state.openIssueCount
        return count == 1 ? "1 open issue" : "\(count) open issues"
    }

    private var unavailableTitle: String {
        if state.hasProjectErrors { return "Can’t load beads" }
        if !state.searchText.isEmpty { return "No search results" }
        switch state.filter {
        case .closed: return "No closed beads"
        case .blocked: return "Nothing blocked"
        case .inProgress: return "Nothing in progress"
        case .open, .all: return "No active beads"
        }
    }

    private var unavailableSymbol: String {
        if state.hasProjectErrors { return "exclamationmark.triangle" }
        if !state.searchText.isEmpty { return "magnifyingglass" }
        return state.filter == .closed ? "archivebox" : "checkmark.circle"
    }

    private var unavailableDescription: String {
        if state.hasProjectErrors {
            return "Check the project folder and bd executable in Settings."
        }
        if !state.searchText.isEmpty {
            return "Try a different title, ID, assignee, description, or label."
        }
        return "This view will update automatically when Beads changes."
    }

    private var visibleEntries: [IssueEntry] {
        state.filteredProjectIssues.flatMap { snapshot in
            snapshot.issues.map {
                IssueEntry(project: snapshot.project, issue: $0)
            }
        }
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

private struct StatusFilterMenu: View {
    @Binding var selection: IssueFilter

    var body: some View {
        Menu {
            ForEach(IssueFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    if selection == filter {
                        Label(filter.label, systemImage: "checkmark")
                    } else {
                        Text(filter.label)
                    }
                }
            }
        } label: {
            FilterLabel(title: selection.label, symbol: selection.symbol, showsDisclosure: true)
        }
        .menuStyle(.borderlessButton)
        .help("Filter by status")
        .accessibilityLabel("Status filter, \(selection.label)")
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
        .font(.caption)
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

    var body: some View {
        HStack(spacing: 6) {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(error)
                    .accessibilityLabel("Project unavailable: \(error)")
            }
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.thinMaterial)
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
            error: detailError
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                inspectorHeader
                Divider()
                description
                properties

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

private extension IssueFilter {
    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .open: IssueStatus.open.symbol
        case .inProgress: IssueStatus.inProgress.symbol
        case .blocked: IssueStatus.blocked.symbol
        case .closed: IssueStatus.closed.symbol
        }
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
