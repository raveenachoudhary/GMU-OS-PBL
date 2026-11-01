#include "gmuos.h"

static const char hex_digits[] = "0123456789ABCDEF";
static char hex_output[3];
static char decimal_digits[10];
static char decimal_output[2];

static gmu_u8 valid_bcd(gmu_u8 value)
{
    return (gmu_u8)(((value >> 4) <= 9) && ((value & 0x0F) <= 9));
}

static gmu_u8 bcd_to_u8(gmu_u8 value)
{
    return (gmu_u8)(((value >> 4) * 10) + (value & 0x0F));
}

static void print_hex8(gmu_u8 value)
{
    hex_output[0] = hex_digits[(value >> 4) & 0x0F];
    hex_output[1] = hex_digits[value & 0x0F];
    hex_output[2] = '\0';
    gmu_print(hex_output);
}

static void print_hex16(gmu_u16 value)
{
    print_hex8((gmu_u8)(value >> 8));
    print_hex8((gmu_u8)value);
}

static void print_hex32(gmu_u32 value)
{
    print_hex16((gmu_u16)(value >> 16));
    print_hex16((gmu_u16)value);
}

static void print_u16(gmu_u16 value)
{
    gmu_u8 count = 0;

    if (value == 0) {
        gmu_print("0");
        return;
    }

    while (value != 0) {
        decimal_digits[count++] = (char)('0' + (value % 10));
        value /= 10;
    }
    while (count != 0) {
        decimal_output[0] = decimal_digits[--count];
        decimal_output[1] = '\0';
        gmu_print(decimal_output);
    }
}

static void print_two_digits(gmu_u8 value)
{
    if (value < 10)
        gmu_print("0");
    print_u16(value);
}

static gmu_u8 read_bios_time(gmu_u8 *hour, gmu_u8 *minute, gmu_u8 *second)
{
    gmu_u16 cx;
    gmu_u16 dx;
    gmu_u8 failed;
    gmu_u8 raw_hour;
    gmu_u8 raw_minute;
    gmu_u8 raw_second;

    __asm__ volatile (
        "movb $0x02, %%ah\n\t"
        "int $0x1a\n\t"
        "setc %0"
        : "=m" (failed), "=c" (cx), "=d" (dx)
        :
        : "ax", "bx", "si", "di", "cc", "memory"
    );

    raw_hour = (gmu_u8)(cx >> 8);
    raw_minute = (gmu_u8)cx;
    raw_second = (gmu_u8)(dx >> 8);
    if (failed || !valid_bcd(raw_hour) || !valid_bcd(raw_minute)
        || !valid_bcd(raw_second))
        return 0;

    *hour = bcd_to_u8(raw_hour);
    *minute = bcd_to_u8(raw_minute);
    *second = bcd_to_u8(raw_second);
    return (gmu_u8)(*hour < 24 && *minute < 60 && *second < 60);
}

static gmu_u8 read_bios_date(gmu_u8 *century, gmu_u8 *year,
                              gmu_u8 *month, gmu_u8 *day)
{
    gmu_u16 cx;
    gmu_u16 dx;
    gmu_u8 failed;
    gmu_u8 raw_century;
    gmu_u8 raw_year;
    gmu_u8 raw_month;
    gmu_u8 raw_day;

    __asm__ volatile (
        "movb $0x04, %%ah\n\t"
        "int $0x1a\n\t"
        "setc %0"
        : "=m" (failed), "=c" (cx), "=d" (dx)
        :
        : "ax", "bx", "si", "di", "cc", "memory"
    );

    raw_century = (gmu_u8)(cx >> 8);
    raw_year = (gmu_u8)cx;
    raw_month = (gmu_u8)(dx >> 8);
    raw_day = (gmu_u8)dx;
    if (failed || !valid_bcd(raw_century) || !valid_bcd(raw_year)
        || !valid_bcd(raw_month) || !valid_bcd(raw_day))
        return 0;

    *century = bcd_to_u8(raw_century);
    *year = bcd_to_u8(raw_year);
    *month = bcd_to_u8(raw_month);
    *day = bcd_to_u8(raw_day);
    return (gmu_u8)(*month >= 1 && *month <= 12
                    && *day >= 1 && *day <= 31);
}

