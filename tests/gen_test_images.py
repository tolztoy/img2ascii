import struct
import zlib
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "img")
os.makedirs(OUT, exist_ok=True)


def chunk(tag, data):
    out = struct.pack(">I", len(data)) + tag + data
    out += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return out


def make_png(path, w, h, pixel, color=2, depth=8, interlace=0):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    raw = bytearray()

    def emit_row(coords):
        row = bytearray([0])
        for x, y in coords:
            for v in pixel(x, y):
                row.append(v & 0xFF)
        raw.extend(row)

    if interlace:
        passes = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8),
                  (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
        for x0, y0, dx, dy in passes:
            pw = max(0, (w - x0 + dx - 1) // dx) if w > x0 else 0
            ph = max(0, (h - y0 + dy - 1) // dy) if h > y0 else 0
            if pw <= 0 or ph <= 0:
                continue
            for py in range(ph):
                y = y0 + py * dy
                emit_row((x0 + px * dx, y) for px in range(pw))
    else:
        for y in range(h):
            emit_row((x, y) for x in range(w))

    if depth == 16:
        pass

    ihdr = struct.pack(">IIBBBBB", w, h, depth, color, 0, 0, interlace)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def make_png16(path, w, h, pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            for v in pixel(x, y):
                raw.extend(struct.pack(">H", v * 257))
    ihdr = struct.pack(">IIBBBBB", w, h, 16, 2, 0, 0, 0)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def make_palette_png(path, w, h, pixel):
    palette = bytearray()
    for i in range(256):
        palette.extend((i, 255 - i, (i * 7) % 256))
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.append(pixel(x, y)[0])
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"PLTE", bytes(palette))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def gradient_rgb(x, y):
    return (x * 255 // 159, y * 255 // 119, 128)


def circle_rgb(x, y):
    d = math.hypot(x - 50, y - 50)
    if d < 40:
        return (255, 255, 255)
    if d < 45:
        return (128, 128, 128)
    return (0, 0, 0)


def checker_rgb(x, y):
    return (255, 255, 255) if (x // 8 + y // 8) % 2 == 0 else (0, 0, 0)


def lowcontrast_rgb(x, y):
    v = 110 + (x + y * 3) % 36
    return (v, v, v)


def smiley_rgb(x, y):
    if math.hypot(x - 110, y - 120) < 18 or math.hypot(x - 190, y - 120) < 18:
        return (0, 0, 0)
    d = math.hypot(x - 150, y - 150)
    if 60 <= d <= 85 and y - 150 > 40:
        return (0, 0, 0)
    if d <= 120:
        return (255, 220, 0)
    return (0, 0, 0)


GLYPHS = {
    "L": ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
    "U": ["X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
    "A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
}


def make_text_pixels(text, scale):
    pixels = set()
    cx = 0
    for ch in text:
        for gy, row in enumerate(GLYPHS[ch]):
            for gx, c in enumerate(row):
                if c == "X":
                    for sy in range(scale):
                        for sx in range(scale):
                            pixels.add((cx + gx * scale + sx, gy * scale + sy))
        cx += 6 * scale
    return pixels


TEXT_PIXELS = make_text_pixels("LUA", 16)
TEXT_OX, TEXT_OY = 44, 24


def lua_rgb(x, y):
    if (x - TEXT_OX, y - TEXT_OY) in TEXT_PIXELS:
        return (255, 255, 255)
    return (0, 0, 0)


def main():
    make_png(os.path.join(OUT, "gradient.png"), 160, 120, gradient_rgb)
    make_png(os.path.join(OUT, "circle.png"), 100, 100, circle_rgb)
    make_png(os.path.join(OUT, "circle_interlaced.png"), 100, 100, circle_rgb, interlace=1)
    make_png(os.path.join(OUT, "gradient_rgba.png"), 160, 120,
             lambda x, y: (*gradient_rgb(x, y), (x * 255 // 159)), color=6)
    make_png(os.path.join(OUT, "gradient_gray.png"), 160, 120,
             lambda x, y: (x * 255 // 159,), color=0)
    make_png(os.path.join(OUT, "checker.png"), 64, 64, checker_rgb)
    make_png16(os.path.join(OUT, "gradient16.png"), 160, 120, gradient_rgb)
    make_palette_png(os.path.join(OUT, "palette.png"), 160, 120,
                     lambda x, y: ((x * 127 // 159) % 256,))
    make_png(os.path.join(OUT, "lowcontrast.png"), 64, 64, lowcontrast_rgb)
    make_png(os.path.join(OUT, "smiley.png"), 300, 300, smiley_rgb)
    make_png(os.path.join(OUT, "lua.png"), 360, 160, lua_rgb)

    ppm = os.path.join(OUT, "gradient.ppm")
    with open(ppm, "wb") as f:
        f.write(b"P6\n160 120\n255\n")
        for y in range(120):
            for x in range(160):
                f.write(bytes(gradient_rgb(x, y)))

    pgm = os.path.join(OUT, "gradient.pgm")
    with open(pgm, "wb") as f:
        f.write(b"P5\n160 120\n255\n")
        for y in range(120):
            for x in range(160):
                f.write(bytes([gradient_rgb(x, y)[0]]))

    jpg = os.path.join(OUT, "gradient.jpg")
    os.system(f"cjpeg -outfile {jpg} {ppm} 2>/dev/null")

    bmp = os.path.join(OUT, "circle.bmp")
    w = h = 100
    rowsize = (3 * w + 3) // 4 * 4
    with open(bmp, "wb") as f:
        pixels = bytearray()
        for y in range(h - 1, -1, -1):
            row = bytearray()
            for x in range(w):
                r, g, b = circle_rgb(x, y)
                row += bytes((b, g, r))
            row += b"\x00" * (rowsize - len(row))
            pixels += row
        offset = 14 + 40
        f.write(b"BM")
        f.write(struct.pack("<IHHI", offset + len(pixels), 0, 0, offset))
        f.write(struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(pixels), 2835, 2835, 0, 0))
        f.write(pixels)

    print("test images written to", OUT)


if __name__ == "__main__":
    main()
