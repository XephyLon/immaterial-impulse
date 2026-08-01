import re
from pathlib import Path


RIPPLES = [
    Path("modules/common/widgets/RippleButton.qml"),
    Path("modules/common/plugins/designsystem/widgets/RippleButton.qml"),
]


def test_ripple_handlers_call_the_owning_component_explicitly():
    for path in RIPPLES:
        source = path.read_text()
        assert "root.startRipple(" in source, path
        handler = source[source.index("MouseArea {"):source.index("RippleAnim {", source.index("MouseArea {"))]
        # Any unqualified call resolves through the delegate context, which
        # may already be invalid by the time the handler runs.
        assert not re.search(r"(?<![\w.])startRipple\(", handler), path


def test_ripple_animations_stop_before_delegate_destruction():
    for path in RIPPLES:
        source = path.read_text()
        assert "Component.onDestruction" in source, path
        assert "rippleAnim.stop()" in source, path
        assert "rippleFadeAnim.stop()" in source, path


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
