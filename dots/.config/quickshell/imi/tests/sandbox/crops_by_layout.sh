#!/usr/bin/env bash
# crops_by_layout.sh <sandbox-dir> <shot.png> <name>: crops in physical px from the nested layout (quickshell:background layer x monitor scale), dock strip + corners + full
SB="$1"; shift; S=$(dirname "$1")
I="$1"; N="$2"; source $SB/env
read IW IH < <(identify -format "%w %h" $I)
eval $(hyprctl layers -j | python3 -c '
import json,sys
d=json.load(sys.stdin); out={}
for mon,lv in d.items():
    for level,items in lv["levels"].items():
        for it in items:
            if it["namespace"]=="quickshell:background": out["LW"],out["LH"]=it["w"],it["h"]
            if it["namespace"]=="quickshell:dock": out["DX"],out["DY"],out["DW"],out["DH"]=it["x"],it["y"],it["w"],it["h"]
print(" ".join(f"{k}={v}" for k,v in out.items()))')
SC=$(hyprctl monitors -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"scale\"])")
PW=$(python3 -c "print(int(round($LW*$SC)))"); PH=$(python3 -c "print(int(round($LH*$SC)))")
px(){ python3 -c "print(int(round($1*$SC)))"; }
echo "image ${IW}x${IH} layout ${LW}x${LH} scale $SC dock logical y=$DY h=$DH edge=$( [ $DW -ge $LW ] && echo horizontal || echo vertical )"
CX=$(px $((LW/2))); 
if [ $DW -ge $LW ]; then  # horizontal dock: bottom or top strip
  if [ $DY -gt $((LH/2)) ]; then Y0=$(px $((DY-15))); else Y0=0; fi
  H=$(px $((DH+20))); W=$(px 450)
  magick $I -crop ${W}x${H}+$((CX-W/2))+$Y0 +repage -scale 200% $S/fd_${N}_dock.png
else                        # vertical dock: side strip
  if [ $DX -gt $((LW/2)) ]; then X0=$(px $((DX-15))); else X0=0; fi
  W=$(px $((DW+20))); H=$(px 450); CY=$(px $((LH/2)))
  magick $I -crop ${W}x${H}+$X0+$((CY-H/2)) +repage -scale 200% $S/fd_${N}_dock.png
fi
C=$(px 45)
magick $I -crop ${C}x${C}+0+$((PH-C)) +repage -scale 600% $S/fd_${N}_blc.png
magick $I -crop ${C}x${C}+$((PW-C))+$((PH-C)) +repage -scale 600% $S/fd_${N}_brc.png
magick $I -crop ${C}x${C}+0+0 +repage -scale 600% $S/fd_${N}_tlc.png
magick $I -crop ${PW}x${PH}+0+0 +repage -resize 1600x $S/fd_${N}_full.png
echo "== samples along x=CX from the bottom (physical rows), and x=300"
for d in 1 3 5 6 8 20 60 70 80; do y=$((PH-d)); printf "y=%4d (%3d up) %s   %s\n" $y $d "$(magick $I -format '%[pixel:p{'$CX','$y'}]' info:)" "$(magick $I -format '%[pixel:p{300,'$y'}]' info:)"; done
echo "== top rows x=1000: $(magick $I -format '%[pixel:p{1000,'$(px 20)'}] %[pixel:p{1000,'$(px 42)'}] %[pixel:p{1000,'$(px 48)'}]' info:)"
echo "== side x=4 / x=14 at mid: $(magick $I -format '%[pixel:p{2,'$((PH/2))'}] %[pixel:p{8,'$((PH/2))'}]' info:)"
