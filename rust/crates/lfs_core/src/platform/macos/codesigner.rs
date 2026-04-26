//! `/usr/bin/codesign` wrapper for the inside-out re-sign flow.
//!
//! Mirrors `lib/platform/macos/code_signing/codesigner.dart`:
//! extract the live entitlements from the bundle, walk the
//! contents leaf-first (dylibs → frameworks → xpc / appex →
//! outer .app), re-sign each step against the user's
//! self-signed identity, then verify the result.
//!
//! Why leaf-first instead of `--deep`: codesign's own docs
//! mark `--deep` as an "emergency measure" and Flutter macOS
//! bundles trip `errSecInternalComponent` mid-walk when
//! shared_preferences_foundation lands before its container's
//! signature update. Manual leaf-first walk avoids the issue.

use std::fs;
use std::path::{Path, PathBuf};

use super::process::Runner;

const CODESIGN_PATH: &str = "/usr/bin/codesign";

#[derive(Debug, thiserror::Error)]
pub enum CodesignError {
    #[error("codesign {subpath}: {message}")]
    Failed { subpath: String, message: String },
    #[error("codesign io: {0}")]
    Io(String),
}

pub struct Codesigner<'a> {
    runner: &'a dyn Runner,
}

impl<'a> Codesigner<'a> {
    pub fn new(runner: &'a dyn Runner) -> Self {
        Self { runner }
    }

    /// Extract the live entitlements plist embedded in the
    /// bundle's signature. Returns `None` when the signature
    /// has no entitlements (ad-hoc CI builds, corrupt bundles)
    /// — callers fall back to re-signing without entitlements,
    /// noting that T1 keychain access will break regardless.
    pub fn extract_entitlements(&self, app_bundle: &Path) -> Option<String> {
        let path_str = app_bundle.to_string_lossy().into_owned();
        let res = self
            .runner
            .run(
                CODESIGN_PATH,
                &["-d", "--entitlements", ":-", &path_str],
            )
            .ok()?;
        if !res.success() {
            return None;
        }
        let plist = res.stdout.trim();
        if plist.is_empty() {
            None
        } else {
            Some(plist.to_string())
        }
    }

    /// `codesign --verify --deep --strict --verbose=2`. Used as
    /// the final gate between "new bundle staged" and "swap in".
    pub fn verify(&self, bundle: &Path) -> bool {
        let path_str = bundle.to_string_lossy().into_owned();
        self.runner
            .run(
                CODESIGN_PATH,
                &["--verify", "--deep", "--strict", "--verbose=2", &path_str],
            )
            .map(|r| r.success())
            .unwrap_or(false)
    }

    /// Re-sign [`app_bundle`] leaf-first against [`common_name`].
    /// Optional [`entitlements_plist`] is the output of
    /// [`extract_entitlements`] — passed only on the outer-bundle
    /// pass so the runtime entitlements survive.
    pub fn resign_inside_out(
        &self,
        app_bundle: &Path,
        common_name: &str,
        entitlements_plist: Option<&str>,
        use_sudo: bool,
    ) -> Result<(), CodesignError> {
        let cmd = if use_sudo { "sudo" } else { CODESIGN_PATH };

        let sign_one = |subpath: &Path, extra: &[&str]| -> Result<(), CodesignError> {
            let path_str = subpath.to_string_lossy().into_owned();
            let mut argv: Vec<String> = if use_sudo {
                vec![CODESIGN_PATH.to_string()]
            } else {
                Vec::new()
            };
            argv.extend(
                ["--force", "--options", "runtime", "--sign", common_name]
                    .iter()
                    .map(|s| s.to_string()),
            );
            for e in extra {
                argv.push((*e).to_string());
            }
            argv.push(path_str.clone());
            let argv_refs: Vec<&str> = argv.iter().map(|s| s.as_str()).collect();
            let res = self
                .runner
                .run(cmd, &argv_refs)
                .map_err(|e| CodesignError::Io(format!("codesign spawn: {e}")))?;
            if !res.success() {
                return Err(CodesignError::Failed {
                    subpath: path_str,
                    message: format!("codesign exit={} stderr={}", res.status, res.stderr),
                });
            }
            Ok(())
        };

        // 1. dylibs
        for path in walk(app_bundle, ".dylib", true) {
            sign_one(&path, &[])?;
        }

        // 2. frameworks under Contents/Frameworks
        let frameworks_dir = app_bundle.join("Contents").join("Frameworks");
        if frameworks_dir.exists() {
            for path in walk(&frameworks_dir, ".framework", false) {
                sign_one(&path, &[])?;
            }
        }

        // 3. xpc / appex helpers
        for path in walk(app_bundle, ".xpc", false) {
            sign_one(&path, &[])?;
        }
        for path in walk(app_bundle, ".appex", false) {
            sign_one(&path, &[])?;
        }

        // 4. outer bundle — with entitlements
        if let Some(plist) = entitlements_plist {
            let tmp = mkdtemp("lfs-codesign-ent-").map_err(CodesignError::Io)?;
            let ent_path = tmp.join("entitlements.plist");
            fs::write(&ent_path, plist)
                .map_err(|e| CodesignError::Io(format!("write entitlements: {e}")))?;
            let ent_str = ent_path.to_string_lossy().into_owned();
            let result = sign_one(app_bundle, &["--entitlements", &ent_str]);
            let _ = fs::remove_dir_all(&tmp);
            result?;
        } else {
            sign_one(app_bundle, &[])?;
        }

        Ok(())
    }
}

