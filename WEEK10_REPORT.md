# GMU OS PBL - Week 10 Report

## 1. Objective

Implement a categorized, useful `HELP` command in the GMU OS command-line
interface and evaluate `?` as a shortcut to the same help handler.

## 2. Problem statement

The existing command reference was a flat list, omitted several implemented
file commands, gave little usage guidance, and listed `SHUTDOWN` as though it
were a built-in CLI command. Users needed a more accurate guide to the
commands and file-program launching behavior supported by the current OS.

## 3. Team-defined extension: categorized HELP

`HELP` prints a categorized command reference with short descriptions and
parameter syntax. It covers file management, system information, screen and
interface commands, and launching disk programs. The reference describes the
commands present in the CLI dispatcher and does not present `SHUTDOWN` as a
built-in command.

The existing shell uppercases the command before dispatch, so both `HELP` and
`help` are accepted. The same help text is also displayed when the command
shell starts.

## 4. Add-on experiment: ? shortcut

The dispatcher checks `?` and branches to the existing `print_help` handler,
just as `HELP` does. The output is shared; there is no duplicate shortcut
implementation or second copy of the reference.

## 5. Technical implementation

Modified files:

- `source/features/cli.asm` - added `?` dispatch to `print_help`, replaced the
  old flat reference with categorized command descriptions and usage syntax.
- `WEEK10_REPORT.md` - this report.

The implementation reuses `os_string_compare` for command dispatch and
`os_print_string` for output. No disk, kernel architecture, bootloader, or
Week 9 SIZE code was changed.

## 6. Before and after

**Before:** The shell showed a flat command list. Some implemented commands
and usage formats were missing, and `SHUTDOWN` was incorrectly shown as a
built-in.

**After:** The shell and `HELP` show a categorized reference. `HELP`, `help`,
and `?` reach the same handler. File-operation parameters and the optional
`.BIN`/`.BAS` program extension are documented.

## 7. Build and QEMU testing

The repository was clean at the Week 9 commit before work began. To avoid
changing generated binaries or disk images in the project checkout, the build
and QEMU validation were run in an isolated copy of the source tree.

Build command run as root in that isolated copy:

```sh
./build-gmu-linux.sh
```

Result: **success**. The C application build, NASM bootloader/kernel/program
build, floppy image creation, and ISO creation all completed; the script
reported `>>> GMU OS image ready: disk_images/gmuos.flp`.

QEMU was launched from the isolated copy with:

```sh
qemu-system-i386 -m 16 -display none \
  -monitor tcp:127.0.0.1:45456,server,nowait \
  -drive file=disk_images/gmuos.flp,format=raw,if=floppy -no-reboot
```

Commands were entered at the QEMU guest CLI. Actual observed results:

| Guest command | Observed result |
|---|---|
| `HELP` | Displayed the categorized reference. |
| `help` | Displayed the same categorized reference. |
| `?` | Displayed the same categorized reference. |
| `ver` | Printed `GMU OS 4.7.0`. |
| `date` | Printed `11/16/2026`. |
| `count` | Printed `File operations completed: 0`. |
| `size kernel.bin` | Printed `File size: 22945 bytes` and `Approximate size: 22 KB`. |
| `notacommand` | Printed `No such command or program`. |

### QEMU screenshot placeholders

Screenshots are not embedded in this report. Capture and insert them when
preparing the final demonstration:

- `[Screenshot placeholder: QEMU showing the categorized HELP output]`
- `[Screenshot placeholder: QEMU showing ? and lowercase help output]`
- `[Screenshot placeholder: QEMU showing existing-command, SIZE, and unknown-command tests]`

## 8. Conclusion and learning outcomes

The help interface now provides discoverable commands, concise explanations,
and usage syntax while keeping both help entry points on one shared handler.
The work demonstrates command dispatch, zero-terminated assembly strings,
console output routines, and validation in a real-mode QEMU guest.

## 9. Previous-week preservation

Only the CLI source and this report were changed. Week 9 SIZE code and
disk routines were not edited. Build-generated outputs remained in the
isolated validation copy, and no backup files or Git history were changed.
The Week 9 regression check `SIZE KERNEL.BIN` succeeded in QEMU.
