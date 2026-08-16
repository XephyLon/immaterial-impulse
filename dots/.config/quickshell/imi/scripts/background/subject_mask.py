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

A fifth file exists for the prompted model only, and it is not a state:

    <key>.<model>.embedding.npz   the wallpaper encoded once, so clicks are cheap

Two kinds of model live behind those four states. The salient detectors
(isnet-*) answer on their own and are asked with `run`. The prompted one
(mobile-sam) answers a click and is asked with `select` - because on the bulk of
this library the salient models have no answer at all: swept over the 91
wallpapers here, one was accepted, 43 produced a candidate, and 45 returned
nothing from BOTH models. Measured before any threshold, isnet-general-use
claims 2.78% of `aishot-3263.jpg` at 0.1 confidence and isnet-anime 0.07%, so
there is no threshold that recovers those pictures - the models are salient
object detectors and a full-bleed wallpaper has no background to separate a
subject from. Pointing at the subject is the answer, not a lower bar.

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
        "kind": "salient",
        "side": 1024,
        "files": {
            "model": {
                "url": "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-anime.onnx",
                "sha256": "f15622d853e8260172812b657053460e20806f04b9e05147d49af7bed31a6e99",
            },
        },
    },
    "isnet-general-use": {
        "kind": "salient",
        "side": 1024,
        "files": {
            "model": {
                "url": "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx",
                "sha256": "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a",
            },
        },
    },
    # The click-to-select model, and the reason it is two files rather than one.
    # Encoding an image costs seconds; decoding a mask from a click costs
    # milliseconds and reads only the embedding, so the split is what makes the
    # second click instant. Fused into one file it would be the same cost per
    # click as the salient models pay per run, and the feature would be
    # unusable - see `image_embedding`.
    #
    # MobileSAM rather than SAM proper: it keeps SAM's own prompt encoder and
    # mask decoder and replaces only the image encoder with a distilled ViT-t,
    # so the decoder contract is Meta's unchanged and the pair is 43MB against
    # SAM ViT-H's 2.4GB. Apache-2.0 upstream (ChaoningZhang/MobileSAM), MIT on
    # the repository hosting this ONNX export.
    #
    # The encoder normalises and pads INSIDE the graph, so it is fed the resized
    # picture in raw 0-255 HWC - see `image_embedding`.
    "mobile-sam": {
        "kind": "prompted",
        "side": 1024,
        "files": {
            "encoder": {
                "url": "https://huggingface.co/Acly/MobileSAM/resolve/main/mobile_sam_image_encoder.onnx",
                "sha256": "580f5fb648ea1062c0aabc26217aed56921985f03f0cbbd852bba81d760cc749",
            },
            "decoder": {
                "url": "https://huggingface.co/Acly/MobileSAM/resolve/main/sam_mask_decoder_single.onnx",
                "sha256": "93915fc7c993ab9d59ab8c9ccd3bce37f7509c81ab4150a74abd4d2abbd8570d",
            },
        },
    },
}

# Below this share of foreground the model found nothing. isnet-anime returns
# exactly 0.0000 on the landscape wallpapers in this library, which is the right
# answer and must be recorded rather than recomputed on every visit.
EMPTY_FOREGROUND = 0.005

# A click's floor is far lower, and it has to be a different number rather than
# the same one reused. The salient threshold answers "did this model find a
# subject in this picture", where 0.5% of the frame is a plausible dividing line
# between an answer and a stray fragment. A click is the user ASSERTING there is
# something there and pointing at it, so the only thing left to detect is a
# decoder that returned nothing at all.
#
# Measured, and this is not theoretical: excluding part of a hillside on
# `aishot-1206.jpg` left a mask at 0.46% of the frame - on that 7680x2160
# wallpaper, 76000 pixels, a plainly visible object - and the salient floor threw
# it away as "nothing there". Meanwhile a click on flat sky comes back at 1.6-10%
# because SAM answers with the sky, so the high floor was not buying a refusal
# for the case it looked like it was for. 0.0002 is about a 57x57 blob at that
# resolution, which is the smallest thing worth compositing over a clock.
EMPTY_PROMPTED_FOREGROUND = 0.0002

# Keys, not files: dropping a key's `.off` while keeping its `.png` would
# resurrect a mask the user declined.
SWEEP_KEEP_KEYS = 200

