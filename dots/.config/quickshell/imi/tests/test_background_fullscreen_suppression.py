#!/usr/bin/env python3
"""Wallpaper suppression pins: never destroy the background's surface.

`hideWhenFullscreen` once hid the wallpaper with `visible: false` on its
PanelWindow. Under WlrLayershell that does not hide a window, it destroys it
(window reuse is forbidden there), so every fullscreen transition tore the
layer surface down and brought it back on a fresh scene-graph GL context. The
embedded Wallpaper Engine renderer had to rebuild against that context, and the
observable result was a desktop strobing at 30Hz - a photosensitive-seizure
hazard, not a cosmetic bug.

These pins guard the shape of the fix rather than its details: the window must
stay mapped, suppression must act on the contents, and the wallpaper must come
back animating.

The load-bearing pin used to be a regex for `^        visible:` - a literal
eight-space indent, which `Background.qml` contains zero of. It matched nothing,
asserted nothing, and reported green (issue #97). Its replacement resolves the
window's *own* `visible` structurally, and it has to cover three different ways
to reach the same property, because the window's lifetime is what is at stake
and not any particular syntax:

  - a declarative binding on the window (`visible: !bgRoot.suppressContents`) -
    the "obvious simplification" form, which mentions no fullscreen keyword at
    all;
  - an imperative assignment (`bgRoot.visible = false`, or a bare `visible =`
    from a handler whose scope is the window) - the form a regex over binding
    syntax cannot see, and the one an earlier replacement still missed;
  - a `Binding` object aimed at the window's `visible`.

Because the old pin was defeated by indentation, and two others were defeated by
a comment happening to contain the word they grepped for, nothing here reads raw
file text. `_qml_source()` blanks comments and string contents, matches braces,
and hands back the tree - so reindenting the file, rewrapping a binding across
lines, or writing a comment about `visible:` changes no result. `QmlParserTests`
pins that parser against fixtures for the shapes it has to get right (grouped
properties, `Behavior on X`, braces inside strings), including one that must
fail, so the parser cannot itself decay into something that matches nothing.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
CORNERS = ROOT / "modules/imi/screenCorners/ScreenCorners.qml"
HYPRLAND_DATA = ROOT / "services/HyprlandData.qml"

# Words that can precede a `{` without opening a QML object body.
_JS_BLOCK_WORDS = {
    "else", "do", "try", "finally", "return", "case", "default", "typeof",
    "new", "in", "of", "void", "delete", "yield", "await", "then",
}

# The last thing before a `{`, if it names something: `Item {`, `anchors {`,
# `Behavior on color {`, `Quickshell.Io.FileView {`.
_HEADER_TAIL_RE = re.compile(r"([A-Za-z_][\w.]*)(?:\s+on\s+[\w.]+)?\s*$")

# One member of an object body: `id: bgRoot`, `readonly property bool x: y`,
# `onFooChanged: {`. Anchored to the start of a line so a `?:` or a dictionary
# key inside an expression is not mistaken for one.
_MEMBER_RE = re.compile(
    r"^[ \t]*(?:(?:readonly|required|default)\s+)*"
    r"(?:property\s+[\w.<>]+\s+)?"
    r"(?P<name>[A-Za-z_][\w.]*)\s*:(?!:)",
    re.M,
)


def _mask(src):
    """Blank what must not be read as code, keeping every index aligned.

    Returns `(code, skeleton)`. `code` has comments blanked to spaces; string
    literals are left intact so a `property: "visible"` is still readable.
    `skeleton` additionally blanks string *contents*, so a brace or a semicolon
    inside a string cannot move the structure. Newlines survive in both, so a
    match offset still maps to a line in the original file.
    """
    code = list(src)
    skeleton = list(src)
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch == "/" and i + 1 < n and src[i + 1] in "/*":
            if src[i + 1] == "/":
                end = src.find("\n", i)
                end = n if end < 0 else end
            else:
                end = src.find("*/", i + 2)
                end = n if end < 0 else end + 2
            for k in range(i, end):
                if src[k] != "\n":
                    code[k] = skeleton[k] = " "
            i = end
            continue
        if ch in "\"'`":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == ch:
                    break
                if ch != "`" and src[j] == "\n":
                    break
                j += 1
            for k in range(i + 1, min(j, n)):
                if src[k] != "\n":
                    skeleton[k] = " "
            i = min(j, n) + 1
            continue
        i += 1
    return "".join(code), "".join(skeleton)


class _Block:
    """One `{ ... }` span, classified by what introduced it."""

    def __init__(self, open_at, header, parent):
        self.open_at = open_at
        self.close_at = None
        self.header = header
        self.parent = parent
        self.children = []
        match = _HEADER_TAIL_RE.search(header)
        self.name = match.group(1) if match else None
        if self.name is None or self.name in _JS_BLOCK_WORDS:
            self.kind = "js"
        elif self.name[0].isupper():
            self.kind = "element"
        else:
            self.kind = "group"

    def contains(self, index):
        return self.close_at is not None and self.open_at < index < self.close_at

    def is_inside(self, other):
        node = self.parent
        while node is not None:
            if node is other:
                return True
            node = node.parent
        return False


class _QmlSource:
    """A brace-matched view of one QML file. Not a parser for QML at large -
    just enough structure to answer "which object owns this line"."""

    def __init__(self, path):
        self.path = path
        self.text = Path(path).read_text()
        self.code, self.skeleton = _mask(self.text)
        self.blocks = []
        self.unclosed = 0
        stack = []
        for i, ch in enumerate(self.skeleton):
            if ch == "{":
                block = _Block(i, self._header_before(i), stack[-1] if stack else None)
                if block.parent is not None:
                    block.parent.children.append(block)
                stack.append(block)
                self.blocks.append(block)
            elif ch == "}":
                if stack:
                    stack.pop().close_at = i
        self.unclosed = len(stack)

    def _header_before(self, index):
        j = index - 1
        while j >= 0 and self.skeleton[j] not in "{};":
            j -= 1
        return self.skeleton[j + 1:index]

    def elements(self, name=None):
        return [b for b in self.blocks
                if b.kind == "element" and (name is None or b.name == name)]

    def body(self, block):
        """The block's own text with every nested block blanked out, so a
        member of a child object cannot be read as a member of this one."""
        if block.close_at is None:
            return ""
        base = block.open_at + 1
        buf = list(self.code[base:block.close_at])
        for child in block.children:
            end = child.close_at + 1 if child.close_at is not None else block.close_at
            for k in range(child.open_at - base, min(end - base, len(buf))):
                if buf[k] != "\n":
                    buf[k] = " "
        return "".join(buf)

    def members(self, block):
        """`[(name, value)]` for the block's own bindings, in source order."""
        text = self.body(block)
        found = list(_MEMBER_RE.finditer(text))
        out = []
        for k, match in enumerate(found):
            end = found[k + 1].start() if k + 1 < len(found) else len(text)
            out.append((match.group("name"), text[match.end():end].strip()))
        return out

    def member(self, block, name):
        for found_name, value in self.members(block):
            if found_name == name:
                return value
        return None

    def element_id(self, block):
        """The block's `id`, as a bare identifier.

        A member's value runs to the next member, and the next thing after an
        `id` is routinely a declaration with no initialiser (`required property
        var modelData`), which is therefore not a member start and gets swallowed
        into the value. Taking the raw value as the id produced a multi-line
        string that `re.escape`d into a pattern matching nothing - which is how
        the qualified-assignment pin below passed a mutation that assigned
        `bgRoot.visible` outright. Take the identifier and nothing else.
        """
        value = self.member(block, "id")
        if value is None:
            return None
        match = re.match(r"[A-Za-z_]\w*", value.strip())
        return match.group(0) if match else None

    def owner_element(self, index):
        """The innermost object whose scope an identifier at `index` resolves
        in. Grouped properties and JS blocks do not open a new object scope."""
        owner = None
        for block in self.blocks:
            if block.kind == "element" and block.contains(index):
                if owner is None or block.open_at > owner.open_at:
                    owner = block
        return owner

    def line_of(self, index):
        return self.text.count("\n", 0, index) + 1


