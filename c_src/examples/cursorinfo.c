#include "gmuos.h"

static char number_text[4];

static void print_number(gmu_u8 number)
{
    gmu_u8 index = 3;

    number_text[index] = '\0';

    do {
        number_text[--index] = '0' + (number % 10);
        number /= 10;
    } while (number > 0);

    gmu_print(&number_text[index]);
}

__attribute__((used, noinline))
void gmu_main(void)
{
    gmu_u8 row, column;

    gmu_clear();

    gmu_print("GMU OS - CURSOR INFORMATION");
    gmu_newline();
    gmu_newline();

    gmu_print("Cursor position:");
    gmu_get_cursor_position(&row, &column);

    gmu_newline();
    gmu_print("Row: ");
    print_number(row);

    gmu_newline();
    gmu_print("Column: ");
    print_number(column);

    gmu_newline();
    gmu_newline();
    gmu_print("Press any key...");
    gmu_wait_key();
}

GMU_C_ENTRY(gmu_main)