# The embedding is swept with the key like everything else - it is derived from
# the same wallpaper and is worthless the moment the key changes.
SUFFIXES = (".png", ".none", ".off", ".npz")

# The PNG text chunk a prompted mask carries its own clicks in. The prompt lives
# INSIDE the mask rather than in a sidecar file or in the cache key; the reasons
# are in `write_mask`.
PROMPT_CHUNK = "clock-depth-prompt"
PROMPT_VERSION = 1


def salient_models():
    """The models that answer on their own, and so take a `run`."""
    return sorted(m for m, spec in MODELS.items() if spec["kind"] == "salient")


def prompted_models():
    """The models that answer a click, and so take a `select`."""
    return sorted(m for m, spec in MODELS.items() if spec["kind"] == "prompted")


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


def resize_longest_side(width, height, side):
    """The box SAM sees the image in: longest side scaled to `side`, aspect kept.

    SAM resizes the longest side and pads the remainder to a square, rather than
    squashing the way the isnet models do. That difference is the whole reason a
    prompted mask comes out at the WALLPAPER's aspect while a salient one comes
    out square - and it is why `coverRect` needs no case for it, since that
    function is a rectangle for the wallpaper and never reads the mask's own
    shape.
    """
    if width <= 0 or height <= 0:
        raise ValueError(f"image has no size: {width}x{height}")
    scale = side / float(max(width, height))
    # round, not floor: the transform SAM's own ResizeLongestSide applies.
    return (max(1, int(width * scale + 0.5)), max(1, int(height * scale + 0.5)))


def parse_point(text):
    """One `--point x,y[,label]` argument, in the image's own normalised frame.

    Normalised rather than pixels because the caller is the picker, which has a
    preview of some arbitrary size showing a crop of the wallpaper: it knows
    where the click landed as a fraction of the picture and does not know, and
    must not have to know, what the file's pixel dimensions are. It is also what
    makes a stored prompt mean the same thing after the mask is regenerated at a
    different resolution.
    """
    parts = text.split(",")
    if len(parts) not in (2, 3):
        raise ValueError(f"point {text!r} is not x,y or x,y,label")
    x, y = float(parts[0]), float(parts[1])
    label = int(parts[2]) if len(parts) == 3 else 1
    if label not in (0, 1):
        raise ValueError(f"point {text!r} has label {label}; expected 1 (include) "
                         f"or 0 (exclude)")
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
        raise ValueError(f"point {text!r} is outside the picture")
    return {"x": x, "y": y, "label": label}


def encode_prompt(points, resized_size):
    """The clicks, as the two arrays SAM's decoder takes.

    Three things here are contract rather than choice, and each of them fails
    silently rather than loudly when it is wrong - a mask in the wrong place, or
    a mask of the whole frame, with no error anywhere:

    - coordinates are in the RESIZED image's pixels, not the original's and not
      the padded square's, because that is the space the encoder saw;
    - a label is 1 for a point the subject must contain and 0 for one it must
      not, and
    - a padding point at (0, 0) labelled -1 is appended. The decoder's exported
      graph has a fixed slot for a box, and with no box the padding point is
      what tells it there is none. Omitting it does not raise: the decoder reads
      the first point as a box corner instead, and the mask comes back wrong.
    """
    import numpy as np

    width, height = resized_size
    coords = [[p["x"] * width, p["y"] * height] for p in points]
    labels = [float(p["label"]) for p in points]
    coords.append([0.0, 0.0])
    labels.append(-1.0)
    return (np.array([coords], dtype=np.float32), np.array([labels], dtype=np.float32))


def read_png_text(path, keyword):
    """One tEXt chunk out of a PNG, with the standard library only.

    `status` is the shell's read path and may not import Pillow (see the module
    docstring), but it has to report the prompt a mask was cut with so the
    picker can show the clicks back. A PNG's chunk layout is simple enough that
    reading one keyword out of it is cheaper than the dependency would be.
    """
    try:
        with open(path, "rb") as handle:
            if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                return None
            while True:
                header = handle.read(8)
                if len(header) < 8:
                    return None
                length = int.from_bytes(header[:4], "big")
                kind = header[4:8]
                if kind == b"IEND":
                    return None
                if kind == b"tEXt":
                    name, _, value = handle.read(length).partition(b"\0")
                    if name.decode("latin-1") == keyword:
                        return value.decode("latin-1")
                else:
                    # Seek rather than read: the pixels are megabytes and the
                    # text chunks are not among them.
                    handle.seek(length, os.SEEK_CUR)
                handle.seek(4, os.SEEK_CUR)
    except OSError:
        return None


