#!/usr/bin/env python3
#
# Regression guard: a shader path a QML file names must exist on disk.
#
# `HyprlandAntiFlashbangShader.qml` named
# `hyprlandAntiFlashbangShader/anti-flashbang-weak.glsl` for the whole life of
# the file while no such file was ever in the tree, and the first click of the
# anti-flashbang quick toggle handed that path to Hyprland's
# `decoration:screen_shader`. Nothing anywhere reported it. Hyprland's
# `applyScreenShader` destroys the previous shader BEFORE it checks the path,
# so the effect goes off; the complaint is a red banner painted across the
# focused monitor, not a log line, so the log-grepping verification loop this
# repo uses cannot see it; and `hyprctl getoption` answers with the bogus path
# and `set: true` regardless, so the service's own `weak`/`enabled` state - and
# therefore the toggle's label - read as if the shader were live.
#
# The whole failure is one missing file, and a missing file is exactly what a
# static check can see. The same hole is open to any shader this shell loads by
# path: a `.frag.qsb` reached through `Qt.resolvedUrl` fails as a shader effect
# that silently draws nothing.
#
# Only STATIC literals can be resolved here. `Background.qml` builds its
# transition path from a template (`shaders/${currentShader}.frag.qsb`); those
# are counted and reported rather than silently ignored, and the catalogue they
# are built from is checked against the same directory by
# `test_wallpaper_transitions.py`.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SHADER_SUFFIXES = (".glsl", ".frag", ".vert", ".qsb", ".fsh", ".vsh")

# `Quickshell.shellPath(...)` resolves against the shell root; `Qt.resolvedUrl`
# and a bare `fragmentShader:` literal resolve against the declaring file's own
# directory. Getting that distinction wrong is the difference between a check
# that reports every path as missing and one that reports none.
SHELL_PATH = re.compile(r'Quickshell\.shellPath\(\s*"([^"]*)"\s*\)')
RESOLVED_URL = re.compile(r'Qt\.resolvedUrl\(\s*"([^"]*)"\s*\)')
SHADER_PROP = re.compile(r'^\s*(?:fragmentShader|vertexShader)\s*:\s*"([^"]*)"\s*$')
# A template is only reported when it sits in one of the forms above. Prose
# quoting a shader name in a backtick fragment - `WallpaperTransitions.qml`'s
# header comment does - is not a declaration, and counting it would make the
# reported number mean nothing.
TEMPLATED = re.compile(
    r"(?:Qt\.resolvedUrl\(|Quickshell\.shellPath\(|(?:fragment|vertex)Shader\s*:\s*)"
    r"[^`\n]*`[^`]*\.(?:glsl|frag|vert|qsb|fsh|vsh)`"
)


def is_shader(value: str) -> bool:
    return value.endswith(SHADER_SUFFIXES)


def scan(root: Path, files):
    """Returns (declarations, missing, templated).

    A declaration is (path, line number, literal, resolved path).
    """
    declarations = []
    missing = []
    templated = []

    for path in sorted(files):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        for number, line in enumerate(text.splitlines(), start=1):
            found = []
            for value in SHELL_PATH.findall(line):
                if is_shader(value):
                    found.append((value, root / value))
            for value in RESOLVED_URL.findall(line):
                if is_shader(value):
                    found.append((value, path.parent / value))
            match = SHADER_PROP.match(line)
            if match and is_shader(match.group(1)):
                found.append((match.group(1), path.parent / match.group(1)))

            for value, resolved in found:
                declarations.append((path, number, value, resolved))
                if not resolved.is_file():
                    missing.append((path, number, value, resolved))

            if TEMPLATED.search(line):
                templated.append((path, number, line.strip()))

    return declarations, missing, templated


