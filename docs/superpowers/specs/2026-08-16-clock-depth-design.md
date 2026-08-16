# Clock depth mode — feasibility and design

**Status:** design, not implemented. The feasibility question is settled with measurements; §1 is the
evidence and §2 onward is what to build on top of it.
**Scope:** `modules/imi/background/Background.qml`, a new `scripts/background/` producer, the
wallpaper selector, `sdata/uv/`.

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative.

## Problem

iOS draws the lock-screen clock *between* the wallpaper's background and its subject, so the person
in the photo stands in front of the time. The shell draws the desktop clock flat on top of
everything. The ask is the iOS effect: the wallpaper's subject in front of the clock.

The hard part is not the compositing. It is deciding, offline, on an arbitrary wallpaper, which
pixels are "the subject". Everything else in this document is contingent on that working, so it is
settled first, with numbers, before a line of design is written against it.

---

## 1. Does segmentation work here?

### 1.1 What is already installed, and why it cannot be used

`rembg` 2.0.76 and `onnxruntime-gpu` 1.26.0 are both already present in the user's global
`~/.local/lib/python3.14/site-packages`. Neither is usable:

```
>>> import rembg
ImportError: Numba needs NumPy 2.4 or less. Got NumPy 2.5.
```

`rembg` pulls `pymatting` → `numba`, and `numba` is pinned below the `numpy` the user's global
site-packages carries. A rolling Arch system with one shared user site-packages will keep breaking
this: `numba` trails `numpy` by months, every unrelated `pip install --user` can move `numpy`, and
`rembg` is only in the AUR (`aur/python-rembg 2.0.72-1`, flagged out-of-date since 2026-07-18) so
`pacman -Syu` will never repair it. **Do not depend on `rembg`.** Its actual value — the ONNX models
it hosts as release assets — is reachable without it.

`onnxruntime` is the opposite case. It is in the **official** Arch repos as
`extra/python-onnxruntime-cpu 1.28.0-1` (12.96 MiB download, 63.89 MiB installed), and the shell
already owns a `uv`-managed venv at `$IMMATERIAL_IMPULSE_VIRTUAL_ENV`
(`~/.local/state/quickshell/.venv`, Python 3.12, 331 MB) built from `sdata/uv/requirements.in` —
which already carries `numpy`, `pillow` and `opencv-contrib-python`. Adding `onnxruntime` there is
one line and one 53 MB wheel, in an environment whose whole point is that it is not the system
Python.

So the shape of the dependency is: **ONNX Runtime directly, no `rembg`, models fetched as files.**
The measurements below were taken exactly that way — a throwaway venv with `onnxruntime`, `pillow`
and `numpy`, driving the `.onnx` files that `rembg` publishes as GitHub release assets.

### 1.2 The general-purpose models do not work on this library

Three candidates, run over **all 91 images in `~/Pictures/Wallpapers`** (the directory
`background.wallpaperPath` points into):

| model | size | input | median inference |
|---|---|---|---|
| `u2netp` | 4.6 MB | 320² | 0.13 s |
| `u2net` | 176 MB | 320² | 0.31 s |
| `isnet-general-use` | 179 MB | 1024² | 0.66 s |

`u2netp` and `u2net` can be dismissed on sight. On a clean, high-contrast, square-cropped figure —
the easiest case in the library — `u2net` returns a featureless blob with no edge definition
anywhere: the silhouette is roughly in the right place and the boundary is a soft cloud tens of
pixels wide. Nothing can be occluded by that convincingly.

`isnet-general-use` is much better and still not good enough. Scoring its 91 masks numerically
(foreground fraction, and what share of foreground pixels are above 0.95) puts 27 of them in a
"candidate" band. Rendering those 27 as cutouts over a flat magenta field — which is the only
honest way to look at a mask, because a soft edge is invisible against the image it came from —
shows the numeric score is far too generous. **Three are clean.** The rest split into two failure
modes, both of which the numbers score as *confident*:

- **Rectangular slabs.** The mask is a box loosely enclosing the characters, carrying a large block
  of background with them. It is high-confidence and bimodal and completely wrong.
