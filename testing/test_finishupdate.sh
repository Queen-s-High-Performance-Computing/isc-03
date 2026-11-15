#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
CC=${CC:-gcc}
"$CC" -O3 -ggdb3 -D_DEFAULT_SOURCE -I "$ROOT/doom" \
    -ffunction-sections -fdata-sections -Wl,--gc-sections \
    "$ROOT/testing/test_finishupdate.c" "$ROOT/doom/tables.c" -o "$OUT/test"
"$OUT/test"
