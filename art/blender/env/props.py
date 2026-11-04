"""Pillars (3 per kit), 2x2 blocks, footprint-sized structures, water-edge pieces (<= 0.6 tall, inside water
tiles), flat decor (<= 0.25), skirt scatter (outside the border) and backdrop silhouettes."""
import json
import math
import os

from lib import palette
from lib.mesh import MeshBuilder, T, R

from .common import KITS, S, box, cone_tree, finish, module, rng, rock


# ------------------------------------------------------------------ pillars (1x1, 2.0-2.6 tall, solid)
def pillar(kit, v, r):
    m = MeshBuilder()
    p, pd, light = S(kit, "pillar"), S(kit, "pillar_dark"), S(kit, "wall_light")
    if kit == "frost":
        box(m, (0, 0, 0.12), (0.96, 0.96, 0.24), pd)
        top = 2.3 if v != 2 else 1.6
        m.loft([(0.24, 0.34, 0.34), (top, 0.31, 0.31)], sides=8, sw=p)
        if v == 2:  # snapped, jagged top + fallen chunk inside its tile
            m.loft([(top, 0.31, 0.31), (top + 0.18, 0.12, 0.2, 0.08, 0.0)], sides=8, sw=p)
            rock(m, (-0.3, -0.28, 0.24), 0.17, p, h=0.2)
        else:
            box(m, (0, 0, top + 0.1), (0.86, 0.86, 0.2), light)
            box(m, (0, 0, top + 0.23), (0.8, 0.8, 0.06), S("frost", "snow"))
        if v == 3:  # encased in ice crystals
            for a in range(5):
                ang = a * 1.26 + 0.3
                x, y = math.cos(ang) * 0.3, math.sin(ang) * 0.3
                m.gem((x, y, 0.5 + a * 0.28), 0.14, S("frost", "ice"), h=0.32)
    elif kit == "ember":
        box(m, (0, 0, 0.14), (0.96, 0.96, 0.28), pd)
        if v == 3:  # weathered stone marker
            box(m, (0, 0, 1.15), (0.78, 0.7, 1.8), p, taper=(0.75, 0.75))
            box(m, (0, -0.33, 1.3), (0.4, 0.04, 0.6), pd)
        else:
            m.loft([(0.28, 0.36, 0.36), (2.1, 0.32, 0.32)], sides=8, sw=p)
            box(m, (0, 0, 2.2), (0.9, 0.9, 0.2), pd)
            box(m, (0, 0, 2.36), (0.8, 0.8, 0.12), p)
            if v == 2:  # wrapped with cloth strips
                for z in (0.7, 1.15, 1.6):
                    m.loft([(z, 0.37, 0.37), (z + 0.14, 0.37, 0.37)], sides=8, sw=S("ember", "cloth"))
                box(m, (0.2, -0.36, 1.2), (0.1, 0.06, 0.9), S("ember", "tarp"))
    elif kit == "mire":
        if v == 1:  # gnarled dead tree, branches above 2.0
            for a in range(4):
                ang = a * math.pi / 2 + 0.4
                box(m, (math.cos(ang) * 0.3, math.sin(ang) * 0.3, 0.1), (0.3, 0.3, 0.2), S("mire", "root"))
            m.loft([(0.0, 0.42, 0.4), (0.8, 0.3, 0.3), (1.7, 0.24, 0.24, 0.05, 0.0), (2.2, 0.16, 0.16, 0.1, 0.05)],
                   sides=6, sw=S("mire", "pillar"))
            for a, l in ((0.5, 0.55), (2.4, 0.6), (4.2, 0.45)):
                x, y = math.cos(a), math.sin(a)
                m.cyl((0.08, 0.02, 2.0), (x * l * 0.8, y * l * 0.8, 2.0 + l * 0.6), 0.06, sw=S("mire", "pillar"),
                      sides=4)
        elif v == 2:  # mossy stone post with a lantern
            box(m, (0, 0, 0.15), (0.96, 0.96, 0.3), S("mire", "wall_dark"))
            box(m, (0, 0, 1.1), (0.7, 0.7, 1.7), S("mire", "wall"), taper=(0.85, 0.85))
            box(m, (0, 0, 1.98), (0.62, 0.62, 0.06), S("mire", "wall_trim"))
            box(m, (0, 0, 2.15), (0.2, 0.2, 0.25), S("mire", "lantern"))
            box(m, (0, 0, 2.3), (0.26, 0.26, 0.05), "common.metal_dark")
        else:  # hollow stump-tower with a jagged top
            m.loft([(0.0, 0.46, 0.46), (1.3, 0.42, 0.42), (1.55, 0.38, 0.38)], sides=7, sw=S("mire", "pillar"))
            for a in range(4):
                ang = a * 1.57 + 0.3
                box(m, (math.cos(ang) * 0.28, math.sin(ang) * 0.28, 1.7), (0.18, 0.18, 0.3 + 0.1 * a),
                    S("mire", "pillar_dark"))
            box(m, (0.2, -0.38, 0.3), (0.24, 0.06, 0.3), S("mire", "dark"))
    else:  # castle
        box(m, (0, 0, 0.15), (0.96, 0.96, 0.3), pd)
        if v == 1:
            m.loft([(0.3, 0.33, 0.33), (2.2, 0.3, 0.3)], sides=8, sw=p)
            box(m, (0, 0, 2.3), (0.84, 0.84, 0.2), light)
        elif v == 2:  # an original knight statue on a plinth
            st = S("castle", "statue")
            box(m, (0, 0, 0.55), (0.82, 0.82, 0.8), p)
            for x in (-0.1, 0.1):
                box(m, (x, 0, 1.15), (0.14, 0.18, 0.4), st)
            box(m, (0, 0, 1.6), (0.38, 0.24, 0.5), st)
            box(m, (0, 0, 2.0), (0.22, 0.22, 0.26), st)
            box(m, (0.24, -0.08, 1.55), (0.06, 0.3, 0.42), st)          # shield
            box(m, (-0.24, -0.05, 1.7), (0.05, 0.05, 0.9), st)          # sword, point down
        else:  # round topiary with a solid trunk
            m.cyl((0, 0, 0.3), (0, 0, 0.8), 0.14, sw=S("castle", "wood"), sides=5)
            m.loft([(0.6, 0.3, 0.3), (0.9, 0.46, 0.46), (1.5, 0.47, 0.47), (2.0, 0.34, 0.34), (2.25, 0.12, 0.12)],
                   sides=8, sw=S("castle", "foliage"))
    return m


