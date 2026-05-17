//! Subprocess hand-off that opens a downloaded installer
//! artefact under the host's default handler (`xdg-open` on
//! Linux, `/usr/bin/open` on macOS, `cmd /c start` on Windows).
//!
//! Lives in `lfs_os_security` because the perimeter rule is
//! "every subprocess spawn that consumes a path the user (or a
//! peer release server) can influence routes through one
//! audited crate". The macOS `.dmg` native installer (atomic
//! swap) is a separate, higher-rung pipeline reached through
//! `lfs_frb::api::macos_installer`; the function below covers
//! ONLY the Finder-reveal / `xdg-open` / `cmd start` fallback
//! the Dart side falls back to when the native installer
//! declines or isn't applicable.

use crate::subprocess_util::{run_subprocess, RunError};

/// Outcome of [`open_installer_file`]. The Dart caller maps each
/// variant onto a UI surface: a `Launched` returns `true` from
/// `UpdateService.openFile`; every other variant returns `false`
/// and is logged before the UI falls back to opening the GitHub
/// release page in a browser.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallerLaunchOutcome {
    /// Host opener (`xdg-open` / `open` / `cmd /c start`) exited
    /// with status zero. The new installer / Finder window is
    /// now the user's foreground task. Dart returns `true`.
    Launched,
    /// Windows-only — the requested path carried one of the
    /// `cmd.exe` metacharacters the allowlist rejects (`& | < >
    /// ^ % " ' ` ( ) ;`). The function returns BEFORE invoking
    /// `cmd` so the attack model below cannot fire. Dart returns
    /// `false` and routes the user to the browser fallback
    /// instead.
    RefusedUnsafePath,
    /// `platform` did not match any of `linux` / `macos` /
    /// `windows`. We don't ship a self-updatable binary for
    /// other operating systems (iOS, fuchsia, mobile), so the
    /// Dart side surfaces this as "Open Release Page" without
    /// ever reaching a spawn.
    UnsupportedPlatform,
    /// The host opener spawned but exited non-zero, OR the spawn
    /// itself failed (executable not found, permission error).
    /// `exit_code` is `Some(_)` for the first case and `None`
    /// for the second; `stderr` carries either the program's
    /// captured stderr or the IO error's `Display` text. Dart
    /// returns `false` and logs both fields.
    LaunchFailed {
        exit_code: Option<i32>,
        stderr: String,
    },
}

/// Dispatch a downloaded installer through the host's default
/// "open this file" handler. The Dart side calls this from
/// `UpdateService.openFile` after the download + signature
/// pipeline finishes.
///
/// Per-platform binding:
///
/// - **Linux** — `xdg-open <path>`. xdg-open delegates to the
///   user's MIME handler (the desktop file associated with the
///   artefact's extension); for an `.AppImage` that means making
///   it executable and launching it.
/// - **macOS** — `/usr/bin/open <path>`. `open` reveals `.dmg`
///   files in Finder (mounts the disk image and pops a window
///   showing the `.app`); for `.pkg` it hands off to Installer.app.
/// - **Windows** — `cmd /c start "" <path>`. The empty quoted
///   string between `start` and the path is the window-title
///   placeholder — `start` interprets the FIRST quoted argument
///   as a title when it's present, so omitting `""` would either
///   silently relabel the new window with our path or fail loudly
///   on paths containing spaces.
///
/// `platform` is passed as a string rather than derived from
/// `cfg!(target_os = …)` so the Dart caller — which already
/// owns the `_selfUpdatablePlatforms` allowlist — stays the
/// single decision point. Any other platform short-circuits to
/// [`InstallerLaunchOutcome::UnsupportedPlatform`].
pub async fn open_installer_file(path: String, platform: String) -> InstallerLaunchOutcome {
    match platform.as_str() {
        "linux" => run_open("xdg-open", &[&path], "installer_launch_xdg_open").await,
        "macos" => run_open("open", &[&path], "installer_launch_open").await,
        "windows" => {
            // `cmd /c start` parses `& | < > ^ %` as shell
            // metacharacters and treats `" ' ` ( ) ;` as
            // argument-boundary anchors. A hostile installer
            // path like `update";calc.exe;` would otherwise
            // inject a command past the `start ""` boundary —
            // the closing quote terminates the title argument,
            // the semicolon ends the start invocation, and the
            // remainder runs in the same `cmd /c` context. The
            // allowlist below rejects every character that lets
            // that escape happen; tokenisation alone is not
            // enough because `cmd.exe`'s parser does its own
            // pass over the joined command line regardless of
            // how the caller framed argv.
            if has_windows_unsafe_char(&path) {
                return InstallerLaunchOutcome::RefusedUnsafePath;
            }
            run_open(
                "cmd",
                &["/c", "start", "", &path],
                "installer_launch_cmd_start",
            )
            .await
        }
        _ => InstallerLaunchOutcome::UnsupportedPlatform,
    }
}

