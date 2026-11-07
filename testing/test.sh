#!/bin/bash
#SBATCH --time=00:20:00
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-cpu=1G
#SBATCH --output=test-%j.out

cd ~/qhpc/isc-03
module load gcc
make -C doom clean
make -C doom -j16
scripts/score.sh demo1 30 1
scripts/score.sh demo2 30 1
scripts/score.sh demo3 30 1
scripts/run-perf.sh demo1
