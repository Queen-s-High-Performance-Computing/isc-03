#!/usr/bin/env bash
# Profile one doomgeneric -timedemo run with perf.
#
# Usage:   scripts/run-perf.sh [demo]
# Default: scripts/run-perf.sh demo1
#
# Writes perf.data and perf-report.txt to the repo root.

set -euo pipefail

DEMO=${1:-demo1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

module load gcc

cd "$ROOT/doom"
perf record -g -o "$ROOT/perf.data" -- ./doomgeneric -iwad "$ROOT/freedoom1.wad" -timedemo "$DEMO"
perf report -i "$ROOT/perf.data" --stdio > "$ROOT/perf-report.txt"

echo "Report written to $ROOT/perf-report.txt"
