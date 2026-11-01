# Writing a C Program for GMU OS

## 1. Start from the supplied example

Open:

`c_src/examples/gmuinfo.c`

The program contains an ordinary C function:

```c
void gmu_main(void)
{
    gmu_clear();
    gmu_print("Hello from C");
    gmu_newline();
}

GMU_C_ENTRY(gmu_main)
```

`GMU_C_ENTRY()` creates the small low-level entry bridge required by the
MikeOS-compatible loader. It saves the loader's 16-bit stack pointer, switches
to a stack suitable for GCC `-m16` code, then restores the original stack
before returning to the OS.

## 2. C wrapper-to-service map

The wrappers in `c_src/include/gmuos.h` show how C code crosses into the
16-bit OS/firmware interfaces. Kernel API vectors are offsets in the OS
segment; wrappers call them indirectly through a register. The time/date
wrappers use `AX` for the vector because `BX` simultaneously carries the
output-buffer offset. BIOS services use software interrupts instead.

| C wrapper/helper | OS service or firmware interface |
|---|---|
| `gmu_print(text)` | OS vector `0x0003`, `os_print_string`; string offset passed in `SI` |
| `gmu_clear()` | OS vector `0x0009`, `os_clear_screen` |
| `gmu_newline()` | OS vector `0x000F`, `os_print_newline` |
| `gmu_wait_key()` | OS vector `0x0012`, `os_wait_for_key` |
| `gmu_speaker_tone(divisor)` | OS vector `0x001B`, `os_speaker_tone`; divisor passed in `AX` |
| `gmu_speaker_off()` | OS vector `0x001E`, `os_speaker_off` |
| `gmu_get_api_version()` | OS vector `0x0057`, `os_get_api_version`; version returned in `AL` |
| `gmu_get_time_string(buffer)` | OS vector `0x0054`, `os_get_time_string`; destination offset passed in `BX` |
| `gmu_get_date_string(buffer)` | OS vector `0x005D`, `os_get_date_string`; destination offset passed in `BX` |
| `gmu_get_memory_size()` | BIOS interrupt `INT 12h`; conventional-memory KB returned in `AX` |
| `gmu_get_video_mode()` | BIOS interrupt `INT 10h`, function `AH=0Fh`; mode returned in `AL` |
| `gmu_bios_ticks()` | BIOS interrupt `INT 1Ah`, function `AH=00h`; ticks returned in `CX:DX` |
| `gmu_bios_hardware_flags()` | BIOS interrupt `INT 11h`; equipment-list word returned in `AX` |
| `shutdown(seconds)` | Waits using BIOS `INT 1Ah`; requests power-off using APM BIOS `INT 15h` |
| `gmu_offset(pointer)` | C helper only: converts a linked C pointer to the 16-bit segment offset expected by OS vectors |
| `GMU_C_ENTRY(main)` / `GMU_C_ENTRY_WITH_ARGS(main)` | Loader entry/return bridge; switches between the loader's 16-bit stack and the C program stack; not an OS service vector |

The `gmu_get_api_version()` result is read from the running OS rather than
reported as a compile-time constant. `GMUINFO` demonstrates OS vectors for
date, time, API version, screen output, and key input, plus BIOS queries for
memory and video mode. `SYSINFO` additionally samples BIOS ticks and equipment
flags. BIOS calls are firmware interfaces, not kernel API vectors.

## 3. GMUINFO runtime demonstration

Run `GMUINFO` from the command prompt. The application clears the screen and
displays the current OS API version, conventional memory, video mode, and
date/time strings returned by OS API vectors. Each field identifies its source;
the footer lists the date, time, and version vector offsets. Press any key to
return to the command prompt.

Example (date, time, memory, and video mode depend on the machine):

```text
========================================
 GMU OS - RUNTIME INFORMATION
 Live values from OS services / BIOS

========================================

OS API version     : 18
Conventional memory: 639 KB (BIOS INT 12h)
BIOS video mode    : 0x03 (BIOS INT 10h)
Date (OS API)      : 10/31/2026
Time (OS API)      : 02:14 PM
App load address   : 0x8000 (CLI loader)

API vectors: version 0x57, date 0x5D, time 0x54
Press any key to return to the CLI.
```

## 4. PC speaker and BIOS-tick delays

