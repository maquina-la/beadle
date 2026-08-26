import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Projects") {
                if state.projects.isEmpty {
                    Text("No projects configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.projects) { project in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .fontWeight(.medium)
                                Text(project.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                state.removeProject(id: project.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 28, height: 28)
                            .help("Remove \(project.name)")
                            .accessibilityLabel("Remove \(project.name)")
                        }
                    }
                }

                Button("Add Project…") { state.chooseAndAddProject() }
            }

            Section("Beads CLI") {
                HStack(spacing: 8) {
                    TextField("Executable path", text: $state.configuredExecutable)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { state.chooseExecutable() }
                }

                if let path = state.resolvedExecutablePath {
                    Label(path, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                } else {
                    Label("bd executable not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Leave empty to discover bd in Homebrew, ~/.local/bin, or ~/go/bin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Issues refresh every 20 seconds. This version only reads from Beads and never changes issue data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 520, height: 420)
        .beadleWindowSurface()
    }
}
