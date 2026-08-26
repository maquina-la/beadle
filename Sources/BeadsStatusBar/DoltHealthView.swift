import AppKit
import SwiftUI

/// Per-project Dolt server diagnostics: pinned ports, contamination findings,
/// repair notes, one-click fixes, and copyable agent-ready reports.
struct DoltHealthView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.projectHealth.isEmpty {
                emptyContent
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(state.projectHealth) { health in
                            ProjectHealthCard(health: health)
                        }
                        explainer
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 460, height: 540)
        .background { DoltHealthBackground() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dolt Health")
                    .font(.headline)
                Text("Per-project server diagnostics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CopyReportButton(
                helpText: "Copy the full report (paths, ports, findings, and repair commands) to hand to an agent or another LLM."
            ) {
                DoltHealthEngine.reportText(for: state.projectHealth)
            }
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Re-check all projects")
            .accessibilityLabel("Re-check all projects")
            Button("Done") { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No projects yet")
                .font(.headline)
            Text("Add a project from the dashboard to see its Dolt health.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Why ports matter", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
            Text(
                "Every bd project runs its own Dolt server, and projects without a pinned port all default to \(DoltPortPolicy.bdDefault). "
                    + "Whichever server starts first owns that port; other projects then reach a server that cannot hold their database, "
                    + "which shows up as load failures — or as their database silently living inside another repository's storage. "
                    + "Beadle pins each project to a unique port (from \(DoltPortPolicy.lowerBound)) in that project's gitignored "
                    + ".beads/metadata.json, repairs collisions automatically, and reports anything it cannot fix safely."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct ProjectHealthCard: View {
    @EnvironmentObject private var state: AppState
    let health: DoltProjectHealth

    private var fixableFindings: [DoltFinding] {
        health.findings.filter(\.isAutoFixable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: health.isHealthy && health.findings.isEmpty
                    ? "checkmark.circle.fill"
                    : (health.isHealthy ? "checkmark.circle" : "exclamationmark.triangle.fill"))
                    .foregroundStyle(health.isHealthy ? Color.green : Color.orange)
                Text(health.projectName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                CopyReportButton(
                    helpText: "Copy this project's health report (findings and repair commands)."
                ) {
                    DoltHealthEngine.reportText(for: [health])
                }
                portChip
            }

            Text("Path: \(health.projectPath)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let databaseName = health.databaseName {
                Text("Database: \(databaseName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !health.dataDirDatabases.isEmpty {
                Text("In data dir: \(health.dataDirDatabases.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            ForEach(health.findings) { finding in
                FindingRow(finding: finding)
            }

            if health.findings.isEmpty {
                Text("No findings. Port is pinned and storage is clean.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !fixableFindings.isEmpty {
                Button {
                    Task { await state.applyPortFix(for: health.projectID) }
                } label: {
                    if state.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Pin unique port")
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(state.isRefreshing)
                .help("Write a free Dolt port to this project's .beads/metadata.json and start the server.")
            }

            if let note = state.repairNotes[health.projectID] {
                Label {
                    Text(note.message)
                        .font(.caption)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: note.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(note.isError ? Color.red : Color.green)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var portChip: some View {
        HStack(spacing: 4) {
            Image(systemName: health.pinnedPort == nil ? "bolt.horizontal.circle" : "bolt.horizontal.circle.fill")
                .font(.caption2)
            Text(health.pinnedPort == nil
                ? "default \(health.effectivePort)"
                : "port \(health.pinnedPort!)")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(health.pinnedPort == nil ? Color.secondary : Color.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.primary.opacity(0.06))
        )
        .help(health.pinnedPort == nil
            ? "No pinned port; this project competes for bd's default port \(DoltPortPolicy.bdDefault)."
            : "Pinned in .beads/metadata.json.")
        .accessibilityLabel(
            health.pinnedPort == nil
                ? "Unpinned Dolt port, defaults to \(health.effectivePort)"
                : "Dolt port \(health.pinnedPort!)"
        )
    }
}

private struct FindingRow: View {
    let finding: DoltFinding

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: finding.symbolName)
                .font(.caption)
                .foregroundStyle(finding.severity == .critical ? Color.orange : Color.yellow)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.caption.weight(.semibold))
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.severity == .critical ? "Critical" : "Warning"): \(finding.title). \(finding.detail)")
    }
}

/// Copies generated report text to the pasteboard and flashes a checkmark.
private struct CopyReportButton: View {
    let helpText: String
    let payload: () -> String
    @State private var copied = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload(), forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Color.green : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityLabel(copied ? "Copied" : "Copy report")
    }
}

/// Liquid Glass on macOS 26, the material fallback below it, and an opaque
/// window background when Reduce Transparency is on — the same three-way
/// gate `DashboardBackground` uses, so the two surfaces age together.
private struct DoltHealthBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
        } else {
            Rectangle()
                .fill(.thinMaterial)
        }
    }
}