# ------------------------------------------------------------------ 2x2 blocks
def block(kit, v, r):
    m = MeshBuilder()
    if kit == "ember":
        wood, cloth, tarp = S("ember", "wood"), S("ember", "cloth"), S("ember", "tarp")
        pot, fruit, rope = S("ember", "pottery"), S("ember", "fruit"), S("ember", "rope")
        if v == 1:  # covered stall: closed counter, canopy >= 1.6
            box(m, (0, 0, 0.5), (1.94, 1.94, 1.0), wood)
            box(m, (0, -0.2, 1.04), (1.8, 1.2, 0.08), S("ember", "wall_light"))
            for x, y in ((-0.9, -0.9), (0.9, -0.9), (-0.9, 0.9), (0.9, 0.9)):
                box(m, (x, y, 1.4), (0.1, 0.1, 0.8), wood)
            box(m, (0, 0, 1.86), (1.98, 1.98, 0.12), cloth, taper=(0.9, 0.9))
            for x in (-0.5, 0.0, 0.5):
                m.gem((x, -0.4, 1.18), 0.11, fruit if x else pot, h=0.12)
            m.cyl((-0.6, 0.3, 1.1), (0.6, 0.3, 1.1), 0.1, sw=S("ember", "rug"), sides=6)
        elif v == 2:  # crate and barrel stack
            box(m, (-0.45, -0.45, 0.45), (0.9, 0.9, 0.9), wood)
            box(m, (0.45, 0.45, 0.45), (0.9, 0.9, 0.9), wood)
            box(m, (-0.45, 0.45, 0.4), (0.8, 0.8, 0.8), S("ember", "wall_trim"))
            box(m, (0.0, 0.1, 1.3), (0.9, 0.9, 0.8), wood)
            box(m, (0.0, 0.1, 1.72), (0.6, 0.6, 0.06), rope)
            m.cyl((0.5, -0.5, 0.0), (0.5, -0.5, 1.05), 0.36, sw=S("ember", "wall_trim"), sides=8)
        elif v == 3:  # spice sacks with a scale and a crate backing
            box(m, (0, 0.6, 0.78), (1.94, 0.7, 1.56), wood)
            for x in (-0.6, 0.0, 0.6):
                box(m, (x, -0.2, 0.35), (0.55, 0.55, 0.7), tarp, taper=(0.7, 0.7))
                m.gem((x, -0.2, 0.75), 0.18, (fruit, cloth, pot)[int(x * 2 + 1.2) % 3], h=0.1)
            m.cyl((0.6, 0.6, 1.56), (0.6, 0.6, 2.0), 0.03, sw="common.metal", sides=4)
            box(m, (0.6, 0.6, 2.0), (0.6, 0.04, 0.04), "common.metal")
        elif v == 4:  # stacked pottery display
            for i, (z, w) in enumerate(((0.3, 1.94), (0.75, 1.5), (1.2, 1.0))):
                box(m, (0, 0, z), (w, w, 0.45 if i < 2 else 0.45), S("ember", "wall_light"))
            for x, y, z in ((-0.7, -0.7, 0.53), (0.7, -0.7, 0.53), (-0.5, -0.5, 0.98), (0.5, 0.5, 0.98), (0, 0, 1.43)):
                m.loft([(0.0, 0.12, 0.12), (0.18, 0.18, 0.18), (0.3, 0.08, 0.08)], sides=6, sw=pot, mat=T(x, y, z))
        elif v == 5:  # hay-bale cart
            box(m, (0, 0, 0.55), (1.9, 1.3, 0.2), wood)
            for x in (-0.6, 0.6):
                m.cyl((x, -0.72, 0.4), (x, -0.62, 0.4), 0.4, sw=S("ember", "dark"), sides=8)
                m.cyl((x, 0.62, 0.4), (x, 0.72, 0.4), 0.4, sw=S("ember", "dark"), sides=8)
            for x, z in ((-0.45, 0.88), (0.45, 0.88), (0.0, 1.32)):
                box(m, (x, 0, z), (0.85, 1.1, 0.44), S("ember", "tarp"))
            box(m, (0, 0, 0.25), (1.6, 1.0, 0.4), S("ember", "dark"))
            box(m, (0.0, 0.0, 1.62), (0.6, 0.9, 0.15), S("ember", "tarp"))
        else:  # tarp-covered goods pile
            box(m, (0, 0, 0.5), (1.9, 1.9, 1.0), S("ember", "wall_trim"))
            m.loft([(0.0, 0.98, 0.98), (1.1, 0.92, 0.9), (1.55, 0.5, 0.55), (1.7, 0.1, 0.1)], sides=4, sw=tarp,
                   flat=True, cap0=False)
            box(m, (0, 0, 1.15), (1.98, 0.08, 0.06), rope)
            box(m, (0, 0, 1.15), (0.08, 1.98, 0.06), rope)
        return m
    # other kits: rock pile / crate stack variants
    if v == 1:
        box(m, (0, 0, 0.12), (1.9, 1.9, 0.24), S(kit, "edging"))
        rock(m, (-0.4, -0.3, 0.2), 0.62, S(kit, "pillar"), h=1.2)
        rock(m, (0.45, 0.35, 0.2), 0.55, S(kit, "pillar_dark"), h=1.4)
        rock(m, (0.2, -0.5, 0.2), 0.4, S(kit, "pillar"), h=0.8)
    else:
        box(m, (-0.45, -0.45, 0.45), (0.9, 0.9, 0.9), S(kit, "wood"))
        box(m, (0.45, 0.45, 0.45), (0.9, 0.9, 0.9), S(kit, "wood"))
        box(m, (0.0, 0.0, 1.25), (1.0, 1.0, 0.8), S(kit, "wood"))
        box(m, (0.45, -0.45, 0.35), (0.8, 0.8, 0.7), S(kit, "pillar_dark"))
        box(m, (-0.45, 0.45, 0.35), (0.8, 0.8, 0.7), S(kit, "pillar_dark"))
    return m


