#include "gmuos.h"

#define BIOS_TICKS_PER_DAY 0x1800B0UL
#define BIOS_TICKS_PER_SECOND 18u
#define BEEP_PIT_DIVISOR 1356u
#define BEEP_DURATION_TICKS 6u

static void wait_bios_ticks(gmu_u16 ticks)
{
    gmu_u32 elapsed = 0;
    gmu_u32 previous = gmu_bios_ticks();

    while (elapsed < ticks) {
        gmu_u32 current = gmu_bios_ticks();

        if (current >= previous)
            elapsed += current - previous;
        else
            elapsed += BIOS_TICKS_PER_DAY - previous + current;

        previous = current;
    }
}

__attribute__((used, noinline))
void gmu_main(void)
{
    gmu_u8 remaining;

    gmu_print("GMU OS BEEP TIMER");
    gmu_newline();
    gmu_print("Starting countdown...");
    gmu_newline();
    gmu_newline();

    for (remaining = 3; remaining > 0; --remaining) {
        if (remaining == 3)
            gmu_print("3");
        else if (remaining == 2)
            gmu_print("2");
        else
            gmu_print("1");
        gmu_newline();
        wait_bios_ticks(BIOS_TICKS_PER_SECOND);
    }

    gmu_newline();
    gmu_print("BEEP!");
    gmu_newline();
    gmu_speaker_tone(BEEP_PIT_DIVISOR);
    wait_bios_ticks(BEEP_DURATION_TICKS);
    gmu_speaker_off();
    gmu_print("Timer finished.");
    gmu_newline();
}

GMU_C_ENTRY(gmu_main)
