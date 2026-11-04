"""A0/A1 pipeline test model: a small wooden crate with iron bands (a map prop, ~60 tris)."""
from lib.mesh import MeshBuilder


def build():
    m = MeshBuilder()
    m.box((0, 0, 0.3), (0.6, 0.6, 0.6), "wood.mid")
    for z in (0.08, 0.52):  # iron bands
        m.box((0, 0, z), (0.64, 0.64, 0.07), "metal.dark")
    m.box((0, -0.31, 0.3), (0.42, 0.04, 0.08), "wood.dark", taper=(1, 1))  # front plank
    m.to_object("crate")


ASSETS = [{"id": "test_crate", "category": "props", "build": build}]
