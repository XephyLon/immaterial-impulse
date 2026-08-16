#!/usr/bin/env python3
"""Subject masks for the desktop clock's depth mode, and the cache they live in.

Segmentation costs 1.3-4.5s and ~1GB of transient RSS per run, and produces an
unusable mask roughly a third of the time it produces one at all - so this never
runs on the shell's startup path. The shell only ever asks `status`, which reads
directory entries and returns in milliseconds; `run` is reached from an explicit
user action in the wallpaper picker.

This script owns the cache key. The shell must never compute one: two
implementations of a hash in two languages is the `activeStill` shape, two things
that must agree with nothing reporting it when they stop.

The key is the wallpaper's path, mtime and size. Path alone is wrong - this
library is full of files edited and re-exported in place, and a stale mask over a
changed image is the worst failure this feature has. Including mtime and size
makes an in-place edit produce a new key automatically, and the old entry becomes
garbage the sweep collects.

Four files can exist per key, and they are the four states of section 5 of
docs/superpowers/specs/2026-08-16-clock-depth-design.md:

    <key>.<model>.png   a candidate mask a model produced, at model resolution
    <key>.<model>.none  that model looked and found no subject
    <key>.png           the candidate the user accepted - the ONLY file the shell draws
    <key>.off           the user declined every candidate for this wallpaper

Output is JSON on stdout rather than a bare path because the shell has to tell
those states apart, and a path can only carry "yes" and "no".
"""
import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

MODELS = {
    "isnet-anime": {
        "url": "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-anime.onnx",
        "sha256": "f15622d853e8260172812b657053460e20806f04b9e05147d49af7bed31a6e99",
        "side": 1024,
    },
    "isnet-general-use": {
        "url": "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx",
        "sha256": "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a",
        "side": 1024,
    },
}

# Below this share of foreground the model found nothing. isnet-anime returns
# exactly 0.0000 on the landscape wallpapers in this library, which is the right
# answer and must be recorded rather than recomputed on every visit.
EMPTY_FOREGROUND = 0.005

# Keys, not files: dropping a key's `.off` while keeping its `.png` would
# resurrect a mask the user declined.
SWEEP_KEEP_KEYS = 200

SUFFIXES = (".png", ".none", ".off")


def cache_root(explicit=None):
    if explicit:
        return Path(explicit)
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return Path(base) / "quickshell" / "clock-depth"


def cache_key(wallpaper):
    """The wallpaper's identity for this cache: path, mtime and size."""
    path = Path(wallpaper).expanduser().resolve()
    st = path.stat()
    material = f"{path}\0{st.st_mtime_ns}\0{st.st_size}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()[:32]


def status(root, wallpaper):
    """What the shell asks. Reads directory entries; loads nothing."""
    try:
        key = cache_key(wallpaper)
    except OSError as exc:
        return {"state": "unreadable", "error": str(exc), "wallpaper": str(wallpaper)}

    result = {"key": key, "wallpaper": str(Path(wallpaper).expanduser().resolve()),
              "cacheDir": str(root)}
    accepted = root / f"{key}.png"
    optout = root / f"{key}.off"
    candidates = {}
    for model in MODELS:
        if (root / f"{key}.{model}.png").exists():
            candidates[model] = str(root / f"{key}.{model}.png")
        elif (root / f"{key}.{model}.none").exists():
            candidates[model] = None
    result["candidates"] = candidates

    if optout.exists():
        result["state"] = "declined"
    elif accepted.exists():
        result["state"] = "accepted"
        result["mask"] = str(accepted)
    elif candidates and all(v is None for v in candidates.values()):
        result["state"] = "none"
    elif candidates:
        result["state"] = "candidate"
    else:
        result["state"] = "absent"
    return result


def model_path(root, model):
    return root / "models" / f"{model}.onnx"


def fetch_model(root, model, progress=None):
    """Download a model on first use. 176MB, so it is not bundled.

    Written to a temporary name and renamed into place: a rename is atomic, so an
    interrupted download can never leave a truncated file that looks like a model
    and fails at session construction instead of at fetch time.
    """
    spec = MODELS[model]
    target = model_path(root, model)
    if target.exists():
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    fd, tmp = tempfile.mkstemp(dir=str(target.parent), suffix=".part")
    try:
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(spec["url"]) as response:
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                digest.update(chunk)
                out.write(chunk)
                if progress:
                    progress(out.tell())
        if digest.hexdigest() != spec["sha256"]:
            raise RuntimeError(
                f"{model}: downloaded file does not match the expected checksum")
        os.rename(tmp, target)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return target


