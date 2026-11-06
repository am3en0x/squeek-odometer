"""Pixel sprites for the Squeek Odometer (v3: Squeektoshi by hand, a hand-drawn wheel, the odometer as its base).

Builds every layer of the 40x40 scene and writes them to src/art/Sprites.sol as compact run data: groups of
[color index, run count, (x, y, length) * count], one byte each. The contract turns a group into one SVG
<path stroke="color" d="M x y.5 h length ..."/>. Coordinates may run off the canvas by a few pixels: they are stored
with an offset of OFF (the contract subtracts it), so the wheel can be bigger than the frame.

To look at the result, render the contract's own SVG: FOUNDRY_PROFILE=gallery forge script script/Gallery.s.sol

    python tools/sprites.py            # writes src/art/Sprites.sol
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = H = 40
OFF = 8  # stored coordinate = real + OFF, so -8..247 fits a byte

# ---------------------------------------------------------------- palette
# Slots marked (token) are recolored per token or per stage by the contract; the color here is a default.
PALETTE = [None] + [
    "#2a1a10",  # 1 outline
    "#9a6b3f",  # 2 dark fur
    "#c99762",  # 3 fur (Squeektoshi's tan)
    "#e2c08f",  # 4 light fur
    "#f4e6cc",  # 5 cream
    "#f2a0a8",  # 6 pink
    "#1a1110",  # 7 eye
    "#ffffff",  # 8 white
    "#d9737e",  # 9 nose
    "#5a6274",  # 10 rim dark (stage)
    "#9aa3b5",  # 11 rim (stage)
    "#cfd6e3",  # 12 rim light (stage)
    "#9a7413",  # 13 gold dark
    "#e0b23a",  # 14 gold
    "#ffe089",  # 15 gold light
    "#d64545",  # 16 red
    "#9e2f2f",  # 17 red dark
    "#4a74c9",  # 18 blue
    "#7d55c7",  # 19 cape
    "#5a3a96",  # 20 cape dark
    "#9fd8ff",  # 21 sweat
    "#b9925a",  # 22 bedding
    "#8c6a3c",  # 23 bedding dark
    "#e8dcc8",  # 24 dust
    "#f1f0ff",  # 25 star
    "#cfe8f5",  # 26 bottle glass
    "#e0b23a",  # 27 bottle liquid (holder tier)
    "#9a7413",  # 28 bottle cap (holder tier)
    "#e9dcb0",  # 29 pouch item (token)
    "#7fc4a4",  # 30 mint (confetti)
    "#fff3c4",  # 31 white gold (crown)
    "#b8c0cc",  # 32 spout metal
]
NAMES = ["_", "outline", "dfur", "fur", "lfur", "cream", "pink", "eye", "white", "nose", "rimd", "rim", "riml",
         "goldd", "gold", "goldl", "red", "redd", "blue", "cape", "caped", "sweat", "bed", "bedd", "dust", "star",
         "glass", "liquid", "cap", "item", "mint", "wgold", "metal"]
C = {n: i for i, n in enumerate(NAMES)}
assert len(PALETTE) == len(NAMES)

# ---------------------------------------------------------------- helpers
def rows_px(x0, y0, rows, legend):
    out = {}
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch != ".":
                out[(x0 + i, y0 + j)] = C[legend[ch]]
    return out


def paint(points, color):
    return {p: C[color] for p in points}


def merge(*layers):
    out = {}
    for l in layers:
        out.update(l)
    return out


def circle(cx, cy, r):
    """Clean 1-px circle (midpoint algorithm)."""
    pts, x, y, err = set(), r, 0, 1 - r
    while x >= y:
        for a, b in ((x, y), (y, x), (-y, x), (-x, y), (-x, -y), (-y, -x), (y, -x), (x, -y)):
            pts.add((cx + a, cy + b))
        y += 1
        if err < 0:
            err += 2 * y + 1
        else:
            x -= 1
            err += 2 * (y - x) + 1
    return pts


# ---------------------------------------------------------------- Squeektoshi
# Side view, facing right. o outline, d dark fur, f fur, l light fur, c cream, p pink, e eye, w eye light, n nose.
COAT = {"o": "outline", "d": "dfur", "f": "fur", "l": "lfur", "c": "cream", "p": "pink", "e": "eye", "w": "white",
        "n": "nose"}
SQUEEK_RUN = [
    "..........oo..oo......",
    "......oooodpooppo.....",
    "....oodffffoodpplo....",
    "...odffffffffffllloo..",
    "..odfffffffffffleewlo.",
    ".odffffffffffffleeelno",
    ".odfffffffffflllccccpo",
    "oddfffffffflllccccccoo",
    "oddfffffllllcccccccco.",
    ".odffllllllccccccccco.",
    "..oddcccccccccccccoo..",
    "...oooooooooooooooo...",
]
EARS_BACK = [  # zoomies: ears pinned back
    "......................",
    "......oooooodppoo.....",
]
LEGS = [  # two frames under the body: stretched, then gathered
    ["..odo..........opo....", ".odo............opo..."],
    ["....odo.....opo.......", ".....oo......po........"],
]
SQUEEK_NAP = [  # curled up asleep, eyes shut
    ".....oooooo.....",
    "...oodfffffoo...",
    "..odffffffflloo.",
    ".odfffffffflllo.",
    ".odffffffflleeo.",
    "oddfffffflllllpo",
    "oddffffflllcccco",
    ".oddffllcccccco.",
    "..ooddcccccooo..",
    "....oooooooo....",
]
RUN_AT = (9, 19)
NAP_AT = (12, 23)
WCX, WCY, R = 20, 17, 17


def at(origin, pts):
    ox, oy = origin
    return {(ox + x, oy + y) for (x, y) in pts}


# ---------------------------------------------------------------- the wheel
def rim():
    return merge(paint(circle(WCX, WCY, R), "rimd"), paint(circle(WCX, WCY, R - 1), "rim"))


def wheel_frame(f):
    """Spokes (a plus, then an x) and the tread rungs, shifted half a step between frames, so it spins."""
    sp = set()
    for t in range(2, R - 2):
        if f == 0:
            sp |= {(WCX + t, WCY), (WCX - t, WCY), (WCX, WCY + t), (WCX, WCY - t)}
        else:
            d = round(t * 0.7071)
            sp |= {(WCX + d, WCY + d), (WCX - d, WCY + d), (WCX + d, WCY - d), (WCX - d, WCY - d)}
    rg = set()
    for k in range(12):
        a = math.radians(k * 30 + f * 15)
        for r in (R - 2, R - 3):
            rg.add((round(WCX + r * math.cos(a)), round(WCY + r * math.sin(a))))
    return merge(paint(sp, "rimd"), paint(rg, "riml"))


def hub():
    return paint({(WCX, WCY), (WCX + 1, WCY), (WCX, WCY + 1), (WCX + 1, WCY + 1)}, "riml")


def pips():
    """Where the endless-ladder pips go: 12 points on the outer rim, clockwise from the top."""
    out = []
    for k in range(12):
        a = math.radians(-90 + k * 30)
        out.append((round(WCX + R * math.cos(a)), round(WCY + R * math.sin(a))))
    return out


# ---------------------------------------------------------------- gear, one shape per stage
def gear():
    g = {}
    g["SWEAT"] = paint(at(RUN_AT, {(9, -2), (9, -1), (11, -3), (12, -4), (7, -1)}), "sweat")  # Warm-up
    band = at(RUN_AT, {(x, 3) for x in range(12, 18)})
    g["HEADBAND_0"] = merge(paint(band, "red"), paint(at(RUN_AT, {(11, 3), (10, 2), (9, 2)}), "redd"))  # Jogger
    g["HEADBAND_1"] = merge(paint(band, "red"), paint(at(RUN_AT, {(11, 3), (10, 4), (9, 4)}), "redd"))
    g["BIB"] = merge(paint(at(RUN_AT, {(x, y) for x in range(4, 9) for y in range(4, 9)}), "white"),
                     paint(at(RUN_AT, {(6, 5), (6, 6), (6, 7), (5, 5)}), "red"))  # Racer: number 1
    g["MEDAL"] = merge(paint(at(RUN_AT, {(13, 7), (14, 8)}), "red"),
                       paint(at(RUN_AT, {(14, 9), (15, 9), (14, 10), (15, 10)}), "gold"),
                       paint(at(RUN_AT, {(14, 9)}), "goldl"))  # Marathoner
    crown = at(RUN_AT, {(x, -1) for x in range(12, 18)} | {(12, -2), (14, -2), (16, -2)})
    g["CROWN"] = merge(paint(crown, "wgold"), paint(at(RUN_AT, {(15, -1)}), "red"), paint(at(RUN_AT, {(17, -1)}), "gold"))
    cape = lambda f: {(x, y) for x in range(-7 + f, 4) for y in range(1, 9 - f) if (y - 1) >= (3 - x) * (0.7 + 0.15 * f)}
    g["CAPE_0"] = merge(paint(at(RUN_AT, cape(0)), "cape"), paint(at(RUN_AT, {(x, 8) for x in range(-1, 4)}), "caped"))
    g["CAPE_1"] = merge(paint(at(RUN_AT, cape(1)), "cape"), paint(at(RUN_AT, {(x, 7) for x in range(0, 4)}), "caped"))
    # asleep: the headband and the crown stay on, on the ball's head
    g["HEADBAND_NAP"] = paint(at(NAP_AT, {(x, 2) for x in range(9, 13)} | {(8, 2)}), "red")
    g["CROWN_NAP"] = merge(paint(at(NAP_AT, {(x, -1) for x in range(7, 12)} | {(7, -2), (9, -2), (11, -2)}), "wgold"),
                           paint(at(NAP_AT, {(9, -1)}), "red"))
    return g


def shoes(frame):
    """Runner's shoes: the feet in blue with a white toe."""
    out = {}
    row = LEGS[frame][1]
    feet = [i for i, ch in enumerate(row) if ch != "."]
    for i in feet:
        out[(RUN_AT[0] + i, RUN_AT[1] + len(SQUEEK_RUN) + 1)] = C["blue"]
    # the front-most pixel of each foot gets a white toe cap
    groups, cur = [], []
    for i in feet:
        if cur and i != cur[-1] + 1:
            groups.append(cur)
            cur = []
        cur.append(i)
    if cur:
        groups.append(cur)
    for gpx in groups:
        out[(RUN_AT[0] + gpx[-1], RUN_AT[1] + len(SQUEEK_RUN) + 1)] = C["white"]
    return out


