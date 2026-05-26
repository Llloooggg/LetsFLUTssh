#!/bin/bash
# PreToolUse hook: scope-aware pre-commit checks. The full CI
# pipeline is the source of truth for validation; this hook
# catches the cheap+fast bugs locally so a `git commit` does not
# produce a PR that is obviously broken on the surface the
# contributor just touched.
#
# Scopes (combinable — each runs independently when its file
# class is staged; the slowest path is still bounded by what is
# tractable in a commit-loop):
#
# 1. Any `*.dart` file staged → `make check` (analyze + tests +
#    lint-workflows + lint-release-hardening). Slowest path,
#    appropriate when Dart source is touched. Implies the
#    workflow + Rust scopes are not separately re-run because
#    `make check` already covers actionlint and the Dart side
#    does not depend on the Rust pre-commit gates.
# 2. Any `.github/workflows/*` file staged (and no Dart) →
#    `make lint-workflows` (actionlint). Catches YAML / shell /
#    GHA expression bugs in seconds.
# 3. Any `rust/**` file staged (and no Dart) → `cargo fmt --check`
#    + `Cargo.lock` parity (when `Cargo.toml` also changed).
#    Skips clippy / test (CI handles those — too slow for the
#    local commit loop, especially on a first-Rust-touch when
#    the cargo target dir is cold). The fmt-check + lock parity
#    are second-scale and catch the classes of bug a contributor
#    would otherwise discover only in CI.
# 4. Otherwise (docs / config-only) → no checks, exit clean.
#
# All checks emit `{"continue":true|false}` JSON for the hook
# runtime to gate the commit.

set -o pipefail

# cd to repo root (hooks run from project root, but be safe)
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

dart_files=$(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
workflow_files=$(git diff --cached --name-only --diff-filter=ACMR -- '.github/workflows/*')
rust_files=$(git diff --cached --name-only --diff-filter=ACMR -- 'rust/')

# ── Scope 1: Dart staged → full make check (covers everything) ─
if [ -n "$dart_files" ]; then
    echo "Dart files staged — running make check (analyze + tests + workflow lint)..."
    output=$(make check 2>&1)
    status=$?
    echo "$output" | tail -30
    if [ $status -ne 0 ]; then
        echo '{"continue":false,"stopReason":"Pre-commit make check failed. Fix issues before committing."}'
        exit 0
    fi
    echo '{"continue":true}'
    exit 0
fi

# ── Scope 2: workflow-only → actionlint ────────────────────────
if [ -n "$workflow_files" ]; then
    echo "Workflow files staged — running make lint-workflows (actionlint)..."
    output=$(make lint-workflows 2>&1)
    status=$?
    echo "$output" | tail -20
    if [ $status -ne 0 ]; then
        echo '{"continue":false,"stopReason":"Pre-commit workflow lint failed. Fix actionlint issues before committing."}'
        exit 0
    fi
fi

# ── Scope 3: Rust staged → fmt-check + Cargo.lock parity ──────
if [ -n "$rust_files" ]; then
    echo "Rust files staged — running cargo fmt --check + Cargo.lock parity..."
    fmt_output=$(cd rust && cargo fmt --all -- --check 2>&1)
    fmt_status=$?
    if [ $fmt_status -ne 0 ]; then
        echo "$fmt_output" | tail -30
        echo "Run 'cd rust && cargo fmt --all' to auto-fix." >&2
        echo '{"continue":false,"stopReason":"Pre-commit cargo fmt --check failed."}'
        exit 0
    fi
    # Lock parity: only if Cargo.toml changed (otherwise the lock
    # cannot have drifted from anything we control here). Use
    # `--offline` so the commit hook does not block on network
    # availability when registry is unreachable.
    cargo_toml_changed=$(git diff --cached --name-only --diff-filter=ACMR -- 'rust/**/Cargo.toml')
    if [ -n "$cargo_toml_changed" ]; then
        if ! (cd rust && cargo update --workspace --locked --offline >/dev/null 2>&1); then
            echo "rust/Cargo.lock appears out of sync with rust/Cargo.toml." >&2
            echo "Run 'cd rust && cargo update --workspace' and stage the regenerated Cargo.lock." >&2
            echo '{"continue":false,"stopReason":"Pre-commit Cargo.lock parity failed."}'
            exit 0
        fi
    fi
    echo "Rust pre-commit checks passed (fmt + lock parity)."
fi

# ── Scope 4 fall-through: docs / config / nothing → no checks ──
if [ -z "$workflow_files" ] && [ -z "$rust_files" ]; then
    echo "No Dart / workflow / Rust files staged — skipping pre-commit checks."
fi

echo '{"continue":true}'
exit 0
