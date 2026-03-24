APP_NAME := letsflutssh
VERSION := 0.1.0
BUILD_DIR := build
FLUTTER := flutter

.PHONY: all build run clean test analyze check gen watch deps upgrade doctor \
        build-linux build-windows build-macos build-apk build-aab build-ios \
        package-linux package-windows release \
        deps-linux deps-macos deps-windows help

all: build

## ─── Development ──────────────────────────────────────────────

run: ## Run the app (debug, current platform)
	$(FLUTTER) run

run-release: ## Run the app (release mode)
	$(FLUTTER) run --release

build: ## Build for current platform (release)
	$(FLUTTER) build $(shell $(FLUTTER) devices --machine 2>/dev/null | head -1 | grep -oP '"targetPlatform":\s*"\K[^"]+' || echo linux) --release

test: ## Run all tests
	$(FLUTTER) test

analyze: ## Run Dart analyzer
	$(FLUTTER) analyze

check: analyze test ## Run analyzer + tests

gen: ## Code generation (freezed, json_serializable)
	dart run build_runner build --delete-conflicting-outputs

watch: ## Watch mode code generation
	dart run build_runner watch --delete-conflicting-outputs

## ─── Platform Builds ──────────────────────────────────────────

build-linux: ## Build for Linux (release)
	$(FLUTTER) build linux --release

build-windows: ## Build for Windows (release)
	$(FLUTTER) build windows --release

build-macos: ## Build for macOS (release)
	$(FLUTTER) build macos --release

build-apk: ## Build Android APK (release)
	$(FLUTTER) build apk --release

build-aab: ## Build Android App Bundle (release)
	$(FLUTTER) build appbundle --release

build-ios: ## Build for iOS (release)
	$(FLUTTER) build ios --release

## ─── Packaging ────────────────────────────────────────────────

package-linux: build-linux ## Build + tar.gz for Linux
	@mkdir -p $(BUILD_DIR)/package
	cd build/linux/x64/release/bundle && \
		tar czf $(CURDIR)/$(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-linux-amd64.tar.gz .
	@echo "Package: $(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-linux-amd64.tar.gz"

package-windows: build-windows ## Build + zip for Windows
	@mkdir -p $(BUILD_DIR)/package
	cd build/windows/x64/runner/Release && \
		zip -r $(CURDIR)/$(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-windows-amd64.zip .
	@echo "Package: $(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-windows-amd64.zip"

release: package-linux ## Build all release packages
	@echo "Built packages:"
	@ls -lh $(BUILD_DIR)/package/
	@echo "Note: Windows/macOS builds require respective host OS"

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
	rm -rf $(BUILD_DIR)/

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
