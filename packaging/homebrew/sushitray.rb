# Homebrew Cask for https://github.com/derkan/SushiTray
# Published via derkan/homebrew-tap — install:
#   brew tap derkan/tap
#   brew install --cask sushitray
#
# After a release, CI updates version/sha256 when HOMEBREW_TAP_TOKEN is set.
# Manual bump:
#   VERSION=1.0.2
#   SHA=$(curl -sL "https://github.com/derkan/SushiTray/releases/download/v${VERSION}/SushiTray-${VERSION}.zip" | shasum -a 256 | awk '{print $1}')

cask "sushitray" do
  version "1.0.1"
  sha256 "834dca49c6429c4a4ef7acec83dbb17abb880b74adfe3cc89b1b1630e785fc05"

  url "https://github.com/derkan/SushiTray/releases/download/v#{version}/SushiTray-#{version}.zip"
  name "SushiTray"
  desc "Menu bar controller for the sushi local AI server"
  homepage "https://github.com/derkan/SushiTray"

  livecheck do
    url "https://github.com/derkan/SushiTray"
    strategy :github_latest
  end

  depends_on macos: :ventura
  depends_on arch: :arm64

  app "SushiTray.app"

  # Strip quarantine so Gatekeeper does not show "damaged" for unsigned builds.
  postflight do
    system_command "xattr", args: ["-cr", "#{appdir}/SushiTray.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.derkan.sushitray.plist",
  ]

  caveats <<~EOS
    SushiTray is not notarized. If macOS still blocks it on first launch:

      xattr -cr "#{appdir}/SushiTray.app"

    You also need the sushi CLI:

      brew install beamivalice/tap/sushi
  EOS
end