- **False positives on landscapes.** On subject-less wallpapers the model latches onto whatever is
  locally salient — a tower, a rock — and returns a small confident fragment.

Two of the three clean results are the only near-photographic images in the collection. That is the
whole finding: **U²-Net and IS-Net general are trained on DUTS-style photographic salient objects,
and this library is overwhelmingly anime illustration and ultrawide AI landscapes.** Flat shading,
graphic backgrounds, and hair that reads as texture rather than as an object are out of
distribution.

Two things measured along the way that are worth not re-deriving:

- **Letterboxing the input is actively wrong.** These models resize to a square, ignoring aspect —
  a 3.56:1 wallpaper gets squashed 3.5×, which is severe, so padding to a square looks like the
  obvious improvement. It is not: with black bars the model treats the bars as background and
  returns the *entire picture* as the subject. Measured foreground fraction 0.9999 on three
  separate images. Squash, or crop; never pad.
- **Tiling is wrong for the same reason the landscape false positives happen.** These are *saliency*
  models: each tile independently answers "what stands out in this tile", so a tile of pure
  background confidently returns its most interesting rock. Whole-image squash is what produces the
  correct "there is nothing here" answer — `isnet-general-use` returns fg=0.0018 on the current
  wallpaper and `isnet-anime` returns exactly 0.0000.

### 1.3 The anime model works, and it is a different answer

`isnet-anime` (176 MB, 1024² input, same normalisation as `isnet-general-use`) is trained on anime
characters, and on this library it is not a marginal improvement — it is the difference between the
feature existing and not existing.

Swept over the same 91 images: 51 return an empty mask, 10 return a near-full-frame mask (character
fills the frame — a correct mask with nothing to sit behind), 9 are mushy, and 21 land in the
candidate band. Rendered as cutouts over magenta, **roughly a dozen of those 21 are clean** — the
silhouette follows the characters, including individual hair tufts, with no background slab and no
halo. The failures that remain are low-contrast white-on-white art and a couple of frames where a
rectangular block of background comes along.

More importantly, the refusals are correct. On `aishot-1206.jpg` (the current wallpaper, a
subject-less valley landscape), on the lock wallpaper, and on a third landscape, `isnet-anime`
returns a foreground fraction of **exactly 0.0000** — where `isnet-general-use` returned confident
fragments on the same images. A model that says nothing when there is nothing is worth more here
than a model with a higher raw hit rate, because a false positive is a visible defect on the
desktop and a false negative is just the feature staying off.

**The proof that matters.** Compositing the real scenario — `arknights-endfield…jpg` cropped to the
monitor's 5120×1440 as the shell would crop it, a 420pt `21:47` drawn on the wallpaper, and the
`isnet-anime` cutout laid back on top:

The `21:` is fully occluded by the central figure. The `47` shows through the gap between two
characters and is clipped on its right by a third. At 1:1 the occlusion boundary follows the raised
arm, the shoulder pad and the short-haired girl's hair tufts. There is no fringe, no halo, no
background bleed. It reads as depth.

**One model does not cover the library.** `isnet-anime` returns fg=0.002 — nothing — on
`wallhaven-13x5vv.jpg`, the semi-photographic girl with a sunflower that `isnet-general-use`
handled best (fg=0.339, conf=0.78). The two models are complementary and neither is a superset. Any
design that picks one model globally throws away half the wallpapers it could have worked on.

### 1.4 What it costs

Measured on this machine (Ryzen, 16 threads, 61 GB RAM; CPU execution provider only — **no GPU is
used or needed**, and the RTX 4080 stays out of it, which matters because the shell's own renderer
wants it):

| | `isnet-anime` | `isnet-general-use` |
|---|---|---|
| model file | 176 MB | 179 MB |
| inference, median / p90 / max over 91 images | 0.59 / 0.74 / 0.83 s | 0.66 / 0.84 / 1.39 s |
| **cold subprocess, end to end**, 3840×1594 | **1.33 s** | 1.5–2.4 s |
| cold subprocess, 7680×2160 JPEG | — | 3.07 s |
| cold subprocess, 8400×4725 43 MB PNG | — | 4.54 s |
| peak RSS | 1.02 GB | 1.07–1.13 GB |
| `import onnxruntime, numpy, PIL` | 0.15 s | — |
| session construction from a warm page cache | 0.28–0.35 s | — |

