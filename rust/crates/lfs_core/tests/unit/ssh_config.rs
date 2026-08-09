/// Unit tests extracted from ssh_config.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn no_includes(_: &str) -> Option<String> {
    None
}

#[test]
fn parses_single_concrete_host() {
    let cfg = "Host prod\n  HostName 10.0.0.1\n  User deploy\n  Port 2222\n  IdentityFile ~/.ssh/prod_id\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries.len(), 1);
    let e = &entries[0];
    assert_eq!(e.host, "prod");
    assert_eq!(e.host_name.as_deref(), Some("10.0.0.1"));
    assert_eq!(e.user.as_deref(), Some("deploy"));
    assert_eq!(e.port, Some(2222));
    assert_eq!(e.identity_files, vec!["~/.ssh/prod_id"]);
    assert!(e.preferred_auth_types.is_none());
}

#[test]
fn comment_and_blank_lines_ignored() {
    let cfg = "# header comment\n\nHost a\n  HostName b\n# trailing comment\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].host_name.as_deref(), Some("b"));
}

#[test]
fn equals_separator_supported() {
    let cfg = "Host eq\n  HostName=internal.local\n  Port = 4242\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries[0].host_name.as_deref(), Some("internal.local"));
    assert_eq!(entries[0].port, Some(4242));
}

#[test]
fn wildcard_block_cascades_onto_concretes() {
    let cfg = "Host *\n  User globaluser\n  Port 2200\nHost prod\n  HostName p.example\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries.len(), 1);
    let e = &entries[0];
    assert_eq!(e.host, "prod");
    assert_eq!(e.user.as_deref(), Some("globaluser"));
    assert_eq!(e.port, Some(2200));
}

#[test]
fn wildcard_user_overridden_by_concrete() {
    // Concrete block declared first → its user wins for its own host;
    // the trailing wildcard fills only Port (which the concrete
    // didn't declare).
    let cfg = "Host prod\n  User deploy\nHost *\n  User other\n  Port 22\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    let e = &entries[0];
    assert_eq!(e.user.as_deref(), Some("deploy"));
    assert_eq!(e.port, Some(22));
}

#[test]
fn negation_pattern_excludes_match() {
    let cfg = "Host *.internal !secret.internal\n  User svc\nHost public.example\n";
    // We test the wildcard `matches` directly via parsing two
    // concrete hosts at once isn't possible here without two
    // blocks; assert via the lower-level matcher.
    let blocks = parse_blocks(cfg);
    let wild = blocks
        .iter()
        .find(|b| b.patterns.contains(&"*.internal".into()))
        .unwrap();
    assert!(wild.matches("foo.internal"));
    assert!(!wild.matches("secret.internal"));
    assert!(!wild.matches("public.example"));
}

#[test]
fn preferred_auth_strips_unknown_methods() {
    let cfg = "Host x\n  PreferredAuthentications gssapi-with-mic,publickey,password\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(
        entries[0].preferred_auth_types.as_deref(),
        Some(&[AuthType::Key, AuthType::Password][..])
    );
}

#[test]
fn preferred_auth_all_unknown_yields_none() {
    let cfg = "Host x\n  PreferredAuthentications gssapi,hostbased\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert!(entries[0].preferred_auth_types.is_none());
}

#[test]
fn multiple_identity_files_accumulate() {
    let cfg = "Host k\n  IdentityFile ~/.ssh/a\n  IdentityFile ~/.ssh/b\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries[0].identity_files, vec!["~/.ssh/a", "~/.ssh/b"]);
}

#[test]
fn quoted_value_preserves_spaces() {
    let cfg = "Host q\n  HostName \"host with space\"\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries[0].host_name.as_deref(), Some("host with space"));
}

#[test]
fn unknown_directive_silently_ignored() {
    let cfg =
        "Host x\n  HostName y\n  StrictHostKeyChecking no\n  ProxyCommand ssh -W %h:%p bastion\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries[0].host_name.as_deref(), Some("y"));
}

#[test]
fn host_line_with_multiple_patterns_emits_one_entry_per_concrete() {
    let cfg = "Host prod stage\n  HostName common.example\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    let names: Vec<&str> = entries.iter().map(|e| e.host.as_str()).collect();
    assert_eq!(names, vec!["prod", "stage"]);
    assert!(entries
        .iter()
        .all(|e| e.host_name.as_deref() == Some("common.example")));
}