def _qml_source(path):
    return _QmlSource(path)


class BackgroundSuppressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qml = _qml_source(BACKGROUND)
        cls.background = cls.qml.code
        cls.corners = _qml_source(CORNERS).code
        cls.hyprland_data = _qml_source(HYPRLAND_DATA).code
        windows = cls.qml.elements("PanelWindow")
        assert len(windows) == 1, (
            f"expected exactly one PanelWindow in {BACKGROUND}, found {len(windows)}")
        cls.window = windows[0]
        cls.window_id = cls.qml.element_id(cls.window)

    def test_the_file_parses(self):
        """Everything below is only as good as the brace matching."""
        self.assertEqual(self.qml.unclosed, 0,
                         "unbalanced braces in Background.qml - the structural "
                         "pins below would silently stop covering anything.")
        self.assertIsNotNone(self.window_id,
                             "the background's PanelWindow needs an `id` for the "
                             "assignment pins below to name it.")
        self.assertRegex(self.window_id, r"^[A-Za-z_]\w*$",
                         "the window's id must resolve to a bare identifier - "
                         "anything else escapes into a pattern that matches "
                         "nothing, and the assignment pin goes vacuous.")

    def test_the_window_never_binds_its_own_visible(self):
        """The PanelWindow's own `visible` must not be bound at all.

        This is the pin that matters most: binding it is the exact regression
        that strobed. The check is deliberately blunt - *any* binding here
        fails, not just one that names fullscreen - because the obvious way to
        reintroduce the bug mentions no fullscreen keyword:
        `visible: !bgRoot.suppressContents` reads as a simplification and moves
        the existing content-item binding up one level onto the surface. The
        window is visible by default and nothing needs to say so.
        """
        offenders = [value for name, value in self.qml.members(self.window)
                     if name == "visible"]
        self.assertEqual(
            offenders, [],
            "Background's PanelWindow binds its own `visible` "
            f"({offenders}). Under WlrLayershell that destroys and recreates "
            "the layer surface on every change - suppress the contents "
            "instead, as the content Item already does.")

    def test_the_window_visible_is_never_assigned(self):
        """The same regression, written imperatively.

        A handler that sets `bgRoot.visible = false` destroys exactly the same
        surface as the binding does, and no amount of inspecting binding syntax
        sees it. Both the qualified form and a bare `visible =` from a handler
        whose scope is the window itself count.
        """
        offenders = []
        qualified = re.compile(
            r"\b" + re.escape(self.window_id) + r"\s*\.\s*visible\s*=(?!=)")
        for match in qualified.finditer(self.qml.code):
            offenders.append((self.qml.line_of(match.start()), match.group(0)))

        bare = re.compile(r"(?<![\w.$])(?<!\bvar )(?<!\blet )(?<!\bconst )"
                          r"visible\s*=(?!=)")
        for match in bare.finditer(self.qml.code):
            if self.qml.owner_element(match.start()) is self.window:
                offenders.append((self.qml.line_of(match.start()), match.group(0)))

        self.assertEqual(
            offenders, [],
            "Background assigns the PanelWindow's own `visible` at "
            f"{offenders}. Under WlrLayershell the window is destroyed rather "
            "than hidden, so this tears the layer surface down on every "
            "fullscreen transition - the 30Hz strobe. Suppress the contents "
            "instead.")

    def test_no_binding_object_aims_at_the_window_visible(self):
        """`Binding { target: bgRoot; property: "visible" }` is the same lever
        with the assignment moved into a declarative object."""
        offenders = []
        for element in self.qml.elements("Binding"):
            prop = self.qml.member(element, "property") or ""
            target = self.qml.member(element, "target") or ""
            if re.search(r'["\']visible["\']', prop) and self.window_id in target:
                offenders.append(self.qml.line_of(element.open_at))
        self.assertEqual(
            offenders, [],
            f"a Binding object drives the background window's `visible` "
            f"(line(s) {offenders}) - that destroys the layer surface just as "
            "a direct binding would.")

    def test_contents_are_suppressed_instead(self):
        """Something *inside* the window is what stops being drawn."""
        holders = []
        for element in self.qml.elements():
            if element is self.window or not element.is_inside(self.window):
                continue
            value = self.qml.member(element, "visible")
            if value and "suppressContents" in value:
                holders.append(self.qml.line_of(element.open_at))
        self.assertTrue(
            holders,
            "nothing inside the background window binds its `visible` to "
            "suppressContents. `hideWhenFullscreen` has to switch off the "
            "contents, since it must not switch off the window.")

    def test_suppression_respects_lock_and_the_config_option(self):
        value = self.qml.member(self.window, "suppressContents")
        self.assertIsNotNone(value, "suppressContents should still exist")
        self.assertIn("screenLocked", value,
                      "The wallpaper must stay drawn on the lock screen.")
        self.assertIn("hideWhenFullscreen", value,
                      "Suppression must remain opt-out via the config option.")

    def test_suppression_never_clears_the_wallpaper_renderer(self):
        """Suppression stops at not drawing; it does not touch `live`.

        `live` only gates the surface's repaint timer, and `updatePaintNode` -
        which the timer drives - is the one place the surface re-shares against
        a recreated GL context and the one place a project switch queued while
        suppressed gets applied. Stopping the timer on an item that is already
        not drawn buys nothing and can strand both.

        (`live` is not what froze video wallpapers behind a fullscreen window on
        another workspace. That is linux-wallpaperengine's own fullscreen pause,
        fixed in the embed's argv - see the comment in Background.qml.)
        """
        self.assertNotRegex(
            self.qml.code, r"\.live\s*=(?!=)",
            "Background assigns the WE surface's `live`. Suppression must only "
            "stop drawing, or a queued project switch and the GL-context "
            "recovery both lose the repaint that would apply them.")

    def test_unsuppress_is_immediate_and_only_hiding_is_debounced(self):
        """Delaying the wallpaper's return would read as a black flash."""
        body = self._handler_body("onMonitorHasFullscreenChanged")
        else_branch = body.split("else", 1)
        self.assertEqual(len(else_branch), 2, "expected an else branch")
        self.assertIn("suppressedForFullscreen = false", else_branch[1],
                      "Leaving fullscreen must clear suppression directly, not "
                      "through the delay timer.")

    def test_a_switch_requested_while_suppressed_is_deferred(self):
        """The surface only builds a project while it is being drawn.

        Declaring `wePendingProject` is not the contract - queueing a switch
        into it while suppressed, and replaying it on un-suppress, is. Both
        halves have to be present or a wallpaper change made behind a
        fullscreen window is simply lost.
        """
        queued = [m for m in re.finditer(r"wePendingProject\s*=\s*(?!\"\"|'')(\S+)",
                                         self.qml.code)]
        self.assertTrue(queued,
                        "nothing ever queues a switch into wePendingProject, so "
                        "the deferral cannot happen.")
        replay = self._handler_body("onSuppressContentsChanged")
        self.assertIn("wePendingProject", replay,
                      "un-suppressing must look at the deferred switch.")
        self.assertIn("loadWeWallpaper", replay,
                      "the deferred switch must actually be replayed, not just "
                      "cleared.")

    def test_transition_cannot_hang_forever(self):
        """A stalled wallpaper transition must settle itself.

        The watchdog existing is not the contract either - it has to be armed
        by the transition and to clear it when it fires, or the peel shader
        stays on screen blending a frozen still against a live texture.
        """
        watchdog = None
        for element in self.qml.elements("Timer"):
            if self.qml.element_id(element) == "weTransitionWatchdog":
                watchdog = element
                break
        self.assertIsNotNone(watchdog, "weTransitionWatchdog should still exist")
        self.assertIn("weTransitioning", self.qml.member(watchdog, "running") or "",
                      "the watchdog must run exactly while a transition is armed.")
        fired = None
        for child in watchdog.children:
            if child.header.rstrip().endswith("onTriggered:"):
                fired = self.qml.code[child.open_at:child.close_at]
        self.assertIsNotNone(fired, "the watchdog needs an onTriggered body.")
        self.assertIn("weTransitioning = false", fired,
                      "the watchdog must clear the transition it is guarding, "
                      "or the peel shader never comes off screen.")

    def test_fullscreen_test_ignores_maximized(self):
        """Maximized is not fullscreen; only the polled int tells them apart."""
        self.assertRegex(self.hyprland_data, r"\bfullscreen\s*>=\s*2",
                         "HyprlandData must keep testing the fullscreen *mode*, "
                         "not its truthiness - 1 is maximized.")
        for name, source in (("Background", self.background),
                             ("ScreenCorners", self.corners)):
            self.assertIn("fullscreenByMonitorName", source,
                          f"{name} should read the polled per-monitor map.")
            self.assertNotIn("wayland?.fullscreen", source,
                             f"{name} still uses the toplevel's own fullscreen "
                             "flag, which is true for maximized windows too.")

    def _handler_body(self, handler):
        for child in self.window.children:
            if child.header.rstrip().endswith(handler + ":"):
                return self.qml.code[child.open_at:child.close_at]
        self.fail(f"{handler} should still exist on the background window")