def segment(image_path, onnx_path, side):
    """Run one model over one image and return the normalised mask.

    Imported here rather than at module scope so `status` never pays for
    onnxruntime, and so a machine without it can still answer cache questions.
    """
    import numpy as np
    import onnxruntime as ort
    from PIL import Image

    Image.MAX_IMAGE_PIXELS = None
    image = Image.open(image_path).convert("RGB")
    # Squash to the square input, never pad. With black bars the model reads the
    # bars as background and returns the entire picture as the subject -
    # measured at foreground 0.9999 on three separate wallpapers.
    array = np.asarray(image.resize((side, side), Image.LANCZOS), np.float32) / 255.0
    array = array - 0.5
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    name = session.get_inputs()[0].name
    mask = session.run(None, {name: array.transpose(2, 0, 1)[None]})[0][0][0]
    mask = (mask - mask.min()) / (mask.max() - mask.min() + 1e-8)
    return mask


def run(root, wallpaper, model, force=False):
    if model not in MODELS:
        raise SystemExit(f"unknown model {model!r}; expected one of {', '.join(MODELS)}")
    key = cache_key(wallpaper)
    root.mkdir(parents=True, exist_ok=True)
    candidate = root / f"{key}.{model}.png"
    negative = root / f"{key}.{model}.none"

    if not force:
        if candidate.exists():
            return {"state": "hit", "key": key, "model": model, "mask": str(candidate)}
        if negative.exists():
            return {"state": "none", "key": key, "model": model, "cached": True}

    onnx_path = model_path(root, model)
    if not onnx_path.exists():
        onnx_path = fetch_model(root, model)

    mask = segment(wallpaper, onnx_path, MODELS[model]["side"])
    foreground = float((mask > 0.5).mean())

    candidate.unlink(missing_ok=True)
    negative.unlink(missing_ok=True)

    if foreground < EMPTY_FOREGROUND:
        negative.write_text("")
        return {"state": "none", "key": key, "model": model, "foreground": foreground}

    write_mask(candidate, mask)
    return {"state": "produced", "key": key, "model": model,
            "mask": str(candidate), "foreground": foreground}


def write_mask(path, mask):
    """Save a mask at model resolution, carrying it in BOTH channels.

    Model resolution rather than the wallpaper's: upscaling to 5120px is a smooth
    texture fetch the GPU does for free, while a wallpaper-resolution mask costs
    3MB and nearly a second of write time to store information the mask does not
    have.

    Grayscale AND alpha, both the same plane. The alpha is what the shell masks
    with - Qt's OpacityMask reads the mask's alpha channel and nothing else, so a
    plain "L" PNG is opaque everywhere and lets the whole wallpaper through,
    which paints the picture flat over the clock instead of the subject behind
    it. The luminance is kept beside it so the file is still a mask to look at,
    which is the point of the producer shipping as a CLI.

    A function of its own rather than four lines inside `run`, because it is the
    only part of the produced artifact that is testable without a model.
    """
    import numpy as np
    from PIL import Image

    plane = (np.clip(np.asarray(mask, dtype="float32"), 0.0, 1.0) * 255).astype("uint8")
    Image.fromarray(np.dstack([plane, plane]), "LA").save(path)


