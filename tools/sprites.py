"""Pixel sprites for the Squeek Odometer.

Builds every layer of the 40x40 scene from simple shapes, writes them to src/art/Sprites.sol as compact run data,
and renders previews/*.png with the same layering the contract uses, for looking at the art before it ships.

Run data per layer: groups of [color index, run count, (x, y, length) * count], one byte each. The contract turns a
group into one SVG <path stroke="color" d="M x y.5 h length ..."/>, so a layer costs a few hundred bytes.

    python tools/sprites.py            # writes src/art/Sprites.sol and previews/
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = H = 40

# ---------------------------------------------------------------- palette (index 0 is unused: transparent)
PALETTE = [
    None,
    "#2b1d14",  # 1 outline
    "#e89b47",  # 2 fur
    "#fde4b8",  # 3 cream
    "#f39aa6",  # 4 pink
    "#101010",  # 5 eye
    "#ffffff",  # 6 white
    "#8b95a8",  # 7 wheel ring
    "#566074",  # 8 spokes, hub
    "#6b5440",  # 9 stand
    "#e5484d",  # 10 red (headband, bib number)
    "#3b82f6",  # 11 blue (shoes, ribbon)
    "#f5b301",  # 12 gold (medal, crown, moon)
    "#8b5cf6",  # 13 purple (cape)
    "#9fdcff",  # 14 sweat
    "#c7d2fe",  # 15 z
    "#7dff9b",  # 16 odometer digits
    "#8a93a6",  # 17 unit letters
    "#dbe4ff",  # 18 speed lines
    "#ffd84d",  # 19 crown
]
C = {name: i for i, name in enumerate(["_", "outline", "fur", "cream", "pink", "eye", "white", "ring", "spoke",
                                       "stand", "red", "blue", "gold", "purple", "sweat", "z", "digit", "unit", "speed", "crown"])}

# ---------------------------------------------------------------- shape helpers (pixel sets)
def ellipse(cx, cy, rx, ry):
    return {(x, y) for x in range(W) for y in range(H)
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0}


def ring(cx, cy, r_in, r_out):
    return {(x, y) for x in range(W) for y in range(H)
            if r_in <= math.hypot(x + 0.5 - cx, y + 0.5 - cy) < r_out}


def line(x0, y0, x1, y1):
    pts, n = set(), int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    for i in range(n + 1):
        t = i / n
        pts.add((int(round(x0 + (x1 - x0) * t - 0.5)), int(round(y0 + (y1 - y0) * t - 0.5))))
    return pts


def rect(x, y, w, h):
    return {(i, j) for i in range(x, x + w) for j in range(y, y + h)}


def from_rows(x, y, rows, colors):
    """Hand-drawn bits: rows of characters, each mapped through `colors` ('.' is empty)."""
    out = {}
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch != ".":
                out[(x + i, y + j)] = C[colors[ch]]
    return out


def paint(shape, color):
    return {p: C[color] for p in shape}


def outlined(fill, color):
    """Fill a shape and draw its inner edge in the outline color."""
    out = {}
    for (x, y) in fill:
        edge = any((x + dx, y + dy) not in fill for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        out[(x, y)] = C["outline"] if edge else C[color]
    return out


def merge(*layers):
    out = {}
    for l in layers:
        out.update(l)
    return out


# ---------------------------------------------------------------- the scene
WCX, WCY = 20, 15  # wheel centre


def wheel():
    spokes = set()
    for k in range(6):
        a = math.radians(90 + k * 60)
        spokes |= line(WCX + 1.8 * math.cos(a), WCY + 1.8 * math.sin(a), WCX + 11.6 * math.cos(a), WCY + 11.6 * math.sin(a))
    stand = line(16.5, 27.5, 13.5, 30.5) | line(23.5, 27.5, 26.5, 30.5) | rect(11, 30, 18, 1)
    return merge(paint(stand, "stand"), paint(spokes, "spoke"), paint(ring(WCX, WCY, 12.0, 13.4), "ring"),
                 paint(ellipse(WCX, WCY, 1.6, 1.6), "spoke"))


# Hand-drawn hamster, facing right. o outline, f fur, c cream, p pink, e eye, w eye glint, z closed eye.
HAM_BODY = [
    "...........oo.....",
    "....ooooo.opfo....",
    "...offfffoffffo...",
    "..offffffffffffo..",
    ".offfffffffffwefo.",
    ".offffffffffffffpo",
    "offffffffffffcccoo",
    "offfffccccccccco..",
    ".offfcccccccccco..",
    "..ooooooooooooo...",
]
HAM_NAP_FACE = {(13, 4): "z", (14, 4): "z", (15, 4): "f"}  # eye closed: a dark line over the eye
RUN_LEGS = ["..oo........oo....", ".oo..........oo..."]  # back leg pushing off, front leg reaching
COLORS = {"o": "outline", "f": "fur", "c": "cream", "p": "pink", "e": "eye", "w": "white", "z": "eye"}
RUN_AT, NAP_AT = (11, 15), (11, 17)  # top-left of the sprite in the scene


def hamster(pose):
    """The hamster on the inner bottom of the wheel. Returns (pixels, top-left of the sprite)."""
    ox, oy = RUN_AT if pose == "run" else NAP_AT
    px = from_rows(ox, oy, HAM_BODY, COLORS)
    if pose == "run":
        px.update(from_rows(ox, oy + len(HAM_BODY), RUN_LEGS, COLORS))
    else:
        for (x, y), ch in HAM_NAP_FACE.items():
            px[(ox + x, oy + y)] = C[COLORS[ch]]
    return px, (ox, oy)


def gear(pose):
    """Stage gear in sprite coordinates, so it sits on either pose. Earlier stages' gear stays on."""
    _, (ox, oy) = hamster(pose)
    at = lambda pts: {(ox + x, oy + y) for (x, y) in pts}
    g = {}
    g["sweat"] = paint(at({(6, -2), (6, -1), (3, 0)}), "sweat")  # Warm-up: a drop or two off the back
    g["headband"] = paint(at({(x, 2) for x in range(10, 15)} | {(9, 3), (8, 4)}), "red")  # Jogger
    g["shoes"] = paint(at({(2, 10), (3, 10), (1, 11), (2, 11), (12, 10), (13, 10), (13, 11), (14, 11)}), "blue") \
        if pose == "run" else {}  # Runner
    g["bib"] = merge(paint(at(set(rect(4, 4, 3, 3))), "white"), paint(at({(5, 4), (5, 5), (5, 6)}), "red"))  # Racer
    g["medal"] = merge(paint(at({(14, 7), (15, 8)}), "blue"), paint(at(set(rect(15, 9, 2, 2))), "gold"))  # Marathoner
    g["cape"] = paint(at({(x, y) for x in range(-5, 4) for y in range(1, 9) if (y - 1) >= (3 - x) * 0.8}),
                      "purple")  # Legend, behind the body
    g["crown"] = paint(at({(x, -1) for x in range(10, 15)} | {(10, -2), (12, -2), (14, -2)}), "crown")  # Legend
    return g


