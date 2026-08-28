#!/usr/bin/env python3
"""A wave member declares `appear` once, and never over one it inherits.

Membership of a StaggerEntrance/StaggerWave is duck-typed: a child is a
member because it declares `property real appear: 1` and folds it into its
opacity. That works right up until a type declares `appear` over a base that
already has one. QML then puts TWO properties of that name on the object: the
wave writes the derived one (JS resolves most-derived) while the base's
opacity binding, compiled in the base's scope, keeps reading its own. Nothing
errors. The member simply stops fading, and the entrance it belongs to looks
like it was retuned by somebody.

That is exactly what happened to the right sidebar's android quick toggles
when GroupButton moved onto RippleButton: the tile had declared its own
`appear` back when its base had none, and inherited a second one that day.

Scope: a QML file whose root type is a shell type that (transitively) declares
`property real appear`, and which declares `property real appear` itself.
"""

import pathlib
import re
import sys

SHELL = pathlib.Path(__file__).resolve().parent.parent
DECLARES = re.compile(r"^\s*property\s+real\s+appear\b", re.M)
ROOT = re.compile(r"^\s*([A-Z][\w.]*)\s*\{", re.M)


def root_type(text: str) -> str:
    body = "\n".join(
        line for line in text.splitlines()
        if not line.strip().startswith(("import ", "pragma ", "//", "*", "/*"))
    )
    match = ROOT.search(body)
    return match.group(1) if match else ""


def main() -> int:
    # Keyed by stem to a LIST, never to one path. This shell vendors a
    # designsystem mirror that carries a second RippleButton.qml, and the
    # first version of this lint kept whichever copy `rglob` yielded last -
    # the mirror's, which declares no `appear`. The root chain died there and
    # the lint reported a clean tree over the very regression it was written
    # for. A name in this repo can mean more than one file; ask them all.
    files = {}
    for path in SHELL.rglob("*.qml"):
        if "/tests/" in str(path):
            continue
        files.setdefault(path.stem, []).append(path)
    texts = {stem: [p.read_text(errors="replace") for p in paths]
             for stem, paths in files.items()}
    declares = {stem for stem, bodies in texts.items()
                if any(DECLARES.search(body) for body in bodies)}

    failures = []
    for stem, bodies in sorted(texts.items()):
        for body, path in zip(bodies, files[stem]):
            if not DECLARES.search(body):
                continue
            seen = set()
            base = root_type(body)
            while base in files and base not in seen:
                seen.add(base)
                if base in declares:
                    failures.append(
                        f"{path.relative_to(SHELL)}: declares `appear` over "
                        f"`{base}`, which already has one")
                    break
                base = next((root_type(b) for b in texts[base] if root_type(b)), "")

    if failures:
        print("A wave member's `appear` must not shadow an inherited one:")
        for failure in failures:
            print(f"  {failure}")
        print("Delete the local declaration - the base's opacity binding "
              "already carries it.")
        return 1
    print(f"  shadowed stagger `appear`: none ({len(declares)} declaring types)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
