.PHONY: build run clean xcode resolve icons help

SWIFT := swift
CONFIG ?= debug
# Prefer classic SPM layout; fall back to Xcode-integrated `.build/debug` symlink.
BUILD_DIR_CLASSIC := .build/arm64-apple-macosx/$(CONFIG)
BUILD_DIR_XCODE := .build/$(CONFIG)
APP_BUNDLE := SushiTray.app
APP_PATH := $(APP_BUNDLE)/Contents/MacOS/SushiTray
PLIST_PATH := $(APP_BUNDLE)/Contents/Info.plist
ICONS_DIR := $(APP_BUNDLE)/Contents/Resources
ICON_SRC := assets/sushi-icon.png

define resolve_binary
$(shell \
  if [ -x "$(BUILD_DIR_CLASSIC)/SushiTray" ]; then echo "$(BUILD_DIR_CLASSIC)/SushiTray"; \
  elif [ -x "$(BUILD_DIR_XCODE)/SushiTray" ]; then echo "$(BUILD_DIR_XCODE)/SushiTray"; \
  else echo "$(BUILD_DIR_CLASSIC)/SushiTray"; fi)
endef

BINARY := $(resolve_binary)

build:
	$(SWIFT) build -c release --product SushiTray

build-release: build

build-debug:
	$(SWIFT) build --product SushiTray

bundle: build-$(CONFIG)
	@echo "Creating .app bundle..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(ICONS_DIR)
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

bundle-debug: CONFIG = debug
bundle-debug: bundle

bundle-release: CONFIG = release
bundle-release: bundle

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
	@rm -rf $(APP_BUNDLE)

resolve:
	$(SWIFT) package resolve

xcode:
	open Package.swift

icons:
	@echo "Generating status bar icons..."
	@mkdir -p SushiTray/Assets.xcassets/StatusBarIcon.imageset
	@mkdir -p SushiTray/Assets.xcassets/AppIcon.appiconset
	sips -z 40 40 $(ICON_SRC) --out SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar@2x.png >/dev/null
	sips -z 20 20 $(ICON_SRC) --out SushiTray/Assets.xcassets/StatusBarIcon.imageset/statusbar.png >/dev/null
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
	@echo "  icons    regenerate from assets/sushi-icon.png"
	@echo "  clean / resolve / xcode"
