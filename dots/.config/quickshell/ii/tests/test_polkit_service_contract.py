"""Contract checks for services/PolkitService.qml.

PolkitService is pure agent wiring around Quickshell.Services.Polkit — there
is no callable pure logic to unit-test, so this pins the structure that must
survive refactors: the agent is actually registered, an incoming request
re-arms the interaction flag, a failed authentication re-enables input
instead of dead-ending the dialog, and submit() disarms input so a response
cannot be sent twice.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "PolkitService.qml"


def _source() -> str:
    return SERVICE.read_text()


def test_agent_is_registered_and_exposed():
    source = _source()
    assert "import Quickshell.Services.Polkit" in source
    assert re.search(r"PolkitAgent\s*\{", source), "no PolkitAgent instance: agent never registers"
    assert "property alias agent: polkitAgent" in source
    assert "property alias active: polkitAgent.isActive" in source
    assert "property alias flow: polkitAgent.flow" in source


def test_incoming_request_enables_interaction():
    source = _source()
    assert re.search(
        r"onAuthenticationRequestStarted:\s*\{\s*root\.interactionAvailable = true;",
        source,
    )


def test_failed_authentication_reenables_interaction():
    source = _source()
    connections = re.search(
        r"Connections\s*\{\s*target:\s*root\.flow(.*?)\n    \}", source, re.S
    )
    assert connections, "no Connections on root.flow"
    body = connections.group(1)
    assert "function onAuthenticationFailed()" in body
    assert "root.interactionAvailable = true;" in body
    # KNOWN GAP (pinned deliberately): the failure path is silent — nothing is
    # logged when authentication fails, so a misbehaving agent leaves no trace
    # in log.log. If logging is ever added, flip this assertion and keep it.
    assert "console." not in body and "print(" not in body, (
        "failure path gained logging — great; update this contract to require it"
    )


def test_submit_disarms_interaction_to_prevent_double_submit():
    source = _source()
    submit = re.search(r"function submit\(string\)\s*\{(.*?)\}", source, re.S)
    assert submit, "submit() missing"
    assert "root.flow.submit(string)" in submit.group(1)
    assert "root.interactionAvailable = false" in submit.group(1)


def test_cancel_routes_through_the_flow():
    assert "root.flow.cancelAuthenticationRequest()" in _source()


def test_prompt_cleanup_expressions_are_null_safe():
    source = _source()
    # cleanMessage bails out before dereferencing a missing flow...
    assert re.search(r'if \(!root\.flow\)\s*return "";', source)
    # ...and cleanPrompt optional-chains into it, with translated fallbacks.
    assert "PolkitService.flow?.inputPrompt" in source
    assert 'Translation.tr("Password")' in source
    assert 'Translation.tr("Input")' in source


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
