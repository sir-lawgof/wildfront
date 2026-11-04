"""Builds the shared palette (ASSETS.md section 7).

Writes:
  art/palette/palette.json          swatch name -> [col, row] cell, tier material names, emissive cells
  assets/palette/palette.png        128 x 128, 16 x 16 cells of 8 x 8 px (only if missing, or with --force,
                                    so a hand-repainted PNG is never overwritten)
  assets/palette/emission_mask.png  16 x 16, white where a cell glows (always rewritten; it holds no colour)

Colours live in the PNG. The STARTING colours below are only used to create it the first time.
Run:  python art/palette/make_palette.py [--force]
"""
import json
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GRID = 16
CELL = 8


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(rgb, k):
    """k < 0 darkens toward black, k > 0 lightens toward white."""
    if k < 0:
        return tuple(max(0, round(c * (1 + k))) for c in rgb)
    return tuple(min(255, round(c + (255 - c) * k)) for c in rgb)


def to_hex(rgb):
    return "#%02x%02x%02x" % rgb


# --------------------------------------------------------------------------- starting colours
# Tier rows 0..6. Each family gets base, dark, light, trim, accent (accent glows on tiers 6-7).
METAL = [("bronze", "#A9713B", "#7a4a22", "#e0b070"), ("iron", "#5C5C61", "#3a3a3e", "#9a9aa0"),
         ("steel", "#A7ADB4", "#6e747c", "#e4e8ec"), ("cobalt", "#3B5BA8", "#d9b45a", "#9fc0ff"),
         ("orichalcum", "#3E8E5A", "#e0c060", "#a0f0b0"), ("starmetal", "#5FC7D9", "#f2fbff", "#a8f6ff"),
         ("wyrmforged", "#B3262E", "#e8b040", "#ff7a3a")]
HIDE = [("leather", "#8B5A2B", "#5c3a1c", "#c99a5a"), ("hardleather", "#5A3A1E", "#3a2412", "#a07040"),
        ("studded", "#7A6650", "#b8bcc4", "#d0c0a0"), ("drakehide", "#3F6A2E", "#9c8a50", "#90d070"),
        ("basilisk", "#7A6A9E", "#d8c890", "#c8b8f0"), ("starhide", "#2F6F8F", "#bfefff", "#8ff0ff"),
        ("wyrmhide", "#7E1E24", "#d0a040", "#ff7040")]
ROBE = [("woven", "#C8B98E", "#8a7a52", "#fff3d0"), ("apprentice", "#5A85CC", "#e6e1d3", "#a0c0ff"),
        ("adept", "#2F7A55", "#d8d0a0", "#90f0b0"), ("warlock", "#3B2F5C", "#a090d0", "#c080ff"),
        ("archmage", "#E6E1D3", "#d4a830", "#fff0a0"), ("starweave", "#1E3B73", "#5ff0ff", "#a0faff"),
        ("wyrmweave", "#4A0E14", "#e0b040", "#ff6a3a")]
WOOD = [("oak", "#9a6b3a"), ("willow", "#b49a64"), ("maple", "#c08a4a"), ("yew", "#6a3f22"),
        ("elder", "#4a3a2e"), ("starwood", "#3a6a8a"), ("wyrmwood", "#5a1e1a")]
TIER_NAMES = [{"metal": m[0], "hide": h[0], "robe": r[0], "wood": w[0]} for m, h, r, w in zip(METAL, HIDE, ROBE, WOOD)]

