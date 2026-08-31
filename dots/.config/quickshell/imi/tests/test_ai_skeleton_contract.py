#!/usr/bin/env python3
"""Source contract: the AI pane's three-surface skeleton stays composed.

The surfaces are not unit-testable headless, so these pins are the
regression net for the shapes that fail silently: a status pill quietly
reintroduced beside the chips, a second writer on the composer's entrance
channels, a chip that lost the command hint that replaced its pill.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CHAT = ROOT / "modules/imi/sidebarLeft/AiChat.qml"
BAR = ROOT / "modules/imi/sidebarLeft/aiChat/ChatControlBar.qml"
CONFIG = ROOT / "modules/common/Config.qml"


def test_the_three_surfaces_stand_and_the_pill_is_gone():
    body = CHAT.read_text(encoding="utf-8")
    for marker in ("id: toolsBarSurface", "id: chatAreaSurface", "id: inputWrapper",
                   "ChatControlBar", "EmptyStateKey"):
        assert marker in body, f"the skeleton lost {marker}"
    for gone in ("statusBg", "component StatusItem", "component StatusSeparator"):
        assert gone not in body, f"the floating status pill crept back: {gone}"


def test_the_composer_has_one_entrance_writer():
    """The wave dressing and the rise animation both write opacity; a
    composer that is both a wave member and its own entrance doubles the
    channel - the quick-toggle grid's two-writers bug, one surface over."""
    body = CHAT.read_text(encoding="utf-8")
    wrapper = re.search(r'id: inputWrapper[\s\S]{0,600}', body).group(0)
    assert "property real appear" not in wrapper, (
        "inputWrapper is a wave member again while carrying its own entrance")
    assert "onEntranceTriggerChanged" in body, "the composer entrance is gone"


def test_the_chips_carry_the_pills_command_hints():
    body = BAR.read_text(encoding="utf-8")
    assert "temp VALUE" in body, "the temp chip lost its command hint"
    assert "keysRequested" in body, (
        "the key chip must open the keys view, not pre-fill a command")
    assert "StyledComboBox" in body and "setModel" in body, (
        "the model control must be a real picker, not a pre-fill")
    assert "StyledToolTip" in body
    assert "clearMessages" in body, "the new-chat chip lost its action"


def test_one_providers_editor_serves_both_surfaces():
    """The sidebar keys view and the Services page render the SAME editor -
    a second copy is how the two drift, and drifting key-migration logic is
    how someone's key lands on the wrong provider."""
    editor = ROOT / "modules/imi/aiProviders/AiProvidersEditor.qml"
    assert editor.exists()
    chat = CHAT.read_text(encoding="utf-8")
    services = (ROOT / "modules/imi/settings/pages/ServicesConfig.qml").read_text(encoding="utf-8")
    assert "AiProvidersEditor" in chat and "AiProvidersEditor" in services
    assert "apiKeysAfterRemoval" not in services, (
        "the key-migration logic must live in the one editor")


def test_the_greeting_key_exists_and_rolls():
    config = CONFIG.read_text(encoding="utf-8")
    assert re.search(r'JsonObject ai: JsonObject \{[^}]*greeting', config, re.DOTALL), (
        "sidebar.ai.greeting is gone from the schema")
    chat = CHAT.read_text(encoding="utf-8")
    assert "refreshGreeting" in chat and "greetingLines" in chat


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from contract_runner import run
    sys.exit(run(globals()))
