#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORY_MAX="${DOCKER_TEST_MEMORY_MAX:-1536M}"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "Docker memory test requires a Wayland session." >&2
    exit 77
fi

run_harness() {
    local name="$1"
    local harness="$2"
    systemd-run --user --wait --collect \
        --unit="quickshell-docker-$name-$USER-$$" \
        -p "MemoryMax=$MEMORY_MAX" \
        -p MemorySwapMax=0 \
        -p TimeoutStopSec=2s \
        quickshell -p "$PROJECT_ROOT/$harness"
}

run_harness control DockerBarControlRuntimeTest.qml
run_harness isolated DockerRuntimeTest.qml
run_harness full-bar DockerBarHostRuntimeTest.qml

echo "Docker control, isolated, and full-bar runtimes stayed within $MEMORY_MAX and exited normally."
