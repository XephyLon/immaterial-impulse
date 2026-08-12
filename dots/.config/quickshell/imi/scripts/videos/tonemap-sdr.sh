#!/usr/bin/env bash
# Tonemap an HDR recording to SDR, in place - the delivery half of HDR capture.
#
# Recording on an HDR display stores real HDR10 (record.sh picks the _hdr
# codec variants), which is correct in HDR-aware players and washed out in
# everything that does not tonemap - VLC's defaults, Discord embeds, browsers,
# editors. gpu-screen-recorder cannot tonemap at capture time, so when the
# user opts in (screenRecord.tonemapSdr) this runs after the save lands,
# invoked by gsr-saved.sh: probe, tonemap to bt709, atomically replace.
#
# Usage: tonemap-sdr.sh <file.mp4>
# Exits 0 without touching the file when: the toggle is off, the file is
# already SDR, or the probe fails. The original is replaced only by a rename
# of a fully-written temporary, so an interrupted run leaves it intact.
set -euo pipefail

FILE="${1:-}"
[[ -f "$FILE" ]] || exit 0

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/immaterial-impulse/config.json"
enabled="$(jq -r '.screenRecord.tonemapSdr // false' "$CONFIG_FILE" 2>/dev/null)"
[[ "$enabled" == "true" ]] || exit 0

# smpte2084 = HDR10 PQ, arib-std-b67 = HLG. Anything else is already SDR (or
# unreadable, in which case leaving it alone is the only correct move).
#
# default=nw=1:nk=1, not csv: on a real gpu-screen-recorder file the CSV row
# grows an extra field from the stream's side data (content light level), so
# the value comes back as "smpte2084," and a strict match silently classifies
# every real HDR recording as SDR. The synthetic test fixture has no side
# data, which is why only the live file caught this.
transfer="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=color_transfer -of default=nw=1:nk=1 "$FILE" 2>/dev/null \
    | head -n 1 || true)"
# Belt and braces: trim any delimiter an output format sneaks in, so a future
# probe-format change degrades to a wrong-looking value rather than a silent
# every-file-is-SDR skip.
transfer="${transfer%%[,$'\r']*}"
case "$transfer" in
    smpte2084|arib-std-b67) ;;
    *) exit 0 ;;
esac

notify-send "Tonemapping to SDR" "${FILE##*/} - the HDR original will be replaced" \
    -a 'Recorder' & disown

