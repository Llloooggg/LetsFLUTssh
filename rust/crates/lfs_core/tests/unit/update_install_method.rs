/// Unit tests extracted from update/install_method.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn appimage_env_wins_even_under_system_prefix() {
    // An AppImage relaunched from /usr/local/bin is still an
    // AppImage — the env pin beats the path heuristic.
    assert_eq!(
        classify(
            "/usr/local/bin/letsflutssh",
            Some("/home/u/Apps/LetsFLUTssh.AppImage"),
            None,
            false
        ),
        LinuxInstall::AppImage
    );
}

#[test]
fn empty_appimage_env_is_not_appimage() {
    // An empty $APPIMAGE (set but blank) must not be treated as an
    // AppImage launch.
    assert_eq!(
        classify("/home/u/lfs/letsflutssh", Some(""), None, false),
        LinuxInstall::Portable
    );
}

#[test]
fn flatpak_via_env_or_info_file() {
    assert_eq!(
        classify("/app/bin/letsflutssh", None, Some("io.github.x"), false),
        LinuxInstall::Flatpak
    );
    assert_eq!(
        classify("/app/bin/letsflutssh", None, None, true),
        LinuxInstall::Flatpak
    );
}

#[test]
fn system_prefixes_are_package_managed() {
    for p in [
        "/usr/lib/letsflutssh/letsflutssh",
        "/usr/bin/letsflutssh",
        "/opt/letsflutssh/letsflutssh",
        "/bin/letsflutssh",
    ] {
        assert_eq!(
            classify(p, None, None, false),
            LinuxInstall::SystemPackage,
            "{p}"
        );
    }
}

#[test]
fn user_writable_paths_are_portable() {
    for p in [
        "/home/u/Downloads/letsflutssh/letsflutssh",
        "/tmp/lfs/letsflutssh",
        "/usr-not-a-prefix/letsflutssh",
        "",
    ] {
        assert_eq!(
            classify(p, None, None, false),
            LinuxInstall::Portable,
            "{p}"
        );
    }
}
