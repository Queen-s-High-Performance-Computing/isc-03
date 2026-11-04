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