def accept(root, wallpaper, model):
    """Promote one model's candidate to the mask the shell draws.

    A copy rather than a link or a rename: the candidate stays where it is so the
    picker can offer it again after a decline, and a link would leave the shell
    drawing through a file the sweep may collect from under it.

    Clears the opt-out in the same call. Accepting while a `.off` is on disk and
    leaving it there would be a mask the shell refuses to draw for a reason the
    user has just overruled - and the refusal is deliberately checked first, so
    the two would not merely disagree, the accept would do nothing at all.
    """
    if model not in MODELS:
        raise SystemExit(f"unknown model {model!r}; expected one of {', '.join(MODELS)}")
    key = cache_key(wallpaper)
    candidate = root / f"{key}.{model}.png"
    if not candidate.exists():
        raise RuntimeError(f"no {model} candidate to accept for this wallpaper")
    accepted = root / f"{key}.png"
    # Written beside the target and renamed, so the shell never sees a
    # half-written mask through a FileView that is watching for one.
    fd, tmp = tempfile.mkstemp(dir=str(root), suffix=".part")
    with os.fdopen(fd, "wb") as out:
        out.write(candidate.read_bytes())
    os.rename(tmp, accepted)
    (root / f"{key}.off").unlink(missing_ok=True)
    return {"state": "accepted", "key": key, "model": model, "mask": str(accepted)}


def decline(root, wallpaper):
    """Record that this wallpaper gets no depth, and drop any accepted mask.

    A file beside the mask rather than a config entry: a per-wallpaper map keyed
    by a runtime path is exactly what Config.qml's JsonAdapter cannot hold, and
    keeping the marker at the key means it invalidates with the key - edit the
    wallpaper in place and the refusal goes with the mask it was about.
    """
    key = cache_key(wallpaper)
    root.mkdir(parents=True, exist_ok=True)
    (root / f"{key}.off").write_text("")
    (root / f"{key}.png").unlink(missing_ok=True)
    return {"state": "declined", "key": key}


def sweep(root, keep=SWEEP_KEEP_KEYS):
    """Drop the oldest keys whole.

    Grouped by key rather than swept by file because the files of one key are one
    decision: a `.off` outliving its `.png` would silently re-enable a mask the
    user declined, and a `.png` outliving its `.off` would re-declare a declined
    wallpaper as accepted.
    """
    if not root.exists():
        return {"kept": 0, "removed": 0}
    keys = {}
    for entry in root.iterdir():
        if not entry.is_file():
            continue
        name = entry.name
        if not any(name.endswith(suffix) for suffix in SUFFIXES):
            continue
        key = name.split(".", 1)[0]
        keys.setdefault(key, []).append(entry)
    ordered = sorted(keys.items(),
                     key=lambda kv: max(f.stat().st_mtime_ns for f in kv[1]),
                     reverse=True)
    removed = 0
    for _, files in ordered[keep:]:
        for entry in files:
            entry.unlink(missing_ok=True)
            removed += 1
    return {"kept": min(len(ordered), keep), "removed": removed}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache-dir", default=None,
                        help="override the cache root (tests)")
    sub = parser.add_subparsers(dest="command", required=True)

    p_status = sub.add_parser("status", help="what the cache holds for a wallpaper")
    p_status.add_argument("wallpaper")

    p_run = sub.add_parser("run", help="produce a candidate mask, or return a cached one")
    p_run.add_argument("wallpaper")
    p_run.add_argument("--model", default="isnet-anime", choices=sorted(MODELS))
    p_run.add_argument("--force", action="store_true",
                       help="re-run even when a candidate is already cached")

    p_accept = sub.add_parser("accept", help="draw this model's candidate from now on")
    p_accept.add_argument("wallpaper")
    p_accept.add_argument("--model", required=True, choices=sorted(MODELS))

    p_decline = sub.add_parser("decline", help="this wallpaper gets no depth")
    p_decline.add_argument("wallpaper")

    p_sweep = sub.add_parser("sweep", help="drop the oldest keys")
    p_sweep.add_argument("--keep", type=int, default=SWEEP_KEEP_KEYS)

    args = parser.parse_args(argv)
    root = cache_root(args.cache_dir)

    try:
        if args.command == "status":
            result = status(root, args.wallpaper)
        elif args.command == "run":
            result = run(root, args.wallpaper, args.model, force=args.force)
        elif args.command == "accept":
            result = accept(root, args.wallpaper, args.model)
        elif args.command == "decline":
            result = decline(root, args.wallpaper)
        else:
            result = sweep(root, keep=args.keep)
    except Exception as exc:  # noqa: BLE001 - the shell needs a parseable failure
        json.dump({"state": "error", "error": str(exc)}, sys.stdout)
        sys.stdout.write("\n")
        return 1

    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
