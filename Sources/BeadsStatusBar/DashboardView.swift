import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if state.projects.isEmpty {
                emptyState
            } else {
                controls
                Divider()
                issueList
            }

            Divider()
            footer
        }
        .frame(width: 440, height: 580)
        .background { DashboardBackground() }
        .task { state.startPolling() }
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
                Text("Beads")
                    .font(.headline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(state.isRefreshing ? .degrees(360) : .zero)
            }
            .buttonStyle(.borderless)
            .disabled(state.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var controls: some View {
        VStack(spacing: 9) {
            HStack {
                Picker("Project", selection: $state.selectedProjectID) {
                    Text("All projects").tag(UUID?.none)
                    ForEach(state.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()

                Picker("Status", selection: $state.filter) {
                    ForEach(IssueFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search issues", text: $state.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var issueList: some View {
        Group {
            if state.isRefreshing && state.projectIssues.isEmpty {
                ProgressView("Loading beads…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.filteredProjectIssues.isEmpty {
                ContentUnavailableView(
                    "No matching beads",
                    systemImage: "checkmark.circle",
                    description: Text("Try another project or filter.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(state.filteredProjectIssues) { snapshot in
                            Section {
                                if let error = snapshot.error {
                                    ProjectErrorView(message: error)
                                }
                                ForEach(snapshot.issues) { issue in
                                    IssueRow(issue: issue)
                                    Divider().padding(.leading, 42)
                                }
                            } header: {
                                ProjectHeader(
                                    name: snapshot.project.name,
                                    count: snapshot.issues.count
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
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
        HStack {
            if let lastRefresh = state.lastRefresh {
                Text("Updated \(lastRefresh, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Not updated yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Settings…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }
                .buttonStyle(.borderless)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var summaryText: String {
        let count = state.openIssueCount
        return count == 1 ? "1 open issue" : "\(count) open issues"
    }
}

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(0.055)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color.accentColor.opacity(0.018),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }
}

private struct ProjectHeader: View {
    let name: String
    let count: Int

    var body: some View {
        HStack {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(.regularMaterial)
    }
}

private struct ProjectErrorView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct IssueRow: View {
    let issue: BeadIssue
    @State private var isRowHovering = false
    @State private var isPanelHovering = false
    @State private var isDetailsPresented = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.normalizedStatus.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(issue.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    PriorityBadge(priority: issue.priority)

                    Label(issue.issueType.capitalized, systemImage: typeSymbol)

                    if let assignee = issue.assignee, !assignee.isEmpty {
                        Label(assignee, systemImage: "person.crop.circle")
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if issue.dependencyCount > 0 || issue.commentCount > 0 {
                    HStack(spacing: 10) {
                        if issue.dependencyCount > 0 {
                            Label("\(issue.dependencyCount)", systemImage: "arrow.triangle.branch")
                        }
                        if issue.commentCount > 0 {
                            Label("\(issue.commentCount)", systemImage: "bubble.left")
                        }
                        if let updated = issue.updatedDate {
                            Text("Updated \(updated, style: .relative) ago")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

            }

            if isRowHovering || isDetailsPresented {
                Button {
                    copyToPasteboard(issue.id)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy issue ID")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isRowHovering || isDetailsPresented ? Color.primary.opacity(0.045) : .clear)
        .animation(.easeOut(duration: 0.12), value: isRowHovering)
        .onHover(perform: handleRowHover)
        .popover(
            isPresented: $isDetailsPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            IssueDetailPanel(issue: issue, statusColor: statusColor)
                .onHover(perform: handlePanelHover)
        }
        .onDisappear { hoverTask?.cancel() }
        .contextMenu {
            Button("Copy issue ID") {
                copyToPasteboard(issue.id)
            }
            Button("Copy title") {
                copyToPasteboard(issue.title)
            }
        }
    }

    private var statusColor: Color {
        switch issue.normalizedStatus {
        case .open: .secondary
        case .inProgress: .yellow
        case .blocked: .red
        case .deferred: .secondary
        case .closed: .green
        }
    }

    private var typeSymbol: String {
        switch issue.issueType {
        case "bug": "ladybug"
        case "feature": "sparkles"
        case "epic": "bolt.fill"
        case "chore": "wrench.and.screwdriver"
        default: "checkmark.square"
        }
    }

    private func handleRowHover(_ hovering: Bool) {
        isRowHovering = hovering
        hoverTask?.cancel()

        if hovering {
            hoverTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(240))
                } catch {
                    return
                }
                guard isRowHovering else { return }
                isDetailsPresented = true
            }
        } else {
            scheduleDismiss()
        }
    }

    private func handlePanelHover(_ hovering: Bool) {
        isPanelHovering = hovering
        if hovering {
            hoverTask?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(260))
            } catch {
                return
            }
            guard !isRowHovering, !isPanelHovering else { return }
            isDetailsPresented = false
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct IssueDetailPanel: View {
    let issue: BeadIssue
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: issue.normalizedStatus.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 20, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(issue.id)
                            .font(.caption.monospaced())
                        PriorityBadge(priority: issue.priority)
                        Text(issue.issueType.capitalized)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(issue.id, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy issue ID")
            }

            Divider()

            if let description = issue.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text("No description")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)
            }

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                GridRow {
                    DetailLabel(
                        title: issue.normalizedStatus.label,
                        symbol: issue.normalizedStatus.symbol,
                        color: statusColor
                    )
                    if let person = issue.assignee ?? issue.owner, !person.isEmpty {
                        DetailLabel(title: person, symbol: "person.crop.circle")
                    }
                }
                GridRow {
                    DetailLabel(
                        title: "\(issue.dependencyCount) dependencies",
                        symbol: "arrow.triangle.branch"
                    )
                    DetailLabel(
                        title: "\(issue.dependentCount) dependents",
                        symbol: "point.3.connected.trianglepath.dotted"
                    )
                }
                GridRow {
                    DetailLabel(
                        title: "\(issue.commentCount) comments",
                        symbol: "bubble.left"
                    )
                    if let updated = issue.updatedDate {
                        DetailLabel(
                            title: updated.formatted(.relative(presentation: .numeric)),
                            symbol: "clock"
                        )
                    }
                }
            }

            HStack(spacing: 12) {
                if let created = issue.createdDate {
                    Text("Created \(created, style: .date)")
                }
                if let updated = issue.updatedDate {
                    Text("Updated \(updated, style: .relative) ago")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }
}

private struct DetailLabel: View {
    let title: String
    let symbol: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(priority <= 1 ? Color.orange : Color.secondary)
    }
}