def self_check() -> bool:
    """Proves the scanner both resolves and reports, without the real tree.

    A source-text check whose pattern has quietly stopped matching passes
    vacuously, and a check over a tree that happens to be clean cannot tell you
    which of the two it is. This builds all three recognised forms twice - once
    at a file that exists, once at a file that does not - so a pattern that has
    stopped matching fails here rather than going quiet in the sweep.
    """
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "services" / "shaders").mkdir(parents=True)
        (root / "modules").mkdir()
        (root / "services" / "shaders" / "real.glsl").write_text("// present\n")
        (root / "modules" / "real.frag.qsb").write_text("// present\n")

        (root / "services" / "Good.qml").write_text(
            'readonly property string a: Quickshell.shellPath("services/shaders/real.glsl")\n'
        )
        (root / "services" / "Bad.qml").write_text(
            'readonly property string a: Quickshell.shellPath("services/shaders/gone.glsl")\n'
        )
        (root / "modules" / "Effects.qml").write_text(
            "ShaderEffect {\n"
            "    fragmentShader: Qt.resolvedUrl(\"real.frag.qsb\")\n"
            "}\n"
            "ShaderEffect {\n"
            "    fragmentShader: Qt.resolvedUrl(\"gone.frag.qsb\")\n"
            "}\n"
            "ShaderEffect {\n"
            '    fragmentShader: "real.frag.qsb"\n'
            "}\n"
            "ShaderEffect {\n"
            '    fragmentShader: "gone.frag.qsb"\n'
            "}\n"
            "ShaderEffect {\n"
            "    fragmentShader: Qt.resolvedUrl(`shaders/${name}.frag.qsb`)\n"
            "}\n"
            "// prose naming `shaders/prose.frag.qsb` is not a declaration\n"
            'Item { property string notAShader: Quickshell.shellPath("scripts/thing.py") }\n'
        )

        files = sorted(root.rglob("*.qml"))
        declarations, missing, templated = scan(root, files)

        problems = []
        if len(declarations) != 6:
            problems.append(f"expected 6 shader declarations, saw {len(declarations)}")
        if {value for _, _, value, _ in missing} != {
            "services/shaders/gone.glsl",
            "gone.frag.qsb",
        }:
            problems.append(f"wrong missing set: {sorted(v for _, _, v, _ in missing)}")
        if len(missing) != 3:
            problems.append(f"expected 3 missing declarations, saw {len(missing)}")
        if len(templated) != 1:
            problems.append(f"expected 1 templated path, saw {len(templated)}")

        if problems:
            print(
                "Shader-path lint FAILED its own self-check, so it can say "
                "nothing about the tree:",
                file=sys.stderr,
            )
            for problem in problems:
                print(f"  {problem}", file=sys.stderr)
            return False
    return True


def main() -> int:
    if not self_check():
        return 1

    files = [
        path
        for path in sorted(ROOT.rglob("*.qml"))
        if ".git" not in path.parts
    ]
    declarations, missing, templated = scan(ROOT, files)

    if not declarations:
        print(
            "Shader-path lint FAILED: the sweep resolved no shader path at all "
            "in the shell. Either every shader is now loaded some way this "
            "check does not recognise - in which case it is guarding nothing - "
            "or the patterns broke.",
            file=sys.stderr,
        )
        return 1

    if missing:
        print(
            "Shader-path lint FAILED: a QML file names a shader that is not on "
            "disk. Hyprland answers a missing `decoration:screen_shader` with a "
            "persistent red banner on the focused monitor and no log line, and "
            "keeps reporting the path through `hyprctl getoption` as though it "
            "had loaded; a missing `.frag.qsb` is a ShaderEffect that draws "
            "nothing. Ship the file or stop naming it:",
            file=sys.stderr,
        )
        for path, number, value, resolved in missing:
            rel = path.relative_to(ROOT)
            print(f"  {rel}:{number}: \"{value}\" -> {resolved}", file=sys.stderr)
        return 1

    print(
        f"Shader-path lint passed ({len(declarations)} static shader paths in "
        f"{len(files)} QML files, {len(templated)} built from a template and "
        "left to test_wallpaper_transitions.py)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
