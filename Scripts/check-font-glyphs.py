#!/usr/bin/env python3
"""Check Vietnamese coverage in an OpenType/TrueType Unicode cmap (stdlib only)."""
import argparse
from pathlib import Path
import struct
import unicodedata


def u16(data, offset):
    return struct.unpack_from('>H', data, offset)[0]


def u32(data, offset):
    return struct.unpack_from('>I', data, offset)[0]


def required_codepoints():
    points = {ord(c) for c in 'ăâđêôơưĂÂĐÊÔƠƯ'}
    points.update(range(0x1EA0, 0x1EFA))
    tones = '\u0300\u0301\u0303\u0309\u0323'
    points.update(map(ord, tones))
    for base in 'aăâeêioôơuưyAĂÂEÊIOÔƠUƯY':
        points.add(ord(base))
        for tone in tones:
            points.update(map(ord, unicodedata.normalize('NFC', base + tone)))
    return points


def tables(data):
    if data[:4] not in (b'OTTO', b'\x00\x01\x00\x00', b'true'):
        raise ValueError('Expected a standalone OpenType or TrueType font')
    result = {}
    for i in range(u16(data, 4)):
        pos = 12 + i * 16
        tag = data[pos:pos + 4]
        offset, length = u32(data, pos + 8), u32(data, pos + 12)
        if offset + length > len(data):
            raise ValueError('Font table extends beyond the file')
        result[tag] = data[offset:offset + length]
    return result


def font_version(name):
    for i in range(u16(name, 2)):
        pos = 6 + i * 12
        platform, _, _, name_id, length, offset = struct.unpack_from('>6H', name, pos)
        if name_id == 5:
            start = u16(name, 4) + offset
            return name[start:start + length].decode('utf-16-be' if platform in (0, 3) else 'mac_roman')
    return 'Unknown version'


def covered_codepoints(cmap, required):
    covered, seen = set(), set()
    for i in range(u16(cmap, 2)):
        pos = 4 + i * 8
        platform, encoding, offset = struct.unpack_from('>HHI', cmap, pos)
        if not (platform == 0 or platform == 3 and encoding in (1, 10)) or offset in seen:
            continue
        seen.add(offset)
        fmt = u16(cmap, offset)
        if fmt == 4:
            sub = cmap[offset:offset + u16(cmap, offset + 2)]
            count = u16(sub, 6) // 2
            ends = 14
            starts = ends + count * 2 + 2
            deltas = starts + count * 2
            offsets = deltas + count * 2
            for cp in required:
                if cp > 0xFFFF:
                    continue
                for j in range(count):
                    end, start = u16(sub, ends + j * 2), u16(sub, starts + j * 2)
                    if start <= cp <= end:
                        delta, shift = u16(sub, deltas + j * 2), u16(sub, offsets + j * 2)
                        if shift:
                            glyph = u16(sub, offsets + j * 2 + shift + (cp - start) * 2)
                            glyph = (glyph + delta) & 0xFFFF if glyph else 0
                        else:
                            glyph = (cp + delta) & 0xFFFF
                        if glyph:
                            covered.add(cp)
                        break
        elif fmt in (12, 13):
            for j in range(u32(cmap, offset + 12)):
                start, end, glyph = struct.unpack_from('>III', cmap, offset + 16 + j * 12)
                for cp in required:
                    if start <= cp <= end and (glyph + cp - start if fmt == 12 else glyph):
                        covered.add(cp)
    return covered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fonts', nargs='+', type=Path)
    args = parser.parse_args()
    required = required_codepoints()
    failed = False
    for path in args.fonts:
        try:
            font = tables(path.read_bytes())
            missing = sorted(required - covered_codepoints(font[b'cmap'], required))
            print(f'{path.name}: {font_version(font[b"name"])}; {len(required)} required code points')
            for cp in missing:
                print(f'  Missing U+{cp:04X} {unicodedata.name(chr(cp), "UNKNOWN")}')
            print(f'  {"FAIL: " + str(len(missing)) + " missing" if missing else "PASS: every Vietnamese code point is present"}')
            failed |= bool(missing)
        except (ValueError, KeyError, struct.error, OSError, UnicodeError) as error:
            print(f'{path}: invalid font: {error}')
            failed = True
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
