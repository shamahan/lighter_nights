"""Draws the 512x512 project logo into assets/logo.png.

Run:  python tools/make_logo.py
The logo is drawn at 2x size and scaled down for smooth edges.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
SCALE = 2
BIG = SIZE * SCALE
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "logo.png"

SKY_TOP = (9, 12, 44)
SKY_BOTTOM = (58, 92, 170)
MOON = (246, 240, 206, 255)
GLOW = (255, 236, 170)
STAR = (255, 252, 232, 255)

# (x, y, radius) as fractions of the image size; the two largest get a sparkle.
STARS = [
    (0.20, 0.17, 0.016), (0.82, 0.24, 0.020), (0.72, 0.10, 0.008),
    (0.12, 0.42, 0.007), (0.88, 0.52, 0.009), (0.30, 0.08, 0.006),
    (0.16, 0.70, 0.010), (0.80, 0.76, 0.007), (0.58, 0.86, 0.006),
]


def sky():
    """Night sky that gets lighter towards the bottom."""
    image = Image.new("RGBA", (BIG, BIG))
    draw = ImageDraw.Draw(image)
    for y in range(BIG):
        t = (y / (BIG - 1)) ** 1.4
        color = tuple(round(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_BOTTOM))
        draw.line([(0, y), (BIG, y)], fill=color + (255,))
    return image


def disc(draw, cx, cy, radius, color):
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color)


def glow(image, cx, cy, radius, alpha):
    """Soft halo: a blurred disc composited over the sky."""
    layer = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    disc(ImageDraw.Draw(layer), cx, cy, radius, GLOW + (alpha,))
    image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * 0.45)))


def sparkle(draw, cx, cy, length, width):
    """Four-point sparkle: two thin diamonds crossing at the centre."""
    draw.polygon([(cx - length, cy), (cx, cy - width), (cx + length, cy), (cx, cy + width)], fill=STAR)
    draw.polygon([(cx, cy - length), (cx + width, cy), (cx, cy + length), (cx - width, cy)], fill=STAR)


def crescent(image, cx, cy, radius):
    """A bright disc with an offset disc cut out of it."""
    layer = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    disc(draw, cx, cy, radius, MOON)
    disc(draw, cx + radius * 0.42, cy - radius * 0.26, radius * 0.88, (0, 0, 0, 0))
    image.alpha_composite(layer)


def main():
    image = sky()
    cx, cy, radius = BIG * 0.47, BIG * 0.50, BIG * 0.30

    glow(image, cx, cy, radius * 1.55, 120)
    glow(image, cx, cy, radius * 1.05, 110)

    draw = ImageDraw.Draw(image)
    for x, y, r in STARS:
        disc(draw, BIG * x, BIG * y, BIG * r, STAR)
    for x, y, r in STARS[:2]:
        sparkle(draw, BIG * x, BIG * y, BIG * r * 3.2, BIG * r * 0.7)

    crescent(image, cx, cy, radius)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print("wrote", OUT.relative_to(OUT.parent.parent).as_posix())


if __name__ == "__main__":
    main()
