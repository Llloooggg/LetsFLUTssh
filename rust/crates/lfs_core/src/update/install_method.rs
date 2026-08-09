//! Detect how a Linux build was installed, so the updater applies the
//! matching channel instead of always treating the install as an
//! AppImage.
//!
//! # Why Linux only
//!
//! Windows (relaunch the Inno `setup.exe`) and macOS (atomic-swap the
//! `.app` from the universal `.dmg`) have one apply path each, so the
//! installer the release ships is unambiguous. Linux is the one target
//! where the same release fans out into formats with incompatible
//! update mechanics: an AppImage self-replaces a single file, a
//! `.deb` / `.rpm` is owned by `apt` / `dnf` / `pacman`, and a Flatpak
//! updates through Flathub. Handing a `.deb`-installed user an
//! AppImage would orphan a second copy outside the package manager.
//!
//! # No declared dependency
//!
//! Classification reads only the process environment and the running
//! executable's path — never a probe that would make `polkit`,
//! `dpkg`, or PackageKit an install-time requirement. The package
//! formats list those as runtime conveniences, not `Depends:` /
//! `Requires:` (see ARCHITECTURE §15 → package metadata).

/// How a Linux build was delivered. Drives the updater's apply path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinuxInstall {
    /// AppImage — `$APPIMAGE` points at the running image. Updater
    /// overwrites that file in place and re-execs.
    AppImage,
    /// Flatpak sandbox — updates come through `flatpak update`; the
    /// in-app updater steps aside.
    Flatpak,
    /// Installed by a system package manager (`deb` / `rpm` / pacman):
    /// the executable lives under a system prefix. The in-app updater
    /// steps aside and defers to that manager.
    SystemPackage,
    /// Self-contained, user-writable layout (extracted `tar.gz` /
    /// portable directory). No package manager owns it, so the updater
    /// downloads the matching format and hands it to the desktop's
    /// installer (or drops it in the downloads dir when none exists).
    Portable,
}

/// System prefixes a package manager installs into. An executable
/// living under one of these is owned by `apt` / `dnf` / `pacman`
/// (the `.deb` lays the bundle under `/usr/lib/letsflutssh` with a
/// `/usr/bin` symlink; `.rpm` / pacman mirror that), so the in-app
/// updater must not overwrite it — the package manager does.
const SYSTEM_PREFIXES: [&str; 3] = ["/usr/", "/opt/", "/bin/"];

/// Classify a Linux install from pre-gathered signals. Pure function
/// so the precedence is unit-testable without a real process
/// environment; [`detect`] supplies the live signals.
///
/// Precedence: AppImage (most specific, env-pinned) → Flatpak →
/// system-package (path under a system prefix) → portable (the
/// user-writable fallback). `$APPIMAGE` wins over a system prefix
/// because an AppImage launched from `/usr/local/bin` still self-
/// replaces via its env-pinned path.
pub fn classify(
    exe_path: &str,
    appimage_env: Option<&str>,
    flatpak_id_env: Option<&str>,
    flatpak_info_exists: bool,
) -> LinuxInstall {
    if appimage_env.is_some_and(|v| !v.is_empty()) {
        return LinuxInstall::AppImage;
    }
    if flatpak_id_env.is_some_and(|v| !v.is_empty()) || flatpak_info_exists {
        return LinuxInstall::Flatpak;
    }
    if SYSTEM_PREFIXES.iter().any(|p| exe_path.starts_with(p)) {
        return LinuxInstall::SystemPackage;
    }
    LinuxInstall::Portable
}

/// Gather live signals and classify. The non-testable edge: reads
/// `$APPIMAGE` / `$FLATPAK_ID`, probes `/.flatpak-info`, and resolves
/// the running executable's path. Falls back to an empty path (→
/// `Portable`) if the executable path can't be resolved.
pub fn detect() -> LinuxInstall {
    let exe = std::env::current_exe().ok();
    let exe_path = exe.as_deref().and_then(|p| p.to_str()).unwrap_or("");
    let appimage = std::env::var("APPIMAGE").ok();
    let flatpak_id = std::env::var("FLATPAK_ID").ok();
    let flatpak_info_exists = std::path::Path::new("/.flatpak-info").exists();
    classify(
        exe_path,
        appimage.as_deref(),
        flatpak_id.as_deref(),
        flatpak_info_exists,
    )
}
#[cfg(test)]
#[path = "../../tests/unit/update_install_method.rs"]
mod tests;
