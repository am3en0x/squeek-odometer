"""Pixel sprites for the Squeek Odometer.

Builds every layer of the 40x40 scene from simple shapes and writes them to src/art/Sprites.sol as compact run data.
To look at the result, render the contract's own SVG: FOUNDRY_PROFILE=gallery forge script script/Gallery.s.sol

Run data per layer: groups of [color index, run count, (x, y, length) * count], one byte each. The contract turns a
group into one SVG <path stroke="color" d="M x y.5 h length ..."/>, so a layer costs a few hundred bytes.

    python tools/sprites.py            # writes src/art/Sprites.sol
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
    "#e8ecff",  # 20 star
]
C = {name: i for i, name in enumerate(["_", "outline", "fur", "cream", "pink", "eye", "white", "ring", "spoke",
                                       "stand", "red", "blue", "gold", "purple", "sweat", "z", "digit", "unit", "speed", "crown", "star"])}

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


def spokes(offset_deg):
    out = set()
    for k in range(6):
        a = math.radians(90 + offset_deg + k * 60)
        out |= line(WCX + 1.8 * math.cos(a), WCY + 1.8 * math.sin(a), WCX + 11.6 * math.cos(a), WCY + 11.6 * math.sin(a))
    return paint(out, "spoke")


def stand():
    return paint(line(16.5, 27.5, 13.5, 30.5) | line(23.5, 27.5, 26.5, 30.5) | rect(11, 30, 18, 1), "stand")


def wheel_ring():
    return paint(ring(WCX, WCY, 12.0, 13.4), "ring")


def hub():
    return paint(ellipse(WCX, WCY, 1.6, 1.6), "spoke")


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
LEGS = [  # two running frames: legs stretched (back pushing off, front reaching), then gathered under the body
    ["..oo........oo....", ".oo..........oo..."],
    ["...oo......oo.....", "....oo....oo......"],
]
COLORS = {"o": "outline", "f": "fur", "c": "cream", "p": "pink", "e": "eye", "w": "white", "z": "eye"}
RUN_AT, NAP_AT = (11, 15), (11, 17)  # top-left of the sprite in the scene


def hamster(pose):
    """The hamster's body on the inner bottom of the wheel (legs are separate frames). Returns (pixels, top-left)."""
    ox, oy = RUN_AT if pose == "run" else NAP_AT
    px = from_rows(ox, oy, HAM_BODY, COLORS)
    if pose == "nap":
        for (x, y), ch in HAM_NAP_FACE.items():
            px[(ox + x, oy + y)] = C[COLORS[ch]]
    return px, (ox, oy)


def legs(frame):
    ox, oy = RUN_AT
    return from_rows(ox, oy + len(HAM_BODY), LEGS[frame], COLORS)


def shoes(frame):
    """Runner's shoes: the feet (the lower leg row) in blue, frame by frame."""
    ox, oy = RUN_AT
    return paint({(ox + i, oy + len(HAM_BODY) + 1) for i, ch in enumerate(LEGS[frame][1]) if ch != "."} |
                 {(ox + i, oy + len(HAM_BODY)) for i, ch in enumerate(LEGS[frame][0]) if ch != "."}, "blue")


def gear(pose):
    """Stage gear in sprite coordinates, so it sits on either pose. Earlier stages' gear stays on."""
    _, (ox, oy) = hamster(pose)
    at = lambda pts: {(ox + x, oy + y) for (x, y) in pts}
    g = {}
    g["sweat"] = paint(at({(6, -2), (6, -1), (3, 0)}), "sweat")  # Warm-up: a drop or two off the back
    g["headband"] = paint(at({(x, 2) for x in range(10, 15)} | {(9, 3), (8, 4)}), "red")  # Jogger
    g["bib"] = merge(paint(at(set(rect(4, 4, 3, 3))), "white"), paint(at({(5, 4), (5, 5), (5, 6)}), "red"))  # Racer
    g["medal"] = merge(paint(at({(14, 7), (15, 8)}), "blue"), paint(at(set(rect(15, 9, 2, 2))), "gold"))  # Marathoner
    g["cape"] = paint(at({(x, y) for x in range(-5, 4) for y in range(1, 9) if (y - 1) >= (3 - x) * 0.8}),
                      "purple")  # Legend, behind the body
    g["crown"] = paint(at({(x, -1) for x in range(10, 15)} | {(10, -2), (12, -2), (14, -2)}), "crown")  # Legend
    return g


def zoomies(frame):
    """Speed lines behind a zooming hamster, two frames that slide."""
    d = frame
    return paint({(x - d, y) for y in (18, 21, 24) for x in range(7, 11)} | {(x - d, 19) for x in range(5, 8)} |
                 {(x - d, 23) for x in range(4, 7)}, "speed")


def stars():
    return paint({(3, 21), (37, 24), (36, 3), (2, 28), (31, 1), (5, 13)}, "star")


def zzz():
    return merge(from_rows(28, 14, ["zzzz", "..z.", ".z..", "zzzz"], {"z": "z"}),
                 from_rows(33, 10, ["zzz", ".z.", "zzz"], {"z": "z"}))


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
    LAYERS["STAND"] = stand()
    LAYERS["RING"] = wheel_ring()
    for i, deg in enumerate((0, 20, 40)):
        LAYERS[f"SPOKES_{i}"] = spokes(deg)
    LAYERS["HUB"] = hub()
    for pose in ("run", "nap"):
        px, _ = hamster(pose)
        LAYERS["HAMSTER_" + pose.upper()] = px
        for k, v in gear(pose).items():
            LAYERS[(k + "_" + pose).upper()] = v
    for f in (0, 1):
        LAYERS[f"LEGS_{f}"] = legs(f)
        LAYERS[f"SHOES_{f}"] = shoes(f)
        LAYERS[f"ZOOMIES_{f}"] = zoomies(f)
    LAYERS["ZZZ"] = zzz()
    LAYERS["MOON"] = moon()
    LAYERS["STARS"] = stars()


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


if __name__ == "__main__":
    build()
    write_solidity()
