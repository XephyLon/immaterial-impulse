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

# The temporary MUST end in .mp4: ffmpeg infers the muxer from the output
# extension, and a bare ".tmp" fails - silently, if stderr is ever discarded.
# Same trap that shipped in we_still.sh once already.
tmp="${FILE%.mp4}.sdr-tmp.mp4"
log="$(mktemp --suffix=-tonemap.log)"

# libplacebo (Vulkan, GPU tonemap - fast and gamut-aware) when this ffmpeg has
# it, else the zscale/tonemap CPU chain.
#
# Captured to a variable, NOT `ffmpeg | grep -q`: grep -q exits at the first
# match, ffmpeg takes SIGPIPE, and under `set -o pipefail` the whole pipeline
# reads as failed - so libplacebo silently never got selected and every
# tonemap ran on the CPU. That single line is why the first version took 13s
# on a clip the GPU does in 5.
filters="$(ffmpeg -hide_banner -filters 2>/dev/null || true)"
if [[ "$filters" == *libplacebo* ]]; then
    VF="libplacebo=tonemapping=auto:colorspace=bt709:color_primaries=bt709:color_trc=bt709:format=yuv420p"
    HW=(-init_hw_device vulkan)
else
    VF="zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
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
VF_CPU="zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"

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
