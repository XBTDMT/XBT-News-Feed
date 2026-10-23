# Building News Feed

News Feed is a Swift Package Manager executable, not an Xcode project: a `Makefile` builds it, wraps the binary in
an app bundle and signs it ad hoc. It has been built on one Mac, Apple Silicon (Intel is untested), with Xcode
27.1 (Swift 6.4) on macOS 27.

## What you need

- A Mac: Apple Silicon (Intel is untested). The bundle declares macOS 15 or later, but only macOS 27 is tested.
- **Xcode**, with `xcode-select -p` pointing at it (for example `/Applications/Xcode.app/Contents/Developer`), not
  at the Command Line Tools: the tests need XCTest, which only a full Xcode has. The Makefile uses whichever Xcode
  `xcode-select -p` names; `make DEV=/path/to/Xcode.app/Contents/Developer test` picks another.
- Network access the first time, so SwiftPM can fetch the packages pinned in `PulseFeed/Package.resolved`.
- No Apple Developer account. The app is signed ad hoc on your Mac.

For the AI features (summaries, the written recap, the daily brief), the Mac also needs macOS 26 or later with
Apple Intelligence switched on in System Settings. Without it the app works, with the plain fallbacks described in
the [README](../README.md).

## Build and run

```sh
git clone https://github.com/XBTDMT/XBT-News-Feed.git
cd XBT-News-Feed/PulseFeed
make run
```

`make run` compiles (`swift build`), assembles `build/PulseFeed.app` (icon, catalog, Readability.js, the Manrope
font), signs it ad hoc, registers it with Launch Services and opens it. It asks for no password.

If notification banners later show a blank or stale icon, `make fix-icon` clears macOS's icon caches. That one
uses `sudo` (so the terminal asks for your password), restarts the Dock and Finder, and asks you to restart the
Mac afterwards.

Notifications need the app to run from a bundle, which is why the build goes through `make run` rather than
`swift run`. On the first launch the welcome flow opens; its Alerts step is where macOS asks for notification
permission.

Only one copy runs at a time: a second launch of the same bundle identifier (`com.pulsefeed.app`) quits itself, so
quit the running copy before you open another.

## Install

```sh
make install
```

builds, copies the bundle to `/Applications/News Feed.app` (replacing an older copy there), signs it ad hoc and
registers it. Open it from `/Applications`; Settings › General › Startup has **Launch at Login**.

`make bundle` stops with an error when any `.swift` file is newer than the binary it would ship, so a stale build
never reaches the bundle; run `make bundle` (or `make run`) again after a failed compile.

## Tests

```sh
make test
```

runs the XCTest suite with the Xcode `xcode-select -p` points at (a few minutes). The tests use in-memory or
temporary databases, never the app's own. A few skip by design: the on-device model tests when Apple
Intelligence is unavailable, and one, AIProfileTests' frozen-prompt test, that reads a fixture file that is not
part of this repository. Expect 0 failures.

## Other targets

| Target | What it does |
|---|---|
| `make build` | `swift build` only. |
| `make bundle` | Build and assemble `build/PulseFeed.app`, unsigned. |
| `make release` | The same bundle from a release (optimised) build. |
| `make showcase` / `make public-images` | Redraws the README's images from the app's own views on sample data. |
| `make check-catalog` | Fetches every feed in `PulseFeed/Resources/Catalog/catalog.json` (in the package folder, so `PulseFeed/PulseFeed/Resources/Catalog/catalog.json` from the clone's root) with the app's own fetcher and parser and stamps the ones that pass into the file (JSON APIs and sockets are skipped; a report goes to `build/catalog-check.json`). It runs the bundled binary against a throwaway database. |
| `make icon` | Redraws the app icon from the app's own drawing code. |
| `make fix-icon` | Clears macOS's icon caches with `sudo` when banners show a stale icon; restart the Mac afterwards. |
| `make clean` | `swift package clean` and removes `build/`. |

`make screenshots` and `make screenshots-diff` are a screenshot regression check for development; they need
screen-recording permission for the terminal. `make screenshots` quits a running News Feed and drives the app on
your own data, so it is a developer tool; its sets go to `docs/screenshots-<date>/`, which `.gitignore` keeps out.

## Where your data lives

| What | Where |
|---|---|
| Stories, read marks, sources, follows | `~/Library/Application Support/PulseFeed/pulsefeed.sqlite` (with its `-wal` and `-shm` files) |
| Your optional keys | `~/Library/Application Support/PulseFeed/.finnhub-key`, `.balldontlie-key`, `.claude-api-key` |
| Settings (design, alert mode, rules, prices…) | the preferences domain `com.pulsefeed.app` |
| Auto-restart on crash, if you switched it on | `~/Library/LaunchAgents/com.pulsefeed.feed.plist` |

The folder is named after the project's internal name, PulseFeed. Tool runs (`make check-catalog`, `make showcase`)
use a temporary database instead and never open this one.

## Removing it

1. In Settings › General, switch off **Auto-restart on crash** (it unloads and deletes the launch agent) and
   **Launch at Login**.
2. Quit the app.
3. Remove the app, its data and its settings:

   ```sh
   rm -rf "/Applications/News Feed.app"
   rm -rf ~/Library/Application\ Support/PulseFeed
   defaults delete com.pulsefeed.app
   ```

   If you ran `make showcase`, also `defaults delete com.pulsefeed.showcase`. macOS may keep caches for the app
   under `~/Library/Caches/com.pulsefeed.app` and `~/Library/WebKit/com.pulsefeed.app`; they can go too.
4. macOS keeps its own record of the app's notification permission (System Settings › Notifications); none of
   these steps touches it.
5. Delete the clone, which holds the build products in `PulseFeed/.build/` and `PulseFeed/build/`.
