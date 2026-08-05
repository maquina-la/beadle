# Beads Status Bar

A native macOS menu-bar companion for [Beads](https://github.com/steveyegge/beads). It keeps open work visible across multiple repositories without changing issue data.

## What is in the first cut

- Native SwiftUI `MenuBarExtra` interface for macOS 14+
- Multiple Beads repositories in one view
- Open, active, and blocked filters plus issue search
- Priority, type, assignee, dependency, comment, and update metadata
- Automatic refresh every 20 seconds
- Read-only access through the local `bd` CLI
- A universal Apple Silicon/Intel `.app` bundle and zip suitable for a Homebrew Cask release

## Run from source

Requirements: macOS 14+, Swift 6+, and `bd` installed locally.

```sh
swift run BeadsStatusBar
```

On first launch, choose one or more folders containing a `.beads` directory. GUI applications have a limited `PATH`, so the app checks common Homebrew, `~/.local/bin`, and `~/go/bin` locations. You can set an explicit `bd` path in Settings.

## Build and install locally

```sh
scripts/install-local.sh
```

The release artifact is written to `dist/beads-status-bar-0.1.0.zip`.

To produce the same universal binary used by tagged releases:

```sh
UNIVERSAL=1 scripts/build-app.sh
```

## Homebrew distribution

1. Publish this repository on GitHub and replace `REPLACE_WITH_OWNER` in `Casks/beads-status-bar.rb`.
2. Push a semantic version tag such as `v0.1.0`; the release workflow builds and uploads the zip.
3. Calculate the artifact checksum with `shasum -a 256 dist/beads-status-bar-0.1.0.zip` and update the Cask.
4. Copy the Cask into a Homebrew tap repository, then install with:

```sh
brew install --cask OWNER/TAP/beads-status-bar
```

Public distribution should replace ad-hoc signing with a Developer ID certificate and Apple notarization. The build script already honors `CODE_SIGN_IDENTITY`.

## Product direction

The intentionally small first release establishes the local data and distribution layers. Natural next steps are issue detail, quick status changes, notifications for newly blocked work, keyboard navigation, and a polished custom app icon.