#[test]
fn glob_matcher_handles_star_question_literal() {
    assert!(glob_matches("*.internal", "foo.internal"));
    assert!(glob_matches("*.internal", "a.b.internal"));
    assert!(glob_matches("ho?t", "host"));
    assert!(!glob_matches("ho?t", "house"));
    assert!(glob_matches("exact", "exact"));
    assert!(!glob_matches("exact", "exactly"));
    assert!(glob_matches("*", ""));
}

#[test]
fn include_directive_expanded_through_reader() {
    let included = "Host inc\n  HostName from-include\n";
    let reader = |path: &str| -> Option<String> {
        if path == "/cfg/extras" {
            Some(included.to_string())
        } else {
            None
        }
    };
    let cfg = "Include extras\nHost main\n  HostName m.example\n";
    let entries = parse_openssh_config(cfg, &reader, "/cfg", 8);
    let mut by_host: std::collections::HashMap<String, &HostEntry> = Default::default();
    for e in &entries {
        by_host.insert(e.host.clone(), e);
    }
    assert_eq!(by_host.len(), 2);
    assert_eq!(by_host["inc"].host_name.as_deref(), Some("from-include"));
    assert_eq!(by_host["main"].host_name.as_deref(), Some("m.example"));
}

#[test]
fn include_max_depth_breaks_recursion() {
    // A reader that always returns a fresh `Include` line would
    // recurse forever without the depth bound.
    let reader = |path: &str| -> Option<String> {
        if path == "/cfg/loop" {
            Some("Include loop\n".to_string())
        } else {
            None
        }
    };
    let cfg = "Include loop\n";
    // Should return without panicking and with no host entries.
    let entries = parse_openssh_config(cfg, &reader, "/cfg", 3);
    assert!(entries.is_empty());
}

#[test]
fn malformed_lines_dropped_gracefully() {
    let cfg = "no-keyword-only-line\nHost ok\n  HostName y\n  : weird\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].host_name.as_deref(), Some("y"));
}

#[test]
fn orphan_directive_before_host_skipped() {
    let cfg = "HostName lone\nHost a\n  HostName actual\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].host_name.as_deref(), Some("actual"));
}

#[test]
fn first_value_wins_inside_block() {
    let cfg = "Host a\n  HostName first\n  HostName second\n  Port 1\n  Port 2\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries[0].host_name.as_deref(), Some("first"));
    assert_eq!(entries[0].port, Some(1));
}

#[test]
fn effective_host_falls_back_to_alias() {
    let cfg = "Host alias\n";
    let entries = parse_openssh_config(cfg, &no_includes, "/cfg", 8);
    assert_eq!(entries[0].effective_host(), "alias");
}

// ---- resolve_include_paths_for_content -------------------------

#[test]
fn resolve_include_paths_for_content_returns_each_relative_token_anchored() {
    // Two `Include` lines, second one carries multiple
    // whitespace-separated tokens. Output order mirrors source
    // order so the Dart caller's visited set deduplicates
    // deterministically.
    let cfg = "\
Host pre\n\
HostName p\n\
Include extras\n\
Include a.conf b.conf\n";
    let sep = if cfg!(windows) { '\\' } else { '/' };
    let resolved = resolve_include_paths_for_content(cfg, "/cfg");
    assert_eq!(
        resolved,
        vec![
            format!("/cfg{sep}extras"),
            format!("/cfg{sep}a.conf"),
            format!("/cfg{sep}b.conf"),
        ]
    );
}

#[test]
fn resolve_include_paths_for_content_skips_comments_and_other_directives() {
    // `HostName` is not an Include line; the `#` strips the
    // include token after it. Both lines must produce zero
    // entries so the Dart walker doesn't fan out into spurious
    // reader calls.
    let cfg = "\
Host x\n\
HostName y\n\
# Include suppressed.conf\n\
HostName z\n";
    assert!(resolve_include_paths_for_content(cfg, "/cfg").is_empty());
}

#[test]
fn resolve_include_paths_for_content_keeps_absolute_paths_unmodified() {
    let cfg = "Include /etc/ssh/ssh_config\n";
    let resolved = resolve_include_paths_for_content(cfg, "/cfg");
    assert_eq!(resolved, vec!["/etc/ssh/ssh_config".to_string()]);
}

// ---- with_fs include resolution ---------------------------------

fn temp_dir(label: &str) -> std::path::PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let pid = std::process::id();
    let dir = std::env::temp_dir().join(format!("lfs_ssh_cfg_test_{label}_{pid}_{nanos}"));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}

