"""Builds the environment palette (docs/ENVIRONMENT.md section 3).

Writes:
  art/palette/palette_env.json and assets/palette/palette_env.json  swatch name -> [col, row]
  assets/palette/palette_env.png        16 x 16 cells of 8 px (only if missing, or with --force)
  assets/palette/palette_env_emission.png  16 x 16 mask, white where a cell glows (always rewritten)

Rows 0-7: two rows per theme kit (frost, ember, mire, castle). Same column meaning in every kit:
  row A: ground_a ground_b path detail wall wall_dark wall_light wall_trim | shore edging spawn plaza skirt
         skirt_detail backdrop backdrop2
  row B: pillar pillar_dark wood cloth foliage water_shallow water_deep glow | x1 x2 x3 metal rope x6 x7 dark
         (x1..x7 are kit extras, named per kit below)
Rows 8-15: shared ("common.*"). Row 9 cols 0-1 (common.banner, common.banner_dark) are tinted per instance.
Run:  python art/palette/make_env_palette.py [--force]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_palette import CELL, GRID, ROOT, hex_rgb, write_png  # noqa: E402

ROW_A = ["ground_a", "ground_b", "path", "detail", "wall", "wall_dark", "wall_light", "wall_trim",
         "shore", "edging", "spawn", "plaza", "skirt", "skirt_detail", "backdrop", "backdrop2"]
ROW_B = ["pillar", "pillar_dark", "wood", "cloth", "foliage", "water_shallow", "water_deep", "glow"]

KITS = {
    "frost": {
        "a": ["#aebcc6", "#a5b3be", "#8fa3b4", "#b9c5ce", "#6f7b86", "#4f5963", "#9aa6b0", "#e6eef4",
              "#cfe3ee", "#868f98", "#9eadb8", "#97a4ae", "#c3cfd8", "#a7b6c2", "#dfe7ee", "#7d8d9b"],
        "b": ["#85919b", "#5d6872", "#5a4636", "#6a2a2a", "#2e4a3e", "#b9dbec", "#2c4f6c", "#9fe8ff"],
        "x": ["snow", "icicle", "ice", "metal", "rope", "pine_dark", "bark", "dark"],
        "xc": ["#eef3f7", "#cfeefc", "#a6dcf2", "#6a6f75", "#8a7a5a", "#1f3a30", "#3e3026", "#3f4850"],
    },
    "ember": {
        "a": ["#c4a272", "#ba9868", "#9a7a55", "#b08c5e", "#b07d55", "#855a3b", "#d0a07a", "#6b4a2e",
              "#8f7a5a", "#a68660", "#b39870", "#9d8a74", "#c7a26c", "#b18c5a", "#b8735a", "#9b5e48"],
        "b": ["#cfae7e", "#9f8058", "#6b4a2e", "#a8432e", "#6e8a3a", "#5fa7b0", "#2f6670", "#ffb347"],
        "x": ["tarp", "rug", "pottery", "metal", "rope", "fruit", "cactus", "dark"],
        "xc": ["#d8c08a", "#3d6e8a", "#b8643c", "#7a6e60", "#b09a6a", "#d0a020", "#5a7a3a", "#3a2a1e"],
    },
    "mire": {
        "a": ["#434830", "#3c4029", "#6b5639", "#4f5838", "#737a6c", "#4f5549", "#8f9788", "#4f6a3a",
              "#3e3a28", "#5b5a42", "#575a42", "#5d5f52", "#42472f", "#383d28", "#2e362c", "#3c4636"],
        "b": ["#5e4c38", "#3a2e22", "#7a6242", "#3a4a3a", "#4a6a32", "#56603e", "#2a3020", "#d8f070"],
        "x": ["lily", "reed", "mushroom", "metal", "rope", "lantern", "root", "dark"],
        "xc": ["#4f7a3a", "#8a8a4a", "#b0886a", "#4a4a44", "#7a6a4a", "#f0d070", "#3a2c1e", "#1e2218"],
    },
    "castle": {
        "a": ["#5a8341", "#537b3d", "#a39c90", "#638c47", "#a9a59a", "#7d7a71", "#c9c5ba", "#8c5a3a",
              "#bdb8ac", "#8f8a7e", "#9d978b", "#aaa598", "#5a8341", "#4f773a", "#5e7e5a", "#9a968c"],
        "b": ["#b5b1a6", "#8a867c", "#6b4a2e", "#6a3a2e", "#3f6f32", "#6fb0d0", "#2f6f9a", "#ffe9a0"],
        "x": ["flower_red", "flower_yellow", "flower_purple", "metal", "rope", "roof", "statue", "dark"],
        "xc": ["#c0404a", "#e0c040", "#8a5ac0", "#7a7c82", "#b09a6a", "#3a5a8a", "#bdbab2", "#2e3a2a"],
    },
}
KIT_ORDER = ["frost", "ember", "mire", "castle"]

COMMON = {
    8: [("stone_light", "#a8a49a"), ("stone", "#7e7a72"), ("stone_dark", "#55524c"), ("metal_light", "#b8bcc2"),
        ("metal", "#7a7c82"), ("metal_dark", "#3e4046"), ("rope", "#b09a6a"), ("glass", "#9ad0e0"),
        ("cloth_white", "#e8e4dc"), ("cloth_black", "#26242a"), ("cloth_red", "#9b2020"), ("cloth_blue", "#26449a"),
        ("wood_light", "#b08a5a"), ("wood", "#7a5530"), ("wood_dark", "#4a321c"), ("gold", "#d8b040")],
    9: [("banner", "#9a9a9a"), ("banner_dark", "#6a6a6a"), ("crystal", "#e8f0ff"), ("crystal_dark", "#a8b8d8"),
        ("ring", "#f0f0f0"), ("danger", "#e03020"), ("danger_dark", "#801810"), ("rune", "#b080ff"),
        ("altar", "#8a8478"), ("altar_dark", "#5a564e"), ("bone", "#e8dcc0"), ("black", "#141416"),
        ("trap", "#5a5c60"), ("trap_dark", "#2e3034"), ("pole", "#5a4636"), ("white", "#ffffff")],
    10: [("glow_white", "#ffffff"), ("glow_fire", "#ff9a30"), ("glow_ember", "#ff6a20"), ("glow_frost", "#9fe8ff"),
         ("glow_magic", "#b080ff"), ("glow_gold", "#ffe070"), ("glow_green", "#a0f070"), ("glow_red", "#ff4030"),
         ("fire_yellow", "#ffe070"), ("fire_orange", "#ff9a30"), ("fire_red", "#e04020"), ("ash", "#4a4a4a"),
         ("coal", "#2a2422"), ("soot", "#3a3430"), ("smoke", "#8a8a8a"), ("spark", "#fff0c0")],
}
EMISSIVE = ["common.glow_white", "common.glow_fire", "common.glow_ember", "common.glow_frost", "common.glow_magic",
            "common.glow_gold", "common.glow_green", "common.glow_red", "common.fire_yellow", "common.fire_orange",
            "common.fire_red", "common.spark", "common.crystal", "common.rune"] + \
           ["%s.glow" % k for k in KIT_ORDER] + ["mire.lantern"]


def build():
    cells, colours = {}, {}
    for i, kit in enumerate(KIT_ORDER):
        k = KITS[kit]
        names_b = ROW_B + k["x"]
        cols_b = k["b"] + k["xc"]
        for c, (n, hx) in enumerate(zip(ROW_A, k["a"])):
            cells["%s.%s" % (kit, n)] = [c, i * 2]
            colours["%s.%s" % (kit, n)] = hex_rgb(hx)
        for c, (n, hx) in enumerate(zip(names_b, cols_b)):
            cells["%s.%s" % (kit, n)] = [c, i * 2 + 1]
            colours["%s.%s" % (kit, n)] = hex_rgb(hx)
    for row, entries in COMMON.items():
        for c, (n, hx) in enumerate(entries):
            cells["common." + n] = [c, row]
            colours["common." + n] = hex_rgb(hx)
    return cells, colours


def main():
    force = "--force" in sys.argv
    cells, colours = build()
    for n in EMISSIVE:
        assert n in cells, n
    meta = {"_doc": "Environment palette: swatch name -> [col, row] in palette_env.png. Generated by "
                    "make_env_palette.py; colours live in the PNG.",
            "grid": GRID, "cell_px": CELL, "kits": KIT_ORDER, "banner_cells": ["common.banner", "common.banner_dark"],
            "emissive": EMISSIVE, "swatches": dict(sorted(cells.items(), key=lambda kv: (kv[1][1], kv[1][0])))}
    for p in (os.path.join(ROOT, "art", "palette", "palette_env.json"),
              os.path.join(ROOT, "assets", "palette", "palette_env.json")):
        with open(p, "w", newline="\n") as f:
            json.dump(meta, f, indent=1)
    png = os.path.join(ROOT, "assets", "palette", "palette_env.png")
    if force or not os.path.exists(png):
        grid = [[(255, 0, 255)] * GRID for _ in range(GRID)]
        for n, (c, r) in cells.items():
            grid[r][c] = colours[n]
        rows = []
        for y in range(GRID * CELL):
            row = []
            for x in range(GRID * CELL):
                row.extend(grid[y // CELL][x // CELL] + (255,))
            rows.append(row)
        write_png(png, GRID * CELL, GRID * CELL, rows)
        print("wrote", png)
    mask = [[0] * GRID for _ in range(GRID)]
    for n in EMISSIVE:
        c, r = cells[n]
        mask[r][c] = 255
    write_png(os.path.join(ROOT, "assets", "palette", "palette_env_emission.png"), GRID, GRID,
              [[v for x in range(GRID) for v in (mask[y][x],) * 3 + (255,)] for y in range(GRID)])
    print("env palette: %d swatches, %d emissive" % (len(cells), len(EMISSIVE)))


if __name__ == "__main__":
    main()