# THE SIGNAL PEAK MUST BE MEASURED FROM THE PIXELS. ffmpeg's `tonemap` filter,
# handed PQ input and no override, assumes a FIXED peak of 10x its reference
# white - 2030 nits - and normalises the curve by it. A desktop capture peaks
# around 235 nits (1.16x), so the whole image was squeezed into the bottom
# eighth of the curve. Scored against the compositor's own SDR rendering of the
# same desktop: SDR white left the converter at 136/255, mean error 27.3/255.
# That 10x is not inferred from the file - `peak=10.0` reproduces the default
# output byte for byte, on clips whose declared MaxCLL differs fourfold.
#
# WHICH IS THE PART THAT MISLEADS: gpu-screen-recorder really does stamp the
# MONITOR's EDID luminance into every recording as mastering-display and
# content-light-level metadata (on this 1015-nit panel every file claims MaxCLL
# 1015 whatever is on screen), and that reads exactly like the cause. It is
# not - the CPU `tonemap` filter never looks at it, and two fixtures tagged 250
# and 1015 nits tonemap identically. It matters only to libplacebo, which does
# read mastering metadata, which is why that chain gets src_max below. Do not
# "fix" this by correcting the file's metadata: the CPU path would not notice.
#
# Keyframes only and downscaled first: bounded work (0.3s on a 5s 5120x1440
# clip) and a peak that lands on the content's p99.99 rather than on one stray
# pixel - measured 235 nits where the frame's absolute maximum was 276.
#
# Floored at 1.0. A peak below reference white would ask the tonemapper to
# EXPAND the signal, and a measurement that fails must not fall back to the
# filter's own 10x, which is the bug: assuming "nothing above SDR white" clips
# a genuine highlight at worst, where 10x crushes every frame.
measure_peak() {
    local depth range ymax
    depth="$(ffprobe -v error -select_streams v:0 -show_entries stream=bits_per_raw_sample \
        -of default=nw=1:nk=1 "$FILE" 2>/dev/null | head -n1 || true)"
    [[ "$depth" =~ ^[0-9]+$ ]] && (( depth >= 8 )) || depth=10
    range="$(ffprobe -v error -select_streams v:0 -show_entries stream=color_range \
        -of default=nw=1:nk=1 "$FILE" 2>/dev/null | head -n1 || true)"
    # Captured to a variable rather than piped into a reader that can exit
    # early - the same pipefail trap documented on the libplacebo probe below.
    ymax="$(ffmpeg -v error -skip_frame nokey -i "$FILE" -an \
        -vf "scale=320:-2,signalstats,metadata=print:key=lavfi.signalstats.YMAX:file=-" \
        -f null - 2>/dev/null | sed -n 's/^lavfi\.signalstats\.YMAX=//p' \
        | sort -n | tail -n1 || true)"
    [[ "$ymax" =~ ^[0-9]+$ ]] || return 1
    awk -v y="$ymax" -v d="$depth" -v r="$range" 'BEGIN {
        s = 2 ^ (d - 8)
        n = (r == "pc" || r == "full") ? y / (2 ^ d - 1) : (y - 16 * s) / (219 * s)
        if (n <= 0) exit 1
        if (n > 1) n = 1
        m1 = 2610 / 16384; m2 = 2523 / 4096 * 128
        c1 = 3424 / 4096;  c2 = 2413 / 4096 * 32; c3 = 2392 / 4096 * 32
        p = exp(log(n) / m2)
        num = p - c1; if (num < 0) num = 0
        den = c2 - c3 * p; if (den <= 0) exit 1
        if (num == 0) exit 1
        nits = 10000 * exp(log(num / den) / m1)
        printf "%.1f", nits
    }'
}

PEAK_NITS="$(measure_peak || true)"
[[ "$PEAK_NITS" =~ ^[0-9.]+$ ]] || PEAK_NITS=203
# ffmpeg measures `peak` in units of its reference white (203 nits), which is
# also the npl the linearising zscale below is given, so the two agree.
PEAK="$(awk -v n="$PEAK_NITS" 'BEGIN { p = n / 203; if (p < 1) p = 1; printf "%.3f", p }')"

# The temporary MUST end in .mp4: ffmpeg infers the muxer from the output
# extension, and a bare ".tmp" fails - silently, if stderr is ever discarded.
# Same trap that shipped in we_still.sh once already.
tmp="${FILE%.mp4}.sdr-tmp.mp4"
log="$(mktemp --suffix=-tonemap.log)"

# libplacebo (Vulkan, GPU tonemap - fast and gamut-aware) when this ffmpeg has
# it, else the zscale/tonemap CPU chain.
#
# mobius rather than hable, now that the peak is honest: hable compresses the
# midtones even when asked to map a range that barely exceeds its target, while
# mobius stays linear below the knee and rolls off only near the peak - which
# is the shape a desktop capture has, almost all of it under SDR white with a
# little headroom above. Scored against the compositor's own SDR rendering of
# the same desktop, mean error 15.2/255 versus hable's 16.3 and the shipped
# hable-on-EDID-peak's 27.3. `clip` scored a shade better still (14.7) and is
# not used: it is only better while nothing on screen is genuinely HDR, and it
# blows those highlights out irrecoverably when something is.
#
# Captured to a variable, NOT `ffmpeg | grep -q`: grep -q exits at the first
# match, ffmpeg takes SIGPIPE, and under `set -o pipefail` the whole pipeline
# reads as failed - so libplacebo silently never got selected and every
# tonemap ran on the CPU. That single line is why the first version took 13s
# on a clip the GPU does in 5.
# ...and having the filter compiled in still does not mean a Vulkan device
# exists to run it - a machine without one dies at -init_hw_device before any
# encoder rung gets a say, taking the CPU floor down with it. So the GPU chain
# is smoke-tested for real on a one-frame nullsrc, the same
# try-it-don't-infer-it rule the encoder ladder follows. (CI is exactly such a
# machine, and the pipefail bug above had been accidentally protecting it.)
filters="$(ffmpeg -hide_banner -filters 2>/dev/null || true)"
if [[ "$filters" == *libplacebo* ]] \
    && ffmpeg -v error -init_hw_device vulkan -f lavfi -i "nullsrc=s=64x64:d=0.1" \
        -vf "libplacebo=format=yuv420p" -frames:v 1 -f null - >/dev/null 2>&1; then
    # src_max for the same reason the CPU chain gets `peak`, and with a second
    # reason of its own: libplacebo DOES read the recorder's mastering-display
    # metadata, so left alone it inherits the panel's EDID luminance rather
    # than the content's. Unverified on this machine - ffmpeg's libplacebo
    # filter fails to initialise here for every invocation, Vulkan device
    # present, so the smoke test below correctly picks the CPU chain and this
    # branch has never run.
    VF="libplacebo=tonemapping=auto:src_max=$PEAK_NITS:colorspace=bt709:color_primaries=bt709:color_trc=bt709:format=yuv420p"
    HW=(-init_hw_device vulkan)
