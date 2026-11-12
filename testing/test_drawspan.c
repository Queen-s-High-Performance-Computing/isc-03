/* Exact-output check and isolated benchmark for the real R_DrawSpan.
 */
#include "r_local.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern byte *ylookup[];
extern int columnofs[];
void R_DrawSpan_reference(void);

void I_Error(char *message, ...)
{
    fprintf(stderr, "Unexpected renderer error: %s\n", message);
    exit(1);
}

static uint32_t seed = 0x7c3a91u;
static uint32_t random_value(void)
{
    seed = seed * 1664525u + 1013904223u;
    return seed;
}

static byte actual[SCREENWIDTH * SCREENHEIGHT + 64];
static byte expected[sizeof actual];
static byte flat[4096], palette[256];

static void reference_pixels(void)
{
    /* Same expression as the real R_DrawSpan -- compiled the same way,
     * so any shift/sign quirk resolves identically here and there. */
    unsigned int position, step;
    unsigned int xtemp, ytemp;
    int spot;

    position = ((ds_xfrac << 10) & 0xffff0000)
             | ((ds_yfrac >> 6)  & 0x0000ffff);
    step = ((ds_xstep << 10) & 0xffff0000)
         | ((ds_ystep >> 6)  & 0x0000ffff);

    for (int x = ds_x1; x <= ds_x2; ++x)
    {
        ytemp = (position >> 4) & 0x0fc0;
        xtemp = (position >> 26);
        spot = xtemp | ytemp;
        expected[32 + ds_y * SCREENWIDTH + x] = palette[flat[spot]];
        position += step;
    }
}

static void test_pixels(void)
{
    for (int trial = 0; trial < 6000; ++trial)
    {
        for (int i = 0; i < 4096; ++i) flat[i] = random_value() >> 24;
        for (int i = 0; i < 256; ++i) palette[i] = random_value() >> 24;
        memset(actual, 0xa5, sizeof actual);
        memcpy(expected, actual, sizeof actual);
        ds_y = random_value() % SCREENHEIGHT;
        ds_x1 = random_value() % SCREENWIDTH;
        /* R_DrawSpan never checks for an empty span (see its own comment);
         * the caller guarantees ds_x2 >= ds_x1, so we must too. */
        int maxpixels = SCREENWIDTH - ds_x1;
        int pixels = trial < maxpixels ? trial + 1
            : 1 + (int)(random_value() % (uint32_t)maxpixels);
        ds_x2 = ds_x1 + pixels - 1;
        /* Full 32-bit random phases/steps: R_DrawSpan only shifts and
         * adds here, no multiply, so there's no overflow to dodge. */
        ds_xfrac = (fixed_t)random_value();
        ds_yfrac = (fixed_t)random_value();
        ds_xstep = (fixed_t)random_value();
        ds_ystep = (fixed_t)random_value();
        reference_pixels();
        R_DrawSpan();
        if (memcmp(actual, expected, sizeof actual))
        {
            fprintf(stderr, "Span mismatch at trial %d (%d pixels)\n", trial, pixels);
            exit(1);
        }
    }
    puts("PASS: 6000 spans match, including single-pixel/full-row spans and buffer guards.");
}

static double benchmark(void (*draw)(void))
{
    struct timespec before, after;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &before);
    for (int i = 0; i < 2000000; ++i)
    {
        /* Mix short and long spans without timing a random generator. */
        ds_y = i % SCREENHEIGHT;
        ds_x1 = 0;
        ds_x2 = (i * 37u) % SCREENWIDTH;
        ds_xfrac = i * 127u;
        ds_yfrac = i * 991u;
        ds_xstep = 60000 + (i & 65535);
        ds_ystep = 30000 + (i & 32767);
        draw();
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &after);
    return (after.tv_sec-before.tv_sec)
        + (after.tv_nsec-before.tv_nsec)/1e9;
}

int main(int argc, char **argv)
{
    ds_source = flat;
    ds_colormap = palette;
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
                candidate = benchmark(R_DrawSpan);
                baseline = benchmark(R_DrawSpan_reference);
            }
            else
            {
                baseline = benchmark(R_DrawSpan_reference);
                candidate = benchmark(R_DrawSpan);
            }
            printf("round=%d baseline=%.6f candidate=%.6f speedup=%.4f\n",
                   round+1, baseline, candidate, baseline/candidate);
            fflush(stdout);
        }
    }
    return 0;
}
