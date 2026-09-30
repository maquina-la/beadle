cask "beadle" do
  version "0.1.4"
  sha256 "9760635f5aab56284b795ca8fa1e49227624be68e9ea60b308882ab87bb003f2"

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
