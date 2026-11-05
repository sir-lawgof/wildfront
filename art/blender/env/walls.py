"""Wall lines (autotiled per tile), wall-face decorations, ramparts and border pieces for every kit.

Wall tile pieces (1x1, line along X): straight (2 opposite neighbours), end (neighbour on -X only; the +X end
is the open, finished end), join (corner / T / cross / single). Wall styles: "wall" (the kit's wall), and the
per-rectangle dressing styles "hedge" + "arch" (castle) and "palisade" (mire)."""
from lib.mesh import MeshBuilder, T, R

from .common import KITS, STYLE, S, box, finish, module, rng, rock

HW = 0.49  # half width of a solid tile piece (fills its tile, tiny gap so neighbours don't z-fight)


# ------------------------------------------------------------------ wall bodies per kit
def _frost_wall(m, kind, r, h):
    wall, dark, light, snow = S("frost", "wall"), S("frost", "wall_dark"), S("frost", "wall_light"), S("frost", "snow")
    box(m, (0, 0, 0.12), (1.02, 1.02, 0.24), dark)                          # plinth
    base = h - 0.35
    box(m, (0, 0, 0.24 + (base - 0.24) / 2), (0.98, 0.96, base - 0.24), wall)
    box(m, (0, 0, 0.9), (1.0, 0.99, 0.08), light)                           # masonry course
    # jagged, broken top: three teeth of random height, snow-capped
    for i, x in enumerate((-0.33, 0.0, 0.33)):
        th = r.uniform(0.15, 0.42)
        if kind == "end" and i == 2:
            th = 0.0  # snapped-off end
        if kind == "end" and i == 1:
            th *= 0.5
        if th <= 0.02:
            continue
        box(m, (x, 0, base + th / 2), (0.33, 0.96, th), wall)
        box(m, (x, 0, base + th + 0.03), (0.3, 0.9, 0.06), snow)
    box(m, (0, 0, base + 0.02), (0.96, 0.94, 0.05), snow)
    if kind == "end":
        rock(m, (0.3, r.uniform(-0.2, 0.2), base - 0.02), 0.16, dark, h=0.14)


def _ember_wall(m, kind, r, h):
    wall, dark, light, beam = S("ember", "wall"), S("ember", "wall_dark"), S("ember", "wall_light"), S("ember", "wall_trim")
    box(m, (0, 0, 0.09), (1.0, 1.02, 0.18), dark)
    box(m, (0, 0, (h - 0.14) / 2 + 0.09), (0.98, 0.96, h - 0.32), wall)
    box(m, (0, 0, h - 0.12), (0.98, 0.96, 0.14), light, taper=(1.0, 0.7))     # rounded top
    for y in (-0.5, 0.5):                                                    # protruding beam ends
        for x in ((-0.25, 0.25) if kind != "join" else (0.0,)):
            box(m, (x, y * 1.08, h - 0.42), (0.1, 0.1, 0.09), beam)
    if kind == "end":
        box(m, (0.45, 0, h / 2), (0.08, 0.98, h - 0.1), light)


def _mire_wall(m, kind, r, h):
    wall, dark, light, moss = S("mire", "wall"), S("mire", "wall_dark"), S("mire", "wall_light"), S("mire", "wall_trim")
    wood = S("mire", "wood")
    box(m, (0, 0, 0.12), (1.02, 1.02, 0.24), dark)
    box(m, (0, 0, h / 2 + 0.06), (0.98, 0.96, h - 0.12), wall)
    box(m, (0, 0, 1.05), (1.0, 1.0, 0.12), wood)                              # timber band
    for x in (-0.3, 0.3):
        mh = r.uniform(0.05, 0.14)
        box(m, (x, 0, h + mh / 2), (0.42, 0.9, mh), moss)                     # moss cap
    if kind == "end":
        box(m, (0.46, 0, h / 2), (0.1, 0.9, h - 0.1), wood)


def _castle_wall(m, kind, r, h):
    wall, dark, light = S("castle", "wall"), S("castle", "wall_dark"), S("castle", "wall_light")
    box(m, (0, 0, 0.1), (1.02, 1.02, 0.2), dark)
    body = h - 0.25
    box(m, (0, 0, body / 2 + 0.05), (0.98, 0.96, body - 0.1), wall)
    box(m, (0, 0, 1.25), (1.0, 0.99, 0.07), light)                            # string course
    box(m, (0, 0, body + 0.01), (0.98, 0.96, 0.04), light)
    merl = [(-0.27, -0.36), (0.27, -0.36), (-0.27, 0.36), (0.27, 0.36)]
    if kind == "join":
        merl = [(-0.33, -0.33), (0.33, -0.33), (-0.33, 0.33), (0.33, 0.33)]
    for x, y in merl:
        box(m, (x, y, body + 0.13), (0.3, 0.24, 0.24), wall)
    if kind == "end":
        box(m, (0.44, 0, body / 2), (0.12, 1.0, body), light)                 # pilaster