def file_revision(path):
    """A token that changes whenever this file's bytes might have."""
    try:
        return str(Path(path).stat().st_mtime_ns)
    except OSError:
        return ""


def read_prompt(path):
    """The clicks a prompted mask was cut with, or None for a salient one."""
    raw = read_png_text(path, PROMPT_CHUNK)
    if raw is None:
        return None
    try:
        payload = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(payload, dict) or payload.get("version") != PROMPT_VERSION:
        return None
    points = payload.get("points")
    return points if isinstance(points, list) else None


def accepted_model(root, key, candidates):
    """Which candidate the accepted mask is a copy of, or None.

    Derived from the bytes rather than recorded in a fifth file. `accept` is a
    byte-for-byte copy, so the answer is already on disk, and a recorded one
    would be a second thing that has to agree with the first with nothing
    reporting it when it stops - the `activeStill` shape, and this cache is full
    of pairs that are deliberately derived for exactly that reason.

    None is a real answer and not only an error: re-running a model overwrites
    its candidate, so an accepted mask can stop matching either of them, and
    "the cutout you accepted is not either of these" is what the picker should
    then say rather than crediting whichever it happens to resemble.
    """
    accepted = root / f"{key}.png"
    blob = None
    try:
        size = accepted.stat().st_size
        for model, path in candidates.items():
            if path is None:
                continue
            candidate = Path(path)
            # Size first: two 1024x1024 masks from different models are
            # routinely both ~300 KB but never the same 300 KB, so this skips
            # the read on the mismatching one without deciding anything by it.
            if candidate.stat().st_size != size:
                continue
            if blob is None:
                blob = accepted.read_bytes()
            if candidate.read_bytes() == blob:
                return model
    except OSError:
        return None
    return None


def status(root, wallpaper):
    """What the shell asks. Reads directory entries; loads nothing."""
    try:
        key = cache_key(wallpaper)
    except OSError as exc:
        return {"state": "unreadable", "error": str(exc), "wallpaper": str(wallpaper)}

    result = {"key": key, "wallpaper": str(Path(wallpaper).expanduser().resolve()),
              "cacheDir": str(root),
              # The models and what each one is asked with, so the picker draws
              # one column per model without carrying its own copy of the list -
              # a second list of model names is the pair that drifts, and the
              # one that would drift silently is the picker's, since a model
              # nobody named simply has no column.
              "models": [{"name": name, "kind": spec["kind"]}
                         for name, spec in MODELS.items()]}
    accepted = root / f"{key}.png"
    optout = root / f"{key}.off"
    candidates = {}
    for model in MODELS:
        if (root / f"{key}.{model}.png").exists():
            candidates[model] = str(root / f"{key}.{model}.png")
        elif (root / f"{key}.{model}.none").exists():
            candidates[model] = None
    result["candidates"] = candidates
    # A token that changes whenever a mask's bytes do. Qt caches a pixmap by its
    # URL, so a mask rewritten at the same path is served from the cache
    # FOREVER - measured with a qml6 probe: a 32x8 image rewritten at 99x17 and
    # re-assigned to the identical URL still reported 32x8, and clearing the
    # source first did not help. Every click after the first would appear to do
    # nothing. The shell hangs this on the URL as a fragment, which Qt leaves out
    # of the filename and keeps in the cache key.
    #
    # A string because these are nanoseconds: 1.8e18 does not survive a JSON
    # round trip through a double, and a revision that quietly stops changing is
    # the bug this exists to prevent.
    result["revisions"] = {model: file_revision(path)
                           for model, path in candidates.items() if path}
    # The clicks each prompted candidate was cut with, read back out of the mask
    # itself. The picker draws them so re-opening on a wallpaper shows what was
    # clicked rather than an unexplained cutout with no way back into the
    # gesture that produced it.
    prompts = {}
    for model, path in candidates.items():
        if path is None:
            continue
        prompt = read_prompt(path)
        if prompt is not None:
            prompts[model] = prompt
    result["prompts"] = prompts

    if optout.exists():
        result["state"] = "declined"
    elif accepted.exists():
        result["state"] = "accepted"
        result["mask"] = str(accepted)
        # The accepted mask is rewritten in place when a second candidate is
        # accepted for the same wallpaper, so the desktop layer needs the same
        # token the picker does - without it, accepting the other column's
        # cutout changes the file and nothing on screen.
        result["maskRevision"] = file_revision(accepted)
        result["acceptedModel"] = accepted_model(root, key, candidates)
        # The accepted mask's OWN prompt, not the live candidate's. Accept is a
        # byte copy, so the clicks travelled with the pixels they produced and
        # this stays right after the candidate is refined further - which is the
        # case where a recorded-beside-it prompt would start describing a mask
        # the desktop is not drawing.
        accepted_prompt = read_prompt(accepted)
        if accepted_prompt is not None:
            result["acceptedPrompt"] = accepted_prompt
    elif candidates and all(v is None for v in candidates.values()):
        result["state"] = "none"
    elif candidates:
        result["state"] = "candidate"
    else:
        result["state"] = "absent"
    return result


