# Beadle

**Your Beads work, one click away.** Beadle is a native macOS menu bar companion for [Beads](https://github.com/steveyegge/beads). It brings issues from all of your local projects into one focused, read-only view without asking you to leave what you are doing.

![Beadle showing a list of Beads issues and its Markdown detail inspector](img/beadle.png)

## A quieter way to follow local work

Beadle is designed for the moment between remembering an issue and opening a terminal. Click the menu bar icon to see what is active, search across projects, or inspect an issue. Hover for context; click to keep the detail inspector open.

- See multiple Beads projects in one place.
- Switch between active, open, in-progress, blocked, and closed work.
- Search by title, ID, assignee, description, or label.
- Read Markdown descriptions, notes, closure reasons, relationships, and dates.
- Navigate with the keyboard using the arrow keys, Return, Escape, and `⌘F`.
- Keep working through temporary CLI or project errors with cached results.
- Stay in sync with automatic refreshes every 20 seconds.

Beadle reads through your local `bd` CLI. It does not edit issues or send project data to a service.

## Install

Beadle requires macOS 14 Sonoma or newer and a working [Beads](https://github.com/steveyegge/beads) installation.

### Homebrew

The repository doubles as a Homebrew tap:

```sh
brew tap maquina-la/beadle https://github.com/maquina-la/beadle
brew install --cask maquina-la/beadle/beadle
```

Upgrade later with:

```sh
brew upgrade --cask beadle
```

### Manual download

Download the latest `beadle-*.zip` from [GitHub Releases](https://github.com/maquina-la/beadle/releases), unzip it, and move `Beadle.app` to Applications.

Current preview builds are ad-hoc signed rather than notarized with an Apple Developer ID. On first launch, macOS may ask you to confirm the app in **System Settings → Privacy & Security**.

## First launch

1. Open Beadle and click its icon in the menu bar. It intentionally has no Dock icon.
2. Choose a repository containing a `.beads` directory.
3. Add more repositories from **Settings…** whenever you need them.

Because macOS apps receive a limited shell `PATH`, Beadle looks for `bd` in the common Homebrew, `~/.local/bin`, and `~/go/bin` locations. If yours lives elsewhere, select it in Settings.

## Build from source

You need macOS 14+, Swift 6+, and `bd` installed locally.

```sh
git clone https://github.com/maquina-la/beadle.git
cd beadle
scripts/install-local.sh
```

For a universal Apple Silicon and Intel release artifact:

```sh
UNIVERSAL=1 scripts/build-app.sh
```

The resulting app and versioned zip are written to `dist/`.

## Uninstall

```sh
brew uninstall --cask beadle
```

Use `--zap` as well if you want Homebrew to remove Beadle's saved project and executable-path preferences.

---

Beadle is made by [Maquina](https://github.com/maquina-la) for people building with Beads.
