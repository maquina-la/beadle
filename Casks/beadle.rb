cask "beadle" do
  version "0.1.1"
  sha256 "7399433f6efdb60c38981246ac6c966315441ea914b0a1433faf2a50dc156eb5"

  url "https://github.com/maquina-la/beadle/releases/download/v#{version}/beadle-#{version}.zip",
      verified: "github.com/maquina-la/beadle/"
  name "Beadle"
  desc "Menu bar companion for local Beads issue trackers"
  homepage "https://github.com/maquina-la/beadle"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Beadle.app"

  zap trash: "~/Library/Preferences/im.carlosrivera.BeadsStatusBar.plist"
end