def model_path(root, model, role="model"):
    """Where one of a model's ONNX files lives.

    The single-file models keep the bare `<model>.onnx` they already occupy on
    disk - a role in the name would orphan the two 176MB files every machine
    that has used this feature has already fetched.
    """
    name = model if role == "model" else f"{model}.{role}"
    return root / "models" / f"{name}.onnx"


def fetch_model(root, model, role="model", progress=None):
    """Download a model file on first use. 176MB, so it is not bundled.

    Written to a temporary name and renamed into place: a rename is atomic, so an
    interrupted download can never leave a truncated file that looks like a model
    and fails at session construction instead of at fetch time.
    """
    spec = MODELS[model]["files"][role]
    target = model_path(root, model, role)
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
    from PIL import Image

    Image.MAX_IMAGE_PIXELS = None
    image = Image.open(image_path).convert("RGB")
    # Squash to the square input, never pad. With black bars the model reads the
    # bars as background and returns the entire picture as the subject -
    # measured at foreground 0.9999 on three separate wallpapers.
    array = np.asarray(image.resize((side, side), Image.LANCZOS), np.float32) / 255.0
    array = array - 0.5
    session = session_for(onnx_path)
    name = session.get_inputs()[0].name
    mask = session.run(None, {name: array.transpose(2, 0, 1)[None]})[0][0][0]
    mask = (mask - mask.min()) / (mask.max() - mask.min() + 1e-8)
    return mask


def session_for(onnx_path):
    """One ONNX session, with the import failure said in words a user can act on.

    A missing `onnxruntime` is the single most likely way this script fails on a
    working machine - the venv is built by the installer and this is the only
    thing in the shell that needs a package in it - and what the picker showed
    for it was `ModuleNotFoundError: No module named 'onnxruntime'`, which names
    neither the venv nor the command that repairs it.
    """
    try:
        import onnxruntime as ort
    except ImportError as exc:
        raise RuntimeError(
            "onnxruntime is missing from the shell's Python environment, so no "
            "model can run. Rebuild it with: uv pip install --python "
            "\"$IMMATERIAL_IMPULSE_VIRTUAL_ENV\" onnxruntime "
            f"(python said: {exc})") from exc
    return ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])


