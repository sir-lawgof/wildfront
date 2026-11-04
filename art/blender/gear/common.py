"""Shared helpers for gear generators.

A Gear collects parts per bone; finish() turns each into an object named <slot>__<bone>.
 - Parts on body bones are modelled in place around the rest pose (world coordinates), with the object's
   origin at the bone head. The client attaches them to the bone with no offsets.
 - Parts on socket bones (weapon, off-hand, back) are modelled grip-relative: the grip/attach point is the
   origin, the weapon points forward (-Y) and its 'up' is +Z.
Silhouette rules by tier (ASSETS.md section 3): trims from tier 4, spikes/fins from tier 6.
"""
import math

from mathutils import Matrix, Vector

from lib import rig
from lib.mesh import MeshBuilder, along

# local (x, y, z) -> world (z, x, y): a 2D outline in the YZ plane (u = forward/back Y, v = up Z),
# extruded along X. Front face points +X.
PLANE_YZ = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
# outline in the XZ plane (u = X, v = Z), extruded along Y; front face points -Y (toward the viewer of the front)
PLANE_XZ = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


class Gear:
    def __init__(self, v):
        self.v = v
        self.tier = int(v.get("tier", 1))
        self.sw = v.get("sw", {})
        self.variant = v.get("variant", "")
        self.parts = {}

    def s(self, role, default="ui.grey"):
        return self.sw.get(role, default)

    @property
    def trims(self):
        return self.tier >= 4

    @property
    def spikes(self):
        return self.tier >= 6

    def part(self, bone):
        if bone not in self.parts:
            self.parts[bone] = MeshBuilder()
        return self.parts[bone]

    def finish(self, slot):
        total = 0
        for bone, mb in self.parts.items():
            if not mb.faces:
                continue
            total += mb.tris()
            origin = (0, 0, 0) if rig.is_socket(bone) else rig.head(bone)
            mb.to_object("%s__%s" % (slot, bone), origin=origin)
        return total


def prism(m, outline, depth, sw_front, sw_back=None, sw_side=None, mat=None, offset=0.0):
    """Extrude a 2D outline (counter-clockwise, local XY) along local Z (centred on `offset`)."""
    sw_back = sw_back or sw_front
    sw_side = sw_side or sw_back
    area = sum(outline[i][0] * outline[(i + 1) % len(outline)][1] - outline[(i + 1) % len(outline)][0] * outline[i][1]
               for i in range(len(outline)))
    if area < 0:
        outline = list(reversed(outline))  # always counter-clockwise, so the front face points +Z
    z0, z1 = offset - depth / 2, offset + depth / 2
    n = len(outline)
    back = m._pts([(u, v, z0) for u, v in outline], mat)
    front = m._pts([(u, v, z1) for u, v in outline], mat)
    m.faces.append(([front + i for i in range(n)], sw_front))
    m.faces.append(([back + i for i in reversed(range(n))], sw_back))
    for i in range(n):
        j = (i + 1) % n
        m.faces.append(([back + i, back + j, front + j, front + i], sw_side))


def blade(m, p0, p1, width, thick, sw, edge_sw=None, curve=0.0, segs=1, tip=0.25, mat=None, widen=1.0):
    """A flat blade from p0 (hilt) to p1 (tip). Width is vertical (local y), thickness sideways.
    curve: upward bow of the blade (fraction of length), tip: fraction of length that tapers to a point."""
    ln = (Vector(p1) - Vector(p0)).length
    base = along(p0, p1)
    if mat is not None:
        base = mat @ base
    rings = []
    n = max(1, segs)
    body_len = ln * (1.0 - tip)
    for i in range(n + 1):
        f = i / n
        z = body_len * f
        cy = curve * ln * (f * f)
        w = width * (1.0 + (widen - 1.0) * f)
        rings.append((z, thick, w, 0.0, cy))
    cy_tip = curve * ln * 1.15
    rings.append((ln, 0.0, 0.0, 0.0, cy_tip + width * 0.4 * (1 if curve > 0 else 0)))
    m.loft(rings, sides=4, sw=sw, mat=base, flat=False, phase=0.0)


def spike(m, p, direction, length, r, sw, sides=4, mat=None):
    p = Vector(p)
    d = Vector(direction).normalized()
    m.cone(p, p + d * length, r, sw, sides=sides, mat=mat)


def ring_band(m, z, rx, ry, h, sw, cx=0.0, cy=0.0, sides=8):
    m.loft([(z - h / 2, rx, ry, cx, cy), (z + h / 2, rx, ry, cx, cy)], sides=sides, sw=sw, cap0=False, cap1=False)


def side_x(side):
    return 1.0 if side == "L" else -1.0
