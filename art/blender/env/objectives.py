"""Objectives and gameplay markers (docs/ENVIRONMENT.md section 8).

The obelisk stands on a walkable capture tile, so its themed base is a flat rune plate (<= 0.25 tall, feet stay
visible) and its crystal floats high above (>= 1.7): it reads as a landmark without looking like a blocker."""
import math

from lib.mesh import MeshBuilder, T

from .common import KITS, S, box, finish, module, rng


def obelisk_base(kit):
    m = MeshBuilder()
    m.loft([(0.0, 0.48, 0.48), (0.08, 0.44, 0.44)], sides=8, sw=S(kit, "pillar_dark"))
    m.loft([(0.08, 0.3, 0.3), (0.16, 0.26, 0.26)], sides=8, sw=S(kit, "pillar"))
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        box(m, (math.cos(ang) * 0.36, math.sin(ang) * 0.36, 0.12), (0.12, 0.12, 0.08), "common.rune")
    return m


def crystal():
    m = MeshBuilder()
    m.loft([(1.75, 0.0, 0.0), (2.1, 0.2, 0.2), (2.45, 0.16, 0.16), (2.65, 0.0, 0.0)], sides=6, sw="common.crystal")
    for a in range(3):  # orbiting shards
        ang = a * math.tau / 3
        m.gem((math.cos(ang) * 0.32, math.sin(ang) * 0.32, 2.1), 0.05, "common.crystal_dark", h=0.1)
    return m


def altar():
    m = MeshBuilder()
    box(m, (0, 0, 0.1), (0.96, 0.96, 0.2), "common.altar_dark")
    box(m, (0, 0, 0.5), (0.7, 0.6, 0.6), "common.altar", taper=(0.85, 0.85))
    box(m, (0, 0, 0.85), (0.9, 0.8, 0.12), "common.altar")
    box(m, (0, 0, 0.92), (0.4, 0.4, 0.02), "common.rune")
    return m


def rune():
    m = MeshBuilder()
    m.loft([(0.0, 0.3, 0.3), (0.06, 0.26, 0.26)], sides=6, sw="common.altar_dark")
    box(m, (0, 0, 0.07), (0.3, 0.06, 0.02), "common.rune")
    box(m, (0, 0, 0.07), (0.06, 0.3, 0.02), "common.rune")
    return m


def banner():
    m = MeshBuilder()
    m.cyl((0, 0, 0.0), (0, 0, 2.4), 0.04, sw="common.pole", sides=5)
    m.gem((0, 0, 2.45), 0.06, "common.gold", h=0.06)
    box(m, (0.28, 0, 1.95), (0.5, 0.03, 0.75), "common.banner")
    box(m, (0.28, -0.02, 2.05), (0.18, 0.02, 0.22), "common.gold")
    return m


def banner_stand():
    m = MeshBuilder()
    m.loft([(0.0, 0.32, 0.32), (0.1, 0.26, 0.26), (0.18, 0.1, 0.1)], sides=6, sw="common.stone_dark")
    box(m, (0, 0, 0.2), (0.12, 0.12, 0.06), "common.metal_dark")
    return m


def trap():
    m = MeshBuilder()
    m.cyl((0, 0, 0.0), (0, 0, 0.03), 0.26, sw="common.trap_dark", sides=8)
    for a in range(8):
        ang = a * math.tau / 8
        m.cone((math.cos(ang) * 0.22, math.sin(ang) * 0.22, 0.03), (math.cos(ang) * 0.14, math.sin(ang) * 0.14, 0.09),
               0.025, "common.trap", sides=3)
    return m


def brazier():
    """Sits on top of a wall tile (ember kit): a bowl with glowing coals."""
    m = MeshBuilder()
    m.loft([(0.0, 0.14, 0.14), (0.16, 0.1, 0.1), (0.22, 0.24, 0.24), (0.32, 0.26, 0.26)], sides=6,
           sw="common.metal_dark")
    m.loft([(0.3, 0.2, 0.2), (0.4, 0.0, 0.0)], sides=6, sw="common.glow_fire")
    return m


def assets():
    out = []
    for kit in KITS:
        out.append(module("env_%s_obelisk_base" % kit, (lambda kit=kit: finish(obelisk_base(kit))), "marker_base",
                          kit=kit))
    for name, fn, role in (("crystal", crystal, "marker"), ("altar", altar, "objective"), ("rune", rune, "objective"),
                           ("banner", banner, "objective"), ("banner_stand", banner_stand, "objective"),
                           ("trap", trap, "marker_base"), ("brazier", brazier, "wall_top")):
        out.append(module("env_common_" + name, (lambda fn=fn: finish(fn())), role, kit="common", open_ok=True))
    return out
