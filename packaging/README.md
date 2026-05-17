# Distribution channel manifests

Templates for publishing LetsFLUTssh through community
package channels. Each channel is **separately submitted** —
the manifests live here as starting points, but the actual
publication is a manual maintainer step (PR to the channel's
upstream repo or web-form upload).

## Channel inventory

| Channel | Manifest | Target users | Submission |
|---|---|---|---|
| **Snap Store** | [`../snap/snapcraft.yaml`](../snap/snapcraft.yaml) | Ubuntu / any Linux with snapd | `snapcraft upload --release=stable letsflutssh_*.snap` |
| **Flathub** | [`flatpak/io.github.llloooggg.LetsFLUTssh.yaml`](flatpak/io.github.llloooggg.LetsFLUTssh.yaml) | All distros via Flatpak | PR to [`flathub/flathub`](https://github.com/flathub/flathub) |
| **Homebrew Cask** | [`homebrew/letsflutssh.rb`](homebrew/letsflutssh.rb) | macOS | PR to [`homebrew/homebrew-cask`](https://github.com/homebrew/homebrew-cask) |
| **WinGet** | [`winget/Llloooggg.LetsFLUTssh*.yaml`](winget/) | Windows 10/11 + ARM64 | PR to [`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs) |

The four channels deliberately do not overlap: Snap + Flatpak
both target Linux but use different sandboxing models, both
have their own distinct user bases. macOS users without
Apple Developer Program installation (`brew install --cask`
> right-click → Open). Windows users get `winget install` UX.

## Per-release publication flow

When cutting a release `vX.Y.Z`:

1. **Build artefacts** via `build-release.yml` on tag push
   (Linux x64 + ARM64, Windows x64 + ARM64, macOS universal,
   Android, iOS unsigned).
2. **Read sha256 sums** from
   `letsflutssh-X.Y.Z.sha256sums` published as a release
   asset.
3. **Bump manifests** here, replacing every
   `0000000000000000000000000000000000000000000000000000000000000000`
   placeholder with the actual sha256 from step 2 + every
   `0.0.0` with the new version.
4. **Submit per channel** — each channel's PR is independent.
   Bake CI for each is enforced by the upstream channel; do
   not merge a manifest until that CI is green.
5. **Track outcomes** — the in-app updater
   (`lib/core/update/`) does NOT route through these
   channels; it talks directly to GitHub Releases. So a
   stalled channel-PR does not break auto-update for the
   users who installed via that channel — it just delays
   the next visible bump in their package manager UI.

## Status

All four manifests are **draft templates**, not
publish-ready. Each carries an inline `**Status**:` block
listing what needs validation (channel-spec compliance,
sandbox permissions, schema versions) before the first
submission. Verification against current channel docs +
upstream CI is the gating step before any of these are
filed as PRs.
