#!/usr/bin/env python3
"""Screenshot regression diff for the sets `make screenshots` writes to docs/screenshots-<date>/.

Pairs PNGs by basename across BASE_DIR and NEW_DIR. If a pair's sizes differ it is reported as
"size changed" and counted 100% changed (nothing is resized); otherwise the share of pixels whose
largest per-channel delta (R, G, B or A) exceeds --tolerance is measured, with the bounding box of
the changed region. Every pair changed by more than 0.05% gets a "before | after | diff" panel in
--out (default NEW_DIR/_diff/); the diff panel is the after image dimmed with changed pixels red.
Exit 1 if any pair exceeds --threshold percent (unless --no-fail), else 0.

  python3 tools/screenshot_diff.py BASE_DIR NEW_DIR [--out DIR] [--threshold 2.0] [--tolerance 24] [--no-fail]
  make screenshots-diff [BASE=dir] [NEW=dir]     # defaults: the two newest docs/screenshots-* folders
Needs python3 + Pillow, nothing else.
"""
import argparse
import os
import sys
from functools import reduce

from PIL import Image, ImageChops

PANEL_MIN_PCT = 0.05          # a pair changed by more than this gets a before|after|diff panel
GAP = 12                      # px between the three panels
GAP_COLOUR = (40, 40, 40, 255)
RED = (255, 0, 0, 255)


def pngs(d):
    return {f: os.path.join(d, f) for f in os.listdir(d)
            if f.lower().endswith(".png") and os.path.isfile(os.path.join(d, f))}


def change_mask(before, after, tolerance):
    """L-mode mask: 255 where max(|dR|,|dG|,|dB|,|dA|) > tolerance, else 0."""
    peak = reduce(ImageChops.lighter, ImageChops.difference(before, after).split())
    return peak.point(lambda v: 255 if v > tolerance else 0)


def diff_panel(after, mask):
    r, g, b, a = after.split()                   # dim RGB only; keep the alpha (transparent corners stay clear)
    dimmed = Image.merge("RGBA", [Image.eval(c, lambda v: v // 3) for c in (r, g, b)] + [a])
    return Image.composite(Image.new("RGBA", after.size, RED), dimmed, mask)


def write_panel(path, before, after, mask):
    canvas = Image.new("RGBA", (before.width + 2 * after.width + 2 * GAP,
                                max(before.height, after.height)), GAP_COLOUR)
    x = 0
    for img in (before, after, diff_panel(after, mask)):
        canvas.paste(img, (x, 0))
        x += img.width + GAP
    canvas.save(path)


def compare(name, base_path, new_path, tolerance, out):
    """Returns (name, pct_changed, note, panel_path_or_None)."""
    before = Image.open(base_path).convert("RGBA")
    after = Image.open(new_path).convert("RGBA")
    if before.size != after.size:
        pct = 100.0
        note = "size changed %dx%d → %dx%d" % (*before.size, *after.size)
        mask = Image.new("L", after.size, 255)
    else:
        mask = change_mask(before, after, tolerance)
        pct = 100.0 * mask.histogram()[255] / (after.width * after.height)
        box = mask.getbbox()
        if box is None:
            note = "unchanged"
        else:
            x0, y0, x1, y1 = box
            note = "bbox %d,%d → %d,%d (%dx%d px)" % (x0, y0, x1, y1, x1 - x0, y1 - y0)
    panel = None
    if pct > PANEL_MIN_PCT:
        os.makedirs(out, exist_ok=True)           # created lazily so an unchanged run leaves no folder
        panel = os.path.join(out, name)
        write_panel(panel, before, after, mask)
    return name, pct, note, panel


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("base_dir")
    ap.add_argument("new_dir")
    ap.add_argument("--out", help="where the before|after|diff panels go (default NEW_DIR/_diff/)")
    ap.add_argument("--threshold", type=float, default=2.0,
                    help="%% of pixels changed above which a pair fails (default 2.0)")
    ap.add_argument("--tolerance", type=int, default=24,
                    help="per-channel delta (0-255) a pixel must exceed to count as changed (default 24)")
    ap.add_argument("--no-fail", action="store_true", help="always exit 0")
    a = ap.parse_args()
    for d in (a.base_dir, a.new_dir):
        if not os.path.isdir(d):
            sys.exit("screenshot_diff: not a directory: %s" % d)
    out = a.out or os.path.join(a.new_dir, "_diff")
    base, new = pngs(a.base_dir), pngs(a.new_dir)
    shared = sorted(set(base) & set(new))

    print("BASE %s\nNEW  %s\n" % (a.base_dir, a.new_dir))
    rows = [compare(n, base[n], new[n], a.tolerance, out) for n in shared]
    rows.sort(key=lambda r: -r[1])
    width = max([len(r[0]) for r in rows] + [4])
    print("%-*s  %8s  %s" % (width, "file", "changed", "region"))
    for name, pct, note, _ in rows:
        flag = "  FAIL" if pct > a.threshold else ""
        print("%-*s  %7.2f%%  %s%s" % (width, name, pct, note, flag))
    only_base, only_new = sorted(set(base) - set(new)), sorted(set(new) - set(base))
    print("\nonly in BASE: %s" % (", ".join(only_base) or "(none)"))
    print("only in NEW:  %s" % (", ".join(only_new) or "(none)"))

    changed = [r for r in rows if r[1] > PANEL_MIN_PCT]
    failed = [r for r in rows if r[1] > a.threshold]
    print("\n%d pairs, %d changed (>%.2f%%), %d over %.1f%%, %d only in base, %d only in new%s"
          % (len(rows), len(changed), PANEL_MIN_PCT, len(failed), a.threshold, len(only_base),
             len(only_new), ("; panels in %s" % out) if changed else ""))
    if failed and not a.no_fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