def zoomies():
    return paint({(x, y) for y in (18, 21, 24) for x in range(7, 11)} | {(x, 19) for x in range(5, 8)} |
                 {(x, 23) for x in range(4, 7)}, "speed")


def zzz():
    return merge(from_rows(29, 12, ["zzzz", "..z.", ".z..", "zzzz"], {"z": "z"}),
                 from_rows(34, 8, ["zzz", ".z.", "zzz"], {"z": "z"}))


def moon():
    return paint(ellipse(6, 6, 2.6, 2.6) - ellipse(7.2, 5.2, 2.2, 2.2), "gold")


# 3x5 font: digits, dot, K, M (5 wide), question mark
FONT = {
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    ".": [".", ".", ".", ".", "#"], "K": ["#.#", "##.", "#..", "##.", "#.#"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"], "?": ["###", "..#", ".##", "...", ".#."],
}

LAYERS = {}


def build():
    LAYERS["WHEEL"] = wheel()
    for pose in ("run", "nap"):
        px, _ = hamster(pose)
        LAYERS["HAMSTER_" + pose.upper()] = px
        for k, v in gear(pose).items():
            if v:
                LAYERS[(k + "_" + pose).upper()] = v
    LAYERS["ZOOMIES"] = zoomies()
    LAYERS["ZZZ"] = zzz()
    LAYERS["MOON"] = moon()


# ---------------------------------------------------------------- encoding
def runs(px):
    """{(x,y): color} -> {color: [(x, y, len)]} of horizontal runs."""
    by_color = {}
    for y in range(H):
        x = 0
        while x < W:
            c = px.get((x, y))
            if not c:
                x += 1
                continue
            start = x
            while x < W and px.get((x, y)) == c:
                x += 1
            by_color.setdefault(c, []).append((start, y, x - start))
    return by_color


def encode(px):
    out = bytearray()
    for c, rs in sorted(runs(px).items()):
        for i in range(0, len(rs), 255):
            part = rs[i:i + 255]
            out += bytes([c, len(part)])
            for (x, y, n) in part:
                out += bytes([x, y, n])
    return bytes(out)


def glyph_runs(ch):
    rows = FONT[ch]
    out = []
    for dy, row in enumerate(rows):
        dx = 0
        while dx < len(row):
            if row[dx] != "#":
                dx += 1
                continue
            s = dx
            while dx < len(row) and row[dx] == "#":
                dx += 1
            out.append((s, dy, dx - s))
    return len(rows[0]), out


def write_solidity():
    lines = [
        "// SPDX-License-Identifier: MIT",
        "// GENERATED by tools/sprites.py. Do not edit by hand: change the generator and run it again.",
        "pragma solidity 0.8.26;",
        "",
        "/// @notice Pixel layers of the 40x40 scene: groups of [color, runs, (x, y, length) * runs], one byte each.",
        "library Sprites {",
        '    /// @notice 7-character hex colors, index 0 unused.',
        '    bytes internal constant PALETTE = "' + "".join(c or "#000000" for c in PALETTE) + '";',
    ]
    for name, px in LAYERS.items():
        lines.append(f"    bytes internal constant {name} = hex\"{encode(px).hex()}\";")
    lines.append("")
    lines.append("    /// @notice A glyph of the odometer font: [width, runs, (dx, dy, length) * runs].")
    lines.append("    function glyph(bytes1 ch) internal pure returns (bytes memory) {")
    for ch in FONT:
        w, rs = glyph_runs(ch)
        data = bytes([w, len(rs)]) + b"".join(bytes(r) for r in rs)
        lines.append(f"        if (ch == \"{ch}\") return hex\"{data.hex()}\";")
    lines.append("        return hex\"\";")
    lines.append("    }")
    lines.append("}")
    path = os.path.join(ROOT, "src", "art", "Sprites.sol")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    total = sum(len(encode(px)) for px in LAYERS.values())
    print(f"wrote {path}: {len(LAYERS)} layers, {total} bytes of run data")


# ---------------------------------------------------------------- previews (same layering as OdometerArt.sol)
STAGE_BG = ["#1b2232", "#1c2a38", "#1b3530", "#273520", "#3a2c1c", "#3a1c2a", "#2a1c3a"]
STAGE_GEAR = [[], ["SWEAT"], ["SWEAT", "HEADBAND"], ["SWEAT", "HEADBAND", "SHOES"],
              ["SWEAT", "HEADBAND", "SHOES", "BIB"], ["SWEAT", "HEADBAND", "SHOES", "BIB", "MEDAL"],
              ["HEADBAND", "SHOES", "BIB", "MEDAL", "CROWN"]]


def preview(stage, status, holder, text, scale=12):
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (W * scale, H * scale), STAGE_BG[stage])
    d = ImageDraw.Draw(img)

    def put(px):
        for (x, y), c in px.items():
            d.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=PALETTE[c])

    pose = "nap" if status in (0, 3) else "run"
    if status == 0:
        put(LAYERS["MOON"])
    put(LAYERS["WHEEL"])
    if status == 2:
        put(LAYERS["ZOOMIES"])
    if stage == 6:
        put(LAYERS["CAPE_" + pose.upper()])
    put(LAYERS["HAMSTER_" + pose.upper()])
    for g in STAGE_GEAR[stage]:
        key = g + "_" + pose.upper()
        if key in LAYERS:
            put(LAYERS[key])
    if status == 0:
        put(LAYERS["ZZZ"])
    # odometer panel and text
    d.rectangle([3 * scale, 31 * scale, 37 * scale - 1, 38 * scale - 1], fill="#0b0e14")
    x = 5
    for ch in text:
        w, rs = glyph_runs(ch)
        for (dx, dy, n) in rs:
            col = PALETTE[C["unit"]] if ch in "KM" else PALETTE[C["digit"]]
            d.rectangle([(x + dx) * scale, (32 + dy) * scale, (x + dx + n) * scale - 1, (33 + dy) * scale - 1], fill=col)
        x += w + 1
    frame = "#f5b301" if holder else "#3a4150"
    width = 2 if holder else 1
    for i in range(width):
        d.rectangle([i * scale, i * scale, (W - i) * scale - 1, (H - i) * scale - 1], outline=frame, width=scale)
    return img


if __name__ == "__main__":
    build()
    write_solidity()
    if "--no-previews" not in sys.argv:
        os.makedirs(os.path.join(ROOT, "previews"), exist_ok=True)
        from PIL import Image
        tiles = []
        texts = ["0.42KM", "1.07KM", "5.31KM", "12.73KM", "27.90KM", "58.12KM", "104.66KM"]
        for stage in range(7):
            for status in (1, 2, 0):
                tiles.append(preview(stage, status, stage % 2 == 1, texts[stage], scale=6))
        sheet = Image.new("RGB", (W * 6 * 3 + 20, H * 6 * 7 + 60), "#000000")
        for i, t in enumerate(tiles):
            sheet.paste(t, ((i % 3) * (W * 6 + 10), (i // 3) * (H * 6 + 10)))
        sheet.save(os.path.join(ROOT, "previews", "sheet.png"))
        preview(6, 2, True, "104.66KM").save(os.path.join(ROOT, "previews", "legend-zoomies-holder.png"))
        preview(2, 1, False, "5.31KM").save(os.path.join(ROOT, "previews", "jogger-jogging.png"))
        print("previews in", os.path.join(ROOT, "previews"))
