# Test 1 Notes

## Baseline — demo1, 30s, 1 run x3

Command: `scripts/score.sh demo1 30 1`, run 3 times in a row on `frnt201.frontenac.local`, 16 CPUs, unmodified checkout (just built with `make -C doom`).

| Run | Valid | Invalid | Score |
|---|---|---|---|
| 1 | 64 | 0 | 64 valid demo1 demos in 30s |
| 2 | 64 | 0 | 64 valid demo1 demos in 30s |
| 3 | 64 | 0 | 64 valid demo1 demos in 30s |

Consistent 64/0 across all three — no node-load variance seen yet. This is the number to beat.

Build warnings seen (not errors, no action needed): `snprintf` truncation warnings in `wi_stuff.c`, unused variable `y_offset` in `i_video.c`, unused `rcsid`/`at_to_doom` consts — all pre-existing in doomgeneric, harmless.

## Baseline — demo2 and demo3, 30s

Command: `scripts/score.sh demo2 30 3` and `scripts/score.sh demo3 30 3` (median of 3), same build/node as above.

| Demo | Run 1 | Run 2 | Run 3 | Median score |
|---|---|---|---|---|
| demo2 | 64 valid, 0 invalid | 64 valid, 0 invalid | 64 valid, 0 invalid | 64 |
| demo3 | 64 valid, 0 invalid | 64 valid, 0 invalid | 64 valid, 0 invalid | 64 |

All three demos (1, 2, 3) baseline at exactly **64 valid / 0 invalid** in 30s, 16 CPUs — fully consistent, no variance across any run. Baseline across the whole demo set is 64.

## Compiler flags — `-O2`

Changed `doom/Makefile` `CFLAGS` from `-Os` to `-O2`, rebuilt with `make -C doom clean && make -C doom -j16`, ran via sbatch (`test.sh`, job 12417092).

`sacct -j 12417092`: COMPLETED, exit 0:0, 16 CPUs, batch step CPU time 00:06:36, MaxRSS 244208K.

```
Scoring demo1: 1 run(s) of 30s on frnt201.frontenac.local, 16 CPUs
  run 1: 64 valid demos, 0 invalid
SCORE: 64 valid demo1 demos in 30s (median of 1)
```