BLOCK_VARIANTS = {"ember": 6, "frost": 2, "mire": 2, "castle": 2}


# ------------------------------------------------------------------ structures sized to their footprint
def structure(kit, w, d, r):
    """w along X, d along Y (w >= d). Fills the footprint exactly; detail on all four sides; <= 3.0 tall."""
    m = MeshBuilder()
    hw, hd = w / 2 - 0.02, d / 2 - 0.02
    wall, dark, light = S(kit, "wall"), S(kit, "wall_dark"), S(kit, "wall_light")
    sides = [((0, -hd), (1, 0), w), ((0, hd), (-1, 0), w), ((-hw, 0), (0, -1), d), ((hw, 0), (0, 1), d)]
    if kit == "frost":  # ruined square guard tower, collapsed roof corner
        h = 2.4
        box(m, (0, 0, 0.15), (w + 0.04, d + 0.04, 0.3), dark)
        box(m, (0, 0, h / 2), (w - 0.04, d - 0.04, h), wall)
        box(m, (0, 0, 1.2), (w, d, 0.1), light)
        for (cx, cy), (tx, ty), length in sides:   # arrow slits on every side
            nx, ny = (0 if cx == 0 else (1 if cx > 0 else -1)), (0 if cy == 0 else (1 if cy > 0 else -1))
            box(m, (cx + nx * 0.02, cy + ny * 0.02, 1.7), (0.08 if nx == 0 else 0.04, 0.04 if nx == 0 else 0.08, 0.4),
                "common.black")
        for x in (-hw + 0.3, hw - 0.3):
            for y in (-hd + 0.3, hd - 0.3):
                if x > 0 and y > 0:
                    rock(m, (x - 0.3, y - 0.3, h), 0.4, wall, h=0.25)  # collapsed corner rubble
                    continue
                box(m, (x, y, h + 0.2), (0.5, 0.5, 0.4), wall)
                box(m, (x, y, h + 0.43), (0.46, 0.46, 0.06), S("frost", "snow"))
        box(m, (0, 0, h + 0.02), (w - 0.3, d - 0.3, 0.05), S("frost", "snow"))
    elif kit == "ember":  # flat-roofed adobe merchant house with parapet and wind-catcher
        h = 2.3
        box(m, (0, 0, 0.1), (w + 0.04, d + 0.04, 0.2), dark)
        box(m, (0, 0, h / 2), (w - 0.04, d - 0.04, h), wall)
        for (cx, cy), (tx, ty), length in sides:
            nx, ny = (0 if cx == 0 else (1 if cx > 0 else -1)), (0 if cy == 0 else (1 if cy > 0 else -1))
            ox, oy = cx + nx * 0.03, cy + ny * 0.03
            sx, sy = (0.7, 0.06) if nx == 0 else (0.06, 0.7)
            box(m, (ox, oy, 0.7), (sx, sy, 1.3), S("ember", "wood"))                       # door
            for k in (-1, 1):
                off = k * length * 0.3
                px, py = ox + tx * off, oy + ty * off
                box(m, (px, py, 1.55), (0.5 if nx == 0 else 0.06, 0.06 if nx == 0 else 0.5, 0.45), S("ember", "wall_trim"))
        for x in (-hw, hw):  # parapet
            box(m, (x * 0.98, 0, h + 0.15), (0.16, d - 0.04, 0.3), light)
        for y in (-hd, hd):
            box(m, (0, y * 0.98, h + 0.15), (w - 0.04, 0.16, 0.3), light)
        box(m, (hw - 0.55, hd - 0.55, h + 0.35), (0.8, 0.8, 0.7), wall)                     # wind-catcher
        box(m, (hw - 0.55, hd - 0.55, h + 0.66), (0.86, 0.86, 0.08), light)
        for i in range(3):                                                                  # rooftop jars
            m.loft([(0.0, 0.12, 0.12), (0.2, 0.17, 0.17), (0.3, 0.07, 0.07)], sides=6, sw=S("ember", "pottery"),
                   mat=T(-hw + 0.6 + i * 0.35, -hd + 0.5, h))
        m.cyl((-hw + 0.4, 0.0, h + 0.12), (-hw + 0.4 + d * 0.0 + 1.6, 0.0, h + 0.12), 0.1, sw=S("ember", "cloth"),
              sides=6)                                                                      # rolled awning
        for k in (-0.15, 0.15):                                                             # ladder on the roof
            box(m, (0.6 + k, 0.4, h + 0.03), (0.05, 1.4, 0.05), S("ember", "wood"))
    else:  # mire stilt-hut ruin / castle gatehouse
        h = 2.4
        box(m, (0, 0, 0.15), (w + 0.04, d + 0.04, 0.3), dark)
        box(m, (0, 0, h / 2), (w - 0.04, d - 0.04, h), wall)
        box(m, (0, 0, 1.1), (w, d, 0.1), S(kit, "wood"))
        roof = S(kit, "cloth") if kit == "mire" else S("castle", "roof")
        m.loft([(h, hw, hd), (h + 0.55, 0.15, hd * 0.9)], sides=4, sw=roof, cap0=False)
    return m


