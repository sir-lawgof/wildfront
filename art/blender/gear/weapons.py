"""Weapon, off-hand, back-slot and ammo generators. All grip-relative: the grip is the origin, weapons point
forward (-Y) with their 'up' along +Z, sized ~1.3x real proportions so they read at game distance.
Tier silhouette: guards/bands in the trim colour from tier 4, spikes and glowing accents from tier 6."""
import math

from mathutils import Matrix, Vector

from lib.mesh import T, R

from .common import PLANE_YZ, Gear, blade, prism, spike

GEM_BY_TIER = {1: "gem.yellow", 2: "gem.blue", 3: "gem.green", 4: "gem.purple", 5: "gem.white", 6: None, 7: None}


def _gem(g):
    return GEM_BY_TIER.get(g.tier) or g.s("accent", "gem.white")


def _hilt(g, m, grip_back=0.07, guard_y=-0.07, guard_h=0.17, guard_sw=None, pommel=True):
    m.cyl((0, grip_back, 0), (0, guard_y, 0), 0.026, sw="grip", sides=6)
    gsw = guard_sw or (g.s("trim") if g.trims else g.s("metal_dark", "metal.dark"))
    m.box((0, guard_y, 0), (0.045, 0.035, guard_h), gsw)
    if pommel:
        m.box((0, grip_back + 0.02, 0), (0.05, 0.04, 0.05), gsw)
    if g.spikes:
        for s in (1, -1):
            spike(m, (0, guard_y, s * guard_h / 2), (0, -0.4, s), 0.07, 0.02, g.s("accent", gsw))


