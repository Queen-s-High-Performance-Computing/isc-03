#!/bin/bash
# Validates the fork-based demo-restart change (branch fork-demo-restart)
# against the baseline recorded in test1.md, then takes the real score.
#
# Submit with:  cd ~/<your-repo> && git checkout fork-demo-restart && sbatch testing/test2.sh
# (cd into the repo first so $SLURM_SUBMIT_DIR -- set by sbatch to the
# submission directory -- actually points at it.)
#SBATCH --time=00:35:00
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-cpu=1G
#SBATCH --output=test-%j.out

# Deliberately no `set -e`: doomgeneric's normal exit is non-zero (it
# reports fps via I_Error -> exit(-1)), so `-e` would kill this script
# after the very first check, the same way it killed run-perf.sh before
# that was fixed. Every check below runs and reports regardless of
# earlier failures, so a bad run still leaves a full log to read.
set -uo pipefail

ROOT=${SLURM_SUBMIT_DIR:-$(pwd)}
cd "$ROOT"

echo "== Build =="
module load gcc
make -C doom clean
make -C doom -j16
if [ ! -x doom/doomgeneric ]; then
    echo "FAIL: build did not produce doom/doomgeneric -- aborting, nothing else can run."
    exit 1
fi
echo "Build OK"

echo
echo "== Check 1: one process plays more than one demo (proves fork-reuse works) =="
smoke_log=$(mktemp)
( cd doom && timeout 20 ./doomgeneric -iwad ../freedoom1.wad -timedemo demo1 -nogui ) > "$smoke_log" 2>&1
n=$(grep -c '^DGVALID' "$smoke_log" || true)
echo "DGVALID lines seen in one 20s process: $n"
if [ "$n" -ge 2 ]; then
    echo "PASS: fork-reuse is producing repeated completions in a single process"
else
    echo "FAIL: expected >=2 DGVALID lines from one 20s run, got $n"
fi
grep '^DGVALID' "$smoke_log" | awk -F'[= ]' '{
    tics = $3; matched = $5
    status = (matched >= tics - 5) ? "ok" : "MISMATCH"
    print "  tics=" tics " matched=" matched " " status
}'
rm -f "$smoke_log"

echo
echo "== Check 2: quick sanity score (30s, 1 run) against the test1.md baseline of 64/demo =="
scripts/score.sh demo1 30 1 || echo "FAIL: score.sh demo1 30 1 exited non-zero"
scripts/score.sh demo2 30 1 || echo "FAIL: score.sh demo2 30 1 exited non-zero"
scripts/score.sh demo3 30 1 || echo "FAIL: score.sh demo3 30 1 exited non-zero"

echo
echo "== Official score (120s, median of 3), all three demos =="
scripts/score.sh demo1 120 3 || echo "FAIL: score.sh demo1 120 3 exited non-zero"
scripts/score.sh demo2 120 3 || echo "FAIL: score.sh demo2 120 3 exited non-zero"
scripts/score.sh demo3 120 3 || echo "FAIL: score.sh demo3 120 3 exited non-zero"

echo
echo "== Check 3: no doomgeneric processes survive scoring (scorer's group-kill reached every forked child) =="
leftover=$(pgrep -f doomgeneric || true)
if [ -z "$leftover" ]; then
    echo "PASS: no leftover doomgeneric processes"
else
    echo "FAIL: leftover processes still running:"
    echo "$leftover"
fi

echo
echo "== Done =="