The end-to-end figure is what the shell would pay, and it is dominated by decode and downscale of a
very large source image, not by the network: on the 43 MB PNG, preprocessing is 1.05 s and
postprocessing 0.88 s against 1.14 s of inference. Peak RSS is around 1 GB regardless.

**This is a one-to-four-second job with a gigabyte of transient RSS.** That is nowhere near a
per-frame cost and it is also nowhere near free. It is firmly in "run it once, off the hot path,
cache the answer" territory — and, as §3 argues, it is slow enough and unreliable enough that
running it automatically on every wallpaper change is the wrong design even though it would be
affordable.

### 1.5 Verdict

Segmentation is **feasible**, with three qualifications that shape everything below:

1. Only `isnet-anime` works on the bulk of this library, and it does not work on the photographic
   minority, which needs `isnet-general-use`. Two models, chosen per wallpaper.
2. Even the right model produces an unusable mask perhaps a third of the time it produces one at
   all, and the failure is not detectable from the numbers — it needs an eye.
3. It costs 1.3–4.5 s and ~1 GB of RSS per run.

Point 2 is the decisive one. A pipeline that segments automatically and applies the result silently
will, several times a week, put a rectangular slab of background over the clock. **So depth mode is
not an automatic effect. It is a per-wallpaper artifact the user accepts once**, with segmentation
as the thing that proposes candidates. That is a smaller feature than "iOS depth mode", it is
honest about a 1-in-3 failure rate, and it makes the visible behaviour deterministic — which is also
the only reason it is testable.

---

## 2. Where the layer lives

`Background.qml` runs one `PanelWindow` per screen (`:20`, `Variants { model: Quickshell.screens }`)
with three visual children:

- `parallaxViewport` (`:661`), z 0, sized `parallaxWidth × parallaxHeight` — the screen times
  `parallax.workspaceZoom` — and positioned at `parallaxOffsets`. **Every wallpaper layer is inside
  it**: the Wallpaper Engine surface, the frozen WE still, the still `wallpaper` image, the outgoing
  `previousWallpaper`, all three peel `ShaderEffect`s, the lock blur, the centred-wallpaper shape.
- `widgetCanvas` (`:1119`), **z 2** (`:1158`), screen-sized and never zoomed, positioned at
  `widgetParallax`. The clock plugin lives here.
- `desktopRightClickArea` (`:1248`), z −2.

The first thing to settle is whether a new layer can even go where it needs to go, because the
obvious placement is wrong. A child declared inside `parallaxViewport` inherits the pan for free —
which is exactly what a cutout tracking the wallpaper wants — but **a child's `z` only reorders it
against its viewport siblings; it can never lift it above `widgetCanvas`.** `weTransition` at
`z: 1` (`:764`) is precisely that case, and the comment at `:1156` says so. A cutout inside the
viewport would be drawn *under* the clock, which is the effect the shell already has.

So the depth layer is a **sibling of `parallaxViewport` with `z > 2`**, and it therefore inherits
nothing. Three things it has to reconstruct, each of which is a bug the file has already been
through once:

**It binds to the viewport's live geometry, not to the parallax targets.** The layer must be
`x: parallaxViewport.x`, `y: parallaxViewport.y`, `width: parallaxViewport.width`,
`height: parallaxViewport.height` — the animating item's own properties. Binding to
`bgRoot.parallaxOffsets` instead reads the 600 ms `Behavior`'s *destination*, so the cutout would
slide to the new position instantly while the wallpaper under it took 600 ms to arrive: a subject
detached from its own image for the whole of every workspace switch. This is the same mistake as
#157, fixed by ca667957a ("fix(widgets): sample the desktop frost in the wallpaper's own space"),
and the file already carries the correct pattern one screen up — the frost's `wallpaperRect` at
`:1241` reads `parallaxViewport.x/.y/.width/.height` for exactly this reason.

**It carries its own `visible: !bgRoot.suppressContents`.** The fullscreen gate is applied three
separate times today, once per top-level visual child (`:669`, `:1127`, `:1253`), and `:1123`
documents why `widgetCanvas` needed its own copy when it moved out of the viewport. A fourth
sibling needs a fourth copy or the subject floats over fullscreen video with the wallpaper gone.