def image_embedding(root, wallpaper, model, key):
    """The wallpaper's SAM embedding, computed once and cached at the key.

    This is the whole reason SAM is the right tool here rather than a fourth
    salient detector. Encoding is the expensive half and depends only on the
    picture; decoding a mask from a set of clicks reads the embedding and is
    over an order of magnitude cheaper. Measured on a 7680x2160 wallpaper:
    encode 1.04s, load the cached embedding 0.004s, decode 0.128s - so the
    first click costs 1.6s end to end and every one after it 0.34s, most of
    which is starting Python. Encoding per click would put the first click's
    price on every attempt, and refinement is the entire interaction.

    Stored as float16. The array is 256x64x64, which is 4MB at float32 and 2MB
    halved, and it is consumed by a decoder that immediately blurs it through a
    transposed convolution into a 256x256 logit field - the mantissa bits are
    not what decides where the edge lands. It is cast back on load because the
    decoder's input is float32.
    """
    import numpy as np
    from PIL import Image

    cached = root / f"{key}.{model}.embedding.npz"
    if cached.exists():
        with np.load(cached) as stored:
            return (stored["embedding"].astype(np.float32), tuple(stored["resized"]))

    spec = MODELS[model]
    encoder = model_path(root, model, "encoder")
    if not encoder.exists():
        encoder = fetch_model(root, model, "encoder")

    Image.MAX_IMAGE_PIXELS = None
    image = Image.open(wallpaper).convert("RGB")
    # Resize the longest side and let the graph pad the rest. This is SAM's own
    # preprocessing and the opposite of what the isnet models want: squashing
    # here would ask the encoder for features of a picture nothing was trained
    # on, and every click would land on the wrong part of it.
    #
    # Raw 0-255, unnormalised and UNPADDED, because this export carries
    # `preprocess()` inside the graph - it subtracts the ImageNet mean, divides
    # by the standard deviation and pads bottom-right itself. Padding here first
    # would put zeros through that normalisation instead of leaving them at
    # zero, which is a border of -2.1 the model has never seen and a mask that
    # goes subtly wrong near the edges of the frame with nothing to show for it.
    resized = resize_longest_side(image.width, image.height, spec["side"])
    array = np.asarray(image.resize(resized, Image.LANCZOS), np.float32)

    session = session_for(encoder)
    name = session.get_inputs()[0].name
    embedding = session.run(None, {name: array})[0]

    root.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(root), suffix=".part")
    try:
        # Handed the open descriptor rather than the path: `np.savez` appends
        # `.npz` to any name that does not already end in it, so passing the
        # temporary name writes a SECOND file and leaves the empty one this
        # created - which then gets renamed into place and loads as "No data
        # left in file" on the next click.
        with os.fdopen(fd, "wb") as out:
            np.savez(out, embedding=embedding.astype(np.float16),
                     resized=np.array(resized, np.int32))
        os.rename(tmp, cached)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return (embedding.astype(np.float32), resized)


def decode_mask(root, model, embedding, resized, points):
    """One set of clicks into one mask. Milliseconds, and no image is opened.

    The decoder returns LOGITS, not a normalised field: zero is the boundary and
    the sign is the answer. The salient path's min-max normalisation would be
    wrong here twice over - it would move the boundary to wherever the extremes
    happen to fall, and on a confident mask it would stretch a hard edge across
    the whole range. A sigmoid keeps 0.5 at the model's own boundary and keeps
    the edge as soft as the model actually left it, which is what stops the
    cutout reading as a sticker.
    """
    import numpy as np

    decoder = model_path(root, model, "decoder")
    if not decoder.exists():
        decoder = fetch_model(root, model, "decoder")

    coords, labels = encode_prompt(points, resized)
    session = session_for(decoder)
    names = {i.name for i in session.get_inputs()}
    feed = {
        "image_embeddings": embedding,
        "point_coords": coords,
        "point_labels": labels,
        # No previous mask. `has_mask_input` is what says so; a zeroed
        # `mask_input` with the flag set is a mask that claims nothing, which is
        # a different prompt.
        "mask_input": np.zeros((1, 1, 256, 256), np.float32),
        "has_mask_input": np.zeros(1, np.float32),
    }
    if "orig_im_size" in names:
        # The RESIZED size, not the wallpaper's. It is what the decoder crops
        # the padding away against, and asking for the wallpaper's own
        # resolution would store a 3MB mask carrying no information the 1024
        # one does not - the same trade §3 of the design already made.
        feed["orig_im_size"] = np.array([resized[1], resized[0]], np.float32)
    outputs = session.run(None, feed)
    masks = outputs[0]
    scores = outputs[1] if len(outputs) > 1 else None
    if masks.shape[1] > 1 and scores is not None:
        # A multi-mask export answers with the subject at three scales - a
        # sleeve, an arm, a person - and the IoU head is the model's own opinion
        # of which one the click meant.
        best = int(np.argmax(np.asarray(scores).reshape(-1)))
    else:
        best = 0
    return 1.0 / (1.0 + np.exp(-masks[0][best].astype(np.float32)))


