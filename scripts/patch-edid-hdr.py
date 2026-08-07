#!/usr/bin/env python3
"""Patch the CTA-861 HDR Static Metadata block in an EDID to advertise PQ.

Some sinks (notably Samsung TVs) ship an EDID whose HDR Static Metadata Data
Block only lists "Traditional gamma - SDR luminance range" (EOTF = 0x01), so
compositors that gate HDR signalling on the EDID (niri HDR fork, KWin, ...)
refuse to enable HDR even though the panel supports it. This script rewrites
the EOTF byte to also advertise SMPTE ST 2084 (PQ) and fills in sane luminance
fields, then fixes the extension-block checksum.

Usage:
    patch-edid-hdr.py <in.bin> <out.bin>

Verify with: edid-decode <out.bin>
"""

import sys

HDR_EXT_TAG = 0x06  # extended tag for HDR Static Metadata Data Block
EOTF_SDR = 0x01
EOTF_PQ = 0x04
EOTF_TARGET = EOTF_SDR | EOTF_PQ  # SDR + PQ (HDR10)


def walk_blocks(ext):
    """Walk a CTA-861 data block collection; return list of (kind, tag, off, payload)."""
    dbc_len = ext[2]
    pos = 3
    end = min(3 + dbc_len, 128)
    blocks = []
    while pos < end:
        tag = ext[pos]
        typ = tag >> 5
        length = tag & 0x1F
        if length == 0 or pos + 1 + length > end:
            # Malformed block; stop walking and let the caller fall back to scanning.
            break
        if typ == 7:  # 0xE0-0xFF: Use Extended Tag
            blocks.append(("ext", ext[pos + 1], pos, ext[pos + 2 : pos + 1 + length]))
            pos += 1 + length
        elif typ == 5:  # 0xA0-0xBF: Extended
            blocks.append(("ext", ext[pos + 1], pos, ext[pos + 2 : pos + 1 + length]))
            pos += 1 + length
        else:
            blocks.append(("std", tag, pos, ext[pos + 1 : pos + 1 + length]))
            pos += 1 + length
    return blocks


def find_hdr_block(ext, blocks):
    """Locate the HDR Static Metadata block within a CTA extension.

    Returns the byte offset (relative to the extension start) of the EOTF byte,
    or None. Falls back to scanning the raw bytes for the known signatures:
      - extended form: 0xE3 0x06 (Use Extended Tag, len 3, ext tag HDR)
      - legacy form:   0x87 (HDR static metadata block, len 7)
    """
    for kind, tag, off, payload in blocks:
        if kind == "ext" and tag == HDR_EXT_TAG and len(payload) >= 7:
            return off + 2  # skip block header + ext tag
        if kind == "std" and tag == 0x87 and len(payload) >= 7:
            return off + 1  # skip block header
    # Raw scan fallback.
    for i in range(3, 128 - 8):
        if ext[i] == 0xE3 and ext[i + 1] == 0x06:
            return i + 2
        if ext[i] == 0x87:
            return i + 1
    return None


def fix_checksum(block):
    block[127] = (-sum(block[:127])) & 0xFF


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1

    data = bytearray(open(sys.argv[1], "rb").read())
    if len(data) % 128 != 0:
        print("error: EDID length is not a multiple of 128 bytes", file=sys.stderr)
        return 1

    n_ext = data[126]
    patched = False
    for i in range(1, n_ext + 1):
        base = i * 128
        ext = data[base : base + 128]
        if ext[0] != 0x02:  # only CTA-861 extension blocks
            continue
        blocks = walk_blocks(ext)
        print(
            f"block {i} (CTA): dbc_len={ext[2]}, parsed {len(blocks)} blocks: "
            + ", ".join(
                f"{'ext/' + hex(t) if k == 'ext' else hex(t)}@+{o + 3:02x}"
                for k, t, o, _ in blocks
            )
        )
        eotf_off = find_hdr_block(ext, blocks)
        if eotf_off is None:
            print(f"  block {i}: no HDR static metadata block found", file=sys.stderr)
            continue
        print(f"  block {i}: HDR block EOTF byte at ext+0x{eotf_off:02x} "
              f"(EDID 0x{base + eotf_off:02x})")
        eotf = data[base + eotf_off]
        print(f"  EOTF before: 0x{eotf:02x}")
        data[base + eotf_off] = EOTF_TARGET
        # Desired content max luminance (2 bytes, cd/m^2)
        data[base + eotf_off + 1 : base + eotf_off + 3] = (1000).to_bytes(2, "big")
        # Desired content max frame-average luminance (2 bytes, cd/m^2)
        data[base + eotf_off + 3 : base + eotf_off + 5] = (400).to_bytes(2, "big")
        # Desired content min luminance (2 bytes, 0.0001 cd/m^2)
        data[base + eotf_off + 5 : base + eotf_off + 7] = (5).to_bytes(2, "big")
        fix_checksum(data[base : base + 128])
        patched = True
        print(f"  EOTF set to 0x{EOTF_TARGET:02x} (SDR + PQ HDR10); checksum fixed")

    if not patched:
        print("error: no HDR Static Metadata Data Block found to patch", file=sys.stderr)
        return 1

    open(sys.argv[2], "wb").write(data)
    print(f"wrote {sys.argv[2]} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
