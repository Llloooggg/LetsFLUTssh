APP_NAME := letsflutssh
VERSION := $(shell grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//;s/+.*//')
BUILD_DIR := build
FLUTTER := flutter
UNAME := $(shell uname)
ARCH := $(shell uname -m)

# Platform detection
IS_LINUX := $(filter Linux,$(UNAME))
IS_MACOS := $(filter Darwin,$(UNAME))

# Map uname arch to Debian arch
DEB_ARCH := $(if $(filter x86_64,$(ARCH)),amd64,$(if $(filter aarch64,$(ARCH)),arm64,$(ARCH)))

.PHONY: all build run clean test analyze check format gen watch deps upgrade doctor \
        build-linux build-windows build-macos build-apk build-aab build-ios \
        linux windows macos apk ios \
        package-linux package-windows release-linux \
        deps-linux deps-macos deps-windows fuzz-build hooks help \
        lint-workflows

all: build

## ─── Development ──────────────────────────────────────────────

run: ## Run the app (debug, current platform)
	$(FLUTTER) run

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

test: ## Run all tests with coverage
	$(FLUTTER) test --coverage --timeout 30s

analyze: ## Run Dart analyzer (fatal on infos, same as CI)
	$(FLUTTER) analyze --fatal-infos

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

check: analyze lint-workflows lint-release-hardening ## Run analyzer + workflow lint + release hardening + tests (sequential — each must pass first)
	@$(MAKE) test

hooks: ## Install local git hooks (pre-commit runs make check)
	@bash scripts/install-hooks.sh

format: ## Format Dart code
	dart format .

gen: ## Code generation (freezed, json_serializable)
	dart run build_runner build --delete-conflicting-outputs

watch: ## Watch mode code generation
	dart run build_runner watch --delete-conflicting-outputs

drift-schema-dump: ## Dump current drift schema to drift_schemas/drift_schema_v$(DB_VERSION).json (bump DB_VERSION before bumping schemaVersion)
	dart run drift_dev schema dump lib/core/db/database.dart drift_schemas/

drift-schema-generate: ## Regenerate drift schema verification helpers in test/generated_drift_schema/
	dart run drift_dev schema generate drift_schemas/ test/generated_drift_schema/ --data-classes --companions

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

## ─── Utility ──────────────────────────────────────────────────

doctor: ## Run Flutter doctor
	$(FLUTTER) doctor -v

clean: ## Remove all build artifacts
	$(FLUTTER) clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
