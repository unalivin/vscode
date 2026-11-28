#!/usr/bin/env python3
"""Convert an Android sparse system image to a raw ext4 image in place.

Android system images are shipped in libsparse format: a 28-byte header, then
chunks that are either raw data, a repeated fill value, or "don't care". The
format is trivial, and doing it here avoids depending on `simg2img`, which Debian
only builds for some architectures.

Exits 0 and leaves the file untouched when it is already raw, so callers can run
this unconditionally.
"""
import os
import struct
import sys

MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4


def main(path: str) -> int:
    with open(path, "rb") as f:
        header = f.read(28)

    if len(header) < 28:
        return 0
    magic, _major, _minor, _file_hdr_size, _chunk_hdr_size, _block_size, total_blocks, _chunks, _checksum = (
        struct.unpack("<IHHHHIIII", header)
    )
    if magic != MAGIC:
        return 0  # already raw

    out_path = path + ".raw"
    with open(path, "rb") as f, open(out_path, "wb") as out:
        f.read(28)
        written = 0
        while written < total_blocks:
            chunk_header = f.read(12)
            if len(chunk_header) < 12:
                break
            chunk_type, _reserved, count, _chunk_total = struct.unpack("<HHII", chunk_header)
            if chunk_type == CHUNK_RAW:
                out.write(f.read(count * 4096))
            elif chunk_type == CHUNK_FILL:
                out.write(f.read(4) * count)
            elif chunk_type == CHUNK_DONT_CARE:
                out.seek(count * 4096, os.SEEK_CUR)
            elif chunk_type == CHUNK_CRC32:
                f.read(4)
            else:
                sys.exit(f"unknown sparse chunk type {chunk_type:#x}")
            written += count

    os.replace(out_path, path)
    print(f"converted sparse image to raw: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