/// `true` when `path` contains any character `cmd.exe` would
/// interpret outside an argument literal. The set covers:
///
/// - `& | < > ^ %` — shell metacharacters (`&` and `|` chain
///   commands, `< >` redirect IO, `^` is the escape character,
///   `%` triggers variable expansion).
/// - `" ' \``  — argument-boundary anchors that let an injected
///   suffix close the `start ""` title and continue past it.
/// - `( ) ;` — command grouping / sequencing for `cmd`'s
///   `&&`/`||`/`(…)` constructs.
///
/// Realistic Windows installer paths (drives, spaces, hyphens,
/// dots, underscores) do not hit any of these. The Dart fallback
/// path (open the GitHub release page in a browser) handles the
/// rare case where a user's profile name embeds a flagged char.
fn has_windows_unsafe_char(path: &str) -> bool {
    path.chars().any(|c| {
        matches!(
            c,
            '&' | '|' | '<' | '>' | '^' | '%' | '"' | '\'' | '`' | '(' | ')' | ';'
        )
    })
}

async fn run_open(program: &str, args: &[&str], stage: &str) -> InstallerLaunchOutcome {
    match run_subprocess(program, args, stage).await {
        Ok(()) => InstallerLaunchOutcome::Launched,
        Err(RunError::NonZero(f)) => InstallerLaunchOutcome::LaunchFailed {
            exit_code: f.exit_code,
            stderr: f.stderr,
        },
        Err(RunError::Io(e)) => InstallerLaunchOutcome::LaunchFailed {
            exit_code: None,
            stderr: e.to_string(),
        },
    }
}

#[cfg(test)]
mod tests {
    //! Tests deliberately avoid any spawn path that could reach
    //! `xdg-open`, `open`, or `cmd` on the host. WSL hosts proxy
    //! `xdg-open` through `wslu` to the Windows shell, where a
    //! path like `/dev/null` would surface a "How do you want to
    //! open null?" Windows file-association dialog. The actual
    //! subprocess plumbing is exercised in `subprocess_util`'s
    //! own tests.

    use super::*;

    #[test]
    fn unsafe_char_detector_flags_every_cmd_metacharacter() {
        // Each character in the allowlist is its own decision —
        // a regression that dropped one (`%`, say) would silently
        // re-open the variable-expansion injection path. Loop
        // covers the full set rather than spot-checking.
        for ch in ['&', '|', '<', '>', '^', '%', '"', '\'', '`', '(', ')', ';'] {
            let probe = format!(r"C:\tmp\bad{ch}name.exe");
            assert!(
                has_windows_unsafe_char(&probe),
                "expected `{ch}` to flag the path as unsafe"
            );
        }
    }

    #[test]
    fn unsafe_char_detector_accepts_safe_paths() {
        // Realistic Windows installer paths must not be rejected
        // — drive letters, Program Files spaces, hyphens, dots,
        // and underscores are common.
        for path in [
            r"C:\Program Files\App\setup.exe",
            r"D:\files\letsflutssh-5.3.1-windows-x64-setup.exe",
            r"E:\nested_folder.name\bin.exe",
            r"C:\Users\me\Downloads\installer.msi",
        ] {
            assert!(
                !has_windows_unsafe_char(path),
                "expected `{path}` to pass the allowlist"
            );
        }
    }

    #[tokio::test]
    async fn unsupported_platform_short_circuits_without_spawn() {
        // The match arm for "ios" / "unknown" has no `run_open`
        // call — control flows straight to the
        // `UnsupportedPlatform` return. Confirms by source
        // inspection above, asserted on outcome here.
        let res_ios = open_installer_file("/tmp/anything".into(), "ios".into()).await;
        assert_eq!(res_ios, InstallerLaunchOutcome::UnsupportedPlatform);

        let res_unknown = open_installer_file("/tmp/anything".into(), "unknown".into()).await;
        assert_eq!(res_unknown, InstallerLaunchOutcome::UnsupportedPlatform);
    }

    #[tokio::test]
    async fn windows_path_with_metacharacter_is_refused_before_spawn() {
        // The `has_windows_unsafe_char` gate runs BEFORE
        // `run_open`, so a flagged path never reaches a spawn.
        // Probing with `&` here; the broader character coverage
        // lives in `unsafe_char_detector_flags_every_cmd_metacharacter`.
        let res = open_installer_file(r"C:\tmp\bad&name.exe".into(), "windows".into()).await;
        assert_eq!(res, InstallerLaunchOutcome::RefusedUnsafePath);
    }
}
