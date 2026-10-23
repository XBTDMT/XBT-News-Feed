APP_NAME = PulseFeed
# What the installed app is called in /Applications (the public export sets "News Feed"); Info.plist carries the same name.
APP_DISPLAY_NAME ?= News Feed
# Where make public-images puts the README's pictures: public/ ships at the public copy's root, so the export sets ../images.
PUBLIC_IMAGES ?= ../images
BUNDLE_DIR = build/$(APP_NAME).app
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
FRAMEWORKS_DIR = $(CONTENTS_DIR)/Frameworks
BUILD_CONFIG = debug
ARCH = arm64-apple-macosx

# Where SwiftPM actually puts the products. The swift-build backend on this toolchain writes to
# .build/out/Products/Debug, NOT .build/arm64-apple-macosx/debug — the old hardcoded path kept a
# stale March 2026 binary that `make bundle` shipped for months. Ask SwiftPM instead of guessing.
# The flavour: `make showcase` bundles the public one (`BUILD_PATH=.build-public SWIFT_FLAGS="-Xswiftc -DPUBLIC_BUILD"`).
BUILD_PATH ?= .build
SWIFT_FLAGS ?=
BIN_DIR = $(shell swift build -c $(BUILD_CONFIG) --build-path $(BUILD_PATH) $(SWIFT_FLAGS) --show-bin-path 2>/dev/null)

# XCTest needs a full Xcode (Command Line Tools lack it: "no such module 'XCTest'"). Use whichever
# Xcode `xcode-select -p` points at, so the build works on any Mac; override with `make DEV=…`.
DEV ?= $(shell xcode-select -p)

.PHONY: build test test-public bundle run clean release install fix-icon screenshots screenshots-diff icon check-catalog showcase public-images

# Compile via SPM
build:
	swift build -c $(BUILD_CONFIG) --build-path $(BUILD_PATH) $(SWIFT_FLAGS)

# Run the smoke tests (with the XCTest of the Xcode `xcode-select -p` points at, via DEVELOPER_DIR). The test bundle links
# Sparkle transitively (via `@testable import PulseFeed`), but SwiftPM doesn't add it to the test
# runner's @rpath — so point the dynamic loader at the built products dir where Sparkle.framework lands.
test:
	DEVELOPER_DIR=$(DEV) swift build --build-tests
	@SPK="$$(find $(CURDIR)/.build -maxdepth 6 -type d -path '*Products/Debug/Sparkle.framework' | head -1)"; \
	DEVELOPER_DIR=$(DEV) DYLD_FRAMEWORK_PATH="$$(dirname "$$SPK")" swift test

# The public flavour (-DPUBLIC_BUILD), in its own build folder; in the public copy it builds what make test builds
test-public:
	DEVELOPER_DIR=$(DEV) swift build --build-tests --build-path .build-public -Xswiftc -DPUBLIC_BUILD
	@SPK="$$(find $(CURDIR)/.build-public -maxdepth 6 -type d -path '*Products/Debug/Sparkle.framework' | head -1)"; \
	DEVELOPER_DIR=$(DEV) DYLD_FRAMEWORK_PATH="$$(dirname "$$SPK")" swift test --build-path .build-public -Xswiftc -DPUBLIC_BUILD

