#!/usr/bin/env python3
"""Per-scheme swatch preview for the settings scheme picker.

Quantizes the wallpaper ONCE, then builds every Material scheme variant from
the same source color and prints a compact JSON map of representative swatches:

    { "scheme-tonal-spot": ["#aabbcc", "#...", "#..."], ... }

Swatches are primary / secondary / tertiary in the requested mode. Needs the
color venv (materialyoucolor + PIL) - run through generate-colors-venv.sh's
environment or with IMMATERIAL_IMPULSE_VIRTUAL_ENV activated.
"""
import argparse
import json
import sys

from PIL import Image
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score
from materialyoucolor.hct import Hct
from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors
from materialyoucolor.scheme.scheme_content import SchemeContent
from materialyoucolor.scheme.scheme_expressive import SchemeExpressive
from materialyoucolor.scheme.scheme_fidelity import SchemeFidelity
from materialyoucolor.scheme.scheme_fruit_salad import SchemeFruitSalad
from materialyoucolor.scheme.scheme_monochrome import SchemeMonochrome
from materialyoucolor.scheme.scheme_neutral import SchemeNeutral
from materialyoucolor.scheme.scheme_rainbow import SchemeRainbow
from materialyoucolor.scheme.scheme_tonal_spot import SchemeTonalSpot

SCHEMES = {
    "scheme-content": SchemeContent,
    "scheme-expressive": SchemeExpressive,
    "scheme-fidelity": SchemeFidelity,
    "scheme-fruit-salad": SchemeFruitSalad,
    "scheme-monochrome": SchemeMonochrome,
    "scheme-neutral": SchemeNeutral,
    "scheme-rainbow": SchemeRainbow,
    "scheme-tonal-spot": SchemeTonalSpot,
}
SWATCH_COLORS = ("primary", "secondary", "tertiary")


def rgba_to_hex(rgba):
    return "#{:02x}{:02x}{:02x}".format(rgba[0], rgba[1], rgba[2])


def source_hct(path, size):
    image = Image.open(path)
    if image.format == "GIF":
        image.seek(1)
    if image.mode in ["L", "P"]:
        image = image.convert("RGB")
    w, h = image.size
    scale = min(1.0, size / max(w, h))
    if scale < 1.0:
        image = image.resize((max(1, int(w * scale)), max(1, int(h * scale))),
                             Image.Resampling.BICUBIC)
    colors = QuantizeCelebi(list(image.getdata()), 128)
    return Hct.from_int(Score.score(colors)[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", required=True, help="wallpaper image")
    parser.add_argument("--mode", choices=["dark", "light"], default="dark")
    parser.add_argument("--size", type=int, default=96, help="quantize bitmap size")
    args = parser.parse_args()

    try:
        hct = source_hct(args.path, args.size)
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)

    dark = args.mode == "dark"
    out = {}
    for name, scheme_class in SCHEMES.items():
        scheme = scheme_class(hct, dark, 0.0)
        out[name] = [
            rgba_to_hex(getattr(MaterialDynamicColors, color).get_hct(scheme).to_rgba())
            for color in SWATCH_COLORS
        ]
    # "auto" picks between these variants from image chroma; preview it with
    # the same rule scheme_for_image.py uses at the boundary that matters
    # here (low chroma -> neutral, else tonal spot approximates the choice).
    out["auto"] = out["scheme-neutral" if hct.chroma < 20 else "scheme-tonal-spot"]
    print(json.dumps(out))


if __name__ == "__main__":
    main()
