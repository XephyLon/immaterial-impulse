#!/usr/bin/env bash

# Resolve script directory to allow running from anywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find Qt6 qmltestrunner
QMLTESTRUNNER=""
POSSIBLE_PATHS=(
    "/usr/lib/qt6/bin/qmltestrunner"
    "/usr/lib64/qt6/bin/qmltestrunner"
    "/usr/lib/x86_64-linux-gnu/qt6/bin/qmltestrunner"
    "qmltestrunner-qt6"
    "qmltestrunner6"
    "qmltestrunner"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [[ -x "$path" ]]; then
        QMLTESTRUNNER="$path"
        break
    elif which "$path" &>/dev/null; then
        QMLTESTRUNNER="$(which "$path")"
        break
    fi
done

if [[ -z "$QMLTESTRUNNER" ]]; then
    echo "Error: qmltestrunner not found. Please install Qt6 Declarative Test package." >&2
    exit 1
fi

echo "Using test runner: $QMLTESTRUNNER"
echo "Running QML unit test suite..."

# Static lint: catch Appearance.* usage missing its qs.modules.common import
# before running the QML tests (this class of bug pegs the shell at 100% CPU).
echo "Running QML import lint..."
if ! "$SCRIPT_DIR/lint_qml_imports.sh"; then
    echo "Import lint failed."
    exit 1
fi

# Run the test runner
"$QMLTESTRUNNER" \
    -import "$PROJECT_ROOT/tests/mocks" \
    -import "$PROJECT_ROOT/tests/imports" \
    -input "$PROJECT_ROOT/tests"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "All tests passed successfully!"
else
    echo "Test suite failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
