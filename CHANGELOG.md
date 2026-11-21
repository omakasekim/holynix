# Changelog

All notable changes to HolyNix (`holy_unix` and `holyc`) are documented in this file.

## [0.2.0] - 2026-11-20

### Added
- **RedSea 64-Bit Contiguous Cluster Filesystem Engine (`src/holyc/RedSea.HC`)**:
  - Real contiguous cluster file reader (`redsea cat <image> <filename>`) reading sector payloads directly from disk images with bounds verification.
  - Contiguous cluster allocator and writer (`redsea put <image> <vfs_src> [redsea_name]`) managing Sector 1 cluster allocation bitmaps and Sector 2 root directory entries.
  - File extractor (`redsea extract <image> <filename> <dest_vfs_path>`) transferring RedSea cluster payloads into the VFS.
  - Volume consistency verifier (`redsea fsck [--json] <image>`) validating boot signatures (`0x88AA`), OEM identifiers, cluster bitmap allocation consistency, overlap detection, bounds checks, and 64-bit FNV-1a volume checksums.
  - Structured JSON output modes for `redsea inspect --json` and `redsea ls --json`.
- **Recursive-Descent HolyC Expression Parser, Control Flow & Ring-0 x86-64 Disassembler (`src/holyc/HolyC_Repl.HC`, `src/holyc/Shell.HC`)**:
  - Full operator-precedence recursive-descent expression parser supporting parentheses, unary operators (`-`, `+`, `~`, `!`), multiplicative (`*`, `/`, `%` with division-by-zero and `INT64_MIN` overflow protection), additive (`+`, `-`), bitwise shifts (`<<`, `>>`), relational/equality (`<`, `<=`, `>`, `>=`, `==`, `!=`), bitwise (`&`, `^`, `|`), logical (`&&`, `||`), hexadecimal (`0x...`) and binary (`0b...`) literals, macro values, and CPU register symbols (`RAX`..`RIP`).
  - Control flow execution (`if`/`else`, `while`, `for`), compound assignments (`+=`, `-=`, `*=`, `/=`, `%=`, `++`, `--`), and multi-argument formatted HolyC implicit print statements.
  - CLI inline HolyC evaluation (`./bin/holy_unix --eval "<code>"` / `-e` and `holyc -e "<code>"` in `holysh`).
  - Expanded Ring-0 inline assembly (`asm { ... }`) register arithmetic (`mov`, `add`, `sub`, `xor`, `and`, `or`, `imul`, `shl`, `shr`, `inc`, `dec`, `push`, `pop`, `syscall`, `int 0x80`, `ret`).
  - Arbitrary x86-64 machine byte sequence disassembler (`disasm [--json] --hex "<hex_bytes>"`) decoding REX.W prefixes, ModR/M register and displacement modes, immediates, relative calls/jumps, stack operations, and system calls.
- **HolyC Compiler & Transpiler AST Telemetry and Syntax Verification (`tools/holyc.c`)**:
  - Added `--ast` and `--json` flags to inspect HolyC translation units, reporting included files, line counts, transpiled byte counts, discovered `class` definitions, implicit print counts, bare function call counts, and inline assembly blocks.
  - Added `--check` flag for fast syntax and C11 type checking (`-fsyntax-only`) without linking.
  - Added lexical hardening to detect and reject unterminated block comments, unclosed `asm` blocks, and unterminated string literals.
- **Structured JSON Kernel Introspection, DolDoc Analysis & Benchmark Modes**:
  - Added `--version` (`-v`) and `--bench [--json]` flags to `holy_unix`.
  - Added `--json` output mode to `ps`, `lsmod`, `vmstat`, `uname`, `linecnt`, `hcbench`, and `disasm`.
  - Added `doldoc --strip <file.DD>` (plain-text extraction) and `doldoc --json <file.DD>` (structured tag, link, tree, color, and unclosed-tag analysis).
- **Automated Verification Suites**:
  - Expanded in-kernel self-tests (`./bin/holy_unix --test`) from 45 to 55 tests.
  - Expanded Linux/POSIX and HolyNix TDD compliance test suite (`./tests/test_linux_kernel`) from 14 suites (216 assertions) to 18 suites (270 assertions).

### Changed
- Aligned compiler, kernel, ProcFS, sysctl, manual page, and shell version constants to `0.2.0` (`0.2.0-holyc`).
- Updated GitHub Actions CI workflow (`.github/workflows/ci.yml`) to execute the C11/HolyC build and 55 in-kernel + 270 TDD verification suites across Ubuntu and macOS runners with SHA-pinned actions.
