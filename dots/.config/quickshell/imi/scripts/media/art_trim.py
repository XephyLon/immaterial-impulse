#!/usr/bin/env python3
"""Letterbox insets of an album-art file, as JSON on stdout.

Some players hand over art with the letterbox baked in - a square cover
shipped as 16:9 with black bars, or a video thumbnail with pillarboxes. The
widget crop-fills its tiles, so those bars become the picture. This probe
answers with the fractional insets of any uniform border it can prove, and
the shell clips the art by them.

Conservative on purpose, because a wrong trim eats real pixels silently:
 - a side is a bar only if its rows/columns are near-uniform AND near the
   corner colour of that side;
 - bars must come in symmetric pairs (top/bottom or left/right) within a
   tolerance - one dark edge on a moody cover is composition, not a bar;
 - a pair is trimmed only between 2% and 45% per side.

Stdlib + Pillow + numpy; no model, no network. Output:
  {"width": W, "height": H, "left": px, "top": px, "right": px, "bottom": px}
with zeros where nothing is proven.
"""
import json
import sys

PROBE_SIDE = 256
UNIFORM_STD = 8.0
COLOR_TOL = 14.0
MIN_FRACTION = 0.02
MAX_FRACTION = 0.45
PAIR_TOL = 0.04


def bar_depth(plane, reference):
    """How many leading rows of `plane` match `reference` near-uniformly."""
    import numpy as np
    depth = 0
    for row in plane:
        if row.std(axis=0).max() > UNIFORM_STD:
            break
        if np.abs(row.mean(axis=0) - reference).max() > COLOR_TOL:
            break
        depth += 1
    return depth


def probe(path):
    import numpy as np
    from PIL import Image

    Image.MAX_IMAGE_PIXELS = None
    with Image.open(path) as picture:
        width, height = picture.size
        scale = max(width, height) / PROBE_SIDE
        pw = max(2, round(width / max(1.0, scale)))
        ph = max(2, round(height / max(1.0, scale)))
        small = np.asarray(
            picture.convert("RGB").resize((pw, ph)), dtype="float32")

    result = {"width": width, "height": height,
              "left": 0, "top": 0, "right": 0, "bottom": 0}

    tops = bar_depth(small, small[0].mean(axis=0)) / ph
    bottoms = bar_depth(small[::-1], small[-1].mean(axis=0)) / ph
    cols = small.transpose(1, 0, 2)
    lefts = bar_depth(cols, cols[0].mean(axis=0)) / pw
    rights = bar_depth(cols[::-1], cols[-1].mean(axis=0)) / pw

    def paired(a, b):
        return (MIN_FRACTION <= a <= MAX_FRACTION
                and MIN_FRACTION <= b <= MAX_FRACTION
                and abs(a - b) <= PAIR_TOL)

    if paired(tops, bottoms):
        result["top"] = round(tops * height)
        result["bottom"] = round(bottoms * height)
    if paired(lefts, rights):
        result["left"] = round(lefts * width)
        result["right"] = round(rights * width)
    return result


def main():
    if len(sys.argv) != 2:
        json.dump({"error": "usage: art_trim.py <image>"}, sys.stdout)
        return 1
    try:
        json.dump(probe(sys.argv[1]), sys.stdout)
    except Exception as exc:  # noqa: BLE001 - the shell needs a parseable no
        json.dump({"error": str(exc)}, sys.stdout)
        return 1
    finally:
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
