cask "beadle" do
  version "0.1.0"
  sha256 "2f34470fd230aa0a87a22321b019b62ccb13e444812783c21a215d5c5a0a37d3"

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
