"""Minimal runner for the pytest-style contract test modules.

These modules only define `test_*` functions. Invoked as `python3 <file>` they
would define those functions and exit 0 without ever calling them, so
`run_tests.sh` reported them as passing while every assertion was dead. Each
module calls `run(globals())` from its `__main__` block instead.
"""

import traceback


def run(namespace) -> int:
    cases = sorted(
        (name, value)
        for name, value in namespace.items()
        if name.startswith("test_") and callable(value)
    )
    if not cases:
        print("No test_* functions found")
        return 1

    failures = 0
    for name, case in cases:
        try:
            case()
        except Exception:
            failures += 1
            print(f"FAIL {name}")
            traceback.print_exc()

    print(f"{len(cases) - failures}/{len(cases)} contract checks passed")
    return 1 if failures else 0