def structure_sizes():
    """Footprints (w >= d) per kit, read from the map data so every structure has an exact-size model."""
    sizes = {k: set() for k in KITS}
    mdir = os.path.join(palette.ROOT, "data", "maps")
    for fn in sorted(os.listdir(mdir)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(mdir, fn), encoding="utf-8") as f:
            d = json.load(f)
        kit = d.get("dressing", {}).get("kit", "")
        if kit not in sizes:
            continue
        for r in d.get("walls", []):
            if len(r) >= 4 and min(r[2], r[3]) >= 3:
                sizes[kit].add((max(r[2], r[3]), min(r[2], r[3])))
    return sizes


# ------------------------------------------------------------------ water-edge pieces (inside water, <= 0.6)
def water_piece(kit, name, r):
    m = MeshBuilder()
    if name == "ice_shards":
        for i in range(4):
            m.gem((r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 0.15), r.uniform(0.08, 0.14), S("frost", "ice"),
                  h=r.uniform(0.15, 0.25))
    elif name == "ice_chunk":
        box(m, (0, 0, 0.02), (0.6, 0.45, 0.12), S("frost", "water_shallow"), taper=(0.8, 0.8))
    elif name == "well_frame":
        for x in (-0.35, 0.35):
            box(m, (x, 0, 0.28), (0.07, 0.07, 0.56), S("ember", "wood"))
        box(m, (0, 0, 0.56), (0.8, 0.06, 0.06), S("ember", "wood"))
        m.cyl((0, 0, 0.53), (0, 0, 0.3), 0.012, sw=S("ember", "rope"), sides=3)
        m.loft([(0.18, 0.09, 0.09), (0.3, 0.1, 0.1)], sides=6, sw=S("ember", "wall_trim"))
    elif name == "reeds":
        for i in range(6):
            x, y = r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3)
            h = r.uniform(0.35, 0.55)
            m.cone((x, y, 0.0), (x + r.uniform(-0.05, 0.05), y, h), 0.025, S("mire", "reed"), sides=3)
        m.cyl((0.1, 0.1, 0.42), (0.1, 0.1, 0.55), 0.035, sw=S("mire", "root"), sides=4)
    elif name == "lily":
        for i in range(3):
            x, y = r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3)
            m.cyl((x, y, 0.0), (x, y, 0.02), r.uniform(0.1, 0.16), sw=S(kit, "lily") if kit == "mire" else
                  S("castle", "foliage"), sides=6)
    elif name == "log":
        m.cyl((-0.38, 0.0, 0.04), (0.38, 0.1, 0.04), 0.1, sw=S("mire", "pillar"), sides=6)
    elif name == "fountain":
        m.loft([(0.0, 0.22, 0.22), (0.2, 0.16, 0.16), (0.24, 0.24, 0.24), (0.3, 0.24, 0.24)], sides=8,
               sw=S("castle", "pillar"))
        m.gem((0, 0, 0.42), 0.06, S("castle", "water_shallow"), h=0.12)
    return m


