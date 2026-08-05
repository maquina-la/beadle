cask "beads-status-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/REPLACE_WITH_OWNER/beads-status-bar/releases/download/v#{version}/beads-status-bar-#{version}.zip"
  name "Beads Status Bar"
  desc "Native macOS menu bar companion for Beads issue trackers"
  homepage "https://github.com/REPLACE_WITH_OWNER/beads-status-bar"

  depends_on macos: ">= :sonoma"

  app "Beads Status Bar.app"

  zap trash: [
    "~/Library/Preferences/im.carlosrivera.BeadsStatusBar.plist",
  ]
end
