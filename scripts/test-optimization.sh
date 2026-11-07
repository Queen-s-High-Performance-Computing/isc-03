#!/usr/bin/env bash
# Submit from the repository root: sbatch scripts/test-optimization.sh
# Practice comparison on the allocated Frontenac CPUs.
#SBATCH --time=00:20:00
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-cpu=1G
#SBATCH --output=optimization-%j.out

set -euo pipefail
cd "$(dirname "$0")/.."
module load gcc

if [[ ! -f freedoom1.wad ]]; then
    echo "Run ./get_freedoom.sh on the login node before submitting this job." >&2
    exit 1
fi

mkdir -p results/optimization
for opt in -Os -O3 -O4; do
    echo "Building with $opt"
    make -C doom clean
    make -C doom -j16 "OPT=$opt"
    for demo in demo1 demo2 demo3; do
        scripts/score.sh "$demo" 30 3 | tee "results/optimization/${opt#-}-${demo}.txt"
    done
done
