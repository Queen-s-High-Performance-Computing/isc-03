#!/usr/bin/env bash
# Profile locally or in a compute allocation. Never run on a cluster login node.
# Usage: RUNS=20 scripts/run-perf.sh [demo1|demo2|demo3] [auto|perf|gprof]
set -euo pipefail
# sbatch executes a spooled copy; SLURM_SUBMIT_DIR locates the real checkout.
ROOT=${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DEMO=${1:-demo1}
BACKEND=${2:-auto}
RUNS=${RUNS:-20}
[[ $RUNS =~ ^([1-9][0-9]?|100)$ ]] || { echo 'RUNS must be 1..100' >&2; exit 2; }
if (( $# > 2 )) || [[ ! $DEMO =~ ^demo[123]$ || ! $BACKEND =~ ^(auto|perf|gprof)$ ]]; then
    echo "Usage: $0 [demo1|demo2|demo3] [auto|perf|gprof]" >&2
    exit 2
fi
if type module >/dev/null 2>&1; then module load gcc; fi
for tool in gcc make awk; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
[[ -f "$ROOT/freedoom1.wad" ]] || { echo 'Missing freedoom1.wad; run ./get_freedoom.sh' >&2; exit 1; }
[[ -f "$ROOT/reference/$DEMO.txt" ]] || { echo "Missing reference for $DEMO" >&2; exit 1; }
mkdir -p "$ROOT/results"
OUT=$(mktemp -d "$ROOT/results/profile-$DEMO-XXXXXXXX")
exec > >(tee "$OUT/summary.txt") 2>&1
echo "Artifacts: $OUT"
uname -a
gcc --version | head -1
printf 'Commit: '; git -C "$ROOT" rev-parse HEAD
printf 'Working tree:\n'; git -C "$ROOT" status --short
EVENT=
if [[ $BACKEND != gprof ]] && command -v perf >/dev/null; then
    for event in cycles:u cpu-clock:u; do
        if perf stat -e "$event" -- true > "$OUT/probe-${event%:*}.txt" 2>&1; then
            EVENT=$event
            break
        fi
    done
fi
if [[ -n $EVENT ]]; then
    BACKEND=perf
elif [[ $BACKEND == perf ]]; then
    echo 'perf events unavailable. See probe logs; try auto or gprof.' >&2
    exit 1
else
    BACKEND=gprof
    command -v gprof >/dev/null || { echo 'Missing tool: gprof (install binutils)' >&2; exit 1; }
    echo 'Using gprof CPU-time sampling (perf unavailable or gprof requested).'
fi
# Separate build directories prevent profiler flags contaminating scoring builds.
mkdir -p "$OUT/build" "$OUT/work"
FLAGS='-ggdb3 -O3 -Wall -DNORMALUNIX -DLINUX -DSNDSERV -D_DEFAULT_SOURCE -fno-omit-frame-pointer'
if [[ $BACKEND == gprof ]]; then FLAGS+=' -pg'; fi
make -C "$ROOT/doom" -j4 OBJDIR="$OUT/build" OUTPUT="$OUT/doomgeneric" \
    CFLAGS="$FLAGS" > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
export DG_REFERENCE="$ROOT/reference/$DEMO.txt"
unset DG_RECORD
cd "$OUT/work"
status=0
if [[ $BACKEND == perf ]]; then
    RUNS=1
    perf record -e "$EVENT" -F 499 --call-graph dwarf -o "$OUT/perf.data" -- \
        "$OUT/doomgeneric" -iwad "$ROOT/freedoom1.wad" -timedemo "$DEMO" > "$OUT/demo.log" 2>&1 || status=$?
    # This engine ends successful timedemos via I_Error, which exits 255.
    [[ $status == 0 || $status == 255 ]] || { cat "$OUT/demo.log"; exit "$status"; }
    perf report -i "$OUT/perf.data" --stdio --no-children > "$OUT/perf-report.txt"
    REPORT="$OUT/perf-report.txt"
else
    echo "Sampling $RUNS complete demos to reduce sampling noise."
    for (( run=1; run<=RUNS; run++ )); do
        status=0
        GMON_OUT_PREFIX="$OUT/work/gmon" "$OUT/doomgeneric" \
            -iwad "$ROOT/freedoom1.wad" -timedemo "$DEMO" >> "$OUT/demo.log" 2>&1 || status=$?
        [[ $status == 0 || $status == 255 ]] || { cat "$OUT/demo.log"; exit "$status"; }
    done
    gprof "$OUT/doomgeneric" "$OUT"/work/gmon.* > "$OUT/gprof-report.txt"
    gprof -l "$OUT/doomgeneric" "$OUT"/work/gmon.* > "$OUT/gprof-lines.txt"
    REPORT="$OUT/gprof-report.txt"
fi
# Match the official scorer's tic count and five-frame tolerance.
expected=$(wc -l < "$DG_REFERENCE")
awk -v want="$expected" -v runs="$RUNS" '
    /^DGVALID/ {
        n++; split($2,t,"="); split($3,m,"=")
        if (NF==3 && $2 ~ /^tics=[0-9]+$/ && $3 ~ /^matched=[0-9]+$/ &&
            t[2]==want && m[2]>=want-5 && m[2]<=want) good++
    }
    END {exit !(n==runs && good==runs)}' "$OUT/demo.log" || {
        cat "$OUT/demo.log"; echo 'Demo validation FAILED' >&2; exit 1;
    }
sed -n '/^DGVALID/p' "$OUT/demo.log"
echo "Validated. Backend: $BACKEND; report: $REPORT"
sed -n '1,40p' "$REPORT"