def select(root, wallpaper, model, points):
    """Cut a mask from clicks, or clear the one that is there.

    No `.none` marker is ever written here, and that is the difference between a
    model's verdict and a user's gesture. `<key>.<model>.none` means "this model
    looked at this picture and there is nothing in it", which is worth recording
    so nobody spends 4.5s learning it twice. A click that lands on flat sky is
    not that: it is one attempt, and recording it would tell the picker to stop
    offering the one column whose whole point is that the user aims it.
    """
    if MODELS.get(model, {}).get("kind") != "prompted":
        raise RuntimeError(f"{model!r} takes no clicks; use `run --model {model}`")
    key = cache_key(wallpaper)
    root.mkdir(parents=True, exist_ok=True)
    candidate = root / f"{key}.{model}.png"

    if not points:
        candidate.unlink(missing_ok=True)
        return {"state": "cleared", "key": key, "model": model}

    embedding, resized = image_embedding(root, wallpaper, model, key)
    mask = decode_mask(root, model, embedding, resized, points)
    foreground = float((mask > 0.5).mean())

    if foreground < EMPTY_PROMPTED_FOREGROUND:
        candidate.unlink(missing_ok=True)
        return {"state": "empty", "key": key, "model": model,
                "foreground": foreground, "prompt": points}

    write_mask(candidate, mask, prompt=points)
    return {"state": "produced", "key": key, "model": model,
            "mask": str(candidate), "foreground": foreground, "prompt": points}


def run(root, wallpaper, model, force=False):
    if model not in MODELS:
        raise SystemExit(f"unknown model {model!r}; expected one of {', '.join(MODELS)}")
    if MODELS[model]["kind"] == "prompted":
        raise RuntimeError(f"{model!r} needs clicks; use `select --model {model} "
                           f"--point x,y`")
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


def write_mask(path, mask, prompt=None):
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

    A prompted mask carries the clicks that produced it in a PNG text chunk,
    INSIDE the file. Three alternatives were available and each of them is a
    pair that has to agree:

    - putting the prompt in the cache key mints an entry per click, so a
      five-click refinement leaves five masks and the question "which of these
      did the user accept" needs a sixth file to answer it;
    - a sidecar JSON beside the mask is two files a sweep, a copy or a crash can
      separate - and `accept` is a byte copy, so the sidecar would have to be
      copied too, by hand, in the one place forgetting is silent;
    - recording it in the config is a per-wallpaper map keyed by a runtime path,
      which is exactly what `Config.qml`'s JsonAdapter cannot hold.

    In the file, the prompt cannot arrive without its mask or outlive it, the
    byte-for-byte `accept` carries it for free, and `accepted_model`'s
    content comparison still works because both sides carry the same chunk.
    """
    import numpy as np
    from PIL import Image
    from PIL import PngImagePlugin

    plane = (np.clip(np.asarray(mask, dtype="float32"), 0.0, 1.0) * 255).astype("uint8")
    info = None
    if prompt is not None:
        info = PngImagePlugin.PngInfo()
        info.add_text(PROMPT_CHUNK, json.dumps({"version": PROMPT_VERSION,
                                                "points": prompt}))
    Image.fromarray(np.dstack([plane, plane]), "LA").save(path, pnginfo=info)


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
    p_run.add_argument("--model", default="isnet-anime", choices=salient_models())
    p_run.add_argument("--force", action="store_true",
                       help="re-run even when a candidate is already cached")

    p_select = sub.add_parser("select", help="cut a mask from clicks on the picture")
    p_select.add_argument("wallpaper")
    p_select.add_argument("--model", default="mobile-sam", choices=prompted_models())
    p_select.add_argument("--point", action="append", default=[], metavar="X,Y[,LABEL]",
                          help="a click, normalised to the picture: 0,0 is the top "
                               "left and 1,1 the bottom right. LABEL is 1 for a "
                               "point the subject must contain (the default) and 0 "
                               "for one it must not. Repeatable; no points at all "
                               "clears the candidate.")

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
        elif args.command == "select":
            result = select(root, args.wallpaper, args.model,
                            [parse_point(p) for p in args.point])
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
