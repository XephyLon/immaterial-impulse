#!/bin/bash
# Looks at the notification popup's compositor blur, which nothing else can.
#
# The blur is produced by Hyprland from an ext-background-effect region the
# shell publishes, so neither qmltestrunner (Quickshell's plugin does not load
# there - Region cannot even be constructed) nor headless weston (it implements
# no ext-background-effect) can see it. This runs a NESTED Hyprland on its own
# D-Bus session instead, and photographs the result with grim.
#
# NotificationBlurProbe.qml draws a hard checkerboard backdrop and, over it, the
# real NotificationPopup between two controls: a card publishing a region the
# way the bar does, and a card publishing none. The notification cards should
# read like the first and not like the second.
#
# It shoots three times, and the third is the point: the popup times out between
# them, so the layer surface goes down and comes back exactly as it does all day
# on a real desktop. The bug this probe was written for only showed from the
# second popup onward - see NotificationCardsRuntimeTest.qml.
#
# It measures rather than leaving you to squint, because the difference is real
# but small: over the checkerboard, at the default 0.11 background transparency,
# a blurred card's interior varies by ~2/255 along a row and an unblurred one by
# ~25. The two control cards are printed beside each shot as the calibration -
# read the notification number against them, not against an absolute threshold.
# Look at the PNGs too, upscaled with `magick -filter point -resize 300%`.
#
# Usage: tests/run_notification_blur_probe.sh [/tmp/notifblur.png]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/notifblur.png}"

for binary in Hyprland qs grim notify-send dbus-launch; do
    command -v "$binary" >/dev/null 2>&1 || { echo "SKIPPED: $binary not on PATH"; exit 0; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"
export XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME/immaterial-impulse" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
# Bottom left, away from Hyprland's own startup banners, and transparency on -
# an opaque card has nothing to show through it either way.
printf '%s' '{"appearance":{"transparency":{"enable":true,"automatic":false,"backgroundTransparency":0.11,"contentTransparency":0.57}},"notifications":{"position":"bottom_left"}}' \
    > "$XDG_CONFIG_HOME/immaterial-impulse/config.json"

# Mirrors dots/.config/hypr/hyprland/rules.lua for the namespaces under test:
# the catch-all whole-surface blur on, turned off again for the surfaces that
# publish a region of their own.
cat > "$TMP/hypr.lua" <<'LUA'
-- Scale 1, so the control cards sit at the pixel coordinates the probe declares
-- and the measurement below can read them without hunting for them.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true,
             force_default_wallpaper = 0, disable_autoreload = true },
    animations = { enabled = false },
    decoration = {
        blur = { enabled = true, xray = false, special = false, new_optimizations = true,
                 size = 10, passes = 3, brightness = 1, noise = 0.05, contrast = 0.89,
                 vibrancy = 0.5, vibrancy_darkness = 0.5, popups = false,
                 popups_ignorealpha = 0.6 },
    },
})
hl.layer_rule({ match = { namespace = ".*" }, xray = false})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.05})
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:probeStatic" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:probeUnblurred" }, blur = false})
LUA

eval "$(dbus-launch --sh-syntax)"
before=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | tr '\n' ' ')
Hyprland -c "$TMP/hypr.lua" > "$TMP/hypr.log" 2>&1 &
HPID=$!

NEW=""
for _ in $(seq 1 60); do
    sleep 0.5
    for s in $(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$'); do
        case " $before " in *" $s "*) ;; *) NEW="$s";; esac
    done
    [ -n "$NEW" ] && break
done
if [ -z "$NEW" ]; then
    echo "FAILED: the nested compositor never came up"
    tail -20 "$TMP/hypr.log"
    kill $HPID 2>/dev/null
    exit 1
fi
export WAYLAND_DISPLAY="$NEW"
echo "nested compositor on $NEW"

cd "$ROOT"
qs -p "$ROOT/NotificationBlurProbe.qml" > "$TMP/probe.log" 2>&1 &
QPID=$!
sleep 8

notify-send "Probe" "First card - the surface is fresh"
sleep 4
grim "${OUT%.png}_first.png"
# 7s default timeout, so this outlives the popup: the surface goes down.
sleep 12
notify-send "Probe" "Second card - the surface was rebuilt"
sleep 4
grim "${OUT%.png}_second.png"
sleep 12
notify-send "Probe" "Third card - and rebuilt again"
sleep 4
grim "${OUT%.png}_third.png"

kill $QPID 2>/dev/null
hyprctl dispatch exit >/dev/null 2>&1
sleep 1
kill $HPID 2>/dev/null
kill "$DBUS_SESSION_BUS_PID" 2>/dev/null

grep -E "ERROR|WARN scene" "$TMP/probe.log" | head -10
echo "wrote ${OUT%.png}_first.png ${OUT%.png}_second.png ${OUT%.png}_third.png"

python3 - "${OUT%.png}" <<'PY'
import sys

try:
    from PIL import Image
except ImportError:
    print("(install python-pillow for the numbers; the PNGs are still there)")
    raise SystemExit(0)


def spread(im, x0, x1, y):
    row = [im.getpixel((x, y))[0] for x in range(x0, x1)]
    return max(row) - min(row), sum(row) / len(row)


def card_rows(im):
    """The notification card's flat interior rows, found from the bottom left.

    Only rows dark enough to be inside the card and free of its text and icon,
    so the number reported is backdrop bleed rather than glyph contrast.
    """
    width, height = im.size
    rows = []
    for y in range(height - 5, height - 200, -1):
        s, mean = spread(im, 45, min(350, width), y)
        if mean < 70 and s < 60:
            rows.append(s)
    return rows


for shot in ("first", "second", "third"):
    im = Image.open(f"{sys.argv[1]}_{shot}.png").convert("RGB")
    blurred, _ = spread(im, 70, 310, 120)
    plain, _ = spread(im, 70, 310, 280)
    rows = card_rows(im)
    card = min(rows) if rows else None
    print(f"  {shot:<6} control blurred={blurred:<4} control unblurred={plain:<4} "
          f"notification card={card if card is not None else 'not found'}")
PY