WATER_PIECES = {"frost": ["ice_shards", "ice_chunk"], "ember": ["well_frame"], "mire": ["reeds", "lily", "log"],
                "castle": ["fountain", "lily"]}


# ------------------------------------------------------------------ flat decor (<= 0.25, walkable tiles)
def decor(kit, name, r):
    m = MeshBuilder()
    if name == "drift":
        m.loft([(0.0, 0.4, 0.3), (0.06, 0.3, 0.22), (0.11, 0.1, 0.08)], sides=6, sw=S("frost", "snow"))
    elif name == "stones":
        for i in range(3):
            rock(m, (r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 0.0), r.uniform(0.05, 0.09), S(kit, "edging"),
                 h=0.07, sides=4)
    elif name == "shield_flat":
        m.cyl((0, 0, 0.0), (0, 0, 0.04), 0.2, sw="common.metal", sides=8)
        m.cyl((0, 0, 0.04), (0, 0, 0.06), 0.06, sw="common.metal_dark", sides=6)
    elif name == "spear_flat":
        m.cyl((-0.4, 0, 0.03), (0.3, 0.05, 0.03), 0.02, sw="common.wood", sides=4)
        m.cone((0.3, 0.05, 0.03), (0.45, 0.06, 0.03), 0.04, "common.metal", sides=4)
    elif name == "rug":
        box(m, (0, 0, 0.01), (0.8, 0.55, 0.02), S("ember", "rug"))
        box(m, (0, 0, 0.022), (0.6, 0.38, 0.01), S("ember", "cloth"))
    elif name == "shards":
        for i in range(4):
            box(m, (r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 0.02), (0.08, 0.06, 0.03), S("ember", "pottery"))
    elif name == "cactus":
        m.loft([(0.0, 0.07, 0.07), (0.2, 0.06, 0.06), (0.24, 0.0, 0.0)], sides=5, sw=S("ember", "cactus"))
        m.cyl((0.0, 0.0, 0.1), (0.1, 0.0, 0.16), 0.03, sw=S("ember", "cactus"), sides=4)
    elif name == "coins":
        for i in range(4):
            x, y = r.uniform(-0.2, 0.2), r.uniform(-0.2, 0.2)
            m.cyl((x, y, 0.0), (x, y, 0.015), 0.035, sw="common.gold", sides=4)
    elif name == "mushrooms":
        for i in range(3):
            x, y, h = r.uniform(-0.25, 0.25), r.uniform(-0.25, 0.25), r.uniform(0.08, 0.18)
            m.cyl((x, y, 0.0), (x, y, h), 0.02, sw="common.bone", sides=4)
            m.loft([(h, 0.07, 0.07, x, y), (h + 0.04, 0.0, 0.0, x, y)], sides=5, sw=S("mire", "mushroom"))
    elif name == "roots":
        for a in (0.3, 1.9, 3.6):
            m.cyl((0, 0, 0.03), (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.01), 0.035, sw=S("mire", "root"), sides=4)
    elif name == "moss":
        box(m, (0, 0, 0.01), (0.7, 0.6, 0.02), S("mire", "detail"), taper=(0.8, 0.8))
    elif name == "wheel":
        m.cyl((0, 0, 0.0), (0, 0, 0.05), 0.3, sw=S("mire", "wood"), sides=8)
        m.cyl((0, 0, 0.05), (0, 0, 0.07), 0.06, sw="common.metal_dark", sides=6)
    elif name == "flowerbed":
        box(m, (0, 0, 0.04), (0.8, 0.5, 0.08), S("castle", "wall_trim"))
        for i in range(4):
            x, y = r.uniform(-0.32, 0.32), r.uniform(-0.18, 0.18)
            box(m, (x, y, 0.11), (0.08, 0.08, 0.06), S("castle", r.choice(["flower_red", "flower_yellow", "flower_purple"])))
    elif name == "hedge_trim":
        box(m, (0, 0, 0.12), (0.5, 0.3, 0.24), S("castle", "foliage"), taper=(0.9, 0.85))
    elif name == "stepping_stone":
        m.cyl((0, 0, 0.0), (0, 0, 0.03), 0.22, sw=S("castle", "path"), sides=7)
    return m


