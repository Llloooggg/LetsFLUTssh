APP_NAME := letsflutssh
VERSION := $(shell grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//;s/+.*//')
BUILD_DIR := build
FLUTTER := flutter
UNAME := $(shell uname)
ARCH := $(shell uname -m)

# Platform detection. `uname` on Cygwin / MSYS / Git-Bash on Windows
# reports `CYGWIN_*`, `MINGW64_*`, `MSYS_*` etc., never `Windows`;
# match the prefixes so `package-exe`'s host guard fires correctly
# regardless of which Windows shell the user invokes `make` from.
IS_LINUX := $(filter Linux,$(UNAME))
IS_MACOS := $(filter Darwin,$(UNAME))
IS_WINDOWS := $(or $(filter Windows_NT,$(OS)),$(findstring CYGWIN,$(UNAME)),$(findstring MINGW,$(UNAME)),$(findstring MSYS,$(UNAME)))

# Map uname arch to Debian arch
DEB_ARCH := $(if $(filter x86_64,$(ARCH)),amd64,$(if $(filter aarch64,$(ARCH)),arm64,$(ARCH)))

.PHONY: all build run run-release clean test lint check format format-check gen watch deps upgrade doctor \
        build-linux build-windows build-macos build-apk build-aab build-ios \
        linux windows macos apk ios \
        package-linux package-appimage package-deb package-windows package-exe release-linux \
        deps-linux deps-macos deps-windows fuzz-build hooks help setup setup-rust-tools \
        lint-workflows lint-release-hardening rust-mutants \
        dart-test dart-lint dart-format dart-format-check \
        rust-format rust-format-check rust-lint rust-lint-host rust-test rust-build rust-codegen rust-clean rust-machete rust-coverage \
        rust-lint-android rust-lint-android-workspace rust-lint-windows-gnu rust-lint-ios rust-lint-macos-arm

all: build

## ─── Development ──────────────────────────────────────────────

run: ## Run the app (debug, current platform, logs=info)
	$(FLUTTER) run --dart-define=LETSFLUTSSH_LOG_LEVEL=info

run-release: ## Run the app (release mode)
	$(FLUTTER) run --release

build: ## Build for current platform (release)
ifdef IS_LINUX
	$(FLUTTER) build linux --release
else ifdef IS_MACOS
	$(FLUTTER) build macos --release
else
	@echo "Error: unsupported platform $(UNAME). Use an explicit target (build-linux, build-windows, etc.)"
	@exit 1
endif

## ─── Quality gates (umbrella + per-language) ──────────────────
## Top-level umbrellas run both languages; `dart-*` / `rust-*`
## variants exist for fast iteration when only one side changed.

test: rust-test dart-test ## Run all tests (Rust core first, then Dart)

lint: dart-lint rust-lint ## Run static analysis (Dart analyzer + Rust clippy)

format: dart-format rust-format ## Auto-format Dart + Rust sources

format-check: dart-format-check rust-format-check ## Verify formatting without touching files

dart-test: rust-build ## Run Dart tests with coverage
	@# Tests that load the FRB native blob — `terminal_clipboard_test.dart`
	@# (sensitivity-routing → `lfs_core::log_sanitize`),
	@# `connection_lifecycle_test.dart` (in-process russh fixture) — call
	@# `requireFrbLoaded()` and throw if the .so is missing. The
	@# `rust-build` dependency above guarantees `rust/target/release/
	@# liblfs_frb.so` exists before the Flutter test runner picks it up.
	@# Without this, FRB-loaded tests fail silently in CI (the previous
	@# behaviour: `make test` ran without the .so, and the bus-driven
	@# integration tests this whole pipeline exists to enable would
	@# never trip).
	$(FLUTTER) test --coverage --timeout 30s
	@# Post-process lcov.info to drop generated + localisation files
	@# from the coverage denominator. Must mirror
	@# `sonar.coverage.exclusions` in sonar-project.properties so the
	@# local and CI coverage numbers agree. Dart-native filter so no
	@# host dependency is added beyond the Flutter toolchain we
	@# already need.
	@dart run dev/scripts/filter_lcov.dart coverage/lcov.info

dart-lint: ## Run Dart analyzer (fatal on infos)
	$(FLUTTER) analyze --fatal-infos

dart-format: ## Format Dart sources in place
	dart format lib test integration_test fuzz dev/scripts

dart-format-check: ## Verify Dart formatting (exit non-zero if changes needed)
	dart format --output=none --set-exit-if-changed lib test integration_test fuzz dev/scripts

# Pinned actionlint version + checksum. Update both together when bumping.
ACTIONLINT_VERSION := 1.7.5
ACTIONLINT_LINUX_AMD64_SHA256 := 3e6e0a832dfa0b5f027e6b8956aad2632d69b7cb778b1cff847b40279950a856
ACTIONLINT_DARWIN_ARM64_SHA256 := 397119f9baa3fd9fe195db340b30acdaea532826e19a047a9cc9d96add7c267d
ACTIONLINT_BIN := .cache/actionlint/$(ACTIONLINT_VERSION)/actionlint

$(ACTIONLINT_BIN):
	@mkdir -p $(dir $(ACTIONLINT_BIN))
	@case "$(UNAME)/$(ARCH)" in \
		Linux/x86_64) \
			URL=https://github.com/rhysd/actionlint/releases/download/v$(ACTIONLINT_VERSION)/actionlint_$(ACTIONLINT_VERSION)_linux_amd64.tar.gz; \
			SHA="$(ACTIONLINT_LINUX_AMD64_SHA256)" ;; \
		Darwin/arm64) \
			URL=https://github.com/rhysd/actionlint/releases/download/v$(ACTIONLINT_VERSION)/actionlint_$(ACTIONLINT_VERSION)_darwin_arm64.tar.gz; \
			SHA="$(ACTIONLINT_DARWIN_ARM64_SHA256)" ;; \
		*) \
			echo "actionlint: unsupported host $(UNAME)/$(ARCH) — install actionlint manually and put it on PATH"; \
			exit 1 ;; \
	esac && \
	echo "Downloading actionlint $(ACTIONLINT_VERSION) for $(UNAME)/$(ARCH)..." && \
	TMP=$$(mktemp -d) && \
	curl -sSL -o "$$TMP/actionlint.tgz" "$$URL" && \
	if [ -n "$$SHA" ]; then \
		echo "$$SHA  $$TMP/actionlint.tgz" | sha256sum -c - || { echo "checksum mismatch"; exit 1; }; \
	else \
		echo "WARNING: no pinned checksum for $(UNAME)/$(ARCH) — pin one in the Makefile"; \
	fi && \
	tar -xzf "$$TMP/actionlint.tgz" -C "$$TMP" actionlint && \
	mv "$$TMP/actionlint" "$(ACTIONLINT_BIN)" && \
	rm -rf "$$TMP"

