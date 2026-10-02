.PHONY: build run clean xcode resolve icons help dist

SWIFT := swift
CONFIG ?= debug
# Prefer classic SPM layout; fall back to Xcode-integrated `.build/debug` symlink.
BUILD_DIR_CLASSIC := .build/arm64-apple-macosx/$(CONFIG)
BUILD_DIR_XCODE := .build/$(CONFIG)
# Keep the .app under .build so Spotlight does not list a second copy beside /Applications.
APP_DIR := .build/app
APP_BUNDLE := $(APP_DIR)/SushiTray.app
APP_PATH := $(APP_BUNDLE)/Contents/MacOS/SushiTray
PLIST_PATH := $(APP_BUNDLE)/Contents/Info.plist
ICONS_DIR := $(APP_BUNDLE)/Contents/Resources
ICON_SRC := assets/icon.png
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' SushiTray/Info.plist 2>/dev/null || echo 0.0.0)
DIST_ZIP := dist/SushiTray-$(VERSION).zip

define resolve_binary
$(shell \
  CFG="$(CONFIG)"; \
  PROD=$$(echo "$$CFG" | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}'); \
  for p in \
    ".build/arm64-apple-macosx/$$CFG/SushiTray" \
    ".build/$$CFG/SushiTray" \
    ".build/out/Products/$$PROD/SushiTray" \
  ; do \
    if [ -x "$$p" ]; then echo "$$p"; exit 0; fi; \
  done; \
  echo ".build/arm64-apple-macosx/$$CFG/SushiTray")
endef

build:
	$(SWIFT) build -c release --product SushiTray

build-release: build

build-debug:
	$(SWIFT) build --product SushiTray

bundle:
	@$(MAKE) build-$(CONFIG)
	@echo "Creating .app bundle ($(CONFIG))..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(ICONS_DIR)
	@touch $(APP_DIR)/.metadata_never_index
	@BIN="$(resolve_binary)"; \
	  if [ ! -x "$$BIN" ]; then echo "Binary not found at $$BIN"; exit 1; fi; \
	  cp "$$BIN" $(APP_PATH)
	@chmod +x $(APP_PATH)
	@cp SushiTray/Info.plist $(APP_BUNDLE)/Contents/
	@cp -R SushiTray/Assets.xcassets $(ICONS_DIR)/
	@cp SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar.png $(ICONS_DIR)/statusbar.png 2>/dev/null || true
	@cp SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar@2x.png $(ICONS_DIR)/statusbar@2x.png 2>/dev/null || true
	@cp SushiTray/AppIcon.icns $(ICONS_DIR)/AppIcon.icns 2>/dev/null || true
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

icons:
	@echo "Generating status bar icons (original colors)..."
	@mkdir -p SushiTray/Assets.xcassets/StatusBarIcon.imageset
	@mkdir -p SushiTray/Assets.xcassets/AppIcon.appiconset
	@magick $(ICON_SRC) -resize 36x36 \
		SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar@2x.png
	@magick $(ICON_SRC) -resize 18x18 \
		SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar.png
	@echo "Generating app icons..."
	sips -z 16 16 $(ICON_SRC) --out SushiTray/Assets.xcassets/AppIcon.appiconset/app-16.png >/dev/null
	sips -z 32 32 $(ICON_SRC) --out SushiTray/Assets.xcassets/AppIcon.appiconset/app-32.png >/dev/null
	sips -z 128 128 $(ICON_SRC) --out SushiTray/Assets.xcassets/AppIcon.appiconset/app-128.png >/dev/null
	sips -z 256 256 $(ICON_SRC) --out SushiTray/Assets.xcassets/AppIcon.appiconset/app-256.png >/dev/null
	sips -z 512 512 $(ICON_SRC) --out SushiTray/Assets.xcassets/AppIcon.appiconset/app-512.png >/dev/null
	sips -z 1024 1024 $(ICON_SRC) --out SushiTray/Assets.xcassets/AppIcon.appiconset/app-1024.png >/dev/null
	@echo "Generating AppIcon.icns..."
	@rm -rf /tmp/SushiTray-AppIcon.iconset
	@mkdir -p /tmp/SushiTray-AppIcon.iconset
	@sips -z 16 16 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/icon_16x16.png >/dev/null
	@sips -z 32 32 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/diana.v@example.org >/dev/null
	@sips -z 32 32 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/icon_32x32.png >/dev/null
	@sips -z 64 64 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/ivan.p@example.net >/dev/null
	@sips -z 128 128 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/icon_128x128.png >/dev/null
	@sips -z 256 256 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/wendy.h@example.net >/dev/null
	@sips -z 256 256 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/icon_256x256.png >/dev/null
	@sips -z 512 512 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/wendy.h@example.net >/dev/null
	@sips -z 512 512 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/icon_512x512.png >/dev/null
	@sips -z 1024 1024 $(ICON_SRC) --out /tmp/SushiTray-AppIcon.iconset/walt.e@example.net >/dev/null
	@iconutil -c icns /tmp/SushiTray-AppIcon.iconset -o SushiTray/AppIcon.icns
	@echo "Icons generated."

help:
	@echo "SushiTray — macOS menu bar app for sushi serve"
	@echo ""
	@echo "Usage: make <target>"
	@echo "  build / build-debug / build-release"
	@echo "  bundle / bundle-debug / bundle-release"
	@echo "  run / run-release"
	@echo "  dist     release zip → dist/SushiTray-\$$(version).zip"
	@echo "  icons    regenerate from assets/icon.png"
	@echo "  clean / resolve / xcode"
