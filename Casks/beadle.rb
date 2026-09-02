cask "beadle" do
  version "0.1.3"
  sha256 "33daa61f85dbcf0b813992ffe16c6c663af073ee8fc0f91be6bae6f6d16548cf"

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

  zap trash: "~/Library/Preferences/la.maquina.BeadsStatusBar.plist"
end