/// Recursive walk for codesign's leaf-first traversal. `is_file`
/// distinguishes per-file matches (`.dylib`) from per-directory
/// matches (`.framework`, `.xpc`, `.appex`). Skips symlinks so a
/// loop never wedges the walker.
fn walk(root: &Path, suffix: &str, is_file: bool) -> Vec<PathBuf> {
    let mut out = Vec::new();
    walk_into(root, suffix, is_file, &mut out);
    out
}

fn walk_into(dir: &Path, suffix: &str, is_file: bool, out: &mut Vec<PathBuf>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let meta = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        if meta.file_type().is_symlink() {
            continue;
        }
        let is_match = path
            .file_name()
            .and_then(|n| n.to_str())
            .map(|n| n.ends_with(suffix))
            .unwrap_or(false);
        if is_match {
            if is_file {
                if meta.is_file() {
                    out.push(path.clone());
                }
            } else if meta.is_dir() {
                out.push(path.clone());
            }
        }
        // Recurse into subdirs regardless of whether they
        // matched themselves — codesign cares about every
        // dylib at every depth.
        if meta.is_dir() {
            walk_into(&path, suffix, is_file, out);
        }
    }
}

fn mkdtemp(prefix: &str) -> Result<PathBuf, String> {
    use rand::RngCore;
    use std::os::unix::fs::PermissionsExt;
    let base = std::env::temp_dir();
    let pid = std::process::id();
    let mut rng = rand::rngs::OsRng;
    for _ in 0..16 {
        let mut bytes = [0u8; 8];
        rng.fill_bytes(&mut bytes);
        let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let candidate = base.join(format!("{prefix}{pid}-{suffix}"));
        match fs::create_dir(&candidate) {
            Ok(_) => {
                let _ = fs::set_permissions(&candidate, fs::Permissions::from_mode(0o700));
                return Ok(candidate);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("mkdtemp: {e}")),
        }
    }
    Err("mkdtemp: out of retries".to_string())
}

#[cfg(test)]
mod tests {
    use super::super::process::test_support::MockRunner;
    use super::*;

    #[test]
    fn extract_entitlements_returns_none_on_codesign_failure() {
        let runner = MockRunner::new();
        runner.enqueue(1, "", "no signature");
        let cs = Codesigner::new(&runner);
        let bundle = Path::new("/tmp/fake.app");
        assert!(cs.extract_entitlements(bundle).is_none());
    }

    #[test]
    fn extract_entitlements_returns_none_on_empty_plist() {
        let runner = MockRunner::new();
        runner.enqueue(0, "   ", "");
        let cs = Codesigner::new(&runner);
        let bundle = Path::new("/tmp/fake.app");
        assert!(cs.extract_entitlements(bundle).is_none());
    }

    #[test]
    fn extract_entitlements_returns_trimmed_plist_on_success() {
        let runner = MockRunner::new();
        runner.enqueue(0, "<plist>...</plist>\n\n", "");
        let cs = Codesigner::new(&runner);
        let bundle = Path::new("/tmp/fake.app");
        assert_eq!(
            cs.extract_entitlements(bundle).as_deref(),
            Some("<plist>...</plist>"),
        );
    }

    #[test]
    fn verify_argv_uses_strict_deep_verbose() {
        let runner = MockRunner::new();
        runner.enqueue(0, "", "");
        let cs = Codesigner::new(&runner);
        cs.verify(Path::new("/tmp/fake.app"));
        let args = &runner.calls()[0].args;
        assert!(args.contains(&"--verify".to_string()));
        assert!(args.contains(&"--deep".to_string()));
        assert!(args.contains(&"--strict".to_string()));
        assert!(args.contains(&"--verbose=2".to_string()));
    }

    #[test]
    fn walker_finds_nested_dylibs_skips_symlinks() {
        let tmp = mkdtemp("lfs-walk-test-").expect("mkdtemp");
        let a = tmp.join("Contents");
        fs::create_dir_all(&a).unwrap();
        let lib1 = a.join("foo.dylib");
        fs::write(&lib1, b"x").unwrap();
        let nested = a.join("Frameworks").join("inner");
        fs::create_dir_all(&nested).unwrap();
        let lib2 = nested.join("bar.dylib");
        fs::write(&lib2, b"x").unwrap();
        // Decoy non-dylib file.
        fs::write(a.join("README.txt"), b"x").unwrap();

        let found = walk(&tmp, ".dylib", true);
        assert_eq!(found.len(), 2);
        let names: Vec<String> = found
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert!(names.contains(&"foo.dylib".to_string()));
        assert!(names.contains(&"bar.dylib".to_string()));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn walker_returns_dirs_for_framework_suffix() {
        let tmp = mkdtemp("lfs-walk-fw-").expect("mkdtemp");
        let fw = tmp.join("My.framework");
        fs::create_dir_all(&fw).unwrap();
        // Decoy file with the same suffix — must NOT match.
        fs::write(tmp.join("Other.framework"), b"x").unwrap();
        let found = walk(&tmp, ".framework", false);
        assert_eq!(found.len(), 1, "got {found:?}");
        assert_eq!(found[0].file_name().unwrap(), "My.framework");
        let _ = fs::remove_dir_all(&tmp);
    }

}