**Same as baseline: 64 valid / 0 invalid.** No change in demo count from `-O2` alone — matches the lecture's note that compiler flags can give only a small speedup, and here it wasn't enough (or wasn't the right kind of speedup) to push past 64 demos in the 30s window. ## Compiler flags — `-O3`

Changed `CFLAGS` to `-O3`, clean rebuild, same sbatch workflow.

```
Scoring demo1: 1 run(s) of 30s on frnt201.frontenac.local, 16 CPUs
  run 1: 64 valid demos, 0 invalid
SCORE: 64 valid demo1 demos in 30s (median of 1)
```

**Still 64 valid / 0 invalid** — identical to baseline and `-O2`. Compiler flags alone (`-Os` → `-O2` → `-O3`) made no measurable difference to the demo count. Strong signal that 64 is capped by something other than raw compute speed (likely how many copies `scripts/run.sh` launches, or I/O/startup overhead, not CPU-bound arithmetic). Next: profile with gprof to confirm where time actually goes before changing anything else.

## Baseline strategy — `scripts/run.sh`

This is where our team's run strategy lives (score.sh just calls it). Baseline, as handed off:

```bash
COPIES=${COPIES:-$(nproc)}        # 16 CPUs -> 16 copies

for i in $(seq 0 $((COPIES - 1))); do
    (
        cd "$workdir"
        while true; do
            "$DOOM_BIN" -iwad "$DOOM_IWAD" -timedemo "$DOOM_DEMO" || true
        done
    ) > "$RESULTS_DIR/w$i.log" 2>&1 &
done
wait
```

One copy per CPU (16 on frnt201 w/ `--cpus-per-task=16`), each copy re-execs `doomgeneric` from scratch for every demo (fresh process, fresh WAD load, fresh init, then plays the demo, then loops).

64 valid demos / 16 copies = 4 completions per copy in 30s → **~7.5s per cycle** (process startup + WAD load + actual demo playback combined).

**Likely explains the -O2/-O3 plateau:** those flags only speed up the rendering/game-logic arithmetic. If a meaningful chunk of the ~7.5s cycle is process startup + WAD loading rather than gameplay computation, faster arithmetic barely moves the total. Same lesson as the hotspot.c lecture: don't guess the hot spot, profile it.

**Hypothesis to test next:** profile one cycle (gprof) to see the startup/WAD-load vs. playback split. If startup dominates, the bigger win isn't compiler flags — it's restructuring `run.sh` to not re-exec Doom for every demo (loop inside one process instance instead of restarting the binary each time).

## Profiling — `perf record`, single `doomgeneric -timedemo demo1`

Ran directly on one invocation (not through `run.sh`), after `module load gcc`:

```
perf record -g -o perf.data -- ./doomgeneric -iwad ../freedoom1.wad -timedemo demo1
perf report -i perf.data --stdio
```

(First attempt failed: ran `perf record -g -o perf.data` with no target command, which defaults to system-wide monitoring and hits `perf_event_paranoid=2` — "Disallow kernel profiling". Fixed by adding `-- ./doomgeneric ...` so it only profiles our one process, which needs no elevated privilege.)

**Result — hypothesis overturned.** Restart/WAD-load overhead is NOT the bottleneck:

```
72.23%    72.23%  doomgeneric  doomgeneric  [.] I_FinishUpdate
```

**72% of all CPU cycles (Self, not just Children) are in `I_FinishUpdate`** (`doom/i_video.c`), called once per tic via `cmap_to_fb`. (The garbage-looking call-graph addresses under it, e.g. `0x24242400242424`, are a broken-stack-unwind artifact from missing frame pointers at this optimization level — unrelated noise, doesn't affect the trustworthy 72.23% Self figure on the leaf.)

**What `I_FinishUpdate`/`cmap_to_fb` actually do:** Doom renders internally to a 320x200, 8-bit palette-indexed buffer. The harness needs 640x400 true-color output (`DOOMGENERIC_RESX/RESY`, fixed by organizers, RULES.md requires full image every tic — can't shrink it). This function walks all 320x200=64,000 palette-index pixels every tic, does a palette lookup, checks `s_Fb.bits_per_pixel` **inside the per-pixel loop** (even though it's constant for the whole run), and writes each pixel `fb_scaling` (=2) times in a scalar byte-store loop to produce the 640x400=256,000 output pixels. One demo is thousands of tics (RULES.md example: `tics=7116`), so this scalar/branchy loop runs ~7000+ times per demo, ~1.8 billion pixel-writes total — dwarfing the actual 3D rendering and game logic.

**Explains the -O2/-O3 plateau:** this loop has a runtime branch and manual byte-stores inside it, which resist auto-vectorization — so compiler flags alone couldn't speed up the actual hot spot.

**Revised priority — supersedes the run.sh re-exec hypothesis above:** the `launcher.c` re-exec fix is still real but clearly secondary. First target now: `cmap_to_fb`/`I_FinishUpdate` in `doom/i_video.c` (editable — only `platform.c` is locked). Concrete first moves: hoist the `bits_per_pixel` branch out of the per-pixel loop (it's invariant per run), and special-case `fb_scaling == 2` to write wider chunks instead of the scalar inner loop.

## `i_video.c` fix — three changes, committed separately on `lucas`

1. **`made pixel packing update`** (`431a808`) — precompute `packed_colors[256]` (the fully packed 32bpp pixel) once per `I_SetPalette` call, instead of redoing the shift/OR packing per pixel per tic in `cmap_to_fb`.
2. **`ccfcb1e`** — fast path in `cmap_to_fb` for the actual case (32bpp, `fb_scaling == 2`): one 8-byte store of `pix | (pix << 32)` instead of a per-pixel branch + loop of two 4-byte stores.
3. **`f141ad7`** — `I_FinishUpdate`'s vertical-upscale loop called `cmap_to_fb` twice per source row with the *same* `line_in` both times, redoing identical work. Now converts once and `memcpy`s the duplicate row.

All three preserve output bit-for-bit (verified by tracing: `packed_colors` is always built after `I_InitGraphics` sets `s_Fb.bits_per_pixel`, before any `I_SetPalette` call can run — confirmed via `d_main.c`'s `D_DoomLoop`/`doomgeneric_Tick` call order).

**Result — demo1, 30s, 1 run, all three changes applied:**

```
Scoring demo1: 1 run(s) of 30s on frnt201.frontenac.local, 16 CPUs
  run 1: 145 valid demos, 0 invalid
SCORE: 145 valid demo1 demos in 30s (median of 1)
```

**145 valid / 0 invalid** — up from the 64/0 baseline (and the 64/0 `-O2`/`-O3` results). **2.27x improvement**, 0 invalid demos, so validation still passes. Matches the prediction from the `perf` data: `I_FinishUpdate` was 72% of per-invocation cycles, so cutting its cost sharply should cut total time-per-invocation sharply too — and since `run.sh`'s restart loop just packs in as many completions as it can in the fixed 30s window, a faster binary directly raises the count without touching `run.sh` at all.

Next: re-check demo2/demo3 (RULES.md — scoring demo is announced at scoring time, must be fast on all three), then revisit the `launcher.c` re-exec fix now that `I_FinishUpdate` isn't dominating as much, and test at full-node scale before trusting this generalizes.
