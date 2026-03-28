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
        package-linux package-windows release-linux tag \
        deps-linux deps-macos deps-windows help

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

check: analyze ## Run analyzer + tests (sequential — analyze must pass first)
	@$(MAKE) test

format: ## Format Dart code
	dart format .

gen: ## Code generation (freezed, json_serializable)
	dart run build_runner build --delete-conflicting-outputs

watch: ## Watch mode code generation
	dart run build_runner watch --delete-conflicting-outputs

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

## ─── Release ─────────────────────────────────────────────────

tag: check ## Analyze + test, verify CI on GitHub, tag vX.Y.Z, push atomically
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: working tree is dirty — commit or stash first"; exit 1; \
	fi
	@TAG=v$(VERSION); \
	if git rev-parse "$$TAG" >/dev/null 2>&1; then \
		echo "Error: tag $$TAG already exists"; exit 1; \
	fi; \
	SHA=$$(git rev-parse HEAD); \
	REPO=$$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); \
	if [ -n "$$REPO" ]; then \
		STATUS=$$(gh api "repos/$$REPO/commits/$$SHA/check-runs" \
			--jq '.check_runs[] | select(.name == "analyze-and-test" and .app.slug == "github-actions") | .conclusion' 2>/dev/null | head -1); \
		if [ -z "$$STATUS" ]; then \
			LAST_CI=$$(gh api "repos/$$REPO/actions/workflows/ci.yml/runs?per_page=5&status=success" \
				--jq '.workflow_runs[0] | "\(.head_sha) \(.head_commit.message)"' 2>/dev/null); \
			LAST_SHA=$${LAST_CI%% *}; \
			LAST_MSG=$${LAST_CI#* }; \
			echo ""; \
			echo "✗ No CI check run found for $$SHA."; \
			echo "  HEAD is likely a ci/docs-only commit. Tag the last app-change commit instead:"; \
			echo "    git tag -a $$TAG $$LAST_SHA -m \"$$TAG\""; \
			echo "    git push origin $$TAG"; \
			echo ""; \
			echo "  Last CI-passed commit: $$LAST_SHA ($$LAST_MSG)"; \
			exit 1; \
		elif [ "$$STATUS" != "success" ]; then \
			echo ""; \
			echo "✗ CI check on $$SHA has not passed yet (status: $$STATUS)."; \
			echo "  Wait for CI to finish, then retry: make tag"; \
			exit 1; \
		fi; \
		echo "==> CI passed on $$SHA ✓"; \
	else \
		echo "==> Warning: gh CLI not available or not in a GitHub repo — skipping CI check"; \
	fi; \
	echo "==> Tagging $$TAG on HEAD..."; \
	git tag -a "$$TAG" -m "$$TAG"; \
	echo "==> Pushing commits + tag (atomic)..."; \
	git push --follow-tags --atomic || { echo "Push failed, removing local tag"; git tag -d "$$TAG"; exit 1; }; \
	echo "==> Done. CI will run, Build & Release will wait for CI, then build + publish $$TAG"

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
