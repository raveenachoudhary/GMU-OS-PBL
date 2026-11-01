/*
 * GMUINFO displays live runtime data through the GMU OS C service wrappers.
 */
#include "gmuos.h"

static const char hex_digits[] = "0123456789ABCDEF";
static char date_buffer[16];
static char time_buffer[16];
static char hex_buffer[3];

static void print_u16(gmu_u16 value)
{
    char digits[5];
    gmu_u8 count = 0;
    char digit_buffer[2];

    if (value == 0) {
        gmu_print("0");
        return;
    }

    while (value != 0) {
        digits[count++] = (char)('0' + value % 10);
        value /= 10;
    }

    while (count != 0) {
        digit_buffer[0] = digits[--count];
        digit_buffer[1] = '\0';
        gmu_print(digit_buffer);
    }
}

static void print_hex8(gmu_u8 value)
{
    hex_buffer[0] = hex_digits[(value >> 4) & 0x0F];
    hex_buffer[1] = hex_digits[value & 0x0F];
    hex_buffer[2] = '\0';
    gmu_print(hex_buffer);
}

static void print_field(const char *label, const char *value)
{
    gmu_print(label);
    gmu_print(value);
    gmu_newline();
}

__attribute__((used, noinline))
void gmu_main(void)
{
    gmu_u16 memory_kb;
    gmu_u8 video_mode;
    gmu_u8 api_version;

    gmu_clear();
    gmu_print("========================================");
    gmu_newline();
    gmu_print(" GMU OS - RUNTIME INFORMATION");
    gmu_newline();
    gmu_print(" Live values from OS services / BIOS");
    gmu_newline();
    gmu_newline();
    gmu_print("========================================");
    gmu_newline();
    gmu_newline();

    api_version = gmu_get_api_version();
    gmu_print("OS API version     : ");
    print_u16(api_version);
    gmu_newline();
    memory_kb = gmu_get_memory_size();
    gmu_print("Conventional memory: ");
    print_u16(memory_kb);
    gmu_print(" KB (BIOS INT 12h)");
    gmu_newline();

    video_mode = gmu_get_video_mode();
    gmu_print("BIOS video mode    : 0x");
    print_hex8(video_mode);
    gmu_print(" (BIOS INT 10h)");
    gmu_newline();

    gmu_get_date_string(date_buffer);
    print_field("Date (OS API)      : ", date_buffer);
    gmu_get_time_string(time_buffer);
    print_field("Time (OS API)      : ", time_buffer);

    gmu_print("App load address   : 0x8000 (CLI loader)");
    gmu_newline();
    gmu_newline();
    gmu_print("API vectors: version 0x57, date 0x5D, time 0x54");
    gmu_newline();
    gmu_print("Press any key to return to the CLI.");
    gmu_newline();
    (void)gmu_wait_key();
}

GMU_C_ENTRY(gmu_main)