The kernel already provides PC-speaker API vectors at offsets `0x001B`
(`os_speaker_tone`) and `0x001E` (`os_speaker_off`). The C wrappers call those
vectors using the same 16-bit indirect-call convention as the print wrappers.
The tone routine programs PIT channel 2 through ports `0x43` and
`0x42`, then enables the speaker using port `0x61`; the off routine clears the
speaker enable bits in port `0x61`.

`gmu_speaker_tone()` takes a PIT divisor, not hertz: the approximate tone is
`1193182 / pit_divisor` Hz. For example, divisor `1356` gives about 880 Hz.
Call `gmu_speaker_off()` to stop it.

There is no hosted `sleep()` in these freestanding applications. The
`gmu_bios_ticks()` helper reads the BIOS 18.2 Hz clock with interrupt `0x1A`.
`c_src/examples/beep.c` waits for BIOS tick changes for its three one-second
countdown intervals and six ticks (about 330 ms) of speaker output. Its wait
helper accounts for the BIOS tick counter wrapping at midnight.

## 5. Command-line arguments and shutdown

`GMU_C_ENTRY_WITH_ARGS()` passes the command-line parameter string to the C
entry function. The `shutdown` example uses this to support:

```text
shutdown 5
```

It waits for the requested number of seconds using BIOS clock ticks and then
requests power-off through the BIOS APM interface. If APM power-off is not
available, the machine halts instead of returning to the command prompt.

## 6. SYSINFO command

At the GMU OS command prompt, enter `SYSINFO` to run the C system-information
application. The CLI loads `SYSINFO.BIN`, just as it does other C programs.
The output includes the project and base OS names, the BIOS date and time,
conventional memory, video mode, BIOS clock ticks, and BIOS equipment details.
The date and time are checked for BIOS errors and invalid BCD values; if either
cannot be read, SYSINFO prints an explicit unavailable message for that value.
The boot-drive BIOS ID is identified as unavailable because the current loader
does not expose it to the application.

Example output (hardware values and date/time depend on the machine):

```text
GMU OS SYSTEM INFO
------------------
Project: GMU OS C-Oriented Learning Edition
Operating system: GMU OS (MikeOS 4.7.0 base)
Date: <date read from BIOS>
Time: <time read from BIOS>
Boot drive BIOS ID: unavailable (not exposed by the loader)
Conventional memory: 640 KB
BIOS video mode: 0x03
BIOS ticks since midnight: <current tick count>
BIOS clock approx: <approximate seconds since midnight>
BIOS equipment flags: 0x0000
Reported floppy drives: 0
Reported serial ports: 0
Reported parallel ports: 0
Pointing device: no
Math coprocessor: no
```

Use `HELP` to see SYSINFO listed with the other CLI commands.

## 7. Compile C applications

From the project root in Linux or WSL with GCC `-m16` and GNU binutils:

```bash
./c_src/build-c-linux.sh
```

The script compiles all `c_src/examples/*.c` files, links them as flat binaries
at `0x8000`, and copies the resulting `.BIN` files into `programs/`. The beep
binary is written to `c_src/build/BEEP.BIN` and copied to `programs/BEEP.BIN`.

## 8. Rebuild the OS image

On Linux/WSL, run `sudo ./build-gmu-linux.sh` from the project root. It builds
the C binaries, assembles the kernel, and creates `disk_images/gmuos.flp`.
On Windows, the convenience build copies all `c_src/prebuilt/*.BIN` files to
the disk image. To include a newly built beep binary there, copy
`c_src/build/BEEP.BIN` to `c_src/prebuilt/BEEP.BIN` before running
`build-gmu-win.bat`.

## 9. Test the beep in QEMU

Boot `disk_images/gmuos.flp` in QEMU with a PC-speaker audio backend enabled.
For a QEMU build with SDL audio support, for example:

```bash
qemu-system-i386 -audiodev sdl,id=audio0 -machine pcspk-audiodev=audio0 -fda disk_images/gmuos.flp
```

At the GMU OS command prompt, enter `BEEP` (the CLI adds `.BIN` when needed).
Ensure host audio is enabled and unmuted. If the installed QEMU lacks the SDL
backend, use an available QEMU audio backend in its place. Verify the countdown
and audible tone in QEMU before preparing physical media.
