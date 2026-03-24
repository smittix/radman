#!/usr/bin/env python3
from __future__ import annotations

import math
import os
import struct
import sys
import zlib


SIZE = 1024


def clamp(value: float, minimum: float = 0.0, maximum: float = 1.0) -> float:
    return max(minimum, min(maximum, value))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def rgba(r: float, g: float, b: float, a: float = 1.0) -> tuple[int, int, int, int]:
    return (
        int(clamp(r) * 255),
        int(clamp(g) * 255),
        int(clamp(b) * 255),
        int(clamp(a) * 255),
    )


class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(width * height * 4)

    def set_pixel(self, x: int, y: int, color: tuple[int, int, int, int]) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return
        index = (y * self.width + x) * 4
        sr, sg, sb, sa = color
        sa_f = sa / 255.0
        dr = self.pixels[index]
        dg = self.pixels[index + 1]
        db = self.pixels[index + 2]
        da = self.pixels[index + 3] / 255.0

        out_a = sa_f + da * (1.0 - sa_f)
        if out_a <= 0.0:
            self.pixels[index:index + 4] = b"\x00\x00\x00\x00"
            return

        out_r = (sr * sa_f + dr * da * (1.0 - sa_f)) / out_a
        out_g = (sg * sa_f + dg * da * (1.0 - sa_f)) / out_a
        out_b = (sb * sa_f + db * da * (1.0 - sa_f)) / out_a

        self.pixels[index] = int(out_r)
        self.pixels[index + 1] = int(out_g)
        self.pixels[index + 2] = int(out_b)
        self.pixels[index + 3] = int(out_a * 255)

    def fill_background(self) -> None:
        for y in range(self.height):
            vy = y / (self.height - 1)
            for x in range(self.width):
                vx = x / (self.width - 1)
                r = lerp(0.03, 0.07, vy)
                g = lerp(0.07, 0.15, vy)
                b = lerp(0.12, 0.22, vy)

                glow_left = clamp(1.0 - math.dist((x, y), (260, 220)) / 500.0)
                glow_right = clamp(1.0 - math.dist((x, y), (820, 820)) / 620.0)
                r += 0.18 * glow_left + 0.05 * glow_right
                g += 0.08 * glow_left + 0.05 * glow_right
                b += 0.02 * glow_left + 0.08 * glow_right

                stripe = 0.015 if ((x + y) // 36) % 2 == 0 else 0.0
                color = rgba(r + stripe, g + stripe, b + stripe)
                index = (y * self.width + x) * 4
                self.pixels[index:index + 4] = bytes(color)

    def fill_rounded_rect(self, left: int, top: int, right: int, bottom: int, radius: int, color: tuple[int, int, int, int]) -> None:
        for y in range(top, bottom):
            for x in range(left, right):
                dx = max(left + radius - x, 0, x - (right - radius - 1))
                dy = max(top + radius - y, 0, y - (bottom - radius - 1))
                if dx * dx + dy * dy <= radius * radius:
                    self.set_pixel(x, y, color)

    def fill_circle(self, cx: int, cy: int, radius: int, color: tuple[int, int, int, int]) -> None:
        r2 = radius * radius
        for y in range(cy - radius, cy + radius + 1):
            for x in range(cx - radius, cx + radius + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                    self.set_pixel(x, y, color)

    def fill_ring_arc(
        self,
        cx: int,
        cy: int,
        radius: int,
        thickness: int,
        angle_start: float,
        angle_end: float,
        color: tuple[int, int, int, int],
    ) -> None:
        inner = (radius - thickness) ** 2
        outer = radius ** 2
        for y in range(cy - radius, cy + radius + 1):
            for x in range(cx - radius, cx + radius + 1):
                dist2 = (x - cx) ** 2 + (y - cy) ** 2
                if not (inner <= dist2 <= outer):
                    continue
                angle = math.degrees(math.atan2(y - cy, x - cx))
                if angle < 0:
                    angle += 360
                if angle_start <= angle <= angle_end:
                    self.set_pixel(x, y, color)

    def fill_rect(self, left: int, top: int, right: int, bottom: int, color: tuple[int, int, int, int]) -> None:
        for y in range(top, bottom):
            start = (y * self.width + left) * 4
            for x in range(left, right):
                self.set_pixel(x, y, color)


def draw_seven_segment_digit(canvas: Canvas, digit: str, left: int, top: int, width: int, height: int, color: tuple[int, int, int, int]) -> None:
    thickness = max(12, width // 7)
    gap = thickness // 2
    segments = {
        "0": "abcfed",
        "1": "bc",
        "2": "abged",
        "3": "abgcd",
        "4": "fgbc",
        "5": "afgcd",
        "6": "afgcde",
        "7": "abc",
        "8": "abcdefg",
        "9": "abfgcd",
    }.get(digit, "")

    horizontal = {
        "a": (left + gap, top, left + width - gap, top + thickness),
        "g": (left + gap, top + height // 2 - thickness // 2, left + width - gap, top + height // 2 + thickness // 2),
        "d": (left + gap, top + height - thickness, left + width - gap, top + height),
    }
    vertical = {
        "f": (left, top + gap, left + thickness, top + height // 2 - gap),
        "b": (left + width - thickness, top + gap, left + width, top + height // 2 - gap),
        "e": (left, top + height // 2 + gap, left + thickness, top + height - gap),
        "c": (left + width - thickness, top + height // 2 + gap, left + width, top + height - gap),
    }

    for segment in segments:
        if segment in horizontal:
            canvas.fill_rounded_rect(*horizontal[segment], thickness // 2, color)
        elif segment in vertical:
            canvas.fill_rounded_rect(*vertical[segment], thickness // 2, color)


def write_png(path: str, width: int, height: int, pixels: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        start = y * stride
        raw.extend(pixels[start:start + stride])

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(chunk(b"IEND", b""))

    with open(path, "wb") as handle:
        handle.write(png)


def build_icon(path: str) -> None:
    canvas = Canvas(SIZE, SIZE)
    canvas.fill_background()

    canvas.fill_rounded_rect(70, 70, 954, 954, 180, rgba(0.08, 0.12, 0.18, 0.88))
    canvas.fill_rounded_rect(96, 96, 928, 928, 150, rgba(0.10, 0.15, 0.22, 0.96))

    canvas.fill_ring_arc(512, 320, 350, 18, 198, 342, rgba(0.16, 0.85, 0.92, 0.60))
    canvas.fill_ring_arc(512, 320, 290, 18, 205, 335, rgba(0.25, 0.90, 0.78, 0.68))
    canvas.fill_ring_arc(512, 320, 230, 16, 214, 326, rgba(1.00, 0.78, 0.24, 0.72))

    canvas.fill_circle(516, 145, 28, rgba(0.95, 0.68, 0.18, 0.95))
    canvas.fill_rounded_rect(498, 155, 534, 278, 18, rgba(0.98, 0.73, 0.22, 0.96))
    canvas.fill_rounded_rect(468, 182, 564, 228, 18, rgba(0.98, 0.73, 0.22, 0.96))

    canvas.fill_rounded_rect(332, 236, 692, 808, 86, rgba(0.12, 0.16, 0.20, 0.97))
    canvas.fill_rounded_rect(350, 254, 674, 790, 68, rgba(0.18, 0.22, 0.27, 0.98))

    canvas.fill_circle(404, 298, 30, rgba(0.10, 0.13, 0.16, 1.0))
    canvas.fill_circle(620, 298, 30, rgba(0.10, 0.13, 0.16, 1.0))
    canvas.fill_circle(404, 298, 16, rgba(0.40, 0.46, 0.52, 0.9))
    canvas.fill_circle(620, 298, 16, rgba(0.40, 0.46, 0.52, 0.9))

    canvas.fill_rounded_rect(388, 340, 636, 448, 28, rgba(0.16, 0.44, 0.30, 0.95))
    canvas.fill_rounded_rect(400, 352, 624, 436, 20, rgba(0.22, 0.80, 0.56, 0.88))

    digit_color = rgba(0.05, 0.24, 0.17, 0.95)
    draw_seven_segment_digit(canvas, "9", 432, 366, 48, 56, digit_color)
    draw_seven_segment_digit(canvas, "5", 488, 366, 48, 56, digit_color)
    draw_seven_segment_digit(canvas, "0", 544, 366, 48, 56, digit_color)

    for row in range(3):
        for column in range(3):
            cx = 424 + column * 88
            cy = 554 + row * 86
            canvas.fill_circle(cx, cy, 26, rgba(0.96, 0.74, 0.25, 0.94))
            canvas.fill_circle(cx, cy, 14, rgba(0.86, 0.36, 0.14, 0.92))

    canvas.fill_rounded_rect(432, 744, 592, 772, 12, rgba(0.20, 0.88, 0.90, 0.78))
    canvas.fill_rounded_rect(438, 748, 586, 768, 10, rgba(0.05, 0.18, 0.24, 0.75))
    canvas.fill_circle(604, 758, 10, rgba(0.18, 0.92, 0.52, 0.96))

    write_png(path, SIZE, SIZE, canvas.pixels)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: generate-radman-icon.py OUTPUT_PNG", file=sys.stderr)
        return 1
    output = argv[1]
    os.makedirs(os.path.dirname(output), exist_ok=True)
    build_icon(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
