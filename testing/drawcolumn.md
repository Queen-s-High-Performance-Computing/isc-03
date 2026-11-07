# R_DrawColumn optimization — 2026-11-07

Changed only `R_DrawColumn` in the engine. The baseline is the original
function at commit `8c8b5a3`; the candidate keeps the same palette lookup,
texture indexing, fixed-point arithmetic, bounds checks, and pixel output.

## Change and reason

- Copy `dc_source` and `dc_colormap` to local pointers once per column.
  GCC 11 previously reloaded both globals on each pixel because byte stores
  can alias global pointer storage. Assembly confirms these reloads are now
  outside the loop. No texture or frame results are cached.
- Draw four pixels per iteration, with a scalar tail for remaining pixels.
  This reduces loop control overhead and lets the compiler schedule more work.

## Checks and measurements

`bash testing/test_drawcolumn.sh` passed 6,000 exact-output cases against an
independent scalar pixel calculation. These cover empty, one-pixel, full-height,
and partial columns, positive/negative phases and steps, randomized texture
and lighting tables, and untouched pixels/buffer guards. Test values avoid
signed overflow. The harness compiles the actual engine source.

`bash testing/test_drawcolumn.sh --bench` compares with the original scalar
function in `testing/drawcolumn_reference.c`, compiled separately with the same
flags. In seven paired rounds, caching the pointers alone gave a median 1.08x
speedup; caching plus four-pixel unrolling gave a median 1.77x speedup. This is
a synthetic mix of column heights, not the distribution of a particular demo.

Full-demo comparison used ordinary `-O3` builds without gprof. Both variants
were pinned to CPU 0 on this four-vCPU local QEMU VM. Five runs per variant per
demo alternated baseline/candidate order. Each used a fresh working directory
and the same WAD/reference. CPU time is child user+system time; elapsed time
covers process launch through exit. Values are medians.

| Demo | Baseline CPU | Candidate CPU | CPU reduction | Elapsed reduction |
|---|---:|---:|---:|---:|
| demo1 | 0.9129 s | 0.8762 s | 4.02% | 1.90% |
| demo2 | 0.8800 s | 0.8479 s | 3.65% | 1.60% |
| demo3 | 0.9341 s | 0.9179 s | 1.73% | 0.79% |

All **30/30 demos validated** (15 baseline, 15 candidate). Demo1 matched
7115/7116 tics within the official tolerance; demo2 and demo3 matched every
tic. Full-demo gains are much smaller than isolated-loop gains. The earlier
gprof shares are not a reliable predictor of exact speedups because profiling
adds overhead and the synthetic column mix differs from real gameplay.

An unsigned phase-shift variant was also tested locally; its isolated gain
over ordinary unrolling was marginal, so it was not retained.

These are local measurements, not competition scores or measurements of
Frontenac. Confirm on the scoring hardware when it is available. No protected
files were changed, and `I_FinishUpdate` was left as it was.

Artifacts: `results/drawcolumn-rthlpgd4/`. This contains baseline and
candidate builds, original source, raw benchmark output, `compare.py`, all
validation logs, per-run `measurements.json`, and aggregate `summary.json`.

AI assistance: OpenAI Codex inspected the loop/assembly, implemented the local
pointer copies and unrolling, and ran correctness and performance checks.
