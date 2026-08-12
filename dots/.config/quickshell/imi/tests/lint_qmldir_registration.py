#!/usr/bin/env python3
"""A QML type used by identifier must be listed in its directory's qmldir.

A directory with a `qmldir` is a module, and the qmldir is the whole of its
type list: implicit same-directory resolution is OFF, and a directory import
(`import "..." as Alias`) shows only the listed names too. So a new .qml file
in such a directory is not a type until the qmldir says so - referencing it
compiles nowhere and fails only at scene load, as `Type X unavailable` /
`X is not a type`, taking every widget built on it down with it.

That is not hypothetical. `WidgetCard.qml` shipped unregistered: the full test
suite was green - `DesignSystemCompile` checked the file standalone and
reported `failures=0` - and the deploy blanked every desktop widget at once.
Second time this blind spot has bitten (the duplicate-import incident was the
first), which per the house rule makes it a check rather than a note.

Files reached only by URL (`Loader { source: "clock/PillClock.qml" }`) are
deliberately exempt: a URL bypasses the qmldir, so listing is not required -
the three NandoClock styles are the standing example. The lint therefore
checks *references by identifier*, not directory contents:

- a bare `TypeName {` in a file whose own directory holds `TypeName.qml`
  under a qmldir that does not list it;
- an `Alias.TypeName {` where `Alias` is a directory import of a qmldir
  module that does not list `TypeName`.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__", "tests"}

DIR_IMPORT = re.compile(r'^\s*import\s+"([^"]+)"\s+as\s+(\w+)\s*$', re.M)


def listed_types(qmldir: Path) -> set:
    names = set()
    for line in qmldir.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        # `Name File.qml` or `singleton Name File.qml` (with optional version
        # numbers between) - the declared name is the first capitalised token.
        if len(parts) >= 2 and parts[-1].endswith(".qml"):
            for token in parts[:-1]:
                if token[:1].isupper():
                    names.add(token)
                    break
    return names


def main() -> int:
    qml_files = [p for p in sorted(ROOT.rglob("*.qml"))
                 if not any(part in SKIP_DIRS for part in p.relative_to(ROOT).parts)]
    modules = {}  # dir -> set of listed type names
    for qmldir in ROOT.rglob("qmldir"):
        if any(part in SKIP_DIRS for part in qmldir.relative_to(ROOT).parts):
            continue
        modules[qmldir.parent.resolve()] = listed_types(qmldir)

    failures = []
    for path in qml_files:
        text = path.read_text(encoding="utf-8")
        directory = path.parent.resolve()

        # Bare same-directory siblings in a bundled package with NO qmldir.
        # A package component loaded BY URL (PluginNode / PluginBarWidget
        # `source:`) gets no implicit directory import under the qs: scheme,
        # so the reference fails at scene load - MediaTransportButton shipped
        # exactly this way and every media widget vanished. A file reached
        # only through a DIRECTORY import would resolve bare (that is how the
        # bar's discord popup worked while the same package's Widget.qml was
        # a latent failure), but which load path reaches a file is invisible
        # here and one qmldir serves both - so the rule is uniform.
        # See docs/PLUGINS.md, Multi-file packages.
        in_bundled_package = "bundled" in path.relative_to(ROOT).parts
        if in_bundled_package and directory not in modules:
            for sibling in directory.glob("*.qml"):
                name = sibling.stem
                if sibling == path or not name[:1].isupper():
                    continue
                if re.search(rf"(?<![\w.\"/]){name}\s*\{{", text):
                    failures.append(
                        f"{path.relative_to(ROOT)}: uses sibling `{name}` but the "
                        f"package has no qmldir - under the qs: URL scheme there is "
                        f"no implicit directory import, so this fails at scene load. "
                        f"Add a qmldir listing it (docs/PLUGINS.md, Multi-file packages).")

        # Bare same-directory siblings under a qmldir.
        if directory in modules:
            listed = modules[directory]
            for sibling in directory.glob("*.qml"):
                name = sibling.stem
                if sibling == path or name in listed or not name[:1].isupper():
                    continue
                if re.search(rf"(?<![\w.\"/]){name}\s*\{{", text):
                    failures.append(
                        f"{path.relative_to(ROOT)}: uses `{name}` but "
                        f"{directory.relative_to(ROOT.resolve())}/qmldir does not list it - "
                        f"a qmldir directory has no implicit siblings, so this fails at "
                        f"scene load as '{name} is not a type'.")

        # Aliased directory imports of qmldir modules.
        for match in DIR_IMPORT.finditer(text):
            target = (directory / match.group(1)).resolve()
            alias = match.group(2)
            if target not in modules:
                continue
            listed = modules[target]
            for use in re.finditer(rf"\b{alias}\.(\w+)\s*\{{", text):
                name = use.group(1)
                if name in listed or not (target / f"{name}.qml").exists():
                    continue
                failures.append(
                    f"{path.relative_to(ROOT)}: uses `{alias}.{name}` but "
                    f"{target.relative_to(ROOT.resolve())}/qmldir does not list it - "
                    f"fails at scene load as 'Type {alias}.{name} unavailable'.")

    if failures:
        print("qmldir registration lint failed:\n", file=sys.stderr)
        for failure in sorted(set(failures)):
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"qmldir registration lint passed: every identifier-referenced type is "
          f"listed ({len(modules)} modules)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