# ------------------------------------------------------------------ melee
def dagger(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _hilt(g, m, 0.07, -0.065, 0.15)
    blade(m, (0, -0.075, 0), (0, -0.47, 0), 0.05, 0.013, g.s("base"), tip=0.3)
    return g.finish("weapon")


def scimitar(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _hilt(g, m, 0.075, -0.07, 0.16)
    blade(m, (0, -0.08, 0), (0, -0.80, 0), 0.062, 0.014, g.s("base"), curve=0.13, segs=4, tip=0.18, widen=1.35)
    return g.finish("weapon")


def longsword(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _hilt(g, m, 0.10, -0.075, 0.26)
    blade(m, (0, -0.09, 0), (0, -1.02, 0), 0.064, 0.016, g.s("base"), tip=0.14)
    if g.trims:
        m.box((0, -0.25, 0), (0.035, 0.22, 0.02), g.s("light"))  # fuller
    return g.finish("weapon")


def battleaxe(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.17, 0), (0, -0.70, 0), 0.03, sw=g.s("wood", "wood.mid"), sides=6)
    head = [(-0.48, 0.03), (-0.66, 0.03), (-0.74, 0.30), (-0.56, 0.34), (-0.47, 0.16)]
    for s in (1, -1):
        prism(m, [(u, z * s) for u, z in head], 0.03, g.s("base"), g.s("dark"), mat=PLANE_YZ)
    m.box((0, -0.57, 0), (0.06, 0.13, 0.09), g.s("trim") if g.trims else g.s("dark"))
    if g.spikes:
        spike(m, (0, -0.70, 0), (0, -1, 0), 0.14, 0.03, g.s("accent", g.s("trim")))
    return g.finish("weapon")


def warhammer(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.15, 0), (0, -0.62, 0), 0.03, sw=g.s("wood", "wood.mid"), sides=6)
    m.box((0, -0.62, 0.02), (0.15, 0.15, 0.30), g.s("base"))
    m.box((0, -0.62, 0.18), (0.17, 0.17, 0.04), g.s("light"))   # striking face
    spike(m, (0, -0.62, -0.13), (0, 0, -1), 0.12, 0.04, g.s("dark"))  # back spike
    if g.trims:
        m.box((0, -0.62, 0.02), (0.16, 0.16, 0.05), g.s("trim"))
    if g.spikes:
        spike(m, (0, -0.70, 0.02), (0, -1, 0), 0.10, 0.035, g.s("accent", g.s("trim")))
    return g.finish("weapon")


# ------------------------------------------------------------------ ranged
def _bow(g, m, half_h, bend, wood, tip_sw=None, r=0.032, spiky=False):
    pts = [(0, 0.0, 0.0), (0, 0.025, half_h * 0.35), (0, bend * 0.55, half_h * 0.72), (0, bend, half_h)]
    for s in (1, -1):
        for a, b in zip(pts, pts[1:]):
            m.cyl((a[0], a[1], a[2] * s), (b[0], b[1], b[2] * s), r, sw=wood, sides=4)
        if tip_sw:
            m.box((0, bend + 0.01, half_h * s), (0.04, 0.05, 0.05), tip_sw)
        if spiky:
            spike(m, (0, bend * 0.55, half_h * 0.72 * s), (0, -0.6, 0.4 * s), 0.1, 0.02, tip_sw or wood)
    m.cyl((0, bend + 0.005, half_h), (0, bend + 0.005, -half_h), 0.006, sw="string", sides=3)
    m.cyl((0, 0.0, -0.07), (0, 0.0, 0.07), 0.03, sw="grip", sides=6)


def shortbow(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _bow(g, m, 0.52, 0.12, g.s("wood", "wood.mid"), g.s("trim") if g.trims else None, spiky=g.spikes)
    if g.spikes:
        m.gem((0, -0.03, 0.0), 0.035, g.s("accent"))
    return g.finish("weapon")


def longbow(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _bow(g, m, 0.78, 0.15, g.s("wood", "wood.mid"), g.s("trim") if g.trims else None, spiky=g.spikes)
    if g.spikes:
        m.gem((0, -0.03, 0.0), 0.035, g.s("accent"))
    return g.finish("weapon")


def _crossbow(g, m, k=1.0, wood=None, metal=None, gem=None):
    wood = wood or g.s("wood", "wood.mid")
    metal = metal or g.s("base")
    m.box((0, -0.08 * k, 0.03), (0.06 * k, 0.66 * k, 0.07 * k), wood)              # stock
    m.box((0, 0.21 * k, 0.0), (0.075 * k, 0.12 * k, 0.12 * k), wood, taper=(1, 1)) # butt
    pts = [(-0.34, -0.30, 0.05), (-0.17, -0.37, 0.05), (0.0, -0.39, 0.05), (0.17, -0.37, 0.05), (0.34, -0.30, 0.05)]
    pts = [tuple(c * k for c in p) for p in pts]
    for a, b in zip(pts, pts[1:]):
        m.cyl(a, b, 0.025 * k, sw=metal, sides=4)
    m.cyl(pts[0], (0, -0.12 * k, 0.07 * k), 0.006, sw="string", sides=3)
    m.cyl(pts[-1], (0, -0.12 * k, 0.07 * k), 0.006, sw="string", sides=3)
    m.box((0, -0.40 * k, 0.05 * k), (0.07 * k, 0.05 * k, 0.07 * k), metal)        # nose
    if g.trims:
        m.box((0, -0.05 * k, 0.07 * k), (0.07 * k, 0.12 * k, 0.02 * k), g.s("trim"))
    if gem or g.spikes:
        m.gem((0, -0.43 * k, 0.05 * k), 0.035 * k, gem or g.s("accent"))


def crossbow(v):
    g = Gear(v)
    _crossbow(g, g.part("socket_weapon"))
    return g.finish("weapon")


def throwing_knives(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.05, 0), (0, -0.04, 0), 0.02, sw="grip", sides=4)
    m.loft([(0, 0.035, 0.035), (0.012, 0.035, 0.035)], sides=6, sw=g.s("dark"),
           mat=T(0, 0.07, 0) @ R(90, "X"))  # ring pommel
    blade(m, (0, -0.045, 0), (0, -0.30, 0), 0.05, 0.012, g.s("base"), tip=0.4)
    if g.spikes:
        m.gem((0, -0.04, 0), 0.025, g.s("accent"))
    return g.finish("weapon")


# ------------------------------------------------------------------ magic
def _staff_shaft(m, wood, top=0.74, bottom=-0.72, r=0.03):
    m.cyl((0, 0, bottom), (0, 0, top), r, sw=wood, sides=6)
    m.cyl((0, 0, -0.08), (0, 0, 0.08), r * 1.25, sw="grip", sides=6)


def staff(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    wood = "bone" if g.tier == 7 else g.s("wood", "wood.mid")
    _staff_shaft(m, wood)
    top = 0.74
    gem = _gem(g)
    if g.tier == 1:
        m.loft([(top - 0.02, 0.05, 0.05), (top + 0.08, 0.065, 0.065), (top + 0.14, 0.03, 0.03)], sides=6, sw=wood)
    elif g.tier == 2:
        m.loft([(top, 0.07, 0.07), (top + 0.035, 0.07, 0.07)], sides=6, sw=g.s("metal", "metal.grey"))
        m.gem((0, 0, top + 0.1), 0.05, gem)
    elif g.tier == 3:
        for a in range(3):
            ang = a * math.tau / 3
            m.cyl((0, 0, top), (math.cos(ang) * 0.06, math.sin(ang) * 0.06, top + 0.15), 0.015, sw=wood, sides=3)
        m.gem((0, 0, top + 0.13), 0.045, gem, h=0.09)
    elif g.tier == 4:
        for s in (1, -1):
            m.cyl((0, 0, top), (0.09 * s, 0, top + 0.12), 0.018, sw=g.s("trim"), sides=4)
            m.cyl((0.09 * s, 0, top + 0.12), (0.05 * s, 0, top + 0.22), 0.016, sw=g.s("trim"), sides=4)
        m.gem((0, 0, top + 0.12), 0.05, gem)
    elif g.tier == 5:
        m.loft([(top + 0.06, 0.085, 0.085), (top + 0.09, 0.085, 0.085)], sides=8, sw=g.s("trim"))
        m.loft([(top, 0.0, 0.0), (top + 0.07, 0.07, 0.07), (top + 0.15, 0.06, 0.06), (top + 0.2, 0.0, 0.0)],
               sides=6, sw=gem)
    elif g.tier == 6:
        star = []
        for i in range(8):
            r = 0.14 if i % 2 == 0 else 0.05
            ang = i * math.tau / 8 + math.pi / 2
            star.append((math.cos(ang) * r, math.sin(ang) * r + top + 0.14))
        prism(m, star, 0.04, g.s("accent"), mat=Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
        m.gem((0, 0, top + 0.14), 0.045, "gem.white")
    else:  # 7: horned wyrm skull
        m.box((0, -0.02, top + 0.07), (0.12, 0.16, 0.12), "bone")
        for s in (1, -1):
            spike(m, (0.05 * s, 0.03, top + 0.11), (0.5 * s, 0.4, 0.8), 0.18, 0.03, "bone")
        m.gem((0, -0.10, top + 0.08), 0.04, g.s("accent"))
    return g.finish("weapon")


def wand(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    wood = "bone" if g.tier == 7 else g.s("wood", "wood.mid")
    m.cyl((0, 0.07, 0), (0, -0.34, 0), 0.024, 0.016, sw=wood, sides=6)
    m.cyl((0, 0.05, 0), (0, -0.05, 0), 0.03, sw="grip", sides=6)
    m.loft([(0, 0.03, 0.03), (0.03, 0.03, 0.03)], sides=6,
           sw=g.s("trim") if g.trims else g.s("metal", "metal.grey"), mat=T(0, -0.32, 0) @ R(90, "X"))
    m.gem((0, -0.40, 0), 0.04, _gem(g), h=0.06)
    return g.finish("weapon")


# ------------------------------------------------------------------ uniques
def whip(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.07, 0), (0, -0.10, 0), 0.028, sw="grip", sides=6)
    m.box((0, 0.08, 0), (0.05, 0.04, 0.05), g.s("base"))
    pts = [(0, -0.10, 0), (0, -0.30, -0.04), (0, -0.48, -0.15), (0, -0.60, -0.32), (0, -0.66, -0.52), (0, -0.64, -0.68)]
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        m.cyl(a, b, 0.022 - i * 0.003, sw=g.s("base"), sides=4)
    return g.finish("weapon")


def stone_maul(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.22, 0), (0, -0.95, 0), 0.035, sw="wood.dark", sides=6)
    m.box((0, -1.0, 0), (0.28, 0.26, 0.42), g.s("base"))
    m.box((0, -1.0, 0.0), (0.30, 0.20, 0.10), "stone.dark")
    m.box((0, -1.0, 0.0), (0.24, 0.30, 0.30), "stone.mid")
    return g.finish("weapon")


def greatblade(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.22, 0), (0, -0.07, 0), 0.032, sw="grip", sides=6)
    m.box((0, 0.25, 0), (0.06, 0.05, 0.06), "gold")
    m.box((0, -0.08, 0), (0.06, 0.06, 0.44), "gold")
    m.gem((0.035, -0.08, 0), 0.035, "magic.holy")
    blade(m, (0, -0.10, 0), (0, -1.48, 0), 0.11, 0.022, g.s("base"), tip=0.12)
    m.box((0, -0.5, 0), (0.05, 0.6, 0.03), "gold.dark")
    return g.finish("weapon")


def claws(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.box((0, -0.04, 0.0), (0.13, 0.08, 0.14), "metal.dark")
    for dz in (-0.045, 0.0, 0.045):
        blade(m, (0, -0.06, dz), (0, -0.40, dz + 0.04), 0.03, 0.012, g.s("base"), curve=0.08, segs=2, tip=0.35)
    return g.finish("weapon")


def void_blade(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _hilt(g, m, 0.10, -0.075, 0.24, guard_sw="metal.dark")
    blade(m, (0, -0.09, 0), (0, -1.0, 0), 0.07, 0.016, g.s("base"), tip=0.16)
    m.box((0, -0.45, 0.0), (0.04, 0.62, 0.025), "magic.void")
    m.gem((0, -0.075, 0.0), 0.04, "magic.void")
    return g.finish("weapon")


def javelins(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.50, 0), (0, -0.78, 0), 0.022, sw="wood.mid", sides=4)
    m.cone((0, -0.78, 0), (0, -0.98, 0), 0.04, "metal.light", sides=4)
    m.box((0, 0.48, 0), (0.008, 0.10, 0.08), "feather.red")
    m.cyl((0, 0.06, 0), (0, -0.06, 0), 0.028, sw="leather.strap", sides=4)
    return g.finish("weapon")


def duskbow(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _bow(g, m, 0.82, 0.17, g.s("base"), "magic.gloom", r=0.036, spiky=True)
    m.gem((0, -0.03, 0), 0.04, "magic.gloom")
    return g.finish("weapon")


def heavy_ballista(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _crossbow(g, m, k=1.4, wood=g.s("base"), metal="metal.dark", gem="metal.grey")
    m.box((0, -0.1, -0.08), (0.05, 0.4, 0.08), "metal.dark")
    return g.finish("weapon")


def sunfire_crossbow(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    _crossbow(g, m, k=1.05, wood="wood.dark", metal=g.s("base"), gem="fire.orange")
    return g.finish("weapon")


def _special_staff(v, shaft, gem, prongs):
    g = Gear(v)
    m = g.part("socket_weapon")
    _staff_shaft(m, shaft)
    top = 0.74
    for i in range(prongs):
        ang = i * math.tau / prongs
        a = (math.cos(ang) * 0.04, math.sin(ang) * 0.04, top)
        b = (math.cos(ang) * 0.11, math.sin(ang) * 0.11, top + 0.12)
        c = (math.cos(ang) * 0.05, math.sin(ang) * 0.05, top + 0.24)
        m.cyl(a, b, 0.016, sw=g.s("base"), sides=4)
        m.cyl(b, c, 0.014, sw=g.s("base"), sides=4)
    m.gem((0, 0, top + 0.13), 0.06, gem)
    return g.finish("weapon")


def forbidden_staff(v):
    return _special_staff(v, "black", "magic.gloom", 4)


def eruption_staff(v):
    return _special_staff(v, "stone.dark", "lava", 3)


def tempest_staff(v):
    return _special_staff(v, "metal.grey", "magic.storm", 5)


# ------------------------------------------------------------------ off-hand and back
def tome(v):
    g = Gear(v)
    m = g.part("socket_offhand")
    m.box((0.06, -0.04, 0.05), (0.07, 0.22, 0.28), g.s("base"))       # cover
    m.box((0.06, -0.05, 0.05), (0.058, 0.21, 0.26), "canvas")          # pages
    m.box((0.098, -0.04, 0.05), (0.01, 0.08, 0.08), "gold")            # clasp emblem
    return g.finish("offhand")


def buckler(v):
    g = Gear(v)
    m = g.part("socket_offhand")
    m.cyl((0.05, -0.02, 0.05), (0.09, -0.02, 0.05), 0.2, sw=g.s("base"), sides=10)
    m.cyl((0.09, -0.02, 0.05), (0.12, -0.02, 0.05), 0.07, sw="team.base", sides=6)
    return g.finish("offhand")


def _cloak(m, length, top_w, bot_w, sw, trim):
    m.loft([(-length, bot_w, 0.022, 0, 0.09), (-length * 0.5, (top_w + bot_w) / 2, 0.022, 0, 0.04),
            (0.0, top_w, 0.022, 0, 0.0)], sides=4, sw=sw)
    m.box((0, 0.09, -length + 0.03), (bot_w * 2.05, 0.05, 0.05), trim)


def cape(v):
    g = Gear(v)
    m = g.part("socket_back")
    _cloak(m, 0.95, 0.2, 0.28, g.s("base"), "gold")
    m.box((0, 0.06, -0.3), (0.14, 0.03, 0.14), "gold")  # emblem
    return g.finish("cape")


def mantle(v):
    g = Gear(v)
    m = g.part("socket_back")
    _cloak(m, 0.6, 0.22, 0.27, g.s("base"), "gold")
    m.loft([(0.0, 0.24, 0.17, 0, -0.12), (0.1, 0.20, 0.15, 0, -0.12)], sides=8, sw=g.s("base"), cap0=False)
    return g.finish("cape")


def quiver(v):
    g = Gear(v)
    m = g.part("socket_back")
    mat = R(-25, "Y")
    m.loft([(-0.45, 0.07, 0.07), (0.12, 0.08, 0.08)], sides=6, sw=g.s("base"), mat=mat)
    for i, dx in enumerate((-0.03, 0.0, 0.03)):
        m.box((dx, 0.0, 0.17), (0.012, 0.05, 0.10), "feather.white", mat=mat)
    m.box((0, -0.06, -0.15), (0.06, 0.03, 0.7), "leather.strap", mat=R(40, "Y"))
    return g.finish("cape")


def pouch(v):
    g = Gear(v)
    m = g.part("socket_back")
    m.box((0.16, -0.02, -0.50), (0.14, 0.10, 0.16), g.s("base"))
    m.box((0.16, -0.02, -0.41), (0.15, 0.11, 0.04), "leather.strap")
    for dx in (-0.02, 0.02):
        m.box((0.16 + dx, -0.02, -0.36), (0.01, 0.04, 0.12), "feather.white")
    return g.finish("cape")


# ------------------------------------------------------------------ ammo (projectiles)
def arrow(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.30, 0), (0, -0.28, 0), 0.012, sw="wood.light", sides=4)
    m.cone((0, -0.28, 0), (0, -0.38, 0), 0.03, g.s("base"), sides=4)
    fl = g.s("accent") if g.spikes else "feather.white"
    m.box((0, 0.24, 0), (0.006, 0.10, 0.06), fl)
    m.box((0, 0.24, 0), (0.06, 0.10, 0.006), fl)
    return g.finish("ammo")


def bolt(v):
    g = Gear(v)
    m = g.part("socket_weapon")
    m.cyl((0, 0.15, 0), (0, -0.14, 0), 0.014, sw="wood.dark", sides=4)
    m.cone((0, -0.14, 0), (0, -0.23, 0), 0.032, g.s("base"), sides=4)
    m.box((0, 0.12, 0), (0.005, 0.06, 0.05), "metal.grey")
    m.box((0, 0.12, 0), (0.05, 0.06, 0.005), "metal.grey")
    return g.finish("ammo")


GENERATORS = {
    "dagger": dagger, "scimitar": scimitar, "longsword": longsword, "battleaxe": battleaxe, "warhammer": warhammer,
    "shortbow": shortbow, "longbow": longbow, "crossbow": crossbow, "throwing_knives": throwing_knives,
    "staff": staff, "wand": wand,
    "whip": whip, "stone_maul": stone_maul, "greatblade": greatblade, "claws": claws, "void_blade": void_blade,
    "javelins": javelins, "duskbow": duskbow, "heavy_ballista": heavy_ballista, "sunfire_crossbow": sunfire_crossbow,
    "forbidden_staff": forbidden_staff, "eruption_staff": eruption_staff, "tempest_staff": tempest_staff,
    "tome": tome, "buckler": buckler, "cape": cape, "mantle": mantle, "quiver": quiver, "pouch": pouch,
    "arrow": arrow, "bolt": bolt,
}