**It accepts no input.** `desktopRightClickArea` sits at `z: -2`, *below* everything, and works only
because every layer above it is a plain `Image`/`ShaderEffect` that lets clicks fall through. A
`MouseArea` or a `HoverHandler` anywhere in the depth layer silently kills the desktop right-click
menu and every widget drag.

The layer itself is small: an `Image` of the same wallpaper source with the same
`fillMode: PreserveAspectCrop`, with the mask applied as an `OpacityMask` (or an `alphaMap`
`ShaderEffect`, whichever profiles better on a 5120-wide texture — one extra textured quad either
way). Because it is the *same* source at the *same* size with the *same* fill mode as the
`wallpaper` item inside the viewport, **the per-screen crop matches automatically**: one mask file
serves every monitor without any per-screen geometry, and a second monitor with a different aspect
crops mask and wallpaper identically. This is worth stating because the alternative — computing a
crop rect per screen — is where this feature would otherwise grow a whole class of alignment bugs.

**A wrong mask is invisible where no widget sits.** The depth layer paints the wallpaper's own
pixels back over themselves; outside the widgets it is a no-op. So a slab of background 2000 px from
the clock costs nothing, and the quality bar is only ever "is it right where a widget is". That does
not rescue the rectangular-slab failures — those are usually large and central — but it does mean
the effect degrades locally rather than globally, and it is why the accept/decline decision in §4
should be shown *with the widgets on screen* rather than as a bare cutout.

---

## 3. Caching

Segmentation must run once per wallpaper, ever — not per frame, not per restart, not per workspace
switch, and not per monitor.

The cache is `${Directories.cache}/clock-depth/`, following `wallpaperEngineStills` (`:52` in
`Directories.qml`) as the precedent for a cache directory that is deliberately **not** wiped at
startup. A 1024² grayscale PNG is 50–190 KB, so a hundred masks is ~10 MB.

**The key is derived from the wallpaper's path, mtime and size, and the shell never computes it.**
Path alone is wrong — the user's directory is full of files edited and re-exported in place, and a
stale mask over a changed image is the worst failure this feature has. Including mtime and size
makes an in-place edit produce a new key automatically, with the old entry becoming garbage the LRU
sweep collects.

The temptation is to derive that key in QML so the shell can check the cache without spawning
anything. Resist it: two implementations of a hash in two languages is the `activeStill` shape —
two things that must agree and eventually will not, with nothing reporting it. **The script owns the
key.** The shell invokes the producer with a wallpaper path; the producer computes the key, finds a
hit, and prints the mask path on stdout in ~30 ms without loading a model. One implementation, and
it is the one that is unit-testable.

Invalidation therefore has exactly three sources and no explicit invalidation code:

- the wallpaper path changes → different key;
- the wallpaper file changes in place → different key;
- the user re-runs the picker on the same wallpaper → the picker overwrites that key's entry.

The mask is stored at **model resolution (1024²), not at wallpaper resolution.** Upscaling to
5120 px is a `smooth: true` texture fetch the GPU does for free, and storing a 7680×2160 grayscale
PNG instead costs 3 MB per wallpaper and 0.88 s of write time for information that is not in the
mask. The boundary is inherently ~5 screen px soft at 5120 wide; against a clock that reads as
antialiasing, which is the one place this feature gets to be lucky.

---

## 4. Interaction with the existing wallpaper features

Depth mode **supports** a still image wallpaper, on any number of monitors, at rest and while
panning. That is the whole supported set. Everything else refuses, and refusing is cheap because
§2's eligibility predicate is one function.

**Wallpaper Engine (live) — refused.** A WE project is a moving surface with no file to segment;
there is nothing to key a cache against and nothing to run a 1.3 s job over. Segmenting the frozen
greeter still and applying it to a moving scene would put a stale silhouette over animated content.

