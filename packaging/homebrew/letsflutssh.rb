# Homebrew cask manifest for the macOS distribution channel.
#
# Publish (per release):
#   1. Update `version` + `sha256` blocks below from the release
#      manifest (.sha256sums file)
#   2. Submit a PR to https://github.com/Homebrew/homebrew-cask
#      adding / updating Casks/letsflutssh.rb with this content
#   3. Pass the cask CI (audit, style, install round-trip)
#
# Subsequent releases: bump `version` + both `sha256` lines and
# re-PR. Homebrew also accepts auto-bumping via brew-bump-cask
# scripts that consume our release-manifest format.
#
# **Status**: draft template — needs validation against the
# current Homebrew Cask DSL (`brew audit --new-cask --strict
# letsflutssh`) before first PR. The cask format has shifted
# multiple times (auto_updates, no_autobump!, depends_on macos
# version pinning); do not assume publish-readiness as-is.

cask "letsflutssh" do
  version "0.0.0"

  # Two-arch download — Homebrew picks the matching slice at
  # install time based on `Hardware::CPU.arch`. Source URLs
  # match the build-release.yml `release` job's `files:` block.
  on_arm do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    url "https://github.com/Llloooggg/LetsFLUTssh/releases/download/v#{version}/letsflutssh-#{version}-macos-universal.dmg"
  end
  on_intel do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    url "https://github.com/Llloooggg/LetsFLUTssh/releases/download/v#{version}/letsflutssh-#{version}-macos-universal.dmg"
  end

  name "LetsFLUTssh"
  desc "Lightweight cross-platform SSH/SFTP client"
  homepage "https://github.com/Llloooggg/LetsFLUTssh"

  # Auto-update: false — the in-app updater (lib/core/update/)
  # owns the upgrade flow with Ed25519 signature verification.
  # Setting auto_updates true here would suppress Homebrew's
  # own bump notifications, which we want for users who installed
  # via brew but later disabled the in-app updater.
  auto_updates false

  app "letsflutssh.app"

  # Bundle ID mirrors `macos/Runner/Configs/AppInfo.xcconfig:11`
  # (`PRODUCT_BUNDLE_IDENTIFIER`). macOS writes `Preferences` /
  # `Caches` directories under that exact reverse-DNS string, so the
  # zap path must match or `brew uninstall --zap` silently leaves
  # stale state on disk.
  zap trash: [
    "~/Library/Application Support/letsflutssh",
    "~/Library/Preferences/com.llloooggg.letsflutssh.plist",
    "~/Library/Caches/com.llloooggg.letsflutssh",
  ]
end