def _hedge(m, kind, r, h):
    leaf, dark = S("castle", "foliage"), S("castle", "dark")
    box(m, (0, 0, 0.06), (0.9, 0.9, 0.12), dark)
    box(m, (0, 0, 0.75), (0.98, 0.96, 1.26), leaf, taper=(0.96, 0.94))
    box(m, (0, 0, 1.45), (0.92, 0.88, 0.14), leaf, taper=(0.9, 0.85))
    if kind == "end":
        box(m, (0.0, 0, 1.56), (0.5, 0.5, 0.1), leaf)


def _arch(m, kind, r, h):
    wall, dark, light = S("castle", "pillar"), S("castle", "pillar_dark"), S("castle", "wall_light")
    box(m, (0, 0, 0.12), (1.02, 1.02, 0.24), dark)
    box(m, (0, 0, (h - 0.2) / 2 + 0.12), (0.98, 0.96, h - 0.2), wall)
    # arch relief on both faces (reads as a sealed archway, still solid)
    for y in (-0.5, 0.5):
        box(m, (0, y, 0.85), (0.56, 0.04, 1.2), dark)
        box(m, (0, y, 1.5), (0.7, 0.05, 0.12), light)
    top = r.uniform(0.0, 0.3) if kind != "end" else 0.0
    if top > 0.05:
        box(m, (r.uniform(-0.2, 0.2), 0, h - 0.08 + top / 2), (0.5, 0.9, top), wall)


def _palisade(m, kind, r, h):
    wood, dark, rope = S("mire", "wood"), S("mire", "dark"), S("mire", "rope")
    for row, y in enumerate((-0.24, 0.24)):
        for i, x in enumerate((-0.33, 0.0, 0.33)):
            lh = h - r.uniform(0.0, 0.25)
            m.loft([(0.0, 0.17, 0.17, x, y), (lh, 0.16, 0.16, x, y), (lh + 0.18, 0.0, 0.0, x, y)], sides=5,
                   sw=[wood, dark])
    box(m, (0, -0.42, 1.0), (1.0, 0.06, 0.1), rope)
    box(m, (0, 0.42, 1.0), (1.0, 0.06, 0.1), rope)


BODIES = {("frost", "wall"): _frost_wall, ("ember", "wall"): _ember_wall, ("mire", "wall"): _mire_wall,
          ("castle", "wall"): _castle_wall, ("castle", "hedge"): _hedge, ("castle", "arch"): _arch,
          ("mire", "palisade"): _palisade}


