"""Low-poly mesh building with per-face palette swatches.

A MeshBuilder collects faceted primitives (lofts, boxes, cones). Every face carries a swatch name; when the
mesh is turned into a Blender object, all UVs of that face go to the swatch's cell centre. Faces are flat
shaded, so the glTF exporter writes split normals (the faceted OSRS look).

Coordinates are Blender's: Z up, the character faces -Y, the character's left is +X. 1 unit = 1 game tile.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import palette

TAU = math.pi * 2.0


def along(p0, p1, up=(0.0, 0.0, 1.0), roll=0.0):
    """Matrix whose local +Z runs from p0 to p1 (origin at p0). Local Z values are distances along the line."""
    p0 = Vector(p0)
    d = (Vector(p1) - p0).normalized()
    upv = Vector(up)
    if abs(d.dot(upv)) > 0.99:
        upv = Vector((0.0, -1.0, 0.0)) if abs(d.z) > 0.5 else Vector((0.0, 0.0, 1.0))
    x = upv.cross(d).normalized()
    y = d.cross(x).normalized()
    m = Matrix((x, y, d)).transposed().to_4x4()
    m.translation = p0
    if roll:
        m = m @ Matrix.Rotation(roll, 4, "Z")
    return m


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def S(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    return Matrix.Diagonal((x, y, z, 1.0))


class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []  # (indices, swatch)

    # ------------------------------------------------------------------ core
    def _pts(self, pts, mat):
        base = len(self.verts)
        for p in pts:
            v = Vector(p)
            if mat is not None:
                v = mat @ v
            self.verts.append(v)
        return base

    def poly(self, pts, sw, mat=None):
        """One flat polygon (counter-clockwise when seen from the side it faces)."""
        b = self._pts(pts, mat)
        self.faces.append((list(range(b, b + len(pts))), sw))

    def merge(self, other, mat=None):
        b = len(self.verts)
        for v in other.verts:
            self.verts.append(mat @ v if mat is not None else v.copy())
        for idx, sw in other.faces:
            self.faces.append(([i + b for i in idx], sw))

    def tris(self):
        return sum(len(i) - 2 for i, _ in self.faces)

    # ------------------------------------------------------------------ primitives
    def loft(self, rings, sides=8, sw="ui.grey", cap0=True, cap1=True, cap_sw=None, mat=None, flat=True,
             phase=None):
        """Faceted loft along local +Z.

        rings: list of (z, rx, ry) or (z, rx, ry, cx, cy). rx = ry = 0 makes a point (cone tip).
        sw:    swatch name, or a list with one swatch per segment (len(rings) - 1).
        flat:  rx/ry are distances to the flat faces (True) instead of to the corners.
        """
        if phase is None:
            phase = math.pi / sides
        k = 1.0 / math.cos(math.pi / sides) if flat else 1.0
        segs = sw if isinstance(sw, (list, tuple)) else [sw] * (len(rings) - 1)
        cap_sw = cap_sw or (segs[0], segs[-1])
        if isinstance(cap_sw, str):
            cap_sw = (cap_sw, cap_sw)
        ring_idx = []
        for r in rings:
            z, rx, ry = r[0], r[1], r[2]
            cx, cy = (r[3], r[4]) if len(r) > 3 else (0.0, 0.0)
            if rx == 0 and ry == 0:
                ring_idx.append(self._pts([(cx, cy, z)], mat))
                continue
            pts = []
            for i in range(sides):
                a = phase + TAU * i / sides
                pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k, z))
            ring_idx.append(self._pts(pts, mat))
        is_pt = [r[1] == 0 and r[2] == 0 for r in rings]
        for s in range(len(rings) - 1):
            a, b = ring_idx[s], ring_idx[s + 1]
            for i in range(sides):
                j = (i + 1) % sides
                if is_pt[s] and is_pt[s + 1]:
                    continue
                if is_pt[s]:
                    self.faces.append(([a, b + j, b + i], segs[s]))
                elif is_pt[s + 1]:
                    self.faces.append(([a + i, a + j, b], segs[s]))
                else:
                    self.faces.append(([a + i, a + j, b + j, b + i], segs[s]))
        if cap0 and not is_pt[0]:
            a = ring_idx[0]
            self.faces.append(([a + i for i in reversed(range(sides))], cap_sw[0]))
        if cap1 and not is_pt[-1]:
            b = ring_idx[-1]
            self.faces.append(([b + i for i in range(sides)], cap_sw[1]))

    def box(self, center, size, sw, mat=None, taper=(1.0, 1.0)):
        """Axis-aligned box (before mat). taper scales the top face (x, y)."""
        cx, cy, cz = center
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
        m = T(cx, cy, cz - sz)
        if mat is not None:
            m = mat @ m
        self.loft([(0.0, sx, sy), (sz * 2, sx * taper[0], sy * taper[1])], sides=4, sw=sw, mat=m)

    def cyl(self, p0, p1, r0, r1=None, sw="ui.grey", sides=6, cap0=True, cap1=True, mat=None, roll=0.0):
        r1 = r0 if r1 is None else r1
        m = along(p0, p1, roll=roll)
        if mat is not None:
            m = mat @ m
        ln = (Vector(p1) - Vector(p0)).length
        self.loft([(0.0, r0, r0), (ln, r1, r1)], sides=sides, sw=sw, cap0=cap0, cap1=cap1, mat=m)

    def cone(self, p0, p1, r, sw, sides=6, mat=None):
        m = along(p0, p1)
        if mat is not None:
            m = mat @ m
        ln = (Vector(p1) - Vector(p0)).length
        self.loft([(0.0, r, r), (ln, 0.0, 0.0)], sides=sides, sw=sw, mat=m)

    def gem(self, center, r, sw, h=None, mat=None, sides=4):
        """Double pyramid (a cut gem / orb)."""
        h = r * 1.3 if h is None else h
        m = T(*center) @ T(0, 0, -h)
        if mat is not None:
            m = mat @ m
        self.loft([(0.0, 0.0, 0.0), (h, r, r), (2 * h, 0.0, 0.0)], sides=sides, sw=sw, mat=m)

    # ------------------------------------------------------------------ output
    def to_object(self, name, origin=(0.0, 0.0, 0.0), collection=None):
        """Create a flat-shaded mesh object. Vertices are stored relative to origin and the object sits at
        origin, so the object's pivot is that point (bone head, grip point...)."""
        o = Vector(origin)
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bverts = [bm.verts.new(v - o) for v in self.verts]
        uv_layer = bm.loops.layers.uv.new("UVMap")
        for idx, sw in self.faces:
            try:
                f = bm.faces.new([bverts[i] for i in idx])
            except ValueError:
                continue  # duplicate face (degenerate input); skip
            u = palette.uv(sw)
            for loop in f.loops:
                loop[uv_layer].uv = u
            f.smooth = False
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        ob.location = o
        mat = palette_material()
        me.materials.append(mat)
        (collection or bpy.context.scene.collection).objects.link(ob)
        return ob


def palette_material():
    """A Blender-side material showing palette.png (for viewing .blend files; export skips materials, and
    Godot's import script applies the shared palette material)."""
    m = bpy.data.materials.get("palette")
    if m is not None:
        return m
    m = bpy.data.materials.new("palette")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    tex = nt.nodes.new("ShaderNodeTexImage")
    import os
    path = os.path.join(palette.ROOT, "assets", "palette", "palette.png")
    try:
        tex.image = bpy.data.images.load(path, check_existing=True)
    except RuntimeError:
        pass
    tex.interpolation = "Closest"
    if bsdf is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 1.0
    return m