lint-workflows: $(ACTIONLINT_BIN) ## Lint .github/workflows/*.yml with actionlint (catches YAML + shell + GHA bugs)
	@echo "Linting workflows..."
	@# Per-path ignores live in `.github/actionlint.yaml`. Keep them
	@# narrow — broad disables would defeat the point of running
	@# actionlint in the first place.
	@$(ACTIONLINT_BIN) -color
	@echo "Workflows OK"

lint-release-hardening: ## Guard against debuggable release builds + dSYM-embedding regressions
	@echo "Checking release-build hardening..."
	@# Android: AndroidManifest.xml must NOT contain debuggable="true".
	@# Flutter default in release is false, but a manual edit for
	@# local debugging (sometimes committed by accident) re-enables
	@# ptrace attach + run-as access to app data on devices without
	@# root. Fail the build rather than ship a release that accepts
	@# `adb shell run-as <pkg>`.
	@if grep -rn 'android:debuggable="true"' android/ 2>/dev/null; then \
		echo "ERROR: android:debuggable=\"true\" found in AndroidManifest — release builds must ship with it absent or false"; \
		exit 1; \
	fi
	@# iOS / macOS: Release config must not embed debug symbols in
	@# the binary. `DEBUG_INFORMATION_FORMAT = dwarf` is the debug-
	@# build default; Release uses `dwarf-with-dsym` (external dSYM
	@# bundle). Reverting Release to plain `dwarf` ships a binary
	@# with inline symbols that makes reverse-engineering trivially
	@# easy. Grep the pbxproj for Release-scope overrides.
	@if grep -A1 'name = Release;' ios/Runner.xcodeproj/project.pbxproj macos/Runner.xcodeproj/project.pbxproj 2>/dev/null \
		| grep -E 'DEBUG_INFORMATION_FORMAT = dwarf;' >/dev/null; then \
		echo "ERROR: Release config uses DEBUG_INFORMATION_FORMAT=dwarf (inline symbols); use dwarf-with-dsym"; \
		exit 1; \
	fi
	@echo "Release hardening OK"

