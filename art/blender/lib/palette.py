"""Palette lookups. Generators never pick colours by value: they ask for a swatch by name and every UV of
the face is set to the centre of that swatch's cell in palette.png (ASSETS.md section 7)."""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
_META = None


def meta():
    global _META
    if _META is None:
        with open(os.path.join(ROOT, "art", "palette", "palette.json"), encoding="utf-8") as f:
            _META = json.load(f)
    return _META


def has(name):
    return name in meta()["swatches"]


def cell(name):
    sw = meta()["swatches"]
    if name not in sw:
        raise KeyError("unknown palette swatch '%s' (add it in art/palette/make_palette.py)" % name)
    return sw[name]


def uv(name):
    """Blender UV (origin bottom-left) of the centre of a swatch cell. glTF export flips V for Godot."""
    c, r = cell(name)
    g = meta()["grid"]
    return ((c + 0.5) / g, 1.0 - (r + 0.5) / g)


def tier_material(tier, family):
    """tier 1..7, family metal|hide|robe|wood -> material name, e.g. (1, 'metal') -> 'bronze'."""
    return meta()["tiers"][str(tier)][family]