fn write_file(dir: &std::path::Path, name: &str, content: &str) -> String {
    let path = dir.join(name);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("mkdir -p");
    }
    std::fs::write(&path, content).expect("write include");
    path.to_string_lossy().into_owned()
}

#[test]
fn with_fs_expands_relative_include() {
    let dir = temp_dir("rel_include");
    write_file(
        &dir,
        "extra.conf",
        "Host remote\n    HostName remote.example.com\n    User admin\n",
    );
    let main = "Host local\n    HostName local.example.com\nInclude extra.conf\n";
    let entries = parse_openssh_config_with_fs(main, dir.to_string_lossy().as_ref(), 8);
    let hosts: std::collections::HashSet<_> = entries.iter().map(|e| e.host.as_str()).collect();
    assert!(hosts.contains("local"));
    assert!(hosts.contains("remote"));
    let remote = entries.iter().find(|e| e.host == "remote").unwrap();
    assert_eq!(remote.user.as_deref(), Some("admin"));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn with_fs_glob_expands_to_multiple_files() {
    let dir = temp_dir("glob");
    let sub = dir.join("config.d");
    std::fs::create_dir_all(&sub).expect("mkdir config.d");
    write_file(&sub, "01-a.conf", "Host a\n    HostName a-host\n");
    write_file(&sub, "02-b.conf", "Host b\n    HostName b-host\n");
    // Distractor that shouldn't match `*.conf`.
    write_file(&sub, "ignore.txt", "Host nope\n    HostName nope\n");
    let main = "Include config.d/*.conf\n";
    let entries = parse_openssh_config_with_fs(main, dir.to_string_lossy().as_ref(), 8);
    let hosts: std::collections::HashSet<_> = entries.iter().map(|e| e.host.as_str()).collect();
    assert!(hosts.contains("a"));
    assert!(hosts.contains("b"));
    assert!(!hosts.contains("nope"));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn with_fs_self_referencing_include_terminates() {
    let dir = temp_dir("loop");
    write_file(
        &dir,
        "loop.conf",
        "Host looped\n    HostName l\nInclude loop.conf\n",
    );
    let entries =
        parse_openssh_config_with_fs("Include loop.conf\n", dir.to_string_lossy().as_ref(), 8);
    let hosts: Vec<_> = entries.iter().map(|e| e.host.as_str()).collect();
    assert_eq!(hosts, vec!["looped"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn with_fs_missing_include_silently_skipped() {
    let dir = temp_dir("missing");
    let entries = parse_openssh_config_with_fs(
        "Host a\n    HostName a\nInclude does_not_exist.conf\n",
        dir.to_string_lossy().as_ref(),
        8,
    );
    let hosts: Vec<_> = entries.iter().map(|e| e.host.as_str()).collect();
    assert_eq!(hosts, vec!["a"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn with_fs_oversized_include_skipped() {
    let dir = temp_dir("oversized");
    // Cap is 1 MiB; write 1.5 MiB so the file is rejected.
    let large = "Host big\n    HostName big\n".repeat(80_000);
    assert!(large.len() as u64 > MAX_INCLUDE_FILE_BYTES);
    write_file(&dir, "big.conf", &large);
    let entries = parse_openssh_config_with_fs(
        "Host a\n    HostName a\nInclude big.conf\n",
        dir.to_string_lossy().as_ref(),
        8,
    );
    let hosts: Vec<_> = entries.iter().map(|e| e.host.as_str()).collect();
    assert_eq!(hosts, vec!["a"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn with_fs_max_depth_caps_recursion() {
    let dir = temp_dir("depth");
    write_file(&dir, "a.conf", "Host a\n    HostName a\nInclude b.conf\n");
    write_file(&dir, "b.conf", "Host b\n    HostName b\nInclude c.conf\n");
    write_file(&dir, "c.conf", "Host c\n    HostName c\n");
    // Depth 1 → only `a` is read; the deeper Include lines are
    // emitted as raw text (parser ignores Include directives in
    // the body) so b and c never land.
    let entries =
        parse_openssh_config_with_fs("Include a.conf\n", dir.to_string_lossy().as_ref(), 1);
    let hosts: std::collections::HashSet<_> = entries.iter().map(|e| e.host.as_str()).collect();
    assert!(hosts.contains("a"));
    assert!(!hosts.contains("b"));
    assert!(!hosts.contains("c"));
    std::fs::remove_dir_all(&dir).ok();
}
