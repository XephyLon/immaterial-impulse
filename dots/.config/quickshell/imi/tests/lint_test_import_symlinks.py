#!/usr/bin/env python3
#
# Regression guard: every symlink under `tests/imports/` resolves.
#
# The QML suite reaches the shell's own singletons through a mirror tree of
# symlinks (`tests/imports/qs/services/Audio.qml -> ../../../../services/
# Audio.qml` and friends), because `qmltestrunner` needs an import path it can
# resolve without the Quickshell plugin. A symlink there is the only kind of
# reference in this repo that survives its target being deleted: git keeps the
# link, `ls` prints it in the same colour as the rest, and nothing fails until
# a test happens to import that exact type - which for a service nothing tests
# is never.
#
# `services/Docker.qml` is the case that motivated this. It moved into the
# bundled plugin as `plugins/bundled/docker/DockerService.qml` when the widget
# became a plugin; the mirror symlink was left behind pointing at a path that
# has not existed since, and showed up in every `diff -rq` of the tree for
# months as a phantom difference between the repo and the deployed config.
#
# Exits non-zero listing dangling links. Wired into run_tests.sh / CI.

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IMPORTS = ROOT / "tests" / "imports"


def main() -> int:
    failures = []
    if not IMPORTS.is_dir():
        print(f"test import symlinks: {IMPORTS} is gone - the mirror tree moved "
              f"without this check", file=sys.stderr)
        return 1

    links = 0
    for path in sorted(IMPORTS.rglob("*")):
        if not path.is_symlink():
            continue
        links += 1
        if path.exists():
            continue
        relative = path.relative_to(ROOT).as_posix()
        failures.append(
            f"{relative} -> {path.readlink()} does not resolve. A mirror "
            f"symlink outlives its target silently: nothing fails until a test "
            f"imports that type, which for an untested singleton is never.")

    if not links:
        failures.append("no symlinks found under tests/imports - the mirror tree "
                        "is gone, or this check is looking in the wrong place")

    for failure in failures:
        print(f"test import symlinks: {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Test import symlink lint passed: {links} links, all resolving")
    return 0


if __name__ == "__main__":
    sys.exit(main())
