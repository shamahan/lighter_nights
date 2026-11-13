"""Draws the four 64x64 time-of-day icons into Media/.

Run:  python tools/make_icons.py
The icons are drawn at 8x size and scaled down for smooth edges.
"""
import math
import pathlib
import random

from PIL import Image, ImageDraw

SIZE = 64
SCALE = 8
BIG = SIZE * SCALE
OUT = pathlib.Path(__file__).resolve().parent.parent / "Media"


def sky(top, bottom):
    """Vertical gradient from `top` to `bottom` (RGB tuples)."""
    image = Image.new("RGBA", (BIG, BIG))
    draw = ImageDraw.Draw(image)
    for y in range(BIG):
        t = y / (BIG - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line([(0, y), (BIG, y)], fill=color + (255,))
    return image


def disc(draw, cx, cy, radius, color):
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color)


def rays(draw, cx, cy, inner, outer, count, width, color):
    for i in range(count):
        angle = 2 * math.pi * i / count
        dx, dy = math.cos(angle), math.sin(angle)
        draw.line([(cx + inner * dx, cy + inner * dy), (cx + outer * dx, cy + outer * dy)],
                  fill=color, width=width)


def ground(draw, horizon, color):
    draw.rectangle([0, horizon, BIG, BIG], fill=color)


def save(image, name):
    OUT.mkdir(exist_ok=True)
    image.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")


def morning():
    image = sky((120, 170, 230), (255, 214, 150))
    draw = ImageDraw.Draw(image)
    horizon = int(BIG * 0.66)
    sun = (255, 236, 130, 255)
    rays(draw, BIG // 2, horizon, BIG * 0.27, BIG * 0.40, 16, SCALE * 3, sun)
    disc(draw, BIG // 2, horizon, BIG * 0.22, sun)
    ground(draw, horizon, (70, 110, 80, 255))
    save(image, "morning")


def day():
    image = sky((40, 120, 225), (140, 200, 250))
    draw = ImageDraw.Draw(image)
    sun = (255, 225, 70, 255)
    rays(draw, BIG // 2, BIG // 2, BIG * 0.27, BIG * 0.42, 12, SCALE * 4, sun)
    disc(draw, BIG // 2, BIG // 2, BIG * 0.22, sun)
    save(image, "day")


def evening():
    image = sky((60, 40, 110), (245, 120, 60))
    draw = ImageDraw.Draw(image)
    horizon = int(BIG * 0.66)
    disc(draw, BIG // 2, horizon + BIG * 0.04, BIG * 0.22, (255, 150, 60, 255))
    ground(draw, horizon, (40, 28, 60, 255))
    save(image, "evening")


def night():
    image = sky((8, 12, 40), (30, 45, 100))
    draw = ImageDraw.Draw(image)
    rng = random.Random(7)
    for _ in range(14):
        x, y = rng.randrange(BIG), rng.randrange(BIG)
        disc(draw, x, y, SCALE * rng.choice((0.6, 0.9, 1.2)), (255, 255, 235, 255))
    # Crescent: a bright disc with an offset disc cut out of it.
    moon = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    moon_draw = ImageDraw.Draw(moon)
    disc(moon_draw, BIG * 0.50, BIG * 0.50, BIG * 0.30, (240, 238, 205, 255))
    disc(moon_draw, BIG * 0.62, BIG * 0.42, BIG * 0.27, (0, 0, 0, 0))
    image.alpha_composite(moon)
    save(image, "night")


if __name__ == "__main__":
    morning()
    day()
    evening()
    night()
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))
