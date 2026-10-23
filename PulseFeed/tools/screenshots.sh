#!/bin/zsh
# Screenshot regression check: launches the built bundle in each design with the debug hooks and
# captures popover / window / widget / settings, then the welcome flow's seven screens, into docs/screenshots-<date>/. Then compare against
# the previous set with `make screenshots-diff` (tools/screenshot_diff.py: % pixels changed per
# surface, before|after|diff panels in <new>/_diff/). Needs a built bundle (make bundle) and Light
# appearance (the designs were drawn light). It quits a running copy and drives the app on the real
# database (your own stories and settings), not a throwaway one: a developer tool.
#   make screenshots            # all three designs
#   tools/screenshots.sh deck   # one design
set -e
cd "$(dirname "$0")/.."
APP="build/PulseFeed.app/Contents/MacOS/PulseFeed"
[ -x "$APP" ] || { echo "no bundle at $APP — run make bundle"; exit 1; }
OUT="../docs/screenshots-$(date +%Y-%m-%d)"; mkdir -p "$OUT"
DESIGNS=(${=${1:-nativePro deck stream}})   # ${=…} forces zsh to word-split the default
# The name the app shows once the main window steps it up to a regular app: the bundle's own.
NAME=$(/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' Info.plist 2>/dev/null || echo PulseFeed)
# The main window's title: the bundle's short name (falls back to the display name).
SHORT=$(/usr/libexec/PlistBuddy -c 'Print PFShortName' Info.plist 2>/dev/null || echo "$NAME")
WIN=$(mktemp).swift
cat > "$WIN" <<'SWIFT'
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list {
    // The process is "PulseFeed" as a utility and the bundle's display name once the main window steps it up.
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard owner == "PulseFeed" || owner == "__NAME__" else { continue }
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let wd = Int((b["Width"] as? Double) ?? 0), ht = Int((b["Height"] as? Double) ?? 0)
    print("\(w[kCGWindowNumber as String]!)\t\(wd)x\(ht)\t\(w[kCGWindowName as String] as? String ?? "")")
}
SWIFT
sed -i '' "s/__NAME__/$NAME/" "$WIN"   # the display name has no / or & in it
capture() { # $1 design, $2 settings pane
  pkill -x PulseFeed || true; sleep 1
  PULSEFEED_DESIGN=$1 PULSEFEED_DEBUG_OPEN=popover,window,widget nohup "$APP" >/dev/null 2>&1 & disown; sleep 11
  swift "$WIN" > /tmp/pf-windows.txt 2>/dev/null
  for kind in popover window widget; do
    case $kind in popover) pat="Popover preview";; window) pat="$SHORT";; widget) pat="320x200";; esac
    id=$(grep -F "$pat" /tmp/pf-windows.txt | head -1 | cut -f1)
    [ -n "$id" ] && screencapture -x -l "$id" "$OUT/$1-$kind.png" && echo "$1 $kind ok" || echo "$1 $kind MISSING"
  done
  pkill -x PulseFeed || true; sleep 1
  PULSEFEED_DESIGN=$1 PULSEFEED_DEBUG_OPEN=settings PULSEFEED_DEBUG_SETTINGS_PANE=$2 nohup "$APP" >/dev/null 2>&1 & disown; sleep 8
  swift "$WIN" > /tmp/pf-windows.txt 2>/dev/null
  id=$(grep -F "Settings" /tmp/pf-windows.txt | head -1 | cut -f1)
  [ -n "$id" ] && screencapture -x -l "$id" "$OUT/$1-settings.png" && echo "$1 settings ok" || echo "$1 settings MISSING"
  pkill -x PulseFeed || true
}
for d in $DESIGNS; do
  case $d in deck) pane=power;; stream) pane=general;; *) pane=sources;; esac
  capture "$d" "$pane"
done
# The welcome flow, each screen in dry run on a throwaway database (PULSEFEED_DEBUG_WELCOME): nothing is applied.
for step in 0 1 2 3 4 5 6; do
  pkill -x PulseFeed || true; sleep 1
  PULSEFEED_DEBUG_WELCOME=1 PULSEFEED_DEBUG_WELCOME_STEP=$step nohup "$APP" >/dev/null 2>&1 & disown; sleep 6
  swift "$WIN" > /tmp/pf-windows.txt 2>/dev/null
  id=$(grep -F "Welcome to News Feed" /tmp/pf-windows.txt | head -1 | cut -f1)
  [ -n "$id" ] && screencapture -x -l "$id" "$OUT/welcome-$step.png" && echo "welcome $step ok" || echo "welcome $step MISSING"
done
pkill -x PulseFeed || true
rm -f "$WIN"
echo "screenshots in $OUT"
