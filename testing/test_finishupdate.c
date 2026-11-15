/* Include the real implementation to exercise its private mode/palette state. */
#include "../doom/i_video.c"
#include <stdio.h>
#include <time.h>

pixel_t *DG_ScreenBuffer;
static volatile unsigned frames;

void DG_DrawFrame(void) { ++frames; }
void I_Error(char *message, ...)
{
    fprintf(stderr, "Unexpected video error: %s\n", message);
    exit(1);
}

static uint32_t seed = 0x81ab379u;
static byte random_byte(void)
{
    seed = seed * 1664525u + 1013904223u;
    return seed >> 24;
}

static void expected_frame(byte *out, const byte *palette)
{
    int bytes = s_Fb.bits_per_pixel / 8;
    int left = (s_Fb.xres - SCREENWIDTH * fb_scaling) / 2;
    for (int y = 0; y < SCREENHEIGHT; ++y)
        for (int x = 0; x < SCREENWIDTH; ++x)
        {
            int index = I_VideoBuffer[y * SCREENWIDTH + x];
            uint32_t r = gammatable[usegamma][palette[index * 3]];
            uint32_t g = gammatable[usegamma][palette[index * 3 + 1]];
            uint32_t b = gammatable[usegamma][palette[index * 3 + 2]];
            uint32_t pixel;
            if (bytes == 4)
            {
                pixel = (r << s_Fb.red.offset) | (g << s_Fb.green.offset)
                    | (b << s_Fb.blue.offset);
#ifdef SYS_BIG_ENDIAN
                pixel = swapLE32(pixel);
#endif
            }
            else
            {
                uint16_t p = ((r & 0xf8) << 8) | ((g & 0xfc) << 3) | (b >> 3);
#ifdef SYS_BIG_ENDIAN
                p = swapeLE16(p);
#endif
                pixel = p;
            }
            for (int dy = 0; dy < fb_scaling; ++dy)
                for (int dx = 0; dx < fb_scaling; ++dx)
                {
                    size_t offset = ((size_t)(y * fb_scaling + dy) * s_Fb.xres
                        + left + x * fb_scaling + dx) * bytes;
                    if (bytes == 4) memcpy(out + offset, &pixel, 4);
                    else { uint16_t p = pixel; memcpy(out + offset, &p, 2); }
                }
        }
}

static void check_mode(int bpp, int scale, int padding)
{
    s_Fb.bits_per_pixel = bpp;
    fb_scaling = scale;
    s_Fb.xres = SCREENWIDTH * scale + padding;
    s_Fb.yres = SCREENHEIGHT * scale;
    s_Fb.red.offset = 16;
    s_Fb.green.offset = 8;
    s_Fb.blue.offset = 0;
    size_t bytes = (size_t)s_Fb.xres * s_Fb.yres * (bpp / 8);
    byte *allocation = malloc(bytes + 64), *expected = malloc(bytes + 64);
    if (!allocation || !expected) exit(1);
    DG_ScreenBuffer = (pixel_t *)(allocation + 32);
    for (int trial = 0; trial < 25; ++trial)
    {
        byte palette[768];
        for (int i = 0; i < 768; ++i) palette[i] = random_byte();
        for (int i = 0; i < SCREENWIDTH * SCREENHEIGHT; ++i)
            I_VideoBuffer[i] = trial == 0 ? i % 256 : random_byte();
        usegamma = trial % 5;
        I_SetPalette(palette);
        memset(allocation, 0xa5, bytes + 64);
        memset(expected, 0xa5, bytes + 64);
        expected_frame(expected + 32, palette);
        unsigned before = frames;
        I_FinishUpdate();
        if (frames != before + 1 || memcmp(allocation, expected, bytes + 64))
        {
            fprintf(stderr, "Frame mismatch: bpp=%d scale=%d padding=%d trial=%d\n",
                    bpp, scale, padding, trial);
            exit(1);
        }
    }
    free(expected);
    free(allocation);
}

int main(void)
{
    I_VideoBuffer = malloc(SCREENWIDTH * SCREENHEIGHT);
    if (!I_VideoBuffer) return 1;
    check_mode(32, 2, 0);
    check_mode(32, 1, 0);
    check_mode(32, 3, 0);
    check_mode(32, 2, 8);
    check_mode(16, 2, 0);
    free(I_VideoBuffer);
    puts("PASS: 125 complete frames, palette/gamma changes, fallback modes, guards, and draw calls.");
    return 0;
}