# ------------------------------------------------------------------ face decorations (-Y face)
def _faces(kit):
    """Returns {variant: builder(m, r)} for decorations on an exposed wall face. They protrude <= 0.1."""
    if kit == "frost":
        def icicles(m, r):
            for x in (-0.3, -0.1, 0.15, 0.32):
                l = r.uniform(0.12, 0.3)
                m.cone((x, -0.52, 1.28), (x, -0.52, 1.28 - l), 0.03, S("frost", "icicle"), sides=4)
            box(m, (0, -0.53, 1.31), (0.9, 0.06, 0.06), S("frost", "snow"))

        def banner(m, r):
            box(m, (0, -0.55, 1.42), (0.5, 0.05, 0.04), S("frost", "wood"))
            m.poly([(-0.2, -0.56, 1.4), (0.2, -0.56, 1.4), (0.2, -0.56, 0.75), (0.05, -0.56, 0.85), (-0.2, -0.56, 0.7)],
                   S("frost", "cloth"))
            m.poly([(-0.2, -0.555, 0.7), (0.05, -0.555, 0.85), (0.2, -0.555, 0.75), (0.2, -0.555, 1.4), (-0.2, -0.555, 1.4)],
                   S("frost", "cloth"))

        def slit(m, r):
            box(m, (0, -0.5, 0.95), (0.08, 0.04, 0.4), "common.black")
            box(m, (0, -0.52, 0.72), (0.3, 0.06, 0.06), S("frost", "wall_light"))
        return {"icicles": icicles, "banner": banner, "slit": slit}
    if kit == "ember":
        def vent(m, r):
            box(m, (0.2, -0.5, 1.05), (0.16, 0.04, 0.16), S("ember", "dark"))
            box(m, (-0.25, -0.5, 1.05), (0.16, 0.04, 0.16), S("ember", "dark"))

        def lantern(m, r):
            box(m, (0, -0.54, 1.3), (0.04, 0.1, 0.04), "common.metal_dark")
            box(m, (0, -0.55, 1.15), (0.12, 0.08, 0.16), "common.glow_fire")
            box(m, (0, -0.545, 1.25), (0.14, 0.09, 0.04), "common.metal_dark")

        def rug(m, r):
            box(m, (0, -0.52, 1.0), (0.5, 0.03, 0.7), S("ember", "rug"))
            box(m, (0, -0.535, 1.0), (0.4, 0.02, 0.6), S("ember", "cloth"))
        return {"vent": vent, "lantern": lantern, "rug": rug}
    if kit == "mire":
        def vines(m, r):
            for x in (-0.3, 0.05, 0.3):
                l = r.uniform(0.6, 1.3)
                box(m, (x, -0.51, 1.75 - l / 2), (0.08, 0.03, l), S("mire", "foliage"))

        def slit(m, r):
            box(m, (0, -0.5, 1.35), (0.08, 0.04, 0.32), "common.black")

        def roots(m, r):
            for x in (-0.25, 0.2):
                box(m, (x, -0.53, 0.3), (0.12, 0.06, 0.6), S("mire", "root"), taper=(0.5, 0.5))
        return {"vines": vines, "slit": slit, "roots": roots}

    def slit(m, r):
        box(m, (0, -0.5, 1.0), (0.08, 0.04, 0.38), "common.black")

    def banner(m, r):  # team-tinted banner (common.banner cells take the friend/foe colour)
        box(m, (0, -0.55, 1.6), (0.5, 0.06, 0.05), "common.wood_dark")
        box(m, (0, -0.56, 1.15), (0.38, 0.03, 0.85), "common.banner")
        box(m, (0, -0.575, 1.2), (0.16, 0.02, 0.3), "common.gold")

    def plaque(m, r):
        box(m, (0, -0.52, 1.0), (0.3, 0.05, 0.34), S("castle", "metal"), taper=(1.0, 0.8))
    return {"slit": slit, "banner": banner, "plaque": plaque}


# ------------------------------------------------------------------ ramparts (2 x 1 slices)
def _rampart(kit, kind, r):
    m = MeshBuilder()
    h = STYLE[kit]["rampart_h"]
    wall, dark, light, trim = S(kit, "wall"), S(kit, "wall_dark"), S(kit, "wall_light"), S(kit, "wall_trim")
    box(m, (0, 0, 0.12), (1.02, 2.02, 0.24), dark)
    box(m, (0, 0, h / 2), (0.98, 1.96, h - 0.1), wall)
    box(m, (0, 0, h - 0.04), (0.98, 1.5, 0.04), S(kit, "path") if kit != "frost" else S("frost", "snow"))  # walkway
    for y in (-0.86, 0.86):
        box(m, (0, y, h + 0.12), (0.98, 0.24, 0.24), wall)                  # parapet
        for x in (-0.25, 0.25):
            if kind == "end" and x > 0 and kit == "frost":
                continue
            box(m, (x, y, h + 0.36), (0.26, 0.24, 0.24), wall)               # merlons
            if kit == "frost":
                box(m, (x, y, h + 0.5), (0.24, 0.22, 0.04), S("frost", "snow"))
    box(m, (0, 0, 1.0), (1.0, 1.99, 0.07), light)
    if kind == "end":
        box(m, (0.46, 0, h / 2), (0.1, 1.6, h - 0.3), trim if kit != "frost" else light)
    return m


def _buttress(kit):
    m = MeshBuilder()
    box(m, (0, -0.52, 0.65), (0.36, 0.08, 1.3), S(kit, "wall_dark"), taper=(0.8, 0.6))
    if kit == "frost":
        box(m, (0, -0.52, 1.32), (0.32, 0.08, 0.05), S("frost", "snow"))
    return m