DECOR = {"frost": ["drift", "stones", "shield_flat", "spear_flat"], "ember": ["rug", "shards", "cactus", "coins"],
         "mire": ["mushrooms", "roots", "moss", "wheel"], "castle": ["flowerbed", "hedge_trim", "stepping_stone", "stones"]}


# ------------------------------------------------------------------ skirt scatter (outside the border)
def scatter(kit, name, r):
    m = MeshBuilder()
    if name == "pine":
        cone_tree(m, (0, 0, 0), 1.0, 3.4, S("frost", "bark"), S("frost", "foliage"))
        box(m, (0, 0, 2.6), (0.6, 0.6, 0.05), S("frost", "snow"))
    elif name == "pine_tall":
        cone_tree(m, (0, 0, 0), 0.9, 4.6, S("frost", "bark"), S("frost", "pine_dark"), tiers=4)
    elif name == "rock":
        rock(m, (0, 0, -0.1), 0.9, S(kit, "pillar_dark"), h=1.0, sides=6)
    elif name == "ruin":
        box(m, (0, 0, 0.6), (1.6, 0.6, 1.2), S(kit, "wall"))
        box(m, (-0.5, 0, 1.4), (0.6, 0.55, 0.4), S(kit, "wall"))
        box(m, (0, 0, 1.24), (1.5, 0.5, 0.06), S("frost", "snow"))
    elif name == "palm":
        pts = [(0, 0, 0), (0.15, 0, 1.2), (0.4, 0, 2.3), (0.7, 0, 3.0)]
        for a, b in zip(pts, pts[1:]):
            m.cyl(a, b, 0.14, 0.12, sw=S("ember", "wood"), sides=5)
        for i in range(6):
            ang = i * math.tau / 6
            tip = (0.7 + math.cos(ang) * 1.2, math.sin(ang) * 1.2, 2.6)
            m.cone((0.7, 0, 3.05), tip, 0.18, S("ember", "foliage"), sides=3)
    elif name == "tent":
        m.loft([(0.0, 1.2, 1.0), (1.5, 0.0, 1.0)], sides=4, sw=S("ember", "tarp"), flat=True)
        box(m, (0, -1.0, 0.5), (0.4, 0.05, 0.9), S("ember", "dark"))
    elif name == "cart":
        box(m, (0, 0, 0.7), (1.6, 1.0, 0.4), S("ember", "wood"))
        for x in (-0.5, 0.5):
            m.cyl((x, -0.55, 0.45), (x, -0.5, 0.45), 0.45, sw=S("ember", "dark"), sides=8)
            m.cyl((x, 0.5, 0.45), (x, 0.55, 0.45), 0.45, sw=S("ember", "dark"), sides=8)
    elif name == "dead_tree":
        m.loft([(0.0, 0.35, 0.35), (2.0, 0.2, 0.2), (3.4, 0.08, 0.08, 0.2, 0.0)], sides=5, sw=S("mire", "pillar"))
        for a in (0.4, 2.2, 4.0):
            m.cyl((0, 0, 1.8), (math.cos(a) * 1.0, math.sin(a) * 1.0, 2.8), 0.07, sw=S("mire", "pillar"), sides=4)
    elif name == "stilt_hut":
        for x in (-0.7, 0.7):
            for y in (-0.6, 0.6):
                m.cyl((x, y, 0), (x, y, 1.2), 0.07, sw=S("mire", "wood"), sides=4)
        box(m, (0, 0, 1.6), (1.8, 1.5, 0.8), S("mire", "wood"))
        m.loft([(2.0, 1.1, 0.95), (2.7, 0.1, 0.9)], sides=4, sw=S("mire", "cloth"), flat=True)
    elif name == "stump":
        m.loft([(0.0, 0.5, 0.5), (0.6, 0.4, 0.4)], sides=6, sw=S("mire", "pillar"))
    elif name == "tree":
        m.cyl((0, 0, 0), (0, 0, 1.4), 0.18, sw=S("castle", "wood"), sides=5)
        m.loft([(1.0, 0.8, 0.8), (1.8, 1.25, 1.25), (2.8, 1.0, 1.0), (3.4, 0.3, 0.3)], sides=7, sw=S("castle", "foliage"))
    elif name == "tree_tall":
        m.cyl((0, 0, 0), (0, 0, 2.0), 0.16, sw=S("castle", "wood"), sides=5)
        m.loft([(1.6, 0.6, 0.6), (2.6, 0.9, 0.9), (4.0, 0.5, 0.5), (4.5, 0.0, 0.0)], sides=6, sw=S("castle", "detail"))
    elif name == "bush":
        m.loft([(0.0, 0.6, 0.5), (0.5, 0.7, 0.6), (0.9, 0.3, 0.3)], sides=6, sw=S("castle", "foliage"))
    return m


