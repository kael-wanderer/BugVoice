#!/usr/bin/env bash
# Runs the speech-to-text and cleanup benchmark on bench/clips.
# Usage: Scripts/stt-bench.sh [bugvoice-bench options]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
swift build -c release --product bugvoice-bench >&2
bench_binary="$(swift build -c release --show-bin-path)/bugvoice-bench"
# Apply the offline boundary only to inference: SwiftPM applies its own
# sandbox while evaluating manifests and cannot run inside a second sandbox.
for option in "$@"; do
    if [[ "$option" == "--latency" ]]; then
        exec /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
            "$bench_binary" --clips bench/clips "$@"
    fi
done
exec "$bench_binary" --clips bench/clips "$@"
