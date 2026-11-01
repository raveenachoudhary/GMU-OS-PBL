/*
 * GMU OS - small C interface for the MikeOS 4.7.0 execution environment
 *
 * GMU modifications: 2026, GM University, Davanagere.
 * Base OS: MikeOS 4.7.0 (Copyright 2006-2022 MikeOS Developers).
 * The original MikeOS license is retained in doc/LICENSE.TXT.
 *
 * Why there is a tiny amount of inline assembly here:
 * MikeOS exposes kernel services at fixed 16-bit offsets. C code can use
 * those services, but a few machine instructions are required to place
 * arguments in the exact registers expected by the original ABI.
 * Student-facing applications can otherwise remain in C.
 */
#ifndef GMUOS_H
#define GMUOS_H

typedef unsigned char  gmu_u8;
typedef unsigned short gmu_u16;
typedef unsigned int   gmu_u32;

/* MikeOS API vector offsets (API v18). */
#define GMU_OS_PRINT_STRING   0x0003u
#define GMU_OS_CLEAR_SCREEN   0x0009u
#define GMU_OS_PRINT_NEWLINE  0x000Fu
#define GMU_OS_WAIT_FOR_KEY   0x0012u
#define GMU_OS_SPEAKER_TONE   0x001Bu
#define GMU_OS_SPEAKER_OFF   0x001Eu
#define GMU_OS_GET_API_VER    0x0057u
#define GMU_OS_GET_TIME_STR   0x0054u
#define GMU_OS_GET_DATE_STR   0x005Du
#define GMU_OS_API_VERSION    18u

/* Convert a linked C pointer (programs are linked at 0x8000) to the
 * 16-bit offset used inside the common MikeOS/GMU OS segment. */
static inline gmu_u16 gmu_offset(const void *p)
{
    return (gmu_u16)((gmu_u32)p & 0xFFFFu);
}

