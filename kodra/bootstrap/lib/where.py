#!/usr/bin/env python3
"""Locate a fault recorded by gdb inside an ELF file.

CI is the only place the Android binaries can run, and its job logs are not
readable from the development sandbox, so a raw gdb dump is close to useless
there: a program counter is an address, and what a maintainer needs is the
function and the instruction. This turns the mapping table gdb prints into that
answer.

Usage:
    where.py <gdb-log> <elf>

Prints the load bias, the faulting virtual address, the nearest preceding symbol
and a few instructions around it, followed by the dynamic section and a section
size summary (a trivial program with hundreds of kilobytes of .text means the
link pulled in objects nobody asked for).
"""
from __future__ import annotations

import bisect
import re
import subprocess
import sys

MAPPING = re.compile(
    r"^\s*0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x[0-9a-f]+\s+0x([0-9a-f]+)\s+(\S+)\s+(.*)$"
)


def run(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True, check=False).stdout


def fault_pc(log: str) -> int | None:
    """The instruction pointer gdb marked with '=>' or reported after the signal."""
    pc = None
    for match in re.finditer(r"^=>\s*0x([0-9a-f]+)", log, re.MULTILINE):
        pc = int(match.group(1), 16)
    if pc is not None:
        return pc
    match = re.search(r"Program received signal SIGSEGV.*?\n0x([0-9a-f]+)", log)
    return int(match.group(1), 16) if match else None


def mappings(log: str) -> list[tuple[int, int, int, str]]:
    found = []
    for line in log.splitlines():
        match = MAPPING.match(line)
        if match:
            found.append(
                (
                    int(match.group(1), 16),
                    int(match.group(2), 16),
                    int(match.group(3), 16),
                    match.group(5).strip(),
                )
            )
    return found


def first_load(elf: str) -> tuple[int, int] | None:
    """(virtual address, file offset) of the first PT_LOAD."""
    for line in run("readelf", "-lW", elf).splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[0] == "LOAD":
            try:
                return int(fields[1], 16), int(fields[2], 16)
            except ValueError:
                continue
    return None


def symbols(elf: str) -> tuple[list[int], list[str]]:
    addresses, names = [], []
    for line in run("nm", "-n", "--defined-only", elf).splitlines():
        fields = line.split()
        if len(fields) >= 3:
            try:
                addresses.append(int(fields[0], 16))
            except ValueError:
                continue
            names.append(fields[2])
    return addresses, names


def enclosing(addresses: list[int], names: list[str], target: int) -> str:
    if not addresses:
        return "<no symbols>"
    index = bisect.bisect_right(addresses, target) - 1
    if index < 0:
        return "<before the first symbol>"
    return f"{names[index]} +0x{target - addresses[index]:x}"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    log_path, elf = sys.argv[1], sys.argv[2]
    with open(log_path, "r", errors="replace") as handle:
        log = handle.read()

    pc = fault_pc(log)
    if pc is None:
        print("no fault address in the gdb log")
        return 1

    maps = mappings(log)
    load = first_load(elf)
    if load is None:
        print("could not read the ELF program headers")
        return 1
    load_vaddr, load_offset = load

    bias = None
    for start, _end, offset, path in maps:
        if offset == load_offset and path == elf:
            bias = start - load_vaddr
            break
    if bias is None:
        # gdb may print the path through the chroot; match on the file name instead.
        name = elf.rsplit("/", 1)[-1]
        for start, _end, offset, path in maps:
            if offset == load_offset and path.endswith(name):
                bias = start - load_vaddr
                break
    if bias is None:
        print(f"no mapping for {elf} in the gdb log")
        return 1

    address = pc - bias
    addresses, names = symbols(elf)
    print(f"fault pc=0x{pc:x} bias=0x{bias:x} vaddr=0x{address:x}")
    print(f"function: {enclosing(addresses, names, address)}")
    print("--- instructions ---")
    print(
        run(
            "objdump",
            "-d",
            f"--start-address={max(address - 32, 0)}",
            f"--stop-address={address + 16}",
            elf,
        ).strip()
    )
    print("--- dynamic section ---")
    print(
        "\n".join(
            line
            for line in run("readelf", "-dW", elf).splitlines()
            if "NEEDED" in line or "FLAGS" in line or "RPATH" in line or "RUNPATH" in line
        )
    )
    print("--- section sizes ---")
    print(
        "\n".join(
            line
            for line in run("readelf", "-SW", elf).splitlines()
            if any(s in line for s in (".text", ".got", ".bss", ".data", ".rodata"))
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
