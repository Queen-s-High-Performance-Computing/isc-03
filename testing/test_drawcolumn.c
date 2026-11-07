/* Exact-output check and isolated benchmark for the real R_DrawColumn.
 * Build instructions and measurements: drawcolumn.md.
 */
#include "r_local.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern byte *ylookup[];
extern int columnofs[];
void R_DrawColumn_reference(void);
int centery;

void I_Error(char *message, ...)
{
    fprintf(stderr, "Unexpected renderer error: %s\n", message);
    exit(1);
}

static uint32_t seed = 0x651a43u;
static uint32_t random_value(void)
{
    seed = seed * 1664525u + 1013904223u;
    return seed;
}

static byte actual[SCREENWIDTH * SCREENHEIGHT + 64];
static byte expected[sizeof actual];
static byte source[128], palette[256];

static void reference_pixels(void)
{
    uint32_t phase = (uint32_t)dc_texturemid
        + (uint32_t)(dc_yl-centery) * (uint32_t)dc_iscale;
    for (int y = dc_yl; y <= dc_yh; ++y)
    {
        expected[32 + y * SCREENWIDTH + dc_x]
            = palette[source[(phase >> FRACBITS) & 127]];
        phase += (uint32_t)dc_iscale;
    }
}

static void test_pixels(void)
{
    for (int trial = 0; trial < 6000; ++trial)
    {
        for (int i = 0; i < 128; ++i) source[i] = random_value() >> 24;
        for (int i = 0; i < 256; ++i) palette[i] = random_value() >> 24;
        memset(actual, 0xa5, sizeof actual);
        memcpy(expected, actual, sizeof actual);
        centery = random_value() % SCREENHEIGHT;
        dc_x = random_value() % SCREENWIDTH;
        dc_yl = random_value() % SCREENHEIGHT;
        int pixels = trial < SCREENHEIGHT + 1 ? trial
            : random_value() % (SCREENHEIGHT - dc_yl + 1);
        if (pixels > SCREENHEIGHT - dc_yl) dc_yl = 0;
        dc_yh = dc_yl + pixels - 1;
        /* Exercise signed phases and steps without signed-overflow UB. */
        dc_texturemid = (int)(random_value() % 200000001) - 100000000;
        dc_iscale = (int)(random_value() % 2000001) - 1000000;
        reference_pixels();
        R_DrawColumn();
        if (memcmp(actual, expected, sizeof actual))
        {
            fprintf(stderr, "Column mismatch at trial %d (%d pixels)\n", trial, pixels);
            exit(1);
        }
    }
    puts("PASS: 6000 columns match, including empty/full columns and buffer guards.");
}

static double benchmark(void (*draw)(void))
{
    struct timespec before, after;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &before);
    for (int i = 0; i < 2000000; ++i)
    {
        /* Mix short and long columns without timing a random generator. */
        dc_x = i % SCREENWIDTH;
        dc_yl = 0;
        dc_yh = (i * 37u) % SCREENHEIGHT;
        dc_texturemid = i * 127u;
        dc_iscale = 60000 + (i & 65535);
        draw();
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &after);
    return (after.tv_sec-before.tv_sec)
        + (after.tv_nsec-before.tv_nsec)/1e9;
}

int main(int argc, char **argv)
{
    dc_source = source;
    dc_colormap = palette;
    for (int y = 0; y < SCREENHEIGHT; ++y)
        ylookup[y] = actual + 32 + y * SCREENWIDTH;
    for (int x = 0; x < SCREENWIDTH; ++x) columnofs[x] = x;
    test_pixels();
    if (argc > 1 && !strcmp(argv[1], "--bench"))
    {
        for (int round = 0; round < 7; ++round)
        {
            double baseline, candidate;
            if (round & 1)
            {
                candidate = benchmark(R_DrawColumn);
                baseline = benchmark(R_DrawColumn_reference);
            }
            else
            {
                baseline = benchmark(R_DrawColumn_reference);
                candidate = benchmark(R_DrawColumn);
            }
            printf("round=%d baseline=%.6f candidate=%.6f speedup=%.4f\n",
                   round+1, baseline, candidate, baseline/candidate);
            fflush(stdout);
        }
    }
    return 0;
}
