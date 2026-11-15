# What we changed and why

This file explains every change we've made to the engine and scripts, how
each one works, and what it did to performance. Start with the background
section if you haven't looked at how Doom draws a frame.

## Background: what one frame costs

For every game tic, Doom:

1. Runs the game logic (monsters, player movement, etc.).
2. Draws the 3D view into `I_VideoBuffer`, a 320x200 buffer with one byte per
   pixel. Each byte is a palette index, not a colour. Walls are drawn as
   vertical strips (`R_DrawColumn`), and floors and ceilings as horizontal
   strips (`R_DrawSpan`).
3. Converts that buffer to the real output in `I_FinishUpdate`: 640x400, 4
   bytes per pixel, so every source pixel becomes a 2x2 block of 32-bit colour.
   That's 1 MB written per frame.
4. Calls `DG_DrawFrame` (organizer's `platform.c`, we can't change it), which
   fingerprints the frame and compares it with the reference.

Profiling showed steps 2 and 3 are nearly all the CPU time. We also found
that a big part of each demo wasn't CPU time at all, but sleeping (see
change 7).

## Score history on frnt201

`scripts/score.sh <demo> 30 1`, 16 CPUs, one run each. These are practice
numbers on a shared node, not the official 128-thread, 120 s score. Running
the same binary twice moved the score by up to ~3% (demo3 went from 146 to
151 with no code change), so small differences are noise.

| Build | demo1 | demo2 | demo3 |
|---|---:|---:|---:|
| Starter kit (`-Os`) | 64 | 64 | 64 |
| `-O2` / `-O3` | 64 | | |
| + I_FinishUpdate changes 1-3 | 145 | | |
| + R_DrawColumn + `-nogui` | 150 | 156 | 148 |
| + R_RenderSegLoop | 158 | 157 | 146 |
| + R_DrawSpan | 162 | 163 | 146 |
| same build, rerun | 161 | 164 | 151 |
| + I_FinishUpdate change 5, melt fix, `-flto` | not measured yet | | |

The melt fix (change 7) is the one we expect to move the score most. It
still needs a cluster run.

## The changes

### 1. Compiler flags: `-Os` -> `-O3 -flto` (`doom/Makefile`)

The starter kit optimised for size. We switched to `-O3`. On its own this
didn't change the score (64 -> 64), because almost all the time was in
`I_FinishUpdate`'s per-pixel loop, which the compiler couldn't speed up much
as written. It helps the later changes, since they're written so the
compiler can optimise them.

We later added `-flto` (link-time optimisation, which lets GCC optimise
across source files). Locally that cut CPU time by about 4% (0.85 -> 0.82 s
on demo1), and all three demos still validate. `-march=native` and PGO gave
nothing extra, so we didn't use them.

### 2. I_FinishUpdate: pack the palette once (`doom/i_video.c`)

Originally, for every pixel of every frame, `cmap_to_fb` looked up the
palette entry and assembled the 32-bit colour with shifts and ORs:

```c
pix = (c.r << s_Fb.red.offset) | (c.g << s_Fb.green.offset) | (c.b << s_Fb.blue.offset);
```

The palette only changes when `I_SetPalette` runs (damage flash, pickups,
gamma change), so `I_SetPalette` now builds `packed_colors[256]` and the
per-pixel work is one table lookup.

### 3. I_FinishUpdate: 2x fast path in `cmap_to_fb`

Each source pixel becomes two identical output pixels side by side. Instead
of a loop writing two 4-byte values (plus a bits-per-pixel check every
pixel), the 32 bpp / 2x case writes one 8-byte value that holds both copies.

### 4. I_FinishUpdate: convert each row once

Each source row becomes two identical output rows. The original converted the
source row twice. Now it converts it once and `memcpy`s the result to the
next row.

Changes 2-4 together took demo1 from 64 to 145 on frnt201.

### 5. I_FinishUpdate: doubled palette + dedicated 2x function

- `I_SetPalette` also builds `doubled_colors[256]`: each entry is the 32-bit
  colour repeated twice in a 64-bit value. A source pixel is now one load and
  one 8-byte store, with no shift/OR at all.
- `finish_update_2x()` handles the normal case (32 bpp, 2x, 640x400 output)
  as one tight loop. It converts 4 source pixels per iteration, so the CPU
  can overlap the 4 independent table loads, then copies the row. Any other
  mode (16 bpp, other scaling, padded framebuffer) still uses the original
  general code.
- We also tried writing both output rows directly instead of copying the
  first. That was 6-8% slower, so we kept the copy.

Locally: 2.6% / 2.1% / 0.7% less CPU on demo1/2/3 (demo3 is within noise).
`testing/test_finishupdate.sh` checks 125 full frames against a simple
reference conversion, including palette and gamma changes and the fallback
modes.

### 6. R_DrawColumn: keep pointers local, unroll by 4 (`doom/r_draw.c`)

`R_DrawColumn` draws one vertical strip of wall, about 1,500 times per frame.
The inner loop was:

```c
*dest = dc_colormap[dc_source[(frac >> FRACBITS) & 127]];
```

`dc_colormap` and `dc_source` are globals. Because `*dest` is a byte write,
the compiler can't prove the write doesn't change those globals, so it
reloaded both from memory for every pixel. Copying them into local variables
before the loop removes those reloads.

Then the loop draws 4 pixels per iteration, with a small loop for the 0-3
left over. That means fewer loop-counter checks and branches per pixel. Each
pixel still uses the same `& 127` texture wrap as the original.

Locally: 1.7-4.0% less CPU per demo. Micro-benchmark: ~1.8x faster on its own.
`testing/test_drawcolumn.sh` checks 6,000 columns pixel-for-pixel against the
original.

