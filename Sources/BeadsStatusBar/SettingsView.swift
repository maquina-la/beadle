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
                        }
                    }
                }

                Button("Add Project…") { state.chooseAndAddProject() }
            }

            Section("Beads CLI") {
                TextField("Executable path", text: $state.configuredExecutable)
                    .textFieldStyle(.roundedBorder)
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
        .frame(width: 520, height: 420)
        .padding()
    }
}
