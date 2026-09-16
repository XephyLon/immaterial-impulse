#!/usr/bin/env python3
"""An icon-only button is IconButton (or IconToolbarButton in a toolbar).

Forty-three call sites had each spelled the same control out by hand - a
RippleButton with a fixed square size, a full radius and a lone
MaterialSymbol as its content - at eight different sizes. They were folded
onto modules/common/widgets/IconButton.qml; this refuses the forty-fourth.

A hit is a `RippleButton {` block (or a local component rooted on one) whose
own properties declare a full radius, an equal literal width and height,
and `contentItem: MaterialSymbol`. The legitimate variants are listed with
their reason; a new one is added here, not written around.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "modules"

# Path relative to the shell root -> why it is not IconButton.
ALLOWED = {
    "modules/common/widgets/IconButton.qml": "the widget itself",
    "modules/common/widgets/IconToolbarButton.qml": "the toolbar variant (fills the toolbar's height)",
    "modules/common/widgets/CloseButton.qml": "IconButton with the close glyph (rooted on IconButton, listed for clarity)",
    "modules/common/widgets/FloatingActionButton.qml": "a FAB: elevated container, its own size ladder",
    "modules/common/widgets/NotificationGroupExpandButton.qml": "a chevron that rotates with the group, on the notification's tones",
    "modules/imi/bar/SysTray.qml": "sizes its background for a PopupAnchorIndicator",
    "modules/imi/overlay/recorder/Recorder.qml": "a 66px hero control",
    "modules/imi/dock/DockMedia.qml": "media transport: album-art colours and a play/pause radius morph",
    "modules/imi/mediaControls/PlayerControls.qml": "media transport (see DockMedia)",
    "modules/imi/mediaControls/PlayerControlsLyrics.qml": "media transport (see DockMedia)",
    "modules/imi/mediaControls/Lyrics.qml": "media transport (see DockMedia)",
    "modules/imi/bar/Media.qml": "media transport (see DockMedia)",
    "modules/imi/sidebarLeft/SidebarPlayerControl.qml": "media transport (see DockMedia)",
    "modules/imi/sidebarLeft/aiChat/MessageThinkBlock.qml": "a chevron with its own rotation Behavior",
    "modules/common/widgets/EditRemoveBadge.qml": "an 18px error-role badge riding a corner, not a 28-40px button",
    "modules/imi/phone/PhoneActionButton.qml": "a 48px filled primary-container action with a label tooltip: the phone row's own shape",
}
EXCLUDED_DIRS = ("modules/common/plugins/designsystem/",)

BLOCK = re.compile(r"(?:component\s+\w+\s*:\s*)?RippleButton\s*\{")
NUMBER = r"(\d+(?:\.\d+)?)"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"(^|\s)//.*", r"\1", text)


def own_lines(text, start):
    """The block's depth-1 lines, and its end offset."""
    depth, i = 1, start
    while i < len(text) and depth:
        depth += (text[i] == "{") - (text[i] == "}")
        i += 1
    lines, d = [], 1
    for line in text[start:i].split("\n"):
        if d == 1:
            lines.append(line.strip())
        d += line.count("{") - line.count("}")
    return lines, i


def is_hand_rolled(lines):
    joined = "\n".join(lines)
    if not re.search(r"^buttonRadius:\s*(Appearance\.rounding\.full|(?:height|width)\s*/\s*2)", joined, re.M):
        return False
    if not re.search(r"^contentItem:\s*MaterialSymbol\s*\{", joined, re.M):
        return False
    w = re.search(r"^(?:implicitWidth|Layout\.preferredWidth):\s*" + NUMBER + r"\s*$", joined, re.M)
    h = re.search(r"^(?:implicitHeight|Layout\.preferredHeight):\s*" + NUMBER + r"\s*$", joined, re.M)
    return bool(w and h and w.group(1) == h.group(1))


def main():
    offenders = []
    for path in sorted(MODULES.rglob("*.qml")):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(EXCLUDED_DIRS) or rel in ALLOWED:
            continue
        text = strip_comments(path.read_text(errors="replace"))
        pos = 0
        while True:
            m = BLOCK.search(text, pos)
            if not m:
                break
            lines, end = own_lines(text, m.end())
            if is_hand_rolled(lines):
                offenders.append(f"{rel}:{text.count(chr(10), 0, m.start()) + 1}")
            pos = m.end()
    stale = [p for p in ALLOWED if not (ROOT / p).exists()]
    if stale:
        print("lint_hand_rolled_icon_button: ALLOWED names files that do not exist:")
        for p in stale:
            print(f"  {p}")
        return 1
    if offenders:
        print("lint_hand_rolled_icon_button: an icon-only RippleButton is IconButton (modules/common/widgets/IconButton.qml);")
        print("a legitimate variant is added to ALLOWED in this lint with its reason:")
        for o in offenders:
            print(f"  {o}")
        return 1
    print("lint_hand_rolled_icon_button: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
