cask "beadle" do
  version "0.1.2"
  sha256 "b6d3a5fe832b7ce85f6622f12abc82b798d11e72f55e59508ea408dd3f9cb271"

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
