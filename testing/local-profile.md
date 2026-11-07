# Local function profile — 2026-11-07

Profiled the current optimized engine at commit `8c8b5a3`, using local GCC
11.4.0, `-O3 -ggdb3 -fno-omit-frame-pointer -pg`, and 20 separate full
invocations per demo. The host is a four-vCPU QEMU VM, not Frontenac.

GCC, make, binutils development files, and Linux perf were installed into
`~/.local/doom-tools` from Ubuntu packages, with command wrappers in
`~/.local/bin`. No administrator password was available for a system install.
Both `perf stat -e cycles:u -- true` and `perf stat -e cpu-clock:u -- true`
failed because the kernel has `perf_event_paranoid=4`. There is no new perf
hardware-counter recording; these are fresh **gprof CPU-time samples**.
The raw perf rejection messages are preserved alongside each auto-mode run.

## Findings

| Function (self sampled time) | demo1 | demo2 | demo3 |
|---|---:|---:|---:|
| I_FinishUpdate | 27.85% | 28.06% | 25.25% |
| R_DrawColumn | 21.11% | 18.01% | 14.60% |
| R_DrawSpan | 8.16% | 10.38% | 10.46% |
| R_RenderSegLoop | 5.76% | 7.22% | 6.72% |
| DG_DrawFrame | 4.72% | 5.60% | 3.55% |

All **60/60 demos passed validation**, using the official reference tic counts
and tolerance of five mismatching frames. Demo1: 7116 tics, 7115 matches;
demo2: 7088/7088; demo3: 6041/6041.

The strongest remaining targets are framebuffer conversion/upscaling, textured
columns, and floor/ceiling spans. The first three functions above account for
roughly 56–57% of sampled time on demo1/demo2. They warrant investigation before
process-launch changes, although this profile does not separately quantify I/O
waiting or prove that start-up costs are negligible.

Source-line sampling for demo1 identifies:

- `doom/i_video.c:176`: 23.99% at the expanded-pixel store in `cmap_to_fb`,
  inlined into `I_FinishUpdate`; another 2.06% at the preceding palette lookup.
- `doom/r_draw.c:139`: 14.00% at the column texture/light-table lookup and store.
- `doom/r_draw.c:634`: 4.27% at the span texture/light-table lookup and store.

Investigate instruction scheduling, redundant work, and exact-output-preserving
loop changes in those locations. The samples alone cannot distinguish cache
misses, bandwidth pressure, or instruction dependencies. `DG_DrawFrame` includes
the validator and is organizer-owned: leave it unchanged.

The old report's 72.23% for `I_FinishUpdate` describes an earlier build on a
different machine. The new figures are consistent with the current optimized
pixel conversion having reduced its dominance, but the two profiles are not a
controlled before/after speedup comparison. For illustration, halving a 28%
component yields only about 1.16x overall improvement under Amdahl's law.

## Reproduce and inspect

```bash
bash scripts/run-perf.sh demo1
bash scripts/run-perf.sh demo2
bash scripts/run-perf.sh demo3
# Force gprof, or change the sample collection length:
RUNS=20 bash scripts/run-perf.sh demo1 gprof
```

Each directory contains `gprof-report.txt` (flat function profile and call graph),
`gprof-lines.txt` (source lines, including inlined functions), `work/gmon.*` (raw
samples), `demo.log`, build logs, and perf probe errors. Source-line attribution
is approximate for optimized machine code. gprof instrumentation changes the
workload and its flat profile does not cover all shared-library/profiling costs;
use these percentages as hotspot guidance, not production cycle measurements.
No cache or branch-miss counters were collected. No scoring time was reported.

Artifacts from this measurement (ignored by Git):

- demo1: `results/profile-demo1-9iJUjAWt/`
- demo2: `results/profile-demo2-DSEDhXIW/`
- demo3: `results/profile-demo3-f7LITIfV/`
