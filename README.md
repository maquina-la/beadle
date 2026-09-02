<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/beadle-lockup-dark.svg">
  <img alt="Beadle" src="img/beadle-lockup-light.svg" height="56">
</picture>

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

Releases created before the Developer ID rollout are ad-hoc signed. Tagged builds made by the current release workflow require Developer ID signing and Apple notarization before publication.

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

## Release signing

The tag-triggered GitHub Actions workflow builds a universal app, signs it with hardened runtime and a secure timestamp, submits the ZIP to Apple's notary service, staples the accepted ticket to `Beadle.app`, recreates the ZIP, verifies it with Gatekeeper, and only then publishes the final archive and checksum.

Configure these GitHub Actions secrets before pushing a release tag:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded, password-protected `.p12` containing the Developer ID Application certificate and its private key.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`.
- `APPLE_API_KEY_BASE64`: base64-encoded App Store Connect API `.p8` key.
- `APPLE_API_KEY_ID`: App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`: App Store Connect API issuer ID.

Encode the certificate and API key without writing encoded copies into the repository:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

Create and push a version tag only after all five secrets are configured. After the release is published, update `Casks/beadle.rb` with the new version and the SHA-256 from the final, stapled ZIP.

## Uninstall

```sh
brew uninstall --cask beadle
```

Use `--zap` as well if you want Homebrew to remove Beadle's saved project and executable-path preferences.

---

Beadle is made by [Maquina](https://github.com/maquina-la) for people building with Beads.