static gmu_u32 divide_u32_u16(gmu_u32 value, gmu_u16 divisor)
{
    gmu_u32 quotient = 0;
    gmu_u16 remainder = 0;
    gmu_u8 bit;

    for (bit = 0; bit < 32; ++bit) {
        remainder = (gmu_u16)((remainder << 1) | (value >> 31));
        value <<= 1;
        quotient <<= 1;
        if (remainder >= divisor) {
            remainder -= divisor;
            quotient |= 1;
        }
    }
    return quotient;
}

static void print_u32(gmu_u32 value)
{
    gmu_u8 count = 0;

    if (value == 0) {
        gmu_print("0");
        return;
    }

    while (value != 0) {
        gmu_u32 quotient = divide_u32_u16(value, 10);
        decimal_digits[count++] = (char)('0' + (value - quotient * 10));
        value = quotient;
    }
    while (count != 0) {
        decimal_output[0] = decimal_digits[--count];
        decimal_output[1] = '\0';
        gmu_print(decimal_output);
    }
}

static gmu_u32 bios_ticks_to_seconds(gmu_u32 ticks)
{
    gmu_u32 whole_seconds = divide_u32_u16(ticks, 182);
    gmu_u32 remaining_ticks = ticks - whole_seconds * 182;
    gmu_u32 fractional_seconds =
        divide_u32_u16(remaining_ticks * 10, 182);

    return whole_seconds * 10 + fractional_seconds;
}

__attribute__((used, noinline))
void gmu_main(void)
{
    gmu_u32 clock_ticks;
    gmu_u8 hour;
    gmu_u8 minute;
    gmu_u8 second;
    gmu_u8 century;
    gmu_u8 year;
    gmu_u8 month;
    gmu_u8 day;
    gmu_u16 flags = gmu_bios_hardware_flags();
    gmu_u8 serial_ports = (gmu_u8)((flags >> 9) & 0x07);
    gmu_u8 parallel_ports = (gmu_u8)((flags >> 14) & 0x03);
    gmu_u8 floppy_count = (flags & 0x01)
        ? (gmu_u8)(((flags >> 6) & 0x03) + 1)
        : 0;

    gmu_newline();
    gmu_print("GMU OS SYSTEM INFO");
    gmu_newline();
    gmu_print("------------------");
    gmu_newline();
    gmu_print("Project: GMU OS C-Oriented Learning Edition");
    gmu_newline();
    gmu_print("Operating system: GMU OS (MikeOS 4.7.0 base)");
    gmu_newline();

    gmu_print("Date: ");
    if (read_bios_date(&century, &year, &month, &day)) {
        print_two_digits(day);
        gmu_print("/");
        print_two_digits(month);
        gmu_print("/");
        print_two_digits(century);
        print_two_digits(year);
    } else {
        gmu_print("unavailable (BIOS date could not be retrieved)");
    }
    gmu_newline();

    gmu_print("Time: ");
    if (read_bios_time(&hour, &minute, &second)) {
        print_two_digits(hour);
        gmu_print(":");
        print_two_digits(minute);
        gmu_print(":");
        print_two_digits(second);
    } else {
        gmu_print("unavailable (BIOS time could not be retrieved)");
    }
    gmu_newline();

    gmu_print("Boot drive BIOS ID: unavailable (not exposed by the loader)");
    gmu_newline();

    gmu_print("Conventional memory: ");
    print_u16(gmu_get_memory_size());
    gmu_print(" KB");
    gmu_newline();

    gmu_print("BIOS video mode: 0x");
    print_hex8(gmu_get_video_mode());
    gmu_newline();

    clock_ticks = gmu_bios_ticks();
    gmu_print("BIOS ticks since midnight: 0x");
    print_hex32(clock_ticks);
    gmu_newline();
    gmu_print("BIOS clock approx: ");
    print_u32(bios_ticks_to_seconds(clock_ticks));
    gmu_print(" seconds since midnight");
    gmu_newline();

    gmu_print("BIOS equipment flags: 0x");
    print_hex16(flags);
    gmu_newline();

    gmu_print("Reported floppy drives: ");
    print_u16(floppy_count);
    gmu_newline();

    gmu_print("Reported serial ports: ");
    print_u16(serial_ports);
    gmu_newline();

    gmu_print("Reported parallel ports: ");
    print_u16(parallel_ports);
    gmu_newline();

    gmu_print("Pointing device: ");
    gmu_print((flags & 0x0004) ? "yes" : "no");
    gmu_newline();
    gmu_print("Math coprocessor: ");
    gmu_print((flags & 0x0002) ? "yes" : "no");
    gmu_newline();
}

GMU_C_ENTRY(gmu_main)