SCATTER = {"frost": ["pine", "pine_tall", "rock", "ruin"], "ember": ["palm", "tent", "cart", "rock"],
           "mire": ["dead_tree", "stilt_hut", "stump", "rock"], "castle": ["tree", "tree_tall", "bush", "rock"]}


# ------------------------------------------------------------------ backdrop silhouettes (60-150 tiles out)
def backdrop(kit, name, r):
    m = MeshBuilder()
    if name == "range":   # a segment of mountains / mesas / treeline / hills, about 60 wide
        for i in range(7):
            x = -30 + i * 10 + r.uniform(-3, 3)
            hh = r.uniform(14, 30)
            ww = r.uniform(9, 15)
            if kit == "frost":
                m.loft([(0.0, ww, ww * 0.8, x, 0), (hh * 0.7, ww * 0.3, ww * 0.25, x, 0), (hh, 0.0, 0.0, x, 0)],
                       sides=5, sw=[S("frost", "backdrop2"), S("frost", "backdrop")])
            elif kit == "ember":
                m.loft([(0.0, ww, ww * 0.7, x, 0), (hh * 0.6, ww * 0.75, ww * 0.55, x, 0)], sides=6,
                       sw=S("ember", "backdrop"))
                m.loft([(hh * 0.6, ww * 0.75, ww * 0.55, x, 0), (hh * 0.62, ww * 0.7, ww * 0.5, x, 0)], sides=6,
                       sw=S("ember", "backdrop2"), cap0=False)
            elif kit == "mire":
                hh *= 0.4
                m.loft([(0.0, ww * 0.6, 4.0, x, 0), (hh, ww * 0.45, 3.0, x, 0), (hh * 1.4, 0.0, 0.0, x, 0)], sides=5,
                       sw=S("mire", "backdrop"))
            else:
                hh *= 0.3
                m.loft([(0.0, ww * 1.3, ww, x, 0), (hh, ww * 0.6, ww * 0.5, x, 0), (hh * 1.2, 0.0, 0.0, x, 0)],
                       sides=6, sw=S("castle", "backdrop"))
    elif name == "keep":  # castle team keep beyond its end of the arena (banners take the team tint)
        st, roof = S("castle", "backdrop2"), S("castle", "roof")
        box(m, (0, 0, 5.0), (16.0, 8.0, 10.0), st)
        for x, y in ((-8, -4), (8, -4), (-8, 4), (8, 4)):
            m.cyl((x, y, 0), (x, y, 14.0), 2.2, sw=st, sides=8)
            m.cone((x, y, 14.0), (x, y, 19.0), 2.6, roof, sides=8)
            m.cyl((x, y, 19.0), (x, y, 21.5), 0.12, sw="common.pole", sides=3)
            box(m, (x + 0.9, y, 20.8), (1.6, 0.1, 1.0), "common.banner")
        m.cyl((0, 0, 10.0), (0, 0, 18.0), 3.0, sw=st, sides=8)
        m.cone((0, 0, 18.0), (0, 0, 24.0), 3.4, roof, sides=8)
        for x in range(-7, 8, 2):
            box(m, (x, -4.0, 10.5), (1.0, 1.0, 1.0), st)
    return m


