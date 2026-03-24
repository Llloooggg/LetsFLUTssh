APP_NAME := letsflutssh
VERSION := 0.7.1
BUILD_DIR := build
FLUTTER := flutter
UNAME := $(shell uname)
ARCH := $(shell uname -m)

# Platform detection
IS_LINUX := $(filter Linux,$(UNAME))
IS_MACOS := $(filter Darwin,$(UNAME))

.PHONY: all build run clean test analyze check gen watch deps upgrade doctor \
        build-linux build-windows build-macos build-apk build-aab build-ios \
        linux windows macos apk ios \
        package-linux package-windows release \
        deps-linux deps-macos deps-windows help

all: build

## ─── Development ──────────────────────────────────────────────

run: ## Run the app (debug, current platform)
	$(FLUTTER) run

run-release: ## Run the app (release mode)
	$(FLUTTER) run --release

build: ## Build for current platform (release)
ifdef IS_LINUX
	$(FLUTTER) build linux
else ifdef IS_MACOS
	$(FLUTTER) build macos
else
	@echo "Error: unsupported platform $(UNAME). Use an explicit target (build-linux, build-windows, etc.)"
	@exit 1
endif

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
## Short aliases: make linux, make macos, make apk, etc.

linux: build-linux
windows: build-windows
macos: build-macos
apk: build-apk
ios: build-ios

build-linux: ## Build for Linux
ifdef IS_LINUX
	$(FLUTTER) build linux
else
	@echo "Error: Linux builds require a Linux host (current: $(UNAME))"
	@exit 1
endif

build-windows: ## Build for Windows
	@echo "Error: Windows builds require a Windows host (current: $(UNAME))"
	@echo "Use: flutter build windows (on Windows)"
	@exit 1

build-macos: ## Build for macOS
ifdef IS_MACOS
	$(FLUTTER) build macos
else
	@echo "Error: macOS builds require a macOS host (current: $(UNAME))"
	@exit 1
endif

build-apk: ## Build Android APK
	$(FLUTTER) build apk

build-aab: ## Build Android App Bundle
	$(FLUTTER) build appbundle

build-ios: ## Build for iOS
ifdef IS_MACOS
	$(FLUTTER) build ios
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

package-windows: build-windows ## Build + zip for Windows
	@mkdir -p $(BUILD_DIR)/package
	cd build/windows/x64/runner/Release && \
		zip -r $(CURDIR)/$(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-windows-amd64.zip .
	@echo "Package: $(BUILD_DIR)/package/$(APP_NAME)-$(VERSION)-windows-amd64.zip"

release: package-linux ## Build all release packages
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
	rm -rf $(BUILD_DIR)/

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