# Create .app bundle from compiled binary
bundle: build
	@echo "Creating $(APP_NAME).app bundle..."
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)
	mkdir -p $(FRAMEWORKS_DIR)
	@test -n "$(BIN_DIR)" -a -f "$(BIN_DIR)/$(APP_NAME)" || { echo "ERROR: no binary at '$(BIN_DIR)/$(APP_NAME)' (swift build --show-bin-path)"; exit 1; }
	@STALE="$$(find PulseFeed -name '*.swift' -newer "$(BIN_DIR)/$(APP_NAME)" | head -1)"; \
	if [ -n "$$STALE" ]; then echo "ERROR: binary is older than $$STALE — build did not produce a fresh product"; exit 1; fi
	cp "$(BIN_DIR)/$(APP_NAME)" $(MACOS_DIR)/
	cp Info.plist $(CONTENTS_DIR)/
	cp $(APP_NAME).entitlements $(RESOURCES_DIR)/ 2>/dev/null || true
	# ── App Icon: generate .icns from source PNG ──
	@echo "Building app icon..."
	@ICON_SOURCE=""; \
	if [ -f "PulseFeed/Resources/AppIcon.iconset/icon_512x512@2x.png" ]; then \
		ICON_SOURCE="PulseFeed/Resources/AppIcon.iconset/icon_512x512@2x.png"; \
	elif [ -f "PulseFeed/Resources/icon1024.png" ]; then \
		ICON_SOURCE="PulseFeed/Resources/icon1024.png"; \
	elif [ -f "PulseFeed/Resources/AppIcon.png" ]; then \
		ICON_SOURCE="PulseFeed/Resources/AppIcon.png"; \
	fi; \
	if [ -n "$$ICON_SOURCE" ]; then \
		echo "  Source: $$ICON_SOURCE"; \
		ICONSET_DIR="build/_AppIcon.iconset"; \
		rm -rf "$$ICONSET_DIR"; \
		mkdir -p "$$ICONSET_DIR"; \
		sips -z 16 16     "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_16x16.png"      > /dev/null 2>&1; \
		sips -z 32 32     "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null 2>&1; \
		sips -z 32 32     "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_32x32.png"       > /dev/null 2>&1; \
		sips -z 64 64     "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_32x32@2x.png"    > /dev/null 2>&1; \
		sips -z 128 128   "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_128x128.png"     > /dev/null 2>&1; \
		sips -z 256 256   "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_128x128@2x.png"  > /dev/null 2>&1; \
		sips -z 256 256   "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_256x256.png"     > /dev/null 2>&1; \
		sips -z 512 512   "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_256x256@2x.png"  > /dev/null 2>&1; \
		sips -z 512 512   "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_512x512.png"     > /dev/null 2>&1; \
		sips -z 1024 1024 "$$ICON_SOURCE" --out "$$ICONSET_DIR/icon_512x512@2x.png"  > /dev/null 2>&1; \
		iconutil -c icns "$$ICONSET_DIR" -o "$(RESOURCES_DIR)/AppIcon.icns" && \
		echo "  AppIcon.icns created ($$(ls -la "$(RESOURCES_DIR)/AppIcon.icns" | awk '{print $$5}') bytes)" || \
		echo "  iconutil FAILED"; \
		rm -rf "$$ICONSET_DIR"; \
	elif [ -f "PulseFeed/Resources/AppIcon.icns" ]; then \
		cp "PulseFeed/Resources/AppIcon.icns" "$(RESOURCES_DIR)/AppIcon.icns"; \
		echo "  Pre-built AppIcon.icns copied"; \
	else \
		echo "  No icon source found! Place a 1024x1024 PNG at PulseFeed/Resources/icon1024.png"; \
	fi
	# Copy Readability.js for reader mode
	@mkdir -p $(RESOURCES_DIR)/Catalog && cp PulseFeed/Resources/Catalog/*.json $(RESOURCES_DIR)/Catalog/ && echo "Catalog copied"
	# The welcome flow's Look step thumbnails (made by make public-images) — LookThumbnail reads Contents/Resources/Welcome
	@mkdir -p $(RESOURCES_DIR)/Welcome && cp PulseFeed/Resources/Welcome/*.png $(RESOURCES_DIR)/Welcome/ 2>/dev/null && echo "Welcome thumbnails copied" || true
	@mkdir -p $(RESOURCES_DIR)/JS
	@cp PulseFeed/Resources/JS/*.js $(RESOURCES_DIR)/JS/ 2>/dev/null && echo "Readability.js copied" || true
	# Copy menu bar icon (lives in the SPM target's Resources dir)
	@for p in PulseFeed/Resources/menubar_icon.png PulseFeed/PulseFeed/Resources/menubar_icon.png; do \
		if [ -f "$$p" ]; then cp "$$p" "$(RESOURCES_DIR)/menubar_icon.png"; echo "Menu bar icon copied"; break; fi; \
	done
	# Bundled fonts (Manrope for the Stream design; OFL) — Fonts.registerBundledFonts() reads Contents/Resources/Fonts
	@mkdir -p $(RESOURCES_DIR)/Fonts && cp PulseFeed/Resources/Fonts/*.ttf PulseFeed/Resources/Fonts/OFL.txt $(RESOURCES_DIR)/Fonts/ 2>/dev/null && echo "Fonts copied" || true
	# Crash-recovery launchd plist (Settings > Crash Recovery reads it from the bundle)
	@cp PulseFeed/Resources/com.pulsefeed.feed.plist $(RESOURCES_DIR)/ 2>/dev/null && echo "launchd plist copied" || true
	# Embed Sparkle framework (dynamic library, linked via @rpath)
	cp -R "$(BIN_DIR)/Sparkle.framework" $(FRAMEWORKS_DIR)/
	# Fix rpath so the binary finds Sparkle in Contents/Frameworks
	install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/$(APP_NAME) 2>/dev/null || true
	@echo "Bundle created at $(BUNDLE_DIR)"

# Build + bundle + deep sign + register + launch (no sudo; make fix-icon clears the icon caches)
run: bundle
	@xattr -cr $(BUNDLE_DIR)   # the app sets a Finder custom icon (xattr) on itself at runtime; codesign refuses it
	@codesign --force --deep --sign - $(BUNDLE_DIR)
	@echo "Code signed (ad-hoc with --deep)"
	@echo "Registering with LaunchServices (no password needed; a stale icon is make fix-icon, which uses sudo)..."
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(BUNDLE_DIR)
	@echo "Launching via open (required for LaunchServices registration)..."
	@open $(BUNDLE_DIR)
	@echo "App launched. Check System Settings > Notifications for icon."

# Regenerate the master icon (PulseFeed/Resources/icon1024.png) from the app's own drawing
# (AppIconStyle.master via PULSEFEED_DEBUG_EXPORT_ICON), then rebuild so AppIcon.icns — what Finder,
# the Dock and notification banners show — follows. Run after touching XTileGlyph or the master's art.
icon: bundle
	@PULSEFEED_DEBUG_EXPORT_ICON="$(CURDIR)/PulseFeed/Resources/icon1024.png" "$(MACOS_DIR)/$(APP_NAME)" | grep '\[Icon\] exported'
	@cp PulseFeed/Resources/icon1024.png Resources/icon1024.png
	@$(MAKE) bundle

# Screenshot regression check: every surface of every design into docs/screenshots-<date>/ (needs the bundle)
screenshots: bundle
	@tools/screenshots.sh

# The README's pictures: the app's own surfaces drawn offscreen on the fictional ShowcaseFixture (no screen
# recording), 2x PNGs into build/showcase/. The PUBLIC flavour, named "News Feed" as the public copy is, in
# build/Showcase.app re-signed as com.pulsefeed.showcase: its own defaults domain (cleared first) and a
# throwaway database, never the owner's; under any other bundle id the binary refuses with exit 2.
SHOWCASE_APP = build/Showcase.app
SHOWCASE_OUT = build/showcase
showcase:
	@rm -rf $(SHOWCASE_APP) $(SHOWCASE_OUT)
	@$(MAKE) --no-print-directory bundle BUNDLE_DIR=$(SHOWCASE_APP) BUILD_PATH=.build-public SWIFT_FLAGS="-Xswiftc -DPUBLIC_BUILD"
	@/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.pulsefeed.showcase' \
		-c 'Set :CFBundleDisplayName News Feed' -c 'Set :CFBundleName News Feed' -c 'Set :PFShortName News Feed' \
		$(SHOWCASE_APP)/Contents/Info.plist
	@xattr -cr $(SHOWCASE_APP) && codesign --force --deep --sign - $(SHOWCASE_APP)
	@defaults delete com.pulsefeed.showcase 2>/dev/null || true
	@for d in nativePro deck stream; do \
		echo "Showcase: $$d"; \
		PULSEFEED_DESIGN=$$d PULSEFEED_FORCE_TIER=ac PULSEFEED_RENDER_SHOWCASE="$(CURDIR)/$(SHOWCASE_OUT)" \
			$(SHOWCASE_APP)/Contents/MacOS/$(APP_NAME) || exit 1; \
	done
	@ls $(SHOWCASE_OUT)

# The public README's pictures and the Look step's thumbnails, from make showcase's composed set
# (ShowcaseComposer, run after the last design): the README's eight into $(PUBLIC_IMAGES)/, look-*.png into
# PulseFeed/Resources/Welcome/ (bundled by make bundle). The X post set and its clip stay in build/showcase/x-post/.
# One pass: the showcase draws the thumbnails from its own popovers before its welcome renders and shows those
# (LookThumbnail.directoryOverride), never the bundle's copy from an earlier run.
public-images: showcase
	@mkdir -p $(PUBLIC_IMAGES) PulseFeed/Resources/Welcome
	@for f in $(SHOWCASE_OUT)/composed/*; do \
		case "$$(basename $$f)" in look-*) cp "$$f" PulseFeed/Resources/Welcome/ ;; *) cp "$$f" $(PUBLIC_IMAGES)/ ;; esac; \
	done
	@ls -l $(PUBLIC_IMAGES) PulseFeed/Resources/Welcome

# Compare two screenshot sets: % of pixels changed per surface, before|after|diff panels for the
# changed ones in $(NEW)/_diff/, exit 1 if any surface moved more than 2%. Defaults to the two newest
# docs/screenshots-* folders; override with BASE=… NEW=…, pass flags with DIFF_ARGS=--no-fail etc.
SHOT_DIRS = $(shell ls -d ../docs/screenshots-* 2>/dev/null | sort | tail -2)
BASE ?= $(word 1,$(SHOT_DIRS))
NEW ?= $(word 2,$(SHOT_DIRS))
DIFF_ARGS ?=
screenshots-diff:
	@test -n "$(BASE)" -a -n "$(NEW)" -a "$(BASE)" != "$(NEW)" || { echo "ERROR: need two docs/screenshots-* folders (or pass BASE=… NEW=…)"; exit 1; }
	@echo "Comparing $(BASE) -> $(NEW)"
	@python3 tools/screenshot_diff.py "$(BASE)" "$(NEW)" $(DIFF_ARGS)

# Install to /Applications
install: bundle
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(APP_DISPLAY_NAME).app" 2>/dev/null || true
	@cp -R $(BUNDLE_DIR) "/Applications/$(APP_DISPLAY_NAME).app"
	@xattr -cr "/Applications/$(APP_DISPLAY_NAME).app"
	@codesign --force --deep --sign - "/Applications/$(APP_DISPLAY_NAME).app"
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$(APP_DISPLAY_NAME).app"
	@echo "Installed to /Applications/$(APP_DISPLAY_NAME).app"
	@echo "Run with: open '/Applications/$(APP_DISPLAY_NAME).app'"

# Nuke IconServices bitmap cache (one-time fix for notification banner icon)
fix-icon:
	@echo "Nuking IconServices cache (requires sudo)..."
	@sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
	@sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -or -name com.apple.iconservices \) -exec rm -rf {} + 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@killall Finder 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(BUNDLE_DIR)
	@echo ""
	@echo "Icon caches cleared. You MUST restart your Mac now."
	@echo "   After restart, run: make run"
	@echo "   The notification icon will appear correctly."

# Release build + bundle
release:
	$(MAKE) bundle BUILD_CONFIG=release
	@echo "Release bundle at $(BUNDLE_DIR)"

# Clean everything
clean:
	swift package clean
	rm -rf build/
	@echo "Cleaned"

# Fetch and parse every catalog feed source with the app's own code; stamp the passes into catalog.json.
# Signed like `run`: an unsigned or stale-signed bundle binary is killed at launch (exit 137, no output).
check-catalog: bundle
	@xattr -cr $(BUNDLE_DIR) && codesign --force --deep --sign - $(BUNDLE_DIR)
	@PULSEFEED_CHECK_CATALOG="$(CURDIR)/PulseFeed/Resources/Catalog/catalog.json:$(CURDIR)/build/catalog-check.json" \
	PULSEFEED_CHECK_CATALOG_WRITE=1 $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
