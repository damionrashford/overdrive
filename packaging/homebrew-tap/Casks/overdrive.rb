# Homebrew cask for the direct edition. Lives in the tap repository damionrashford/homebrew-tap;
# the release workflow updates version and sha256 on every tagged release.
#
#   brew tap damionrashford/tap
#   brew install --cask --no-quarantine overdrive
cask "overdrive" do
  version "1.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/damionrashford/overdrive/releases/download/v#{version}/Overdrive-#{version}.dmg"
  name "Overdrive"
  desc "System monitor and cleaner for the Mac, built for local AI"
  homepage "https://github.com/damionrashford/overdrive"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Overdrive.app"

  zap trash: [
    "~/Library/Preferences/com.damionrashford.overdrive.plist",
    "~/Library/Caches/com.damionrashford.overdrive",
    "~/Library/Application Scripts/com.damionrashford.overdrive",
    "~/Library/Containers/com.damionrashford.overdrive",
  ]

  caveats <<~EOS
    Overdrive is not notarized by Apple yet. Installing with --no-quarantine skips the
    "Apple could not verify" dialog; otherwise allow it once in System Settings › Privacy & Security.
  EOS
end