**Video wallpapers (mpvpaper) — refused, and for a stronger reason.** mpvpaper is a separate Wayland
client on its own layer surface. The shell does not own those pixels, cannot sample them
(a `ShaderEffectSource` reaches items in this scene graph, and another client's surface is not one),
and `parallaxViewport` does not move them — 918592d33 ("fix(background): frost a video wallpaper
against the screen, not the viewport") is the whole story. A cutout would have to be built from
`thumbnailPath`, the ffmpeg first frame, and laid over a video that has since moved: a still ghost
of frame 1 hovering over a playing video. Refuse on `wallpaperIsVideo`.

**Transitions — the layer fades out and back, it does not follow.** For the 1200 ms of a switch
(`Appearance.wallpaperTransitionDuration`) the viewport is showing a shader blend of two images.
A depth layer showing the incoming wallpaper's subject would be a hard cutout of an image that is
only 30 % faded in. The alternative — running the same peel shader in the depth layer against two
masked cutouts — means keeping the outgoing mask alive, doubling the shader work, and getting the
`weTransition` visibility guards (`:769-773`, three of them, each earned) wrong in a new place. Fade
the depth layer to 0 when a transition starts and back to 1 when it settles; the clock is briefly
flat, during 1.2 s in which the whole wallpaper is visibly changing anyway.

**Parallax — supported, and it is the reason for §2's live-geometry binding.** Note what the user
will actually see: the wallpaper travels edge-relative at factor 1.0 while `widgetCanvas` travels
centre-relative at `widgetsFactor` (default 1.2) — two different formulas, `parallax.js:68` and
`:105`. So the clock moves *relative to the subject* during a workspace switch, and the occlusion
changes as it does. That is correct; it is what makes the effect read as depth rather than as a
sticker. It also means a clock positioned to peek out from behind a shoulder at rest may be fully
hidden two workspaces over, which is a real usability wrinkle and belongs in the picker's preview.

**Multi-monitor — supported, and free.** One mask per wallpaper serves every screen, per §2. The
per-screen `Background` instances each build their own depth layer bound to their own viewport.

**Lock screen — out of scope for the first landing.** `lockWall` is a different image with its own
peel machine (`:900`) and a blur that zooms (`:919`), and `lock.centerClock` overrides the clock's
position entirely (`clock/Widget.qml:40`). It is a coherent second feature, not a special case of
this one.

**Centred wallpaper mode — refused.** `centeredWallpaperShapeItem` (`:959`) is a
`centerIn`-anchored `MaterialShape` with an `OpacityMask`, at `centeredWallpaperSize`, which is a
completely different geometry from the viewport. A depth layer bound to the viewport would be
wallpaper-sized over a shape-sized wallpaper.

---

## 5. Failure and opt-out

There are four distinct failure states and they need four different behaviours, because collapsing
them is how a feature ends up silently off with no way to find out why.

**No mask has been produced for this wallpaper.** The default state for every wallpaper. The depth
layer does not exist; the clock draws flat, exactly as today. This is not an error and must not
surface as one.

**Segmentation ran and found nothing.** `isnet-anime` on a landscape returns 0.0000, which is the
right answer. The picker says so — "no subject found" — and writes a negative marker at the key so
the answer is not recomputed on every visit. The marker is a `<key>.none` file, not a config entry,
so it invalidates with the key like everything else.

**Segmentation ran and the mask is bad.** The user declines it in the picker. This writes
`<key>.off`, which is the **per-wallpaper opt-out**, keyed identically to the mask and invalidated
identically. It is deliberately not a `Config` key: a per-wallpaper map keyed by a runtime path is
exactly what `Config.qml`'s `JsonAdapter` cannot hold (undeclared children have segfaulted
deserialization here), and `PluginState` is for plugin state. A file beside the mask is the whole
mechanism, and re-running the picker overwrites it.

**The mask file is missing or corrupt at load.** An `Image` with a bad source is `Image.Error` and
paints nothing, which for this layer degrades to exactly the flat clock — the right failure
direction, and worth asserting rather than assuming.

Above all of that sits one global `Config.options.background.clockDepth.enable`, default **false**.
A feature that puts pixels over the clock ships off; the first wallpaper the user accepts a mask
for is what turns it on for that wallpaper.

The eligibility predicate is then one pure function of six inputs — global enable, mask present,
opt-out marker, `wallpaperIsVideo`, `weActive`, transition in flight — and it belongs in
`modules/common/functions/clockDepth.js` as a `.pragma library`, for the reason §6 gives.

---

## 6. Testability

Split honestly, because most of this feature is not reachable from `qmltestrunner` and pretending
otherwise is how the parallax opt-out stayed green through its entire broken life.

**Fully unit-testable, and where the real logic is:**

- *Cache key derivation and cache lookup*, in Python beside the producer.
  `tests/test_clock_depth_cache.py` pins that a path/mtime/size triple maps to a stable key, that
  touching the file changes it, that a hit returns without constructing a session, and that the LRU
  sweep keeps the newest N. This is the piece with real edge cases and it is the piece the shell
  trusts blindly, so it is the piece that gets tested hardest.
- *The eligibility predicate*, in `clockDepth.js`, via `tests/tst_clock_depth_eligibility.qml`.
  Six boolean inputs, and the cases that matter are the refusals: video, WE, mid-transition,
  opt-out marker present alongside a valid mask.

**Testable only as pixels, via a probe of the `run_card_shadow_probe.sh` kind:** headless weston,
`qs -p ClockDepthProbe.qml`, screenshot, analyse in Python with `magick`. The critical property is
that the probe **uses a synthetic mask** — a known rectangle over a flat field, with a text item
under it — so the test asserts the *compositing contract* and never runs a model. Concretely:
a pixel inside the mask rectangle where the text would be shows wallpaper; a pixel outside it shows
text; and after driving a parallax offset, the mask rectangle has travelled by exactly the
viewport's offset and not by the target. That last assertion is the one that would have caught the
live-geometry bug in §2, and it is only reachable by sampling mid-animation — the same lesson as
`WidgetResizeMotionRuntimeTest.qml` sampling at 80 ms rather than at settle.

**Guardable by lint, because it is a two-sided contract:** the depth layer's `fillMode` and geometry
must match the `wallpaper` item's, or the mask crops differently from the image it masks. That is a
source-text property and belongs in a small check rather than in a comment.

**Not testable at all, and say so:** whether any given mask is *good*. There is no automatic check —
that is the entire finding of §1.2, where a numeric score confidently ranked rectangular background
slabs above clean cutouts. The accept/decline step in the picker is not a UI nicety; it is where the
quality gate lives, and it is a human.

---

## 7. Decomposition

Four stages, each landable and reviewable on its own.

**Stage 1 — the subject-mask producer and its cache.** `scripts/background/subject_mask.py`: takes a
wallpaper path and a model name, computes the cache key, returns a hit immediately or runs
ONNX Runtime and writes a 1024² mask plus a `.none` marker when the model returns nothing. Adds
`onnxruntime` to `sdata/uv/requirements.in` and a first-use model fetch (two 176 MB files, not
bundled). Ships with `tests/test_clock_depth_cache.py`. **No shell changes and no visible
behaviour** — the deliverable is a CLI whose output can be inspected by hand, which is the right
first stage precisely because §1 says the interesting question is what the masks look like.

**Stage 2 — the depth layer.** The sibling item in `Background.qml`, `clockDepth.js`, the
eligibility wiring, the probe and the geometry lint. Driven by a mask path handed to it; the only
way to get one is to run stage 1 by hand. This is where the live-geometry, fullscreen-gate and
input-transparency traps get resolved against a real compositor.

**Stage 3 — the picker.** In the wallpaper selector: run both models on the current wallpaper,
preview each result *with the desktop widgets composited over it*, and accept, decline (`.off`) or
choose neither. This is the stage that makes the feature usable and it is deliberately last, because
its whole design depends on having looked at stage 1's real output.

**Stage 4 — lock screen.** `lockWall` and `lock.centerClock`, if wanted.

Start with **Stage 1: the subject-mask producer and its cache.**

---

## 8. Wallpaper Engine — designed, not landed

§4 refused a live Wallpaper Engine project on the reasoning that it is "a moving
surface with no file to segment". The first half is true and the second is not:
the shell already photographs every WE project it renders. This section is what
that opens, what it costs, and where it stops being honest — written now because
WE support is wanted, and stated as a design rather than shipped because none of
it is reachable from a headless harness.

### 8.1 There is already a static input, and it registers for free

`Background.captureGreeterStill` (`Background.qml:381-404`) grabs `weLoader.item`
into `${Directories.wallpaperEngineStills}/${activeProject}.png`, 600 ms after the
surface reports its first frame, once per project load, on the first screen only.

Two measured properties of those files decide most of the design. There are 16 on
this machine, at 5120x1440 and 5478x1540 — **the viewport's own size**, because
the WE layer is `anchors.fill: parent` inside `parallaxViewport`. So a still's
aspect *is* the viewport's aspect, `coverRect` degenerates to the identity, and a
mask cut from a still registers 1:1 onto the layer with no new geometry at all.
The zoom is baked in, but only as a scale factor on both axes, which `coverRect`
already absorbs.

`web` projects never arrive here: `weActive` (`:274`) excludes them and they fall
back to the static wallpaper, which this feature already supports.

### 8.2 The cache key cannot be the still's stat triple

`cache_key` hashes path, mtime and size. The still is re-grabbed on **every load
of the project**, so its mtime moves every session — measured, four of the 16
stills on this machine were rewritten today. Keying on the file would therefore
mint a new key per session, which does not merely re-run a 1.3 s job: the
acceptance lives at the key (`<key>.png`), so **the user's verdict would be lost
on every restart**, silently, and the feature would read as "it forgets".

So the producer needs a caller-supplied identity — `--identity we:<projectId>` —
hashed in place of the stat triple, with the still passed as the image to
segment. Roughly fifteen lines and a handful of cases in
`test_clock_depth_cache.py`. The trade it makes is the mirror image of §3's: an
identity keyed on the project id does **not** notice the user editing the
project, so a changed scene keeps its old mask until the picker is re-run. That
is the right way round — a stale mask over an edited *file* is §3's worst
failure because nothing prompts the user, whereas changing a WE project is
something the user did on purpose and can re-judge from the picker.

### 8.3 Mask the live surface, never the still

The obvious implementation — draw the still, masked — is wrong. It would put a
frozen frame over a moving scene, so every animated pixel inside the silhouette
would be visibly stale.

The layer should mask the **live** surface instead:
`ShaderEffectSource { sourceItem: weLoader.item }`, which this file already
builds as `weLiveSource` (`:753`) for the WE transition, sized to the same
viewport. Then the pixels are live and only the *silhouette* is static.
`ClockDepthCutout` grows a `liveSource` alternative to `wallpaperSource` and
hands whichever is set to the `OpacityMask`; the lint's "shares the wallpaper's
image request" rule stays scoped to the still-image path, since there is no
second decode to share on the live one.

### 8.4 Where it stops being honest, and what the UI must say

A static mask over a live scene is correct exactly while the subject does not
move within the frame. A character standing in a parallaxing scene is the case
that works, and it is the common case in this library. A scene whose subject
walks, turns or is occluded by its own animation will drift out of its silhouette
— the clock will be covered by nothing, or uncovered by something.

There is no way to detect that automatically (the same finding as §1.2, one level
up: judging whether a mask holds across a scene's motion is exactly as
unautomatable as judging whether it is a good mask). So it belongs in the picker
next to the verdict, in the same place the mask's own quality is judged, and the
inspect mode added since §6 is what makes it judgeable: dim what the model did
not claim, then let the scene run for a few seconds and watch whether the
subject leaves its own outline.

### 8.5 Two availability edges

A project that has not rendered in a session with the shell up has **no still**,
so the picker must say "show this wallpaper first" rather than fail. And the
still belongs to the first screen only, which is fine — one mask serves every
monitor, per §2 — but it means a project that has only ever been shown while the
first screen was suppressed has none either.

### 8.6 Why this is a separate landing

None of §8 can be verified where the rest of this feature is verified. Weston
runs no Wallpaper Engine renderer and the WE module is a separate build, so the
probes cannot reach any of it; it has to be judged on the real desktop, by
looking at a moving scene. That is a different kind of change from the ones this
PR carries, all of which are pinned headlessly — and the instrument §8.4 depends
on is the inspect mode this PR adds, so the order is the right way round.
