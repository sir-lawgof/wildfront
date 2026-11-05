"""Helpers for environment generators (docs/ENVIRONMENT.md).

Conventions (Blender axes): a module's tile is centred on the origin, 1 unit = 1 tile, Z up.
Line-shaped modules run along X. A module's "front" is -Y (Godot +Z): face decorations sit on the -Y face and
the builder rotates them to whichever side is exposed. Footprints: 1x1 = +-0.5, 2x1 rampart slice = X +-0.5,
Y +-1.0, 2x2 block = +-1.0, structures = +-w/2, +-d/2. Pieces may overhang their tiles by at most 0.1.
"""
import math
import random
import zlib

from lib.mesh import MeshBuilder, T, R

KITS = ["frost", "ember", "mire", "castle"]

# Per-kit heights (tiles). Walls/pillars block line of sight, so everything solid is >= 1.4 tall.
STYLE = {
    "frost": {"wall_h": 1.7, "border_h": 2.1, "rampart_h": 1.75},
    "ember": {"wall_h": 1.6, "border_h": 2.0, "rampart_h": 1.7},
    "mire": {"wall_h": 1.8, "border_h": 2.2, "rampart_h": 1.8},
    "castle": {"wall_h": 1.9, "border_h": 2.3, "rampart_h": 1.9},
}


def rng(asset_id):
    """Deterministic RNG per asset (rebuilds give identical files)."""
    return random.Random(zlib.crc32(asset_id.encode()))


def S(kit, name):
    """Kit swatch name, e.g. S('frost', 'wall') -> 'frost.wall'."""
    return "%s.%s" % (kit, name)


def box(m, c, size, sw, taper=(1.0, 1.0), mat=None):
    m.box(c, size, sw, taper=taper, mat=mat)


def slab_stack(m, x0, x1, y0, y1, z0, z1, sw):
    box(m, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), sw)


def rock(m, c, r, sw, h=None, sides=5, mat=None):
    """A faceted boulder (squashed double pyramid)."""
    h = r * 0.8 if h is None else h
    x, y, z = c
    mm = T(x, y, z)
    if mat is not None:
        mm = mat @ mm
    m.loft([(0.0, r * 0.75, r * 0.7), (h * 0.45, r, r * 0.95), (h, r * 0.35, r * 0.3)], sides=sides, sw=sw, mat=mm)


def cone_tree(m, c, r, h, trunk_sw, leaf_sw, tiers=3):
    x, y, z = c
    m.cyl((x, y, z), (x, y, z + h * 0.25), r * 0.18, sw=trunk_sw, sides=5)
    for i in range(tiers):
        f = i / tiers
        z0 = z + h * (0.18 + 0.27 * i)
        rr = r * (1.0 - 0.28 * i)
        m.loft([(0.0, rr, rr), (h * 0.42, 0.0, 0.0)], sides=6, sw=leaf_sw, mat=T(x, y, z0))


def module(asset_id, build, role, **meta):
    """Registry entry for build_all (category env)."""
    m = {"role": role}
    m.update(meta)
    return {"id": asset_id, "category": "env", "build": build, "meta": m}


def finish(m, name="env"):
    m.to_object(name)
    return m.tris()


def deg(a):
    return math.radians(a)
