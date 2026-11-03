
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

void gmu_main(void)
{
    gmu_u8 row, column;

    gmu_clear();

    gmu_print("GMU OS - CURSOR CONTROL");
    gmu_newline();
    gmu_newline();

    gmu_print("Moving cursor to row 10, column 20...");

    gmu_set_cursor_position(10, 20);

    gmu_get_cursor_position(&row, &column);

    gmu_print("Cursor moved successfully!");
    gmu_newline();

    gmu_print("New row: ");
    print_number(row);

    gmu_newline();
    gmu_print("New column: ");
    print_number(column);

    gmu_newline();
    gmu_newline();
    gmu_print("Press any key...");
    gmu_wait_key();
}

GMU_C_ENTRY(gmu_main)