_FIXTURE = '''
import QtQuick

PanelWindow {
    id: win

    required property var modelData

    anchors {
        top: true
        visible: "this belongs to the grouped property, not the window"
    }

    // A comment that says visible: false, and one that says win.visible = false.
    property string label: "a string with { and } and // in it"

    Behavior on color {
        NumberAnimation { duration: 100 }
    }

    Item {
        visible: !win.suppressed
    }

    onSomethingChanged: {
        if (something)
            other.visible = false;
    }
}
'''


class QmlParserTests(unittest.TestCase):
    """The pins above are only as strong as this parser. The predecessor was a
    regex whose element header matched `anchors {` and `Behavior on color {`,
    and whose window-level `visible:` looked for a literal indent - so it
    matched nothing and reported green. These fixtures are the shapes that
    broke it, plus one that must still be caught."""

    def setUp(self):
        import tempfile
        self.tmp = tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False)
        self.tmp.write(_FIXTURE)
        self.tmp.close()
        self.qml = _qml_source(self.tmp.name)
        self.window = self.qml.elements("PanelWindow")[0]

    def tearDown(self):
        Path(self.tmp.name).unlink()

    def test_braces_inside_strings_and_comments_do_not_move_the_structure(self):
        self.assertEqual(self.qml.unclosed, 0)

    def test_a_grouped_property_is_not_an_element(self):
        self.assertEqual([b.name for b in self.qml.elements()],
                         ["PanelWindow", "Behavior", "NumberAnimation", "Item"])

    def test_behavior_on_x_parses_as_its_element_type(self):
        behaviors = self.qml.elements("Behavior")
        self.assertEqual(len(behaviors), 1)
        self.assertTrue(behaviors[0].is_inside(self.window))

    def test_an_id_is_read_as_a_bare_identifier(self):
        """`required property var modelData` has no initialiser, so it is not a
        member start and lands inside the preceding member's value. Reading the
        id off that raw value gave a multi-line string, and the assignment pin
        built from it matched nothing."""
        self.assertEqual(self.qml.element_id(self.window), "win")

    def test_a_grouped_property_member_is_not_a_window_member(self):
        self.assertEqual([b.name for b in self.window.children if b.kind == "group"],
                         ["anchors"])
        names = [n for n, _ in self.qml.members(self.window)]
        self.assertEqual(names, ["id", "label", "onSomethingChanged"],
                         "`visible` inside `anchors { }` is not the window's, "
                         "and neither is the one inside the child Item.")

    def test_a_comment_is_never_read_as_code(self):
        assignments = re.findall(r"win\s*\.\s*visible\s*=(?!=)", self.qml.code)
        self.assertEqual(assignments, [],
                         "the only `win.visible =` in the fixture is inside a "
                         "comment.")

    def test_a_child_element_owns_its_own_scope(self):
        index = self.qml.code.index("other.visible")
        self.assertIs(self.qml.owner_element(index), self.window,
                      "a signal handler's JS block does not open a new object "
                      "scope; a bare identifier there is the window's.")
        inner = self.qml.elements("Item")[0]
        self.assertIs(self.qml.owner_element(self.qml.code.index("!win.suppressed")),
                      inner)

    def test_a_window_level_visible_binding_is_still_found(self):
        """The check has to be able to fail."""
        broken = _FIXTURE.replace("    anchors {",
                                  "    visible: !win.suppressed\n\n    anchors {")
        path = Path(self.tmp.name).with_suffix(".broken.qml")
        path.write_text(broken)
        try:
            qml = _qml_source(path)
            window = qml.elements("PanelWindow")[0]
            self.assertIn("visible", [n for n, _ in qml.members(window)])
        finally:
            path.unlink()


if __name__ == "__main__":
    unittest.main()
