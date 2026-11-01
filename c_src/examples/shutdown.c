#include "gmuos.h"

static void print_usage(void)
{
    gmu_print("Usage: SHUTDOWN <seconds>");
    gmu_newline();
}

__attribute__((used, noinline))
void gmu_main(const char *args)
{
    gmu_u16 seconds = 0;
    gmu_u8 has_digit = 0;

    if (args == 0) {
        print_usage();
        return;
    }

    while (*args == ' ')
        ++args;

    while (*args >= '0' && *args <= '9') {
        gmu_u8 digit = (gmu_u8)(*args - '0');

        if (seconds > 6553u || (seconds == 6553u && digit > 5u)) {
            gmu_print("Seconds must be between 0 and 65535.");
            gmu_newline();
            return;
        }

        seconds = (gmu_u16)(seconds * 10u + digit);
        has_digit = 1;
        ++args;
    }

    while (*args == ' ')
        ++args;

    if (!has_digit || *args != 0) {
        print_usage();
        return;
    }

    gmu_print("GMU OS will shut down after the requested delay.");
    gmu_newline();
    shutdown(seconds);
}

GMU_C_ENTRY_WITH_ARGS(gmu_main)
