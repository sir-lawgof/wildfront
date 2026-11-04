"""Armour generators: plate (melee), hide (ranged), robe (magic) for helm, body, legs, boots, gloves and shields.

Parts are modelled in place around the base body's rest pose (see characters/base_body.py), a little larger
than the body segments they cover. Every body piece carries a small team-coloured tabard/sash (team.* swatches).
"""
from lib import rig
from lib.mesh import T

from .common import PLANE_YZ, Gear, prism, ring_band, side_x, spike

SX = rig.SHOULDER_X
HX = rig.HIP_X


# ============================================================ PLATE (melee)

def plate_helm(v):
    g = Gear(v)
    m = g.part("head")
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    bulwark = g.variant == "bulwark_plate"
    w = 1.08 if bulwark else 1.0
    m.loft([(1.43, 0.15 * w, 0.15 * w), (1.50, 0.198 * w, 0.192 * w), (1.70, 0.205 * w, 0.198 * w),
            (1.83, 0.178 * w, 0.17 * w), (1.91, 0.10 * w, 0.095 * w)], sides=8, sw=[dark, base, base, light])
    # visor: eye slit and breaths
    m.box((0, -0.205 * w, 1.665), (0.27, 0.03, 0.035), "black")
    m.box((0, -0.212 * w, 1.60), (0.05, 0.03, 0.10), light)
    m.box((0, -0.205 * w, 1.72), (0.30, 0.03, 0.05), light)  # brow ridge
    if g.trims:
        m.box((0, 0.0, 1.915), (0.05, 0.36, 0.06), trim)      # crest ridge
        ring_band(m, 1.47, 0.205 * w, 0.198 * w, 0.04, trim)
    if g.spikes:
        if g.tier >= 7 or g.variant == "berserker_plate":
            for s in (1, -1):  # horns
                spike(m, (0.18 * s, 0.0, 1.80), (0.6 * s, 0.1, 0.75), 0.24, 0.045, g.s("accent", trim))
        else:
            m.box((0, 0.04, 1.97), (0.03, 0.28, 0.12), g.s("accent", trim), taper=(1.0, 0.6))  # fin
    if g.variant == "duelist_plate":
        m.box((0, 0.05, 1.96), (0.04, 0.2, 0.16), "feather.red", taper=(1.0, 0.3))
    return g.finish("helm")


def _tabard(m, z_top, z_bot, y, w=0.15):
    m.box((0, y, (z_top + z_bot) / 2), (w, 0.02, z_top - z_bot), "team.base")
    m.box((0, y - 0.004, z_bot + 0.02), (w + 0.01, 0.02, 0.04), "team.dark")


