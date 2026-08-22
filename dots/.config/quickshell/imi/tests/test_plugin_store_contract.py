"""Contract checks for services/PluginStore.qml (plugin store client).

PluginStore is curl/cache Process wiring around three pure functions
(compareVersions / parseIndex / statusFor), so this pins what must survive
refactors: the pure logic stays byte-identical with the test double that
tst_plugin_store.qml exercises, the registry index URL stays a constant
https raw.githubusercontent.com URL, no process invocation goes through a
shell (argv arrays only, paths as their own elements), the fetch publishes
atomically via mv, and installs/upgrades delegate to PluginManager's
hardened installer pipeline instead of growing a second install path.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "PluginStore.qml"
DOUBLE = ROOT / "tests" / "imports" / "testservices" / "PluginStore.qml"
STORE_PAGE = ROOT / "modules" / "imi" / "settings" / "pages" / "PluginStorePage.qml"


def _source() -> str:
    return SERVICE.read_text()


def _function_block(source: str, name: str) -> str:
    """Extracts a brace-balanced `function <name>(...) { ... }` block."""
    start = source.index(f"function {name}")
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start : pos + 1]
    raise AssertionError(f"unbalanced braces in function {name}")


def test_logic_double_is_in_sync():
    double = DOUBLE.read_text()
    source = _source()
    for name in ("compareVersions", "parseIndex", "statusFor"):
        assert _function_block(source, name) == _function_block(double, name), (
            f"{name} drifted between services/PluginStore.qml and its test double"
        )


def test_index_url_is_a_constant_https_github_raw_url():
    match = re.search(
        r'readonly property string indexUrl: "([^"]+)"', _source()
    )
    assert match, "indexUrl must be a readonly string constant"
    assert re.match(r"^https://raw\.githubusercontent\.com/", match.group(1)), (
        "indexUrl must point at raw.githubusercontent.com over https"
    )
    assert match.group(1).endswith("/index.json")


def test_no_shell_invocations_anywhere():
    # Every Process in the service is a plain argv array; there is no shell
    # for interpolated values to escape into.
    source = _source()
    assert '"bash"' not in source, "PluginStore must not shell out via bash"
    assert '"sh"' not in source and "bash -c" not in source


def test_curl_is_argv_with_constant_flags():
    source = _source()
    assert (
        'command: ["curl", "-sfL", "--max-time", "15", "-o", root.tmpPath, root.indexUrl]'
        in source
    ), "curl must be invoked as an argv array with path and URL as own elements"


def test_fetch_publishes_atomically_via_mv():
    source = _source()
    assert 'command: ["mv", "-f", root.tmpPath, root.cachePath]' in source, (
        "the fetched index must be renamed over the cache, not written in place"
    )
    # The temp file lives in the same directory as the cache, so the rename
    # cannot cross filesystems and stays atomic.
    assert "readonly property string tmpPath: `${root.cacheDir}/" in source
    assert "readonly property string cachePath: `${root.cacheDir}/" in source


def test_install_and_upgrade_delegate_to_plugin_manager():
    source = _source()
    assert "PluginManager.installFromManifest(entry?.manifestUrl" in source
    assert "PluginManager.upgradeFromManifest(entry?.manifestUrl" in source


def test_cache_is_loaded_at_startup_for_offline_render():
    source = _source()
    assert re.search(
        r"FileView \{\s*\n\s*id: cacheView\s*\n\s*path: root\.cachePath", source
    ), "the on-disk index cache must load via a FileView at instantiation"
    assert "onLoaded: root.applyIndexText(cacheView.text())" in source


def test_parse_failure_keeps_last_good_entries():
    block = _function_block(_source(), "applyIndexText")
    assert "root.lastError = result.error" in block
    assert re.search(
        r"if \(result\.error !== null\) \{[^}]*return;", block, re.S
    ), "a malformed index must return early without touching entries"


def test_store_ui_is_gated_off_by_default():
    # The store ships dark until the public registry exists: the config flag
    # defaults to false, and PluginsPage both hides the entry points behind
    # it and constructs the store page through a gated Loader, so a disabled
    # store never instantiates the page or wakes the PluginStore singleton.
    config = (ROOT / "modules" / "common" / "Config.qml").read_text()
    assert "property bool storeEnabled: false" in config, (
        "plugins.storeEnabled must exist and default to off"
    )
    page = (ROOT / "modules" / "imi" / "settings" / "pages" / "PluginsPage.qml").read_text()
    assert "Config.options.plugins.storeEnabled" in page
    assert re.search(r"Loader \{\s*\n\s*active: root\.storeAvailable", page), (
        "PluginStorePage must sit behind a Loader gated on storeAvailable"
    )


def test_store_page_refreshes_on_show():
    # The store page must exist and trigger the stale-cache refresh when it
    # is shown, so the catalog is fresh without hammering the registry.
    assert STORE_PAGE.exists(), "PluginStorePage.qml is missing"
    assert "PluginStore.refreshIfStale()" in STORE_PAGE.read_text()


def test_store_page_renders_registry_strings_as_plain_text():
    # Registry content is remote attacker-influenced text; every explicit
    # textFormat in the store page must be PlainText (never RichText or
    # AutoText, which would let a malicious index inject markup), and the
    # page must actually carry the annotation on its registry-fed texts.
    source = STORE_PAGE.read_text()
    formats = re.findall(r"textFormat:\s*([A-Za-z.]+)", source)
    assert len(formats) >= 3, (
        "store page must annotate its registry-sourced texts with textFormat"
    )
    assert all(fmt == "Text.PlainText" for fmt in formats), (
        f"non-PlainText textFormat in PluginStorePage.qml: {formats}"
    )


def test_the_card_draws_its_identity_with_the_shared_catalogue_row():
    """The registry's name and byline reach the screen through CatalogueRow.

    The card's header used to be a hand-rolled icon / name / byline /
    affordance row - the third copy of one Edit Mode's drawer wrote five times
    and `ConfigSwitch` a sixth. It is the shared component now, which moves
    two of this file's registry-fed strings out of its own `textFormat`
    sweep above: `title` and `description` are annotated inside
    `CatalogueRow.qml` instead. That is only safe while it stays annotated
    there, and nothing else in this suite reads that file, so this does.
    """
    source = STORE_PAGE.read_text()
    assert "CatalogueRow {" in source, (
        "the store card no longer draws its identity with the shared row - a "
        "fourth hand-rolled copy is how the three drifted apart in the first "
        "place"
    )
    row = (ROOT / "modules" / "common" / "widgets" / "CatalogueRow.qml").read_text()
    formats = re.findall(r"textFormat:\s*([A-Za-z.]+)", row)
    assert len(formats) >= 2 and all(fmt == "Text.PlainText" for fmt in formats), (
        f"CatalogueRow must pin PlainText on the strings it renders, found "
        f"{formats} - the store's name and byline go through it, and "
        f"Text.AutoText would render a registry-supplied <img src=...>"
    )


def test_shell_version_read_from_version_file():
    source = _source()
    assert 'Qt.resolvedUrl(Quickshell.shellPath("VERSION"))' in source, (
        "shell version must come from the VERSION file, same as the About page"
    )


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
