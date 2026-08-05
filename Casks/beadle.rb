cask "beadle" do
  version "0.1.0"
  sha256 "990edafedbd29e8aa0771225ff4461c6708ce8772c8fbb0563e2df7fb6aef6c1"

  url "https://github.com/maquina-la/beadle/releases/download/v#{version}/beadle-#{version}.zip",
      verified: "github.com/maquina-la/beadle/"
  name "Beadle"
  desc "Native macOS menu bar companion for Beads issue trackers"
  homepage "https://github.com/maquina-la/beadle"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Beadle.app"

  zap trash: [
    "~/Library/Preferences/im.carlosrivera.BeadsStatusBar.plist",
  ]
end
