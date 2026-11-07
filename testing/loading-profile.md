# Local startup/loading measurement — 2026-11-07

This measures startup directly rather than estimating it from gprof samples.
The current engine was copied into an ignored results directory and built with
its ordinary `-O3` Makefile flags, without `-pg`. Timing probes only affect that
copy; production engine sources and the organizer validator are unchanged.

The startup interval begins at `main` and ends on entry to the first
`doomgeneric_Tick`, after `D_DoomLoop` has performed its initial `TryRunTics`
(which initializes the demo and level), graphics initialization, and view setup.
This includes engine initialization, WAD directory reads, initial level loading,
and graphics setup. It excludes process creation/the dynamic linker before
`main`, and resource reads deferred until rendering or later gameplay. It is a
startup measurement, not a sum of every resource-loading operation in the game.

Two clocks record the interval: elapsed monotonic time (including I/O waits)
and process CPU time. An exit handler records the corresponding totals after
the engine's shutdown handlers. A third probe records the end of demo playback.
The external runner also records whole-process elapsed time.

Ten fresh processes per demo were measured, alternating demos, each in its own
working directory. Every run must satisfy the official frame validation.
Filesystem caches were left intact: this is repeated-run startup, as in the
scoring loop, not a cold-disk benchmark. The host is the local QEMU VM; these
figures are not measurements of Frontenac.

## Results

All 30/30 demos passed validation. Times below are medians; percentages are
ratios of summed startup intervals to summed run totals across the ten runs.

| Demo | Startup elapsed | Total elapsed | Startup % elapsed | Startup % CPU |
|---|---:|---:|---:|---:|
| demo1 | 8.98 ms | 2.032 s | 0.45% | 1.00% |
| demo2 | 9.10 ms | 2.001 s | 0.46% | 1.05% |
| demo3 | 8.99 ms | 2.070 s | 0.47% | 1.02% |

Startup is a small fraction of these local runs. Removing all startup work
would therefore have little effect (less than roughly 0.5% on elapsed time
under these conditions). This does not rule out costs from lazy resource
loading during gameplay, or different storage behavior on another machine.

Elapsed time exceeds CPU time substantially during playback. This experiment
does not attribute that gap to specific causes; it must not be labeled disk
loading without further measurement.

Artifacts: `results/loading-profile-ea5o4zvb/`

`summary.json` has aggregate numbers, `measurements.json` has every run,
`demo*/<run>/demo.log` holds validation and timing probes, `measure.py` is the
runner, and `source/` preserves the exact measurement build. To repeat:

```bash
python3 results/loading-profile-ea5o4zvb/measure.py
```
