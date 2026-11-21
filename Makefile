.PHONY: build run clean xcode resolve icons help dist test release

SWIFT := swift
SWIFT_FLAGS ?=
RELEASE_BRANCH ?= main
export VERSION RELEASE_BRANCH
CONFIG ?= debug
# Keep the .app under .build so Spotlight does not list a second copy beside /Applications.
APP_DIR := .build/app
APP_BUNDLE := $(APP_DIR)/SushiTray.app
APP_PATH := $(APP_BUNDLE)/Contents/MacOS/SushiTray
PLIST_PATH := $(APP_BUNDLE)/Contents/Info.plist
ICONS_DIR := $(APP_BUNDLE)/Contents/Resources
ICON_SRC := assets/icon.svg
ICON_PNG := assets/icon.png
APP_ICON_SET := SushiTray/Assets.xcassets/AppIcon.appiconset
STATUS_ICON_SET := SushiTray/Assets.xcassets/StatusBarIcon.imageset
APP_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' SushiTray/Info.plist 2>/dev/null || echo 0.0.0)
DIST_ZIP := dist/SushiTray-$(APP_VERSION).zip

build:
	$(SWIFT) build $(SWIFT_FLAGS) -c release --product SushiTray

build-release: build

build-debug:
	$(SWIFT) build $(SWIFT_FLAGS) --product SushiTray

bundle:
	@$(MAKE) build-$(CONFIG)
	@echo "Creating .app bundle ($(CONFIG))..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(ICONS_DIR)
	@touch $(APP_DIR)/.metadata_never_index
	@BIN="$$($(SWIFT) build $(SWIFT_FLAGS) -c $(CONFIG) --show-bin-path)/SushiTray"; \
	  if [ ! -x "$$BIN" ]; then echo "Binary not found at $$BIN"; exit 1; fi; \
	  cp "$$BIN" $(APP_PATH)
	@chmod +x $(APP_PATH)
	@cp SushiTray/Info.plist $(APP_BUNDLE)/Contents/
	@cp -R SushiTray/Assets.xcassets $(ICONS_DIR)/
	@cp SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar.png $(ICONS_DIR)/statusbar.png 2>/dev/null || true
	@cp SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar@2x.png $(ICONS_DIR)/statusbar@2x.png 2>/dev/null || true
	@cp SushiTray/AppIcon.icns $(ICONS_DIR)/AppIcon.icns 2>/dev/null || true
	@# Ad-hoc sign the whole .app so Gatekeeper does not report it as "damaged"
	@# after download (linker-signed binary alone leaves Info.plist unbound).
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Bundle ready: $(APP_BUNDLE)"

bundle-debug:
	@$(MAKE) CONFIG=debug bundle

bundle-release:
	@$(MAKE) CONFIG=release bundle

run: bundle-debug
	@echo ""
	@echo "Launching SushiTray..."
	@open $(APP_BUNDLE)

run-release: bundle-release
	@echo ""
	@echo "Launching SushiTray (release)..."
	@open $(APP_BUNDLE)

clean:
	$(SWIFT) package clean
	@rm -rf $(APP_DIR) SushiTray.app dist

resolve:
	$(SWIFT) package resolve

xcode:
	open Package.swift

# Release zip for GitHub Releases / Homebrew Cask (arm64).
dist: bundle-release
	@mkdir -p dist
	@rm -f $(DIST_ZIP)
	@ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(DIST_ZIP)
	@echo "Created $(DIST_ZIP)"
	@shasum -a 256 $(DIST_ZIP)

test:
	$(SWIFT) test $(SWIFT_FLAGS) -Xswiftc -warnings-as-errors

# Requires committed release-notes/$(VERSION).md and a clean tracked worktree.
release:
	@python3 scripts/release.py

icons:
	@mkdir -p $(APP_ICON_SET) $(STATUS_ICON_SET)
	@magick -background none $(ICON_SRC) -strip PNG32:$(APP_ICON_SET)/app-1024.png
	@set -e; for size in 16 32 64 128 256 512; do \
		magick $(APP_ICON_SET)/app-1024.png -resize "$${size}x$${size}" \
			-strip PNG32:$(APP_ICON_SET)/app-$$size.png; \
	done
	@cp $(APP_ICON_SET)/app-256.png $(ICON_PNG)
	@magick $(APP_ICON_SET)/app-1024.png -resize 18x18 -strip PNG32:$(STATUS_ICON_SET)/statusbar.png
	@magick $(APP_ICON_SET)/app-1024.png -resize 36x36 -strip PNG32:$(STATUS_ICON_SET)/statusbar@2x.png
	@set -e; tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
		iconset="$$tmp/AppIcon.iconset"; mkdir "$$iconset"; \
		for size in 16 32 128 256 512; do \
			doubled=$$((size * 2)); \
			cp "$(APP_ICON_SET)/app-$$size.png" "$$iconset/icon_$${size}x$${size}.png"; \
			cp "$(APP_ICON_SET)/app-$$doubled.png" "$$iconset/icon_$${size}x$${size}@2x.png"; \
		done; \
		iconutil -c icns "$$iconset" -o SushiTray/AppIcon.icns
	@echo "Icons generated."

help:
	@echo "SushiTray — macOS menu bar app for sushi serve"
	@echo ""
	@echo "Usage: make <target>"
	@echo "  build / build-debug / build-release"
	@echo "  bundle / bundle-debug / bundle-release"
	@echo "  run / run-release"
	@echo "  dist     release zip → dist/SushiTray-\$$(version).zip"
	@echo "  test     run regression tests"
	@echo "  release VERSION=X.Y.Z  test, build, bump, commit, tag and push"
	@echo "  icons    regenerate from assets/icon.svg"
	@echo "  clean / resolve / xcode"