def dust(frame):
    pts = {(6, 31), (5, 32), (7, 32), (4, 31)} if frame == 0 else {(4, 32), (3, 31), (5, 30), (2, 32)}
    return paint(pts, "dust")


def bedding():
    return merge(paint({(x, 32) for x in range(9, 32)}, "bed"),
                 paint({(x, 31) for x in range(10, 31) if x % 3}, "bed"),
                 paint({(x, 32) for x in range(9, 32) if x % 4 == 1}, "bedd"))


def zzz():
    return merge(rows_px(27, 16, ["zzzz", "...z", "..z.", ".z..", "zzzz"], {"z": "star"}),
                 rows_px(32, 11, ["zzz", "..z", ".z.", "zzz"], {"z": "star"}))


def moon():
    pts = {(x, y) for x in range(34, 39) for y in range(1, 6) if (x - 36) ** 2 + (y - 3) ** 2 <= 5}
    bite = {(x, y) for x in range(34, 40) for y in range(0, 6) if (x - 37.4) ** 2 + (y - 2.2) ** 2 <= 4}
    return paint(pts - bite, "goldl")


def stars():
    return paint({(1, 2), (37, 10), (2, 24), (38, 26), (30, 0), (8, 1), (1, 13)}, "star")


def bottle():
    """The holder's water bottle, clipped to the cage on the left: glass, liquid by tier, cap, metal spout."""
    glass = {(x, y) for x in range(1, 5) for y in range(5, 16)}
    edge = {(x, y) for (x, y) in glass if x in (1, 4) or y in (5, 15)}
    liquid = {(x, y) for x in range(2, 4) for y in range(9, 15)}
    return merge(paint(glass, "glass"), paint(edge, "outline"), paint(liquid, "liquid"),
                 paint({(x, y) for x in range(1, 5) for y in (3, 4)}, "cap"),
                 paint({(5, 16), (6, 17)}, "metal"), paint({(2, 6)}, "white"))