static inline void gmu_print(const char *text)
{
    gmu_u16 off = gmu_offset(text);
    __asm__ volatile (
        "movw %0, %%si\n\t"
        "movw $0x0003, %%bx\n\t"
        "callw *%%bx"
        :
        : "rm" (off)
        : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

static inline void gmu_newline(void)
{
    __asm__ volatile (
        "movw $0x000f, %%bx\n\t"
        "callw *%%bx"
        : : : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

static inline void gmu_clear(void)
{
    __asm__ volatile (
        "movw $0x0009, %%bx\n\t"
        "callw *%%bx"
        : : : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

/* Start a PC-speaker tone. pit_divisor is the PIT channel 2 divisor,
 * not a frequency in hertz (1193182 / divisor gives the tone frequency). */
static inline void gmu_speaker_tone(gmu_u16 pit_divisor)
{
    __asm__ volatile (
        "movw %0, %%ax\n\t"
        "movw $0x001b, %%bx\n\t"
        "callw *%%bx"
        :
        : "rm" (pit_divisor)
        : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

static inline void gmu_speaker_off(void)
{
    __asm__ volatile (
        "movw $0x001e, %%bx\n\t"
        "callw *%%bx"
        : : : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

static inline gmu_u16 gmu_wait_key(void)
{
    gmu_u16 key;
    __asm__ volatile (
        "movw $0x0012, %%bx\n\t"
        "callw *%%bx"
        : "=a" (key)
        :
        : "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
    return key;
}

static inline gmu_u32 gmu_bios_ticks(void)
{
    gmu_u16 high;
    gmu_u16 low;
    __asm__ volatile (
        "xorw %%ax, %%ax\n\t"
        "int $0x1a"
        : "=c" (high), "=d" (low)
        :
        : "ax", "si", "di", "cc", "memory"
    );
    return ((gmu_u32)high << 16) | low;
}

/* Wait using the BIOS 18.2 Hz clock, request APM power-off, then halt if it
 * is unsupported or returns. BIOS ticks reset at midnight (0x1800B0/day). */
static inline void shutdown(gmu_u16 seconds)
{
    gmu_u32 required_ticks = (gmu_u32)seconds * 18u
                           + (gmu_u32)seconds / 5u;
    gmu_u32 elapsed_ticks = 0;
    gmu_u32 previous_ticks = gmu_bios_ticks();

    while (elapsed_ticks < required_ticks) {
        gmu_u32 current_ticks = gmu_bios_ticks();

        if (current_ticks >= previous_ticks)
            elapsed_ticks += current_ticks - previous_ticks;
        else
            elapsed_ticks += 0x1800B0UL - previous_ticks + current_ticks;

        previous_ticks = current_ticks;
    }

    __asm__ volatile (
        "movw $0x5300, %%ax\n\t"
        "xorw %%bx, %%bx\n\t"
        "int $0x15\n\t"
        "jc 1f\n\t"
        "cmpw $0x504d, %%bx\n\t"
        "jne 1f\n\t"
        "movw $0x5301, %%ax\n\t"
        "xorw %%bx, %%bx\n\t"
        "int $0x15\n\t"
        "jc 1f\n\t"
        "movw $0x530e, %%ax\n\t"
        "xorw %%bx, %%bx\n\t"
        "movw $0x0102, %%cx\n\t"
        "int $0x15\n\t"
        "jc 1f\n\t"
        "movw $0x5308, %%ax\n\t"
        "movw $0x0001, %%bx\n\t"
        "movw $0x0001, %%cx\n\t"
        "int $0x15\n\t"
        "jc 1f\n\t"
        "movw $0x5307, %%ax\n\t"
        "movw $0x0001, %%bx\n\t"
        "movw $0x0003, %%cx\n\t"
        "int $0x15\n\t"
        "1:\n\t"
        "cli\n\t"
        "2: hlt\n\t"
        "jmp 2b"
        :
        :
        : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

/* C program entry helper.
 * MikeOS loads .BIN programs at offset 0x8000 and invokes them with a
 * 16-bit CALL. GCC -m16 generated C functions use a 32-bit stack model.
 * Save the OS stack pointer before switching stacks, then restore it so
 * the final 16-bit RET returns to the loader's caller.
 */
#define GMU_C_ENTRY(main_function) \
    __attribute__((naked, section(".text.start"), used)) \
    void _start(void) { \
        __asm__ volatile ( \
            "movw %sp, 3f\n\t" \
            "movl $0x0000fff0, %esp\n\t" \
            "calll " #main_function "\n\t" \
            "movw 3f, %sp\n\t" \
            "retw\n\t" \
            "3: .word 0\n\t" \
        ); \
    }

/* Variant for programs that need the command-line parameters supplied in SI. */
#define GMU_C_ENTRY_WITH_ARGS(main_function) \
    __attribute__((naked, section(".text.start"), used)) \
    void _start(void) { \
        __asm__ volatile ( \
            "movw %sp, 3f\n\t" \
            "movl $0x0000fff0, %esp\n\t" \
            "movzwl %si, %eax\n\t" \
            "pushl %eax\n\t" \
            "calll " #main_function "\n\t" \
            "addl $4, %esp\n\t" \
            "movw 3f, %sp\n\t" \
            "retw\n\t" \
            "3: .word 0\n\t" \
        ); \
    }
/* API version is returned by os_get_api_version at vector 0x0057. */
static inline gmu_u8 gmu_get_api_version(void)
{
    gmu_u8 version;
    __asm__ volatile (
        "movw $0x0057, %%bx\n\t"
        "callw *%%bx"
        : "=a" (version)
        :
        : "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
    return version;
}

static inline void gmu_get_time_string(char *buffer)
{
    gmu_u16 off = gmu_offset(buffer);
    /* AX holds the vector because BX carries the output-buffer offset. */
    __asm__ volatile (
        "movw %0, %%bx\n\t"
        "movw $0x0054, %%ax\n\t"
        "callw *%%ax"
        :
        : "rm" (off)
        : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

static inline void gmu_get_date_string(char *buffer)
{
    gmu_u16 off = gmu_offset(buffer);
    __asm__ volatile (
        "movw %0, %%bx\n\t"
        "movw $0x005d, %%ax\n\t"
        "callw *%%ax"
        :
        : "rm" (off)
        : "ax", "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
}

static inline gmu_u16 gmu_get_memory_size(void)
{
    gmu_u16 memory_kb;
    __asm__ volatile (
        "int $0x12"
        : "=a" (memory_kb)
        :
        : "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
    return memory_kb;
}
static inline void gmu_get_cursor_position(gmu_u8 *row, gmu_u8 *column)
{
    gmu_u16 position;

    __asm__ volatile (
        "movw $0x0069, %%bx\n\t"
        "callw *%%bx"
        : "=d" (position)
        :
        : "ax", "bx", "cx", "si", "di", "cc", "memory"
    );

    *row = (gmu_u8)(position >> 8);
    *column = (gmu_u8)(position & 0xFF);
}

static inline gmu_u8 gmu_get_video_mode(void)
{
    gmu_u16 mode;
    __asm__ volatile (
        "xorw %%ax, %%ax\n\t"
        "movb $0x0f, %%ah\n\t"
        "int $0x10"
        : "=a" (mode)
        :
        : "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
    return (gmu_u8)mode;
}

/* BIOS INT 11h equipment-list word; see gmu_docs/C_DEVELOPMENT.md. */
static inline gmu_u16 gmu_bios_hardware_flags(void)
{
    gmu_u16 flags;
    __asm__ volatile (
        "int $0x11"
        : "=a" (flags)
        :
        : "bx", "cx", "dx", "si", "di", "cc", "memory"
    );
    return flags;
}
#endif /* GMUOS_H */
