#!/usr/bin/env bash
# Runs the speech-to-text and cleanup benchmark on bench/clips.
# Usage: Scripts/stt-bench.sh [bugvoice-bench options]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
swift build -c release --product bugvoice-bench
"$(swift build -c release --show-bin-path)/bugvoice-bench" --clips bench/clips "$@"