# Other rows: (row, [(name, colour), ...]) listed left to right.
ROWS = {
    7: [("skin.1", "#f1c8a0"), ("skin.2", "#d9a77a"), ("skin.3", "#b07a52"), ("skin.4", "#8a5a3a"),
        ("skin.5", "#6a4028"), ("skin.dark", "#a06a48"), ("hair.1", "#3a2618"), ("hair.2", "#6a4424"),
        ("hair.3", "#c8a060"), ("hair.4", "#202020"), ("eye", "#1a1a22"), ("mouth", "#7a3a30"),
        ("cloth.shirt", "#8a7a60"), ("cloth.trousers", "#4a4038"), ("cloth.belt", "#3a2a1a"), ("cloth.shoe", "#2e241c")],
    8: [("team.base", "#9a9a9a"), ("team.dark", "#6a6a6a"), ("team.light", "#c8c8c8"),
        ("team.blue", "#2F6FD6"), ("team.blue_dark", "#1f4a90"), ("team.red", "#D64A2F"), ("team.red_dark", "#902e1c"),
        ("cloth.white", "#e8e4dc"), ("cloth.black", "#26242a"), ("cloth.red", "#9b2020"), ("cloth.green", "#2f6d32"),
        ("cloth.blue", "#26449a"), ("cloth.purple", "#4a2a7a"), ("cloth.brown", "#6a4a2a"), ("gold", "#d8b040"), ("silver", "#d0d4da")],
    9: [("wood.light", "#b08a5a"), ("wood.mid", "#7a5530"), ("wood.dark", "#4a321c"), ("leather.strap", "#4a2e1a"),
        ("string", "#ece4cc"), ("rope", "#b09a6a"), ("feather.white", "#f2f2ee"), ("feather.red", "#c03028"),
        ("bone", "#e8dcc0"), ("metal.dark", "#2e2e34"), ("metal.grey", "#7a7c82"), ("metal.light", "#c4c8ce"),
        ("gold.dark", "#9a7a20"), ("grip", "#3a2418"), ("pommel", "#5a5a60"), ("black", "#141416")],
    10: [("stone.light", "#a8a49a"), ("stone.mid", "#7e7a72"), ("stone.dark", "#55524c"), ("stone.moss", "#5e6e48"),
         ("ice.light", "#e8f8ff"), ("ice.mid", "#a8dcf0"), ("ice.dark", "#6aa8c8"), ("snow", "#f4f6f8"),
         ("fire.yellow", "#ffe070"), ("fire.orange", "#ff9a30"), ("fire.red", "#e04020"), ("ember", "#ff6a20"),
         ("lava", "#c83010"), ("sand", "#d8c08a"), ("dirt", "#7a6040"), ("mud", "#4e3e2a")],
    11: [("foliage.light", "#7aa848"), ("foliage.mid", "#4e7e32"), ("foliage.dark", "#2e5222"), ("grass", "#5e8a3a"),
         ("water.light", "#6ab0d8"), ("water.mid", "#3a7aaa"), ("water.dark", "#1e4a72"), ("bark", "#5a4230"),
         ("hay", "#d8b860"), ("cloth.banner", "#b02a2a"), ("canvas", "#d8ccaa"), ("iron.rust", "#8a4a2a"),
         ("brick", "#9a5a42"), ("roof", "#6a3a2e"), ("glass", "#9ad0e0"), ("ash", "#4a4a4a")],
    12: [("magic.ember", "#ff7a2a"), ("magic.frost", "#9fe0ff"), ("magic.leech", "#a0202a"), ("magic.miasma", "#6ad040"),
         ("magic.gloom", "#8a40d0"), ("magic.storm", "#80c0ff"), ("magic.holy", "#fff0a0"), ("magic.void", "#7a3ae0"),
         ("gem.red", "#e0303a"), ("gem.blue", "#3a70ff"), ("gem.green", "#30d060"), ("gem.purple", "#b040ff"),
         ("gem.white", "#f0f8ff"), ("gem.yellow", "#ffd040"), ("gem.onyx", "#2a2a36"), ("glow.white", "#ffffff")],
    13: [("u.whip", "#5a3d7a"), ("u.claws", "#b03a2e"), ("u.greatblade", "#e3c35a"), ("u.voidblade", "#6b2fbf"),
         ("u.maul", "#7d7d78"), ("u.duskbow", "#2b2b3a"), ("u.ballista", "#6b4a2a"), ("u.sunfire", "#f0c040"),
         ("u.eruption", "#d9531e"), ("u.forbidden", "#3b1f4f"), ("u.tempest", "#7fb3ff"), ("tome.arcane", "#4a2f8a"),
         ("tome.novice", "#6a4f2a"), ("tome.star", "#39c1d1"), ("tome.wyrmbone", "#e8dcc0"), ("cape.melee", "#9b1c1c")],
    14: [("cape.ranged", "#2f7d32"), ("cape.magic", "#2340a8"), ("cape.mantle", "#3a2a7a"), ("u.quiver", "#7a5a2a"),
         ("u.pouch", "#9a7a3a"), ("u.eagle_coif", "#8c6f3a"), ("u.ranger_boots", "#4d7a3a"), ("u.wizard_boots", "#2e4a9a"),
         ("u.buckler", "#6f5a35"), ("bolt.diamond", "#e8f6ff"), ("bolt.dragonfire", "#ff7a1a"), ("bolt.onyx", "#2a2a2a"),
         ("ui.black", "#000000"), ("ui.white", "#ffffff"), ("ui.grey", "#808080"), ("ui.dark", "#303030")],
    15: [("sg.berserker", "#4a2a22"), ("sg.bulwark", "#4e555e"), ("sg.duelist", "#e2e2e8"), ("sg.armoured", "#316741"),
         ("sg.skirmisher", "#3a3a40"), ("sg.trackers", "#2e6a6a"), ("sg.warded", "#d8d8cc"), ("sg.sorcerers", "#2e8691"),
         ("sg.battlemage", "#6a1e1a"), ("sg.berserker.trim", "#c03028"), ("sg.bulwark.trim", "#d8b040"),
         ("sg.duelist.trim", "#b0202a"), ("sg.skirmisher.trim", "#d04a2a"), ("sg.warded.trim", "#3a8a5a"),
         ("sg.sorcerers.trim", "#f0e8c0"), ("sg.battlemage.trim", "#202020")],
}