def pouch(pose):
    """A treat in the cheek pouch (token trait), seen at the mouth."""
    if pose == "run":
        return paint(at(RUN_AT, {(18, 7), (19, 7), (18, 8), (19, 8)}), "item")
    return paint(at(NAP_AT, {(12, 6), (13, 6), (12, 7)}), "item")


def confetti():
    return merge(paint({(12, 4), (22, 9), (31, 7)}, "red"), paint({(26, 5), (17, 2), (9, 9)}, "gold"),
                 paint({(8, 6), (28, 11), (15, 7)}, "blue"), paint({(30, 3), (14, 11), (24, 2)}, "mint"))


# 3x5 font: digits, dot, question mark
FONT = {
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    ".": [".", ".", ".", ".", "#"], "?": ["###", "..#", ".##", "...", ".#."],
}

LAYERS = {}


def build():
    LAYERS["RIM"] = rim()
    LAYERS["WHEEL_0"] = wheel_frame(0)
    LAYERS["WHEEL_1"] = wheel_frame(1)
    LAYERS["HUB"] = hub()
    LAYERS["SQUEEK_RUN"] = rows_px(*RUN_AT, SQUEEK_RUN, COAT)
    LAYERS["SQUEEK_ZOOM"] = rows_px(*RUN_AT, EARS_BACK + SQUEEK_RUN[2:], COAT)
    for f in (0, 1):
        LAYERS[f"LEGS_{f}"] = rows_px(RUN_AT[0], RUN_AT[1] + len(SQUEEK_RUN), LEGS[f], COAT)
        LAYERS[f"SHOES_{f}"] = shoes(f)
        LAYERS[f"DUST_{f}"] = dust(f)
    LAYERS["SQUEEK_NAP"] = rows_px(*NAP_AT, SQUEEK_NAP, COAT)
    LAYERS["BEDDING"] = bedding()
    LAYERS.update(gear())
    LAYERS["POUCH_RUN"] = pouch("run")
    LAYERS["POUCH_NAP"] = pouch("nap")
    LAYERS["ZZZ"] = zzz()
    LAYERS["MOON"] = moon()
    LAYERS["STARS"] = stars()
    LAYERS["BOTTLE"] = bottle()
    LAYERS["CONFETTI"] = confetti()


