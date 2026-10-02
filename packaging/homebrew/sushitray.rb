# Homebrew Cask for https://github.com/derkan/SushiTray
# Published via derkan/homebrew-tap — install:
#   brew tap derkan/tap
#   brew install --cask sushitray
#
# After a release, CI updates version/sha256 when HOMEBREW_TAP_TOKEN is set.
# Manual bump:
#   VERSION=1.0.0
#   SHA=$(curl -sL "https://github.com/derkan/SushiTray/releases/download/v${VERSION}/SushiTray-${VERSION}.zip" | shasum -a 256 | awk '{print $1}')

cask "sushitray" do
  version "1.0.0"
  sha256 "4f1aa04a9deaf1a94bd36dec7318ccc8e4d75ed71015c4a6093cccdedc5ca5f4"

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

  zap trash: [
    "~/Library/Preferences/com.derkan.sushitray.plist",
  ]

  caveats <<~EOS
    SushiTray is not notarized. If macOS blocks it on first launch:

      xattr -cr "#{appdir}/SushiTray.app"

    You also need the sushi CLI:

      brew install beamivalice/tap/sushi
  EOS
end
