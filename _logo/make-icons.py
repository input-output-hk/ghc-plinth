#!/usr/bin/env python3
"""Cut the favicon set from the square render of plinth-icon.pov.

POV-Ray renders a square tile with hard corners; this rounds them off with an
alpha mask and resamples down to the sizes the site uses. Corner radius is 22%
of the edge, which is the iOS proportion and close to the existing flat mark.

    povray +Iplinth-icon.pov +Oplinth-icon.png +W1024 +H1024 +A0.2 +AM2 +R4 +Q11
    ./make-icons.py plinth-icon.png

Outputs, named to drop straight into the site's assets directory:
    apple-touch-icon.png         180
    favicon-32x32.png             32
    favicon-16x16.png             16
    android-chrome-192x192.png   192
    android-chrome-512x512.png   512
    favicon.ico                   16, 32, 48
    mstile-70x70.png              70   Windows tiles, square corners
    mstile-150x150.png           150
    mstile-310x310.png           310
    mstile-310x150.png           310x150, the wide tile
    <stem>-rounded.png          full size, for READMEs and slides
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

# 12/64, the corner radius of the flat master artwork the site already ships in
# assets/images/favicon-source.svg, so the 3D tile lines up with the header logo.
RADIUS_FRACTION = 12 / 64
SUPERSAMPLE = 4  # the mask is drawn large and shrunk, to antialias the corners
PNG_SIZES = {
    "apple-touch-icon.png": 180,
    "favicon-32x32.png": 32,
    "favicon-16x16.png": 16,
    "android-chrome-192x192.png": 192,
    "android-chrome-512x512.png": 512,
}
ICO_SIZES = [(16, 16), (32, 32), (48, 48)]

# Windows tiles. These keep their hard corners -- Windows draws them as squares
# on a TileColor background -- so they come off the raw render, not the rounded
# one. Only the sizes assets/browserconfig.xml actually references.
TILE_SQUARES = {
    "mstile-70x70.png": 70,
    "mstile-150x150.png": 150,
    "mstile-310x310.png": 310,
}
TILE_WIDE = ("mstile-310x150.png", 310, 150)


def rounded_mask(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=int(big * RADIUS_FRACTION), fill=255
    )
    return mask.resize((size, size), Image.LANCZOS)


def main(argv: list[str]) -> int:
    src = Path(argv[1] if len(argv) > 1 else "plinth-icon.png")
    prefix = argv[2] if len(argv) > 2 else ""

    tile = Image.open(src).convert("RGBA")
    if tile.width != tile.height:
        print(f"{src}: expected a square render, got {tile.size}", file=sys.stderr)
        return 1
    tile.putalpha(rounded_mask(tile.width))

    written = []
    full = src.with_name(f"{src.stem}-rounded.png")
    tile.save(full)
    written.append((full.name, tile.width))

    for name, size in PNG_SIZES.items():
        out = src.with_name(prefix + name)
        tile.resize((size, size), Image.LANCZOS).save(out, optimize=True)
        written.append((out.name, size))

    # Windows tiles, square and wide. The wide one is the square tile centred on
    # a canvas of the tile colour, sampled from the render's own corner so the
    # join is invisible.
    square = Image.open(src).convert("RGB")
    for name, size in TILE_SQUARES.items():
        out = src.with_name(prefix + name)
        square.resize((size, size), Image.LANCZOS).save(out, optimize=True)
        written.append((out.name, size))

    name, wide_w, wide_h = TILE_WIDE
    canvas = Image.new("RGB", (wide_w, wide_h), square.getpixel((2, 2)))
    canvas.paste(square.resize((wide_h, wide_h), Image.LANCZOS), ((wide_w - wide_h) // 2, 0))
    out = src.with_name(prefix + name)
    canvas.save(out, optimize=True)
    written.append((out.name, f"{wide_w}x{wide_h}"))

    ico = src.with_name(prefix + "favicon.ico")
    tile.save(ico, sizes=ICO_SIZES)
    written.append((ico.name, ", ".join(str(w) for w, _ in ICO_SIZES)))

    for name, size in written:
        print(f"  {name:<24} {size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