### 7. Screen melt: no real-time wait during timedemo (`doom/d_main.c`)

This is the biggest change.

When the game switches screens (for example title screen -> level), Doom
plays the "melt" transition. The loop in `D_Display` was:

```c
do {
    nowtime = I_GetTime();          // real clock, in 1/35 s units
    tics = nowtime - wipestart;
    I_Sleep(1);                     // sleep 1 ms
} while (tics <= 0);                // until 1/35 s has really passed
wipe_ScreenWipe(..., tics);         // advance melt, draw frame
```

So the melt runs at human speed: about 41 steps x 1/35 s = 1.1-1.2 s per
demo. `-timedemo` removes this kind of wait for gameplay, but nobody removed
it here. A demo1 run was 0.87 s of real work plus about 1.13 s of sleeping,
in about 1,060 one-millisecond sleeps. CPU profilers didn't show it, since
they only see time when the program is running.

Now, when `timingdemo` is set, each loop pass just sets `tics = 1`: advance
the melt one step, draw it, repeat. No waiting. Every melt frame is still
drawn, and normal (non-timedemo) play is unchanged. `g_game.h` gained an
`extern` for the existing `timingdemo` flag.

Is it safe for validation? `platform.c` only checks the last frame of each
game tic, and the whole melt happens inside one tic. We still checked: with
the same starting image, all 41 melt frames are identical to the unmodified
engine on all three demos.

Locally, one copy, 5 runs each, medians, all 30 runs valid:

| Demo | Before | After | Change |
|---|---:|---:|---:|
| demo1 | 1.96 s | 0.83 s | -57.7% |
| demo2 | 1.93 s | 0.79 s | -59.1% |
| demo3 | 2.01 s | 0.87 s | -56.7% |

CPU time is unchanged (~0.8 s): we removed waiting, not work. On the full
node with 128 copies the gain will be smaller (copies compete for memory and
cache), so it needs a score run on frnt201.

### 8. R_RenderSegLoop: copy loop-invariant flags to locals (`doom/r_segs.c`)

`R_RenderSegLoop` walks across a wall one screen column at a time and checks
flags like `markfloor`, `markceiling`, `midtexture`, `toptexture` on every
column. They're globals set once before the loop and never changed inside it,
but the loop calls `colfunc()` and `R_GetColumn()`, and the compiler has to
assume those might change them. So it re-read every flag every column. Same
fix as change 6: copy them into `const` locals before the loop.

frnt201: demo1 150 -> 158, demo2 156 -> 157, demo3 148 -> 146 (demo2 and
demo3 are within noise).

### 9. R_DrawSpan: same as R_DrawColumn (`doom/r_draw.c`)

`R_DrawSpan` draws horizontal strips of floor and ceiling. Same two fixes as
change 6: copy `ds_source` and `ds_colormap` to locals, and draw 4 pixels per
iteration. The texture coordinate maths for each pixel is unchanged.

frnt201: demo1 158 -> 162, demo2 157 -> 163. Micro-benchmark ~1.25x.
`testing/test_drawspan.sh` checks 6,000 spans against the original.

### 10. `-nogui` in `scripts/run.sh`

A finished `-timedemo` run ends through `I_Error` (that's how this engine
prints its fps line). In `I_Error`, if stdout isn't a terminal, which it
isn't in `run.sh` since output goes to a log file, the engine tries to show
an error popup: it runs `system("zenity --help")`, which starts a shell,
before exiting. That happens at the end of every demo. `-nogui` skips the
popup.

Also note: because of this, a successful demo exits with status 255, not 0.
Our scripts treat 255 as normal.

## Where the time goes now

Local gprof, demo1, all changes except the melt fix (which doesn't change CPU
time):

| Function | Share of CPU |
|---|---:|
| I_FinishUpdate | 35% |
| R_DrawColumn | 13% |
| R_DrawSpan | 8% |
| R_RenderSegLoop | 7% |
| DG_DrawFrame (organizers', can't change) | 5% |
| R_DrawSprite | 3% |

I_FinishUpdate is still the biggest, because it has to write 1 MB per frame
whatever we do. Startup (WAD loading etc.) is only ~9 ms per demo, so running
several demos per process wouldn't gain much.

## Ideas not done yet

Rough order of expected payoff:

1. R_DrawColumn: walls call it through the `colfunc` function pointer, so it
   can never be inlined. Call it directly from `R_RenderSegLoop`. Also remove
   the leftover-pixel loop, which is where most of its mispredicted branches
   are.
2. I_FinishUpdate: skip rows that haven't changed since the last frame (the
   status bar is 16% of the screen and rarely changes). Output is still the
   full correct frame, but it reuses the previous frame, so check with the
   organizers first (rule 3).
3. Full node: 128 copies x 1 MB output buffer is more than the L3 cache. Try
   64 copies (one per physical core) against 128, and huge pages for the
   buffer.

Things that won't help: streaming (cache-bypassing) stores in I_FinishUpdate
(`DG_DrawFrame` reads the buffer straight after), AVX gather instructions
(slow on the Xeon 6430), PGO (no gain locally).

## Testing and profiling

```bash
bash testing/test_drawcolumn.sh       # 6,000 columns vs original (--bench for timing)
bash testing/test_drawspan.sh         # 6,000 spans vs original
bash testing/test_finishupdate.sh     # 125 full frames vs reference conversion

bash scripts/run-perf.sh demo1        # perf if allowed, otherwise gprof over 20 runs
bash scripts/run-callgrind.sh demo1   # instruction counts + cache simulation (slow, needs valgrind)
```

Both profiling scripts build into a fresh `results/` folder so they don't
touch the normal build, and they check that the demo is still valid. On
Frontenac, only run them inside a job.
