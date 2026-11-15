#!/usr/bin/env bash
# Profile one doomgeneric -timedemo run with perf.
#
# Usage:   scripts/run-perf.sh [demo]
# Default: scripts/run-perf.sh demo1
#
# Writes perf.data and perf-report.txt to the repo root.

set -euo pipefail

DEMO=${1:-demo1}
# $0 points at Slurm's spooled copy of this script when run via sbatch, not
# the real repo, so prefer SLURM_SUBMIT_DIR (set by salloc/sbatch) and only
# fall back to self-locating via $0 when run outside a Slurm job.
ROOT=${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}

module load gcc

cd "$ROOT/doom"
# A normal, successful -timedemo run still ends by calling I_Error (it's how
# this engine reports its own fps), which always exit(-1)s -- status 255.
# perf record propagates that, so under `set -e` the script died right here
# every time, before ever reaching `perf report` below.
status=0
perf record -g -o "$ROOT/perf.data" -- ./doomgeneric -iwad "$ROOT/freedoom1.wad" -timedemo "$DEMO" || status=$?
if [[ $status != 0 && $status != 255 ]]; then
    exit "$status"
fi
perf report -i "$ROOT/perf.data" --stdio > "$ROOT/perf-report.txt"

echo "Report written to $ROOT/perf-report.txt"
