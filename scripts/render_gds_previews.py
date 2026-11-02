#!/usr/bin/env python3
"""Render faithful *top-level metal routes* from FIFO GDSII, using Python/Pillow.

The preview is based on the actual placed-and-routed GDSII polygons and paths.
It intentionally does not flatten standard-cell transistor geometry, and is
not a KLayout screenshot or a replacement for signoff inspection.
"""

from collections import defaultdict
from pathlib import Path
import struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
METALS = [11, 13, 15, 17, 19, 21, 23]
COLORS = {
    11: "#708dff",
    13: "#50aaff",
    15: "#36ecd5",
    17: "#a7ff9f",
    19: "#ffc857",
    21: "#ff93bd",
    23: "#c7abff",
}


def parse_routes(file):
    raw = file.read_bytes()
    pos, cell, element = 0, None, None
    routes = defaultdict(list)
    bounds = [float("inf"), float("inf"), float("-inf"), float("-inf")]
    while pos < len(raw):
        n = int.from_bytes(raw[pos:pos + 2], "big")
        if n < 4 or pos + n > len(raw):
            raise ValueError(f"Bad GDSII record offset {pos}")
        record = raw[pos + 2]
        value = raw[pos + 4:pos + n]
        pos += n
        if record == 5:   # BGNSTR
            cell = None
        elif record == 6:  # STRNAME
            cell = value.rstrip(b"\x00").decode("ascii")
        elif record == 7:  # ENDSTR
            cell = None
        elif cell == "fifo_sync":
            if record in (8, 9, 10, 11, 12):  # elements
                element = {"type": record, "layer": None, "xy": [], "width": 0}
            elif element is None:
                continue
            elif record == 13:  # LAYER
                element["layer"] = int.from_bytes(value, "big")
            elif record == 15:  # WIDTH
                element["width"] = struct.unpack(">i", value)[0]
            elif record == 16:  # XY
                element["xy"] = [
                    struct.unpack_from(">ii", value, i)
                    for i in range(0, len(value), 8)
                ]
            elif record == 17:  # ENDEL
                if element["type"] in (8, 9) and element["layer"] in METALS:
                    xy = element["xy"]
                    if xy:
                        routes[element["layer"]].append(element)
                        for x, y in xy:
                            bounds[0] = min(bounds[0], x)
                            bounds[1] = min(bounds[1], y)
                            bounds[2] = max(bounds[2], x)
                            bounds[3] = max(bounds[3], y)
                element = None
    if not routes:
        raise ValueError("No routed top-level shapes found")
    return routes, bounds


def font(size):
    for name in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    ):
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def render(design, label):
    source = ROOT / "layout" / design / f"{design}.gds"
    target = ROOT / "docs" / "images" / f"{design}_routed.png"
    routes, bounds = parse_routes(source)
    pixels, margin, title, footer = 1300, 68, 104, 76
    region = pixels - 2 * margin
    canvas = Image.new("RGB", (pixels, title + region + footer), "#101c2b")
    draw = ImageDraw.Draw(canvas, "RGBA")
    xmin, ymin, xmax, ymax = bounds
    scale = min(region / (xmax - xmin), region / (ymax - ymin))
    px0 = margin + (region - (xmax - xmin) * scale) / 2
    py0 = title + (region - (ymax - ymin) * scale) / 2

    def point(x, y):
        return round(px0 + (x - xmin) * scale), round(py0 + (ymax - y) * scale)

    draw.text((margin, 20), label, fill="#edf8ff", font=font(28))
    draw.text(
        (margin, 65), "Real GDSII top-level metal routing  |  Nangate45",
        fill="#a4bacf", font=font(17),
    )
    draw.rectangle(
        (px0 - 5, py0 - 5, px0 + (xmax - xmin) * scale + 5,
         py0 + (ymax - ymin) * scale + 5),
        outline="#568ca7", width=2,
    )
    for layer in METALS:
        rgba = tuple(bytes.fromhex(COLORS[layer][1:])) + (187,)
        for path in routes[layer]:
            coords = [point(x, y) for x, y in path["xy"]]
            if path["type"] == 8 and len(coords) >= 3:
                draw.polygon(coords, fill=rgba)
            elif len(coords) > 1:
                width = max(1, round(abs(path["width"]) * scale))
                draw.line(coords, fill=rgba, width=width, joint="curve")
    count = sum(len(items) for items in routes.values())
    draw.text(
        (margin, title + region + 20),
        f"{count:,} top-level metal shapes | Coordinates from original routed GDSII",
        fill="#b5c9db", font=font(15),
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, optimize=True)
    print(f"Rendered {source} -> {target} ({count} shapes)")


if __name__ == "__main__":
    render("fifo_8x16", "8-bit x 16-entry FIFO | routed layout")
    render("fifo_32x32", "32-bit x 32-entry FIFO | routed layout")
