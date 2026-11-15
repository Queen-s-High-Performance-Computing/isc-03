#!/usr/bin/env bash
# Detailed instruction/cache/branch simulation; run locally or in a compute job.
set -euo pipefail
ROOT=${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DEMO=${1:-demo1}
if (( $# > 1 )) || [[ ! $DEMO =~ ^demo[123]$ ]]; then
    echo "Usage: $0 [demo1|demo2|demo3]" >&2
    exit 2
fi
if type module >/dev/null 2>&1; then module load gcc; fi
for tool in make valgrind callgrind_annotate; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
[[ -f "$ROOT/freedoom1.wad" && -f "$ROOT/reference/$DEMO.txt" ]] || {
    echo 'Missing WAD or demo reference.' >&2; exit 1;
}
mkdir -p "$ROOT/results"
OUT=$(mktemp -d "$ROOT/results/callgrind-$DEMO-XXXXXXXX")
exec > >(tee "$OUT/summary.txt") 2>&1
echo "Artifacts: $OUT"
echo 'Instruction counts and simulated cache/branch behavior, not elapsed-time percentages.'
valgrind --version
git -C "$ROOT" rev-parse HEAD
git -C "$ROOT" status --short
mkdir -p "$OUT/work"
make -C "$ROOT/doom" -j4 OBJDIR="$OUT/build" OUTPUT="$OUT/doomgeneric" \
    > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
cd "$OUT/work"
export DG_REFERENCE="$ROOT/reference/$DEMO.txt"
unset DG_RECORD
status=0
valgrind --tool=callgrind --cache-sim=yes --branch-sim=yes \
    --dump-instr=yes --collect-jumps=yes --callgrind-out-file="$OUT/callgrind.out" \
    --log-file="$OUT/valgrind.log" "$OUT/doomgeneric" \
    -iwad "$ROOT/freedoom1.wad" -timedemo "$DEMO" > "$OUT/demo.log" 2>&1 || status=$?
[[ $status == 0 || $status == 255 ]] || {
    cat "$OUT/valgrind.log" "$OUT/demo.log"; exit "$status";
}
expected=$(wc -l < "$DG_REFERENCE")
awk -v want="$expected" '
    /^DGVALID/ {
        n++; split($2,t,"="); split($3,m,"=")
        if (NF==3 && $2 ~ /^tics=[0-9]+$/ && $3 ~ /^matched=[0-9]+$/ &&
            t[2]==want && m[2]>=want-5 && m[2]<=want) good++
    }
    END {exit !(n==1 && good==1)}' "$OUT/demo.log" || {
        cat "$OUT/demo.log"; echo 'Demo validation FAILED' >&2; exit 1;
    }
callgrind_annotate --auto=no --show=Ir --sort=Ir "$OUT/callgrind.out" \
    > "$OUT/instructions.txt"
callgrind_annotate --auto=no --show=Dr,Dw,D1mr,D1mw,DLmr,DLmw \
    --sort=D1mr,D1mw "$OUT/callgrind.out" > "$OUT/memory.txt"
callgrind_annotate --auto=no --show=Ir,Dr,Dw,D1mr,D1mw,DLmr,DLmw \
    --sort=D1mw "$OUT/callgrind.out" > "$OUT/writes.txt"
callgrind_annotate --auto=no --show=Bc,Bcm,Bi,Bim --sort=Bcm \
    "$OUT/callgrind.out" > "$OUT/branches.txt"
callgrind_annotate --auto=no --show=Ir,Dr,Dw,D1mr,D1mw,Bc,Bcm \
    "$OUT/callgrind.out" "$ROOT/doom/i_video.c" > "$OUT/video-lines.txt"
callgrind_annotate --auto=no --show=Ir,Dr,Dw,D1mr,D1mw,Bc,Bcm \
    "$OUT/callgrind.out" "$ROOT/doom/r_draw.c" > "$OUT/draw-lines.txt"
sed -n '/^DGVALID/p' "$OUT/demo.log"
sed -n '1,45p' "$OUT/instructions.txt"
echo "Details: $OUT/video-lines.txt, $OUT/draw-lines.txt, and $OUT/memory.txt"