def plate_body(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    bulky = 1.06 if g.variant == "bulwark_plate" else 1.0
    c = g.part("chest")
    c.loft([(1.06, 0.212 * bulky, 0.142), (1.30, 0.255 * bulky, 0.16), (1.40, 0.222 * bulky, 0.142),
            (1.445, 0.12, 0.10)], sides=8, sw=[base, light, dark], cap0=False)
    c.box((0, -0.162, 1.22), (0.07, 0.03, 0.22), light)          # breastplate ridge
    s = g.part("spine")
    s.loft([(0.86, 0.205, 0.138), (1.12, 0.215, 0.142)], sides=8, sw=dark, cap0=False, cap1=False)
    _tabard(s, 1.0, 0.70, -0.15)
    if g.trims:
        ring_band(s, 0.88, 0.212, 0.144, 0.045, trim)
        c.box((0, -0.15, 1.40), (0.30, 0.03, 0.04), trim)
    for side in ("L", "R"):
        x = SX * side_x(side)
        ua = g.part("upperarm_" + side)
        # pauldron
        ua.loft([(1.20, 0.115, 0.11, x * 1.03, 0), (1.34, 0.125, 0.12, x * 1.03, 0), (1.42, 0.07, 0.07, x, 0)],
                sides=6, sw=[light, base], cap0=False)
        ua.loft([(1.04, 0.074, 0.074, x, 0), (1.20, 0.08, 0.08, x, 0)], sides=6, sw=dark, cap0=False, cap1=False)
        if g.trims:
            ring_band(ua, 1.205, 0.12, 0.115, 0.03, trim, cx=x * 1.03, sides=6)
        if g.spikes:
            spike(ua, (x * 1.15, 0, 1.36), (side_x(side) * 0.7, 0, 0.7), 0.16, 0.035, g.s("accent", trim))
        fa = g.part("forearm_" + side)
        fa.loft([(0.79, 0.07, 0.07, x, 0), (1.08, 0.074, 0.074, x, 0)], sides=6, sw=base, cap0=False, cap1=False)
        if g.trims:
            ring_band(fa, 0.80, 0.075, 0.075, 0.03, trim, cx=x, sides=6)
    return g.finish("armour_body")


def plate_legs(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    h = g.part("hips")
    h.loft([(0.62, 0.225, 0.152), (0.78, 0.205, 0.14), (0.92, 0.195, 0.132)], sides=8, sw=[base, dark])
    if g.trims:
        ring_band(h, 0.635, 0.228, 0.155, 0.035, trim)
    for side in ("L", "R"):
        x = HX * side_x(side)
        th = g.part("thigh_" + side)
        th.loft([(0.42, 0.098, 0.10, x, 0), (0.62, 0.112, 0.112, x, 0), (0.70, 0.116, 0.115, x, 0)],
                sides=6, sw=base, cap1=False)
        sh = g.part("shin_" + side)
        sh.loft([(0.10, 0.08, 0.085, x, 0), (0.30, 0.09, 0.094, x, 0), (0.47, 0.097, 0.10, x, 0)], sides=6,
                sw=[base, light])
        sh.box((x, -0.10, 0.46), (0.12, 0.05, 0.10), light, taper=(0.8, 0.8))  # knee cop
        if g.trims:
            ring_band(sh, 0.12, 0.085, 0.09, 0.03, trim, cx=x, sides=6)
        if g.spikes:
            spike(sh, (x, -0.12, 0.47), (0, -1, 0.2), 0.1, 0.03, g.s("accent", trim))
    return g.finish("armour_legs")


def plate_boots(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    for side in ("L", "R"):
        x = HX * side_x(side)
        f = g.part("foot_" + side)
        f.box((x, -0.045, 0.065), (0.145, 0.29, 0.13), base, taper=(0.95, 0.85))
        f.box((x, -0.18, 0.04), (0.135, 0.07, 0.08), light, taper=(1.0, 0.7))
        f.box((x, 0.0, 0.14), (0.15, 0.17, 0.05), dark)  # ankle cuff
        if g.trims:
            f.box((x, -0.045, 0.012), (0.15, 0.30, 0.024), trim)
    return g.finish("boots")


def kiteshield(v):
    g = Gear(v)
    m = g.part("socket_offhand")
    base, dark, trim = g.s("base"), g.s("dark"), g.s("trim")
    s = 1.12 if g.variant == "bulwark_plate" else 1.0
    kite = [(-0.24 * s, 0.32 * s), (-0.25 * s, 0.06 * s), (0.0, -0.46 * s), (0.25 * s, 0.06 * s), (0.24 * s, 0.32 * s)]
    # outline is (u = Y, v = Z), counter-clockwise seen from +X (the outside of the left arm)
    kite_ccw = kite
    mat = T(0.075, -0.02, 0.06) @ PLANE_YZ
    prism(m, kite_ccw, 0.05, base, dark, dark, mat=mat)
    inner = [(u * 0.55, z * 0.55 + 0.03) for u, z in kite_ccw]
    prism(m, inner, 0.02, "team.base", mat=T(0.105, -0.02, 0.06) @ PLANE_YZ)  # team emblem
    if g.trims:
        border = [(u * 1.08, z * 1.06) for u, z in kite_ccw]
        prism(m, border, 0.03, trim, mat=T(0.06, -0.02, 0.06) @ PLANE_YZ)
    if g.spikes:
        spike(m, (0.12, -0.02, 0.09), (1, 0, 0), 0.12, 0.04, g.s("accent", trim))
    m.box((0.035, 0.0, 0.0), (0.05, 0.05, 0.12), "grip")  # strap
    return g.finish("offhand")


def defender(v):
    g = Gear(v)
    m = g.part("socket_offhand")
    base, dark, trim = g.s("base"), g.s("dark"), g.s("trim")
    shape = [(0.12, 0.18), (-0.14, 0.16), (-0.18, -0.02), (-0.06, -0.20), (0.14, -0.12)]
    prism(m, shape, 0.05, base, dark, dark, mat=T(0.075, -0.05, 0.05) @ PLANE_YZ)
    spike(m, (0.075, -0.18, 0.05), (0, -1, 0.1), 0.16, 0.03, g.s("light"))
    if g.trims:
        prism(m, [(u * 1.12, z * 1.12) for u, z in shape], 0.03, trim, mat=T(0.06, -0.05, 0.05) @ PLANE_YZ)
    if g.spikes:
        spike(m, (0.1, -0.05, 0.22), (0.2, 0, 1), 0.12, 0.03, g.s("accent", trim))
    return g.finish("offhand")


# ============================================================ HIDE (ranged)

def hide_coif(v):
    g = Gear(v)
    m = g.part("head")
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    # hood over the crown, back and sides; the face stays open
    m.loft([(1.69, 0.198, 0.192, 0, 0.005), (1.80, 0.184, 0.176, 0, 0.01), (1.875, 0.135, 0.125, 0, 0.01),
            (1.91, 0.06, 0.06, 0, 0.01)], sides=8, sw=base, cap0=False)
    m.box((0, 0.085, 1.60), (0.40, 0.19, 0.34), base)                 # back of the hood
    for s in (1, -1):
        m.box((0.19 * s, -0.04, 1.58), (0.04, 0.24, 0.26), dark)    # cheek flaps
    m.box((0, -0.06, 1.44), (0.36, 0.22, 0.07), dark)                # neck drape
    m.box((0, -0.19, 1.745), (0.36, 0.04, 0.05), light)              # brow edge
    if g.trims:
        m.box((0, -0.205, 1.745), (0.38, 0.02, 0.025), trim)
    if g.spikes:
        for s in (1, -1):
            spike(m, (0.12 * s, 0.05, 1.86), (0.5 * s, 0.6, 0.6), 0.16, 0.035, g.s("accent", trim))
    if g.variant == "eagle_eye_coif":
        m.box((0, 0.06, 1.93), (0.04, 0.22, 0.10), "feather.white", taper=(1, 0.3))
    return g.finish("helm")


def hide_body(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    c = g.part("chest")
    c.loft([(1.07, 0.205, 0.133), (1.31, 0.242, 0.148), (1.395, 0.21, 0.13),
            (1.43, 0.115, 0.095)], sides=8, sw=[base, light, dark], cap0=False)
    c.box((0.0, -0.13, 1.26), (0.42, 0.02, 0.05), "leather.strap")    # bandolier strap
    s = g.part("spine")
    s.loft([(0.86, 0.198, 0.13), (1.12, 0.205, 0.134)], sides=8, sw=base, cap0=False, cap1=False)
    ring_band(s, 0.90, 0.205, 0.137, 0.045, "leather.strap")
    _tabard(s, 0.98, 0.74, -0.142, w=0.12)
    if g.tier == 3 or g.trims:  # studs (tier 3) / trims
        for xx in (-0.12, 0.12):
            c.box((xx, -0.152, 1.20), (0.035, 0.02, 0.035), trim)
    for side in ("L", "R"):
        x = SX * side_x(side)
        ua = g.part("upperarm_" + side)
        ua.loft([(1.12, 0.074, 0.074, x, 0), (1.30, 0.088, 0.086, x, 0), (1.39, 0.065, 0.065, x, 0)],
                sides=6, sw=[base, light], cap0=False)
        if g.trims:
            ua.loft([(1.26, 0.105, 0.1, x * 1.04, 0), (1.38, 0.1, 0.095, x * 1.04, 0)], sides=6, sw=trim,
                    cap0=False)
        if g.spikes:
            spike(ua, (x * 1.12, 0, 1.36), (side_x(side) * 0.6, 0.2, 0.8), 0.13, 0.03, g.s("accent", trim))
    return g.finish("armour_body")


def hide_chaps(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    h = g.part("hips")
    h.loft([(0.68, 0.18, 0.122), (0.80, 0.198, 0.125), (0.92, 0.19, 0.12)], sides=8, sw=[dark, base])
    ring_band(h, 0.885, 0.195, 0.125, 0.04, "leather.strap")
    for side in ("L", "R"):
        x = HX * side_x(side)
        th = g.part("thigh_" + side)
        th.loft([(0.42, 0.093, 0.096, x, 0), (0.62, 0.108, 0.108, x, 0), (0.74, 0.115, 0.113, x, 0)],
                sides=6, sw=base, cap1=False)
        sh = g.part("shin_" + side)
        sh.loft([(0.10, 0.075, 0.08, x, 0), (0.30, 0.085, 0.088, x, 0), (0.47, 0.092, 0.095, x, 0)], sides=6,
                sw=[base, base])
        sh.box((x, -0.09, 0.44), (0.1, 0.03, 0.1), light)   # knee patch
        if g.trims:
            th.box((x + 0.1 * side_x(side), 0, 0.6), (0.02, 0.06, 0.3), trim)  # side stripe
    return g.finish("armour_legs")


def hide_vambraces(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    for side in ("L", "R"):
        x = SX * side_x(side)
        fa = g.part("forearm_" + side)
        fa.loft([(0.80, 0.068, 0.068, x, 0), (0.98, 0.076, 0.076, x, 0)], sides=6, sw=base)
        ring_band(fa, 0.85, 0.08, 0.08, 0.025, "leather.strap", cx=x, sides=6)
        hd = g.part("hand_" + side)
        hd.box((x, -0.005, 0.745), (0.118, 0.133, 0.155), dark)           # glove
        hd.box((x - 0.035 * side_x(side), -0.07, 0.775), (0.055, 0.055, 0.075), dark)
        if g.trims:
            ring_band(fa, 0.96, 0.08, 0.08, 0.025, trim, cx=x, sides=6)
        if g.spikes:
            spike(fa, (x + 0.07 * side_x(side), 0, 0.9), (side_x(side), 0, 0.2), 0.09, 0.025, g.s("accent", trim))
    return g.finish("gloves")


def hide_boots(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    for side in ("L", "R"):
        x = HX * side_x(side)
        f = g.part("foot_" + side)
        f.box((x, -0.045, 0.06), (0.14, 0.28, 0.12), dark, taper=(0.95, 0.85))
        f.box((x, -0.17, 0.035), (0.13, 0.065, 0.07), dark, taper=(1.0, 0.7))
        f.box((x, 0.0, 0.17), (0.15, 0.16, 0.14), base)      # shaft
        f.box((x, 0.0, 0.245), (0.16, 0.17, 0.035), light)   # fold-over cuff
        if g.trims:
            f.box((x, -0.08, 0.17), (0.02, 0.02, 0.12), trim)
    return g.finish("boots")


# ============================================================ ROBE (magic)

def robe_hat(v):
    g = Gear(v)
    m = g.part("head")
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    m.loft([(1.73, 0.31, 0.30), (1.765, 0.31, 0.30)], sides=10, sw=dark)                # brim
    m.loft([(1.76, 0.19, 0.185), (1.90, 0.15, 0.145, 0, 0.02), (2.04, 0.09, 0.085, 0, 0.06),
            (2.14, 0.0, 0.0, 0, 0.14)], sides=8, sw=base)                               # crooked cone
    ring_band(m, 1.795, 0.193, 0.188, 0.045, trim if g.trims else dark)
    if g.spikes:
        m.gem((0, -0.19, 1.80), 0.045, g.s("accent", trim))
        m.gem((0, 0.15, 2.15), 0.04, g.s("accent", trim))
    return g.finish("helm")


def robe_top(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    c = g.part("chest")
    c.loft([(1.07, 0.208, 0.134), (1.31, 0.244, 0.148), (1.395, 0.212, 0.13),
            (1.45, 0.13, 0.11)], sides=8, sw=[base, base, trim if g.trims else dark], cap0=False)
    c.box((0, -0.142, 1.22), (0.13, 0.02, 0.32), "team.base")  # team stole
    s = g.part("spine")
    s.loft([(0.86, 0.2, 0.13), (1.12, 0.207, 0.134)], sides=8, sw=base, cap0=False, cap1=False)
    ring_band(s, 0.93, 0.208, 0.138, 0.05, trim if g.trims else dark)
    s.box((0, -0.138, 0.88), (0.13, 0.02, 0.32), "team.base")
    for side in ("L", "R"):
        x = SX * side_x(side)
        ua = g.part("upperarm_" + side)
        ua.loft([(1.05, 0.082, 0.08, x, 0), (1.30, 0.088, 0.086, x, 0), (1.39, 0.066, 0.066, x, 0)],
                sides=6, sw=base, cap0=False)
        fa = g.part("forearm_" + side)
        fa.loft([(0.80, 0.115, 0.115, x, 0), (0.92, 0.09, 0.09, x, 0), (1.08, 0.08, 0.08, x, 0)],
                sides=6, sw=[base, base], cap1=False)                       # bell sleeve
        ring_band(fa, 0.81, 0.12, 0.12, 0.035, trim if g.trims else dark, cx=x, sides=6)
        if g.spikes:
            ua.loft([(1.30, 0.11, 0.105, x * 1.04, 0), (1.40, 0.09, 0.085, x * 1.04, 0)], sides=6,
                    sw=g.s("accent", trim), cap0=False)
    return g.finish("armour_body")


def robe_bottom(v):
    g = Gear(v)
    base, dark, light, trim = g.s("base"), g.s("dark"), g.s("light"), g.s("trim")
    h = g.part("hips")
    h.loft([(0.30, 0.255, 0.20), (0.55, 0.225, 0.165), (0.78, 0.198, 0.13), (0.92, 0.19, 0.12)], sides=10,
           sw=[base, base, dark])
    ring_band(h, 0.32, 0.258, 0.203, 0.045, trim if g.trims else dark, sides=10)
    if g.spikes:
        h.box((0, -0.19, 0.55), (0.06, 0.04, 0.4), g.s("accent", trim))
    for side in ("L", "R"):
        x = HX * side_x(side)
        sh = g.part("shin_" + side)
        sh.loft([(0.09, 0.072, 0.076, x, 0), (0.30, 0.082, 0.085, x, 0)], sides=6, sw=dark, cap1=False)
    return g.finish("armour_legs")


def robe_gloves(v):
    g = Gear(v)
    base, dark, trim = g.s("base"), g.s("dark"), g.s("trim")
    for side in ("L", "R"):
        x = SX * side_x(side)
        hd = g.part("hand_" + side)
        hd.box((x, -0.005, 0.745), (0.116, 0.131, 0.152), dark if g.tier < 5 else base)
        hd.box((x - 0.035 * side_x(side), -0.07, 0.775), (0.054, 0.054, 0.074), dark if g.tier < 5 else base)
        hd.box((x, 0.0, 0.83), (0.14, 0.15, 0.05), trim if g.trims else base)
    return g.finish("gloves")


def robe_boots(v):
    g = Gear(v)
    base, dark, trim = g.s("base"), g.s("dark"), g.s("trim")
    for side in ("L", "R"):
        x = HX * side_x(side)
        f = g.part("foot_" + side)
        f.box((x, -0.04, 0.06), (0.135, 0.27, 0.12), dark, taper=(0.9, 0.8))
        f.loft([(0.0, 0.05, 0.035), (0.09, 0.0, 0.0, 0.0, 0.03)], sides=4, sw=dark,
               mat=T(x, -0.17, 0.04) @ _forward())
        if g.trims:
            f.box((x, 0.0, 0.125), (0.15, 0.16, 0.03), trim)
    return g.finish("boots")


def _forward():
    from mathutils import Matrix
    return Matrix.Rotation(1.5708, 4, "X")  # local +Z -> world -Y


GENERATORS = {
    "plate_helm": plate_helm, "plate_body": plate_body, "plate_legs": plate_legs, "plate_boots": plate_boots,
    "kiteshield": kiteshield, "defender": defender,
    "hide_coif": hide_coif, "hide_body": hide_body, "hide_chaps": hide_chaps, "hide_vambraces": hide_vambraces,
    "hide_boots": hide_boots,
    "robe_hat": robe_hat, "robe_top": robe_top, "robe_bottom": robe_bottom, "robe_gloves": robe_gloves,
    "robe_boots": robe_boots,
}