check-static: format-check lint lint-workflows lint-release-hardening rust-machete ## Static gate (no tests): format, lint, workflow lint, release hardening, unused-deps

check: check-static ## Full gate (Dart + Rust): static checks, then the test suite
	@$(MAKE) test

hooks: ## Install local git hooks (pre-commit: check-static; pre-push: test; commit-msg: lint + plan-id; post-commit: target GC)
	@bash dev/scripts/install-hooks.sh

gen: ## Code generation (freezed, json_serializable)
	dart run build_runner build --delete-conflicting-outputs

watch: ## Watch mode code generation
	dart run build_runner watch --delete-conflicting-outputs

fuzz-build: ## Compile standalone fuzz targets to native (fuzz/out/)
	@mkdir -p fuzz/out
	@for f in fuzz/fuzz_*.dart; do \
		name=$$(basename "$$f" .dart); \
		echo "Compiling $$name..."; \
		dart compile exe "$$f" -o "fuzz/out/$$name"; \
	done
	@echo "Fuzz targets built in fuzz/out/"

## ─── Platform Builds ──────────────────────────────────────────
## Short aliases: make linux, make macos, make apk, etc.

linux: build-linux
windows: build-windows
macos: build-macos
apk: build-apk
ios: build-ios

build-linux: ## Build for Linux (release)
ifdef IS_LINUX
	$(FLUTTER) build linux --release
else
	@echo "Error: Linux builds require a Linux host (current: $(UNAME))"
	@exit 1
endif

build-windows: ## Build for Windows
	@echo "Error: Windows builds require a Windows host (current: $(UNAME))"
	@echo "Use: flutter build windows (on Windows)"
	@exit 1

build-macos: ## Build for macOS (release)
ifdef IS_MACOS
	$(FLUTTER) build macos --release
else
	@echo "Error: macOS builds require a macOS host (current: $(UNAME))"
	@exit 1
endif

build-apk: ## Build Android APK (release, per-ABI)
	$(FLUTTER) build apk --release --split-per-abi

build-aab: ## Build Android App Bundle (release)
	$(FLUTTER) build appbundle --release

build-ios: ## Build for iOS (release)
ifdef IS_MACOS
	$(FLUTTER) build ios --release
else
	@echo "Error: iOS builds require a macOS host (current: $(UNAME))"
	@exit 1
endif

## ─── Packaging ────────────────────────────────────────────────