else
    VF="zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=mobius:desat=0:peak=$PEAK,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
    HW=()
fi

# Encoder ladder: GPU first, CPU as the floor. NVENC turns a 0.6x-realtime
# x264 job into a few seconds (measured: 12.9s -> 4.9s on an 8s 5120x1440
# clip), but hardware encoders lie by omission - ffmpeg listing one does not
# mean the silicon will take the job - so each rung is tried for real and the
# first that produces output wins.
#
# H.264 preferred for the same reason the container is mp4: shareability. But
# NVENC's H.264 tops out at 4096px wide and rejects wider frames with a
# misleading "No capable devices found" (found the hard way at 5120x1440), so
# past that the rung is HEVC - still fixes every non-tonemapping player, at
# the cost of Discord-embed friendliness for ultrawide clips specifically.
width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
    -of default=nw=1:nk=1 "$FILE" 2>/dev/null | head -n 1 || echo 0)"

# The vaapi rung uses the CPU tonemap chain: mixing the Vulkan libplacebo
# filter with a VAAPI hwupload made ffmpeg's format negotiation fall over.
VF_CPU="zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=mobius:desat=0:peak=$PEAK,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"

try_encode() {
    local enc="$1" vfarg="$VF" hw=("${HW[@]}") pre=() args=()
    case "$enc" in
        h264_nvenc) args=(-c:v h264_nvenc -preset p4 -cq 23) ;;
        hevc_nvenc) args=(-c:v hevc_nvenc -preset p4 -cq 23) ;;
        h264_vaapi)
            pre=(-vaapi_device /dev/dri/renderD128)
            hw=()
            vfarg="$VF_CPU,format=nv12,hwupload"
            args=(-c:v h264_vaapi -qp 23) ;;
        libx264)    args=(-c:v libx264 -preset veryfast -crf 20) ;;
    esac
    echo "--- attempt: $enc" >>"$log"
    ffmpeg -y -v error "${pre[@]}" "${hw[@]}" -i "$FILE" \
        -vf "$vfarg" "${args[@]}" \
        -c:a copy -movflags +faststart \
        "$tmp" >>"$log" 2>&1 && [[ -s "$tmp" ]]
}

if [[ "$width" =~ ^[0-9]+$ ]] && (( width > 4096 )); then
    LADDER=(hevc_nvenc libx264)
else
    LADDER=(h264_nvenc h264_vaapi libx264)
fi

ok=0
for enc in "${LADDER[@]}"; do
    if try_encode "$enc"; then ok=1; break; fi
    rm -f "$tmp"
done

if [[ $ok -eq 1 ]]; then
    mv -f "$tmp" "$FILE"
    rm -f "$log"
    notify-send "SDR ready" "${FILE##*/}" -a 'Recorder' -i video-x-generic & disown
else
    rm -f "$tmp"
    notify-send "Tonemap failed - HDR original kept" \
        "${FILE##*/} (details: $log)" -a 'Recorder' -u critical & disown
    exit 1
fi