# Cells that glow (emission mask). Tier 6-7 accents, magic, gems, fire and a few unique accents.
EMISSIVE = ["starmetal.accent", "wyrmforged.accent", "starhide.accent", "wyrmhide.accent",
            "starweave.accent", "wyrmweave.accent", "glow.white", "fire.yellow", "fire.orange", "ember", "lava",
            "u.sunfire", "bolt.dragonfire"] + [n for n, _ in ROWS[12] if n.startswith("magic.") or n.startswith("gem.")
                                               and n != "gem.onyx"]


def build_cells():
    cells = {}
    colours = {}
    for t in range(7):
        for col0, fam in ((0, METAL), (5, HIDE), (10, ROBE)):
            name, base, trim, accent = fam[t]
            b = hex_rgb(base)
            entries = [("base", b), ("dark", shade(b, -0.35)), ("light", shade(b, 0.35)),
                       ("trim", hex_rgb(trim)), ("accent", hex_rgb(accent))]
            for i, (suffix, rgb) in enumerate(entries):
                cells["%s.%s" % (name, suffix)] = [col0 + i, t]
                colours["%s.%s" % (name, suffix)] = rgb
        cells[WOOD[t][0]] = [15, t]
        colours[WOOD[t][0]] = hex_rgb(WOOD[t][1])
    for row, entries in ROWS.items():
        assert len(entries) <= GRID, row
        for col, (name, hx) in enumerate(entries):
            assert name not in cells, name
            cells[name] = [col, row]
            colours[name] = hex_rgb(hx)
    return cells, colours


def write_png(path, w, h, rows_rgba):
    raw = b"".join(b"\x00" + bytes(r) for r in rows_rgba)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def main():
    force = "--force" in sys.argv
    cells, colours = build_cells()
    for n in EMISSIVE:
        assert n in cells, n
    meta = {
        "_doc": "Swatch name -> [col, row] in palette.png (16 x 16 cells of 8 px). Colours live in the PNG: repaint it, "
                "then rebuild. Generated by make_palette.py; add new names there.",
        "grid": GRID, "cell_px": CELL,
        "tiers": {str(i + 1): TIER_NAMES[i] for i in range(7)},
        "team_cells": ["team.base", "team.dark", "team.light"],
        "emissive": EMISSIVE,
        "swatches": dict(sorted(cells.items(), key=lambda kv: (kv[1][1], kv[1][0]))),
    }
    # art/palette/palette.json is the pipeline copy; assets/palette/palette.json ships with the game
    # (the client reads team-colour cells from it at runtime).
    for p in (os.path.join(ROOT, "art", "palette", "palette.json"),
              os.path.join(ROOT, "assets", "palette", "palette.json")):
        with open(p, "w", newline="\n") as f:
            json.dump(meta, f, indent=1)
    png_path = os.path.join(ROOT, "assets", "palette", "palette.png")
    if force or not os.path.exists(png_path):
        grid = [[(255, 0, 255)] * GRID for _ in range(GRID)]  # magenta = unused cell
        for name, (c, r) in cells.items():
            grid[r][c] = colours[name]
        rows = []
        for y in range(GRID * CELL):
            row = []
            for x in range(GRID * CELL):
                row.extend(grid[y // CELL][x // CELL] + (255,))
            rows.append(row)
        write_png(png_path, GRID * CELL, GRID * CELL, rows)
        print("wrote", png_path)
    else:
        print("kept existing", png_path, "(use --force to reset colours)")
    mask = [[0] * GRID for _ in range(GRID)]
    for n in EMISSIVE:
        c, r = cells[n]
        mask[r][c] = 255
    write_png(os.path.join(ROOT, "assets", "palette", "emission_mask.png"), GRID, GRID,
              [[v for x in range(GRID) for v in (mask[y][x],) * 3 + (255,)] for y in range(GRID)])
    print("palette: %d swatches, %d emissive" % (len(cells), len(EMISSIVE)))


if __name__ == "__main__":
    main()