# ---------------------------------------------------------------- encoding
def runs(px):
    by_color = {}
    ys = sorted({y for (_, y) in px})
    for y in ys:
        xs = sorted(x for (x, yy) in px if yy == y)
        i = 0
        while i < len(xs):
            c = px[(xs[i], y)]
            start = xs[i]
            j = i
            while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1 and px[(xs[j + 1], y)] == c:
                j += 1
            by_color.setdefault(c, []).append((start, y, xs[j] - start + 1))
            i = j + 1
    return by_color


def encode(px):
    out = bytearray()
    for c, rs in sorted(runs(px).items()):
        for i in range(0, len(rs), 255):
            part = rs[i:i + 255]
            out += bytes([c, len(part)])
            for (x, y, n) in part:
                assert -OFF <= x and x + OFF < 256 and -OFF <= y and y + OFF < 256
                out += bytes([x + OFF, y + OFF, n])
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
        "/// @notice Pixel layers of the 40x40 scene: groups of [color, runs, (x, y, length) * runs], one byte each, with x",
        f"/// and y stored + OFF ({OFF}) so a layer may run off the canvas.",
        "library Sprites {",
        f"    uint256 internal constant OFF = {OFF};",
        "    /// @notice 7-character hex colors, index 0 unused. Some slots are recolored per token by OdometerArt.",
        '    bytes internal constant PALETTE = "' + "".join(c or "#000000" for c in PALETTE) + '";',
    ]
    for name, px in LAYERS.items():
        lines.append(f"    bytes internal constant {name} = hex\"{encode(px).hex()}\";")
    pip_bytes = b"".join(bytes([x + OFF, y + OFF]) for (x, y) in pips())
    lines.append(f"    /// @notice The 12 rim points for the endless-ladder pips, clockwise from the top: (x, y) + OFF.")
    lines.append(f"    bytes internal constant PIPS = hex\"{pip_bytes.hex()}\";")
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
    print(f"wrote {path}: {len(LAYERS)} layers, {total} bytes of run data; palette slots: " +
          ", ".join(f"{n}={i}" for n, i in C.items() if n in ("rimd", "rim", "riml", "liquid", "cap", "item")))


if __name__ == "__main__":
    build()
    write_solidity()