BACKDROP = {"frost": ["range"], "ember": ["range"], "mire": ["range"], "castle": ["range", "keep"]}


# ------------------------------------------------------------------ registry
def assets():
    out = []
    for kit in KITS:
        for v in (1, 2, 3):
            aid = "env_%s_pillar_v%d" % (kit, v)
            out.append(module(aid, (lambda kit=kit, v=v, aid=aid: finish(pillar(kit, v, rng(aid)))), "pillar", kit=kit))
        for v in range(1, BLOCK_VARIANTS[kit] + 1):
            aid = "env_%s_block_v%d" % (kit, v)
            out.append(module(aid, (lambda kit=kit, v=v, aid=aid: finish(block(kit, v, rng(aid)))), "block", kit=kit))
        for name in WATER_PIECES[kit]:
            aid = "env_%s_water_%s" % (kit, name)
            out.append(module(aid, (lambda kit=kit, n=name, aid=aid: finish(water_piece(kit, n, rng(aid)))),
                              "water_decor", kit=kit, open_ok=True))
        for name in DECOR[kit]:
            aid = "env_%s_decor_%s" % (kit, name)
            out.append(module(aid, (lambda kit=kit, n=name, aid=aid: finish(decor(kit, n, rng(aid)))), "decor",
                              kit=kit, open_ok=True))
        for name in SCATTER[kit]:
            aid = "env_%s_scatter_%s" % (kit, name)
            out.append(module(aid, (lambda kit=kit, n=name, aid=aid: finish(scatter(kit, n, rng(aid)))), "scatter",
                              kit=kit, open_ok=True))
        for name in BACKDROP[kit]:
            aid = "env_%s_backdrop_%s" % (kit, name)
            out.append(module(aid, (lambda kit=kit, n=name, aid=aid: finish(backdrop(kit, n, rng(aid)))), "backdrop",
                              kit=kit, open_ok=True))
    for kit, sizes in structure_sizes().items():
        for w, d in sorted(sizes):
            aid = "env_%s_structure_%dx%d" % (kit, w, d)
            out.append(module(aid, (lambda kit=kit, w=w, d=d, aid=aid: finish(structure(kit, w, d, rng(aid)))),
                              "structure", kit=kit, w=w, d=d))
    return out