package-linux: build-linux ## Build + tar.gz for Linux
	@mkdir -p $(BUILD_DIR)/package
	cd build/linux/$(ARCH)/release/bundle && \
		tar czf $(CURDIR)/$(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-linux-$(ARCH).tar.gz .
	@echo "Package: $(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-linux-$(ARCH).tar.gz"

package-appimage: build-linux ## Build + AppImage for Linux
	@rm -rf $(BUILD_DIR)/AppDir
	@mkdir -p $(BUILD_DIR)/AppDir/usr/bin $(BUILD_DIR)/AppDir/usr/share/applications $(BUILD_DIR)/AppDir/usr/share/icons/hicolor/256x256/apps
	cp -r build/linux/$(ARCH)/release/bundle/* $(BUILD_DIR)/AppDir/usr/bin/
	cp linux/packaging/letsflutssh.desktop $(BUILD_DIR)/AppDir/usr/share/applications/
	cp linux/packaging/letsflutssh.desktop $(BUILD_DIR)/AppDir/
	cp assets/icons/icon.png $(BUILD_DIR)/AppDir/usr/share/icons/hicolor/256x256/apps/letsflutssh.png
	cp assets/icons/icon.png $(BUILD_DIR)/AppDir/letsflutssh.png
	printf '#!/bin/bash\nHERE="$$(dirname "$$(readlink -f "$$0")")"\nexec "$$HERE/usr/bin/letsflutssh" "$$@"\n' > $(BUILD_DIR)/AppDir/AppRun
	chmod +x $(BUILD_DIR)/AppDir/AppRun
	@echo "AppDir created. Run: ARCH=$(ARCH) appimagetool $(BUILD_DIR)/AppDir $(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-linux-$(ARCH).AppImage"

package-deb: build-linux ## Build + deb for Linux
	@mkdir -p $(BUILD_DIR)/package
	@PKG=$(APP_NAME)_$(VERSION)_$(DEB_ARCH) && \
	mkdir -p $$PKG/DEBIAN $$PKG/usr/bin $$PKG/usr/lib/letsflutssh $$PKG/usr/share/applications $$PKG/usr/share/icons/hicolor/256x256/apps && \
	cp -r build/linux/$(ARCH)/release/bundle/* $$PKG/usr/lib/letsflutssh/ && \
	ln -sf /usr/lib/letsflutssh/letsflutssh $$PKG/usr/bin/letsflutssh && \
	cp linux/packaging/letsflutssh.desktop $$PKG/usr/share/applications/ && \
	cp assets/icons/icon.png $$PKG/usr/share/icons/hicolor/256x256/apps/letsflutssh.png && \
	printf 'Package: letsflutssh\nVersion: $(VERSION)\nArchitecture: $(DEB_ARCH)\nMaintainer: LetsFLUTssh <noreply@letsflutssh.dev>\nDescription: Lightweight cross-platform SSH/SFTP client\nDepends: libgtk-3-0\nSection: net\nPriority: optional\n' > $$PKG/DEBIAN/control && \
	dpkg-deb --build $$PKG && \
	mv $${PKG}.deb $(BUILD_DIR)/package/ && \
	rm -rf $$PKG
	@echo "Package: $(BUILD_DIR)/package/$(APP_NAME)_$(VERSION)_$(DEB_ARCH).deb"

package-windows: build-windows ## Build + zip for Windows
	@mkdir -p $(BUILD_DIR)/package
	cd build/windows/x64/runner/Release && \
		zip -r $(CURDIR)/$(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-windows-amd64.zip .
	@echo "Package: $(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-windows-amd64.zip"

package-exe: build-windows ## Build + EXE installer for Windows (requires Inno Setup)
ifndef IS_WINDOWS
	@echo "Error: package-exe is Windows-only (uses Inno Setup Compiler). Run on a Windows host with Inno Setup 6 installed." && exit 1
endif
	@if not exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (echo "Error: Inno Setup 6 not found. Install from https://jrsoftware.org/isdl.php" && exit 1)
	set APP_VERSION=$(VERSION) && set BUILD_DIR=$(CURDIR)\build\windows\x64\runner\Release && "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\packaging\setup.iss
	@echo "Installer: Output/$(APP_NAME)-$(VERSION)-windows-x64-setup.exe"

release-linux: package-linux ## Build Linux release packages
	@echo "Built packages:"
	@ls -lh $(BUILD_DIR)/package/
	@echo ""
	@echo "Cross-platform builds require the respective host OS:"
	@echo "  Linux:   make linux    (on Linux)"
	@echo "  macOS:   make macos    (on macOS)"
	@echo "  Windows: flutter build windows (on Windows)"
	@echo "  Android: make apk      (any host with Android SDK)"
	@echo "  iOS:     make ios      (on macOS with Xcode)"


## ─── Dependencies ─────────────────────────────────────────────

setup: deps hooks setup-rust-tools ## One-shot post-clone bootstrap: pub deps + git hooks + Rust dev tools
	@echo "Setup complete. Run 'make run' or 'make build' to continue."

# Pinned cargo plugin versions used in `make check` / `make
# rust-coverage` / CI. Bump the version constant together with
# any comment that names it elsewhere.
CARGO_MACHETE_VERSION := 0.7.0
CARGO_LLVM_COV_VERSION := 0.6.20

setup-rust-tools: ## Install pinned cargo plugins (cargo-machete, cargo-llvm-cov) used by `make check` / `make rust-coverage`
	@if ! command -v cargo-machete >/dev/null 2>&1; then \
		echo "Installing cargo-machete $(CARGO_MACHETE_VERSION)..."; \
		cargo install --locked --version $(CARGO_MACHETE_VERSION) cargo-machete; \
	else \
		echo "cargo-machete already installed."; \
	fi
	@if ! command -v cargo-llvm-cov >/dev/null 2>&1; then \
		echo "Installing cargo-llvm-cov $(CARGO_LLVM_COV_VERSION)..."; \
		cargo install --locked --version $(CARGO_LLVM_COV_VERSION) cargo-llvm-cov; \
	else \
		echo "cargo-llvm-cov already installed."; \
	fi

deps: ## Install Flutter dependencies
	$(FLUTTER) pub get

upgrade: ## Upgrade Flutter dependencies
	$(FLUTTER) pub upgrade

deps-linux: ## Install system build deps (Debian/Ubuntu)
	sudo apt-get install -y \
		clang cmake ninja-build pkg-config \
		libgtk-3-dev lld
	@echo ""
	@echo "Done. If using LLVM-based toolchain, ensure lld is in LLVM bin:"
	@echo "  sudo apt-get install lld-<version>  (e.g. lld-19)"

deps-macos: ## Install system build deps (macOS)
	@echo "Xcode and CocoaPods required:"
	@echo "  xcode-select --install"
	@echo "  sudo gem install cocoapods"

deps-windows: ## Install system build deps (Windows)
	@echo "Visual Studio 2022 with C++ desktop workload required."
	@echo "  winget install Microsoft.VisualStudio.2022.Community"
	@echo "  (select 'Desktop development with C++' workload)"

## ─── Rust core ────────────────────────────────────────────────
# Security/transport core lives in rust/. See ARCHITECTURE.md §3.14.
RUST_DIR := rust

rust-format: ## Format Rust code (cargo fmt)
	cd $(RUST_DIR) && cargo fmt --all

rust-format-check: ## Verify Rust formatting (exit non-zero if changes needed)
	cd $(RUST_DIR) && cargo fmt --all -- --check

# `rust-lint` umbrella — host clippy plus every cross-target whose
# std ships with `rustup` (Android, Windows-GNU). Apple targets
# need a real SDK for the link step and are gated to macOS hosts.
# Any feature-branch push that introduces a cfg-gated regression
# trips here before the operator commits, not on the CI matrix
# after push.
# Override-friendly list of cross-target clippy gates the umbrella
# `rust-lint` walks alongside `rust-lint-host`. Default = Android +
# Windows-GNU (cross-target rustup std ships on every host). Apple
# targets append when `uname` is `Darwin` (Apple SDK link step
# requires macOS).
#
# CI sets `RUST_CROSS_LINT_TARGETS=` (empty) because the same lints
# run in the separate `rust-cross-check` matrix job in
# `.github/workflows/ci.yml` — running them again under `make
# check` would serially double the work the matrix does in
# parallel. Local developers keep the cross-target catch on every
# `make check` invocation.
RUST_CROSS_LINT_TARGETS ?= rust-lint-android rust-lint-windows-gnu

rust-lint: rust-lint-host $(RUST_CROSS_LINT_TARGETS) ## Run clippy (host + cross-targets per RUST_CROSS_LINT_TARGETS)
	@if [ "$$(uname -s)" = "Darwin" ] && [ -n "$(RUST_CROSS_LINT_TARGETS)" ]; then \
		$(MAKE) rust-lint-ios rust-lint-macos-arm; \
	fi

rust-lint-host: ## clippy lint for the host target (whole workspace, deny warnings)
	cd $(RUST_DIR) && cargo clippy --workspace --all-targets --locked -- -D warnings

# Cross-target clippy gates — catch regressions in cfg-gated code
# that host-only clippy never sees (`lfs_os_security::{android,
# windows, ios, macos}` and the Apple-cfg blocks under
# `apple_se_ssh`, `fido2_broker`, `backup_exclusion`). Scoped to
# `lfs_os_security` because that crate owns every OS-FFI module;
# the rest of the workspace is target-agnostic and falls under the
# host-target `rust-lint-host`.
#
# Android + Windows-GNU std ships via rustup on every host, so
# they're wired into the `rust-lint` umbrella above. Apple targets
# require an Apple SDK for the link step (rustc short-circuits
# before link so clippy still type-checks the bodies), so they
# stay opt-in via the macOS-host guard and the standalone targets
# below.
#
# Requires `rustup target add aarch64-linux-android
# x86_64-pc-windows-gnu aarch64-apple-ios aarch64-apple-darwin`.
# Cross-target lints. The Windows-GNU + Apple targets run
# `--workspace --exclude lfs_fuzz` so cfg-gated code lives wherever
# it actually lives — `lfs_os_security` for FFI shims, `lfs_core`
# for `platform/*` glue + Windows-cfg branches inside transport /
# fs / recorder helpers, `lfs_frb` for per-OS FRB shims
# (`api/hello.rs`, `api/enclave.rs`, `api/macos_*.rs`). Limiting
# to `-p lfs_os_security` (the previous shape) missed every
# FRB-layer cfg-leak.
#
# Android is the exception: `lfs_core → rusqlite →
# bundled-sqlcipher-vendored-openssl` requires a target C compiler
# (Android NDK) the dev host typically does not have on PATH.
# CI provisions it via `cargo-ndk`; locally we stay narrow on
# `-p lfs_os_security` (which itself stops short of OpenSSL) so
# `make rust-lint` works without an NDK install. Devs who want the
# wider Android workspace lint run `rust-lint-android-workspace`
# opt-in (requires NDK on PATH).
#
# `lfs_fuzz` is excluded everywhere because `libfuzzer-sys` needs
# its own target C compiler that rustup does not ship per
# cross-target — its host-only fuzz coverage stays under
# `make fuzz-build`.
rust-lint-android: ## clippy lint for aarch64-linux-android (lfs_os_security; no NDK needed)
	cd $(RUST_DIR) && cargo clippy -p lfs_os_security --target aarch64-linux-android --all-targets --locked -- -D warnings

rust-lint-android-workspace: ## clippy lint for aarch64-linux-android (full workspace; requires Android NDK on PATH)
	cd $(RUST_DIR) && cargo clippy --workspace --exclude lfs_fuzz --target aarch64-linux-android --all-targets --locked -- -D warnings

rust-lint-windows-gnu: ## clippy lint for x86_64-pc-windows-gnu (workspace minus fuzz)
	cd $(RUST_DIR) && cargo clippy --workspace --exclude lfs_fuzz --target x86_64-pc-windows-gnu --all-targets --locked -- -D warnings

rust-lint-ios: ## clippy lint for aarch64-apple-ios (workspace minus fuzz; macOS hosts)
	cd $(RUST_DIR) && cargo clippy --workspace --exclude lfs_fuzz --target aarch64-apple-ios --all-targets --locked -- -D warnings

rust-lint-macos-arm: ## clippy lint for aarch64-apple-darwin (workspace minus fuzz; macOS hosts)
	cd $(RUST_DIR) && cargo clippy --workspace --exclude lfs_fuzz --target aarch64-apple-darwin --all-targets --locked -- -D warnings

rust-test: ## Run Rust tests (unit + integration + doc), --locked enforces Cargo.lock parity
	cd $(RUST_DIR) && cargo test --workspace --locked
	cd $(RUST_DIR) && cargo test --workspace --doc --locked

# Opt-in: PKCS#11 integration tests against a real SoftHSM v2 install.
# Requires `softhsm2` on PATH + a provisioned per-user tokenstore;
# see docs/CONTRIBUTING.md → "Optional hardware-backed integration
# tests". Outside the default rust-test umbrella because SoftHSM is
# not bundled with the project.
rust-test-pkcs11: ## Run #[ignore]-gated PKCS#11 tests against a local SoftHSM v2 (opt-in)
	cd $(RUST_DIR) && cargo test -p lfs_os_security --test pkcs11_softhsm_test -- --ignored --nocapture

rust-build: ## Build Rust workspace (release, host), --locked enforces Cargo.lock parity
	cd $(RUST_DIR) && cargo build --release --workspace --locked

rust-codegen: ## Regenerate Dart bindings from Rust API surface
	flutter_rust_bridge_codegen generate

rust-clean: ## cargo clean
	cd $(RUST_DIR) && cargo clean

rust-machete: ## Detect unused dependencies (`cargo install cargo-machete` via `make setup-rust-tools`)
	cd $(RUST_DIR) && cargo machete --with-metadata

rust-coverage: ## Generate Rust workspace coverage as lcov (rust-lcov.info). Used by SonarCloud alongside Dart lcov. Requires `make setup-rust-tools`.
	cd $(RUST_DIR) && cargo llvm-cov --workspace --all-features --locked --lcov --output-path ../rust-lcov.info

rust-mutants: ## Mutation-test a scope of lfs_core (e.g. `make rust-mutants SCOPE=archive`). Requires `cargo install cargo-mutants`. Honours MUTANTS_JOBS / MUTANTS_TIMEOUT_MUL.
	@if [ -z "$(SCOPE)" ]; then \
		echo "Error: pass SCOPE=<dir under rust/crates/lfs_core/src/>"; \
		echo "Examples: SCOPE=archive | SCOPE=security | SCOPE=ssh"; \
		exit 64; \
	fi
	@bash dev/scripts/run-mutants.sh "$(SCOPE)"

## ─── Utility ──────────────────────────────────────────────────

doctor: ## Run Flutter doctor
	$(FLUTTER) doctor -v

clean: ## Remove all build artifacts
	$(FLUTTER) clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