# ------------------------------------------------------------------ border pieces (front -Y faces the arena)
def _border(kit, kind, r):
    m = MeshBuilder()
    h = STYLE[kit]["border_h"]
    wall, dark, light, trim = S(kit, "wall"), S(kit, "wall_dark"), S(kit, "wall_light"), S(kit, "wall_trim")
    if kit == "mire" and kind != "corner":
        # dead-tree and root wall with a rotting palisade
        box(m, (0, 0, 0.15), (1.02, 1.02, 0.3), S("mire", "root"))
        for i, (x, y) in enumerate([(-0.25, 0.22), (0.28, 0.1), (-0.05, -0.28)]):
            th = h + r.uniform(-0.3, 0.6)
            m.loft([(0.0, 0.2, 0.2, x, y), (th * 0.6, 0.15, 0.15, x, y), (th, 0.07, 0.07, x + 0.05, y)], sides=4,
                   sw=S("mire", "pillar"))
        box(m, (0, 0, h * 0.45), (1.0, 0.98, h * 0.9), S("mire", "pillar_dark"))
        if kind == "gate":
            box(m, (0, -0.5, 0.9), (0.6, 0.05, 1.4), S("mire", "wood"))
        return m
    box(m, (0, 0, 0.12), (1.02, 1.02, 0.24), dark)
    box(m, (0, 0, h / 2), (0.98, 0.98, h - 0.1), wall)
    box(m, (0, 0, h * 0.55), (1.0, 1.0, 0.08), light)
    if kit == "frost":
        for x in (-0.3, 0.05, 0.32):
            th = r.uniform(0.1, 0.45)
            box(m, (x, 0, h - 0.05 + th / 2), (0.3, 0.98, th), wall)
            box(m, (x, 0, h - 0.05 + th + 0.03), (0.28, 0.92, 0.06), S("frost", "snow"))
        if kind != "gate":
            box(m, (0, -0.42, 0.35), (0.96, 0.18, 0.7), S("frost", "snow"), taper=(1.0, 0.2))  # drift (inside the tile)
    elif kit == "ember":
        box(m, (0, 0, h - 0.02), (0.98, 0.98, 0.12), light, taper=(1.0, 0.7))
        for x in (-0.25, 0.25):
            box(m, (x, -0.53, h - 0.4), (0.1, 0.08, 0.09), trim)
    else:  # castle
        for x, y in [(-0.27, -0.36), (0.27, -0.36), (-0.27, 0.36), (0.27, 0.36)]:
            box(m, (x, y, h + 0.12), (0.3, 0.24, 0.24), wall)
    if kind == "gate":  # sealed decorative arch on the arena face
        box(m, (0, -0.5, 0.75), (0.62, 0.05, 1.3), S(kit, "wood") if kit != "frost" else S("frost", "wood"))
        box(m, (0, -0.52, 1.45), (0.78, 0.07, 0.14), light)
        box(m, (0, -0.53, 0.75), (0.04, 0.04, 1.2), "common.metal_dark")
    if kind == "corner":
        box(m, (0, 0, h + 0.2), (0.7, 0.7, 0.4), wall)                        # corner turret cap
        box(m, (0, 0, h + 0.42), (0.74, 0.74, 0.06), light if kit != "frost" else S("frost", "snow"))
    return m


# ------------------------------------------------------------------ registry
def _wall_assets(kit, style):
    out = []
    h = STYLE[kit]["wall_h"] if style not in ("hedge",) else 1.55
    body = BODIES[(kit, style)]
    for kind, variants in (("straight", 2), ("end", 1), ("join", 1)):
        for v in range(1, variants + 1):
            aid = "env_%s_%s_%s%s" % (kit, style, kind, "_v%d" % v if variants > 1 else "")

            def build(aid=aid, kind=kind):
                m = MeshBuilder()
                body(m, kind, rng(aid), h)
                finish(m)
            out.append(module(aid, build, "wall", kit=kit, style=style, kind=kind))
    return out


def assets():
    out = []
    for kit in KITS:
        out += _wall_assets(kit, "wall")
        for name, fn in _faces(kit).items():
            aid = "env_%s_face_%s" % (kit, name)

            def build(fn=fn, aid=aid):
                m = MeshBuilder()
                fn(m, rng(aid))
                finish(m)
            out.append(module(aid, build, "face", kit=kit, open_ok=True))
        for kind in ("mid", "end"):
            for v in ((1, 2) if kind == "mid" else (1,)):
                aid = "env_%s_rampart_%s%s" % (kit, kind, "_v%d" % v if kind == "mid" else "")
                out.append(module(aid, (lambda kit=kit, kind=kind, aid=aid: finish(_rampart(kit, kind, rng(aid)))),
                                  "rampart", kit=kit, kind=kind))
        aid = "env_%s_rampart_buttress" % kit
        out.append(module(aid, (lambda kit=kit: finish(_buttress(kit))), "face", kit=kit))
        for kind in ("straight_v1", "straight_v2", "corner", "gate"):
            aid = "env_%s_border_%s" % (kit, kind)
            k = kind.split("_")[0]
            out.append(module(aid, (lambda kit=kit, k=k, aid=aid: finish(_border(kit, k, rng(aid)))), "border",
                              kit=kit, kind=k))
    out += _wall_assets("castle", "hedge") + _wall_assets("castle", "arch") + _wall_assets("mire", "palisade")
    return out
