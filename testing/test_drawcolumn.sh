#!/usr/bin/env bash
# Run exact-output checks; pass --bench for an isolated original/candidate A/B.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
CC=${CC:-gcc}
"$CC" -O3 -ggdb3 -D_DEFAULT_SOURCE -I "$ROOT/doom" \
    -ffunction-sections -fdata-sections -c "$ROOT/doom/r_draw.c" -o "$OUT/actual.o"
"$CC" -O3 -ggdb3 -D_DEFAULT_SOURCE -I "$ROOT/doom" \
    -ffunction-sections -fdata-sections -c "$ROOT/testing/drawcolumn_reference.c" \
    -o "$OUT/reference.o"
"$CC" -O3 -ggdb3 -D_DEFAULT_SOURCE -I "$ROOT/doom" -Wl,--gc-sections \
    "$ROOT/testing/test_drawcolumn.c" "$OUT/actual.o" "$OUT/reference.o" \
    -o "$OUT/test"
"$OUT/test" "$@"
