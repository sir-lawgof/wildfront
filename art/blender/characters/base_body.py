"""The shared base body: rigid low-poly segments, each parented to one bone, plus every animation clip.

Chunky proportions (big head and hands, short legs). About 1.84 tiles tall, so a player is ~100 px tall at the
default in-game camera (see docs/DECISIONS.md: art scale). The tunic uses the team.* swatches, which the
palette shader recolours per player. Exports assets/models/characters/base_body.glb and writes
data/art/anim_sets.json.
"""
import json
import os

from anims import bake, clips
from lib import palette, rig
from lib.mesh import MeshBuilder

SKIN = "skin.2"
HAIR = "hair.2"
SHIRT = "team.base"
SHIRT_DARK = "team.dark"
TROUSERS = "cloth.trousers"
BELT = "cloth.belt"
SHOE = "cloth.shoe"


def head_parts(m):
    # skull: faceted 8-sided loft, wider at the cheeks
    m.loft([(1.47, 0.09, 0.09), (1.50, 0.145, 0.14), (1.57, 0.172, 0.165), (1.70, 0.178, 0.17),
            (1.79, 0.16, 0.152), (1.85, 0.11, 0.10)], sides=8, sw=SKIN)
    # hair cap and back of the head
    m.loft([(1.69, 0.188, 0.182), (1.80, 0.172, 0.166), (1.87, 0.125, 0.115), (1.885, 0.05, 0.05)], sides=8, sw=HAIR,
           cap0=False)
    m.box((0, 0.075, 1.66), (0.33, 0.17, 0.24), HAIR)
    m.box((0, -0.15, 1.765), (0.30, 0.06, 0.05), HAIR)  # fringe
    # face: eyes, brow, nose, mouth, ears
    for x in (-0.068, 0.068):
        m.box((x, -0.172, 1.665), (0.05, 0.02, 0.045), "eye")
        m.box((x, -0.175, 1.70), (0.07, 0.02, 0.022), HAIR)
        m.box((x * 2.65, 0.0, 1.645), (0.035, 0.07, 0.085), SKIN)
    m.box((0, -0.19, 1.625), (0.05, 0.05, 0.075), SKIN, taper=(0.8, 0.4))
    m.box((0, -0.175, 1.56), (0.09, 0.012, 0.02), "mouth")


def torso_parts(parts):
    chest = parts["chest"]
    chest.loft([(1.08, 0.19, 0.12), (1.20, 0.215, 0.13), (1.32, 0.232, 0.138), (1.385, 0.205, 0.122),
                (1.425, 0.11, 0.09)], sides=8, sw=[SHIRT, SHIRT, SHIRT, SHIRT_DARK])
    chest.box((0, -0.125, 1.30), (0.12, 0.03, 0.08), SHIRT_DARK)  # collar notch
    parts["neck"].cyl((0, 0, 1.37), (0, 0, 1.49), 0.072, sw=SKIN, sides=6)
    parts["spine"].loft([(0.88, 0.18, 0.115), (0.94, 0.183, 0.116), (1.12, 0.192, 0.12)], sides=8,
                        sw=[BELT, SHIRT])
    parts["spine"].box((0, -0.122, 0.91), (0.07, 0.02, 0.05), "gold.dark")  # buckle
    parts["hips"].loft([(0.70, 0.165, 0.11), (0.80, 0.19, 0.115), (0.90, 0.184, 0.114)], sides=8, sw=TROUSERS)


def arm_parts(parts, side):
    x = rig.SHOULDER_X * (1 if side == "L" else -1)
    parts["upperarm_" + side].loft([(1.04, 0.062, 0.062, x, 0), (1.18, 0.066, 0.066, x, 0), (1.30, 0.08, 0.078, x, 0),
                                    (1.385, 0.06, 0.06, x, 0)], sides=6, sw=[SKIN, SHIRT, SHIRT])
    parts["forearm_" + side].loft([(0.80, 0.054, 0.054, x, 0), (0.95, 0.062, 0.062, x, 0), (1.09, 0.063, 0.063, x, 0)],
                                  sides=6, sw=SKIN)
    h = parts["hand_" + side]
    h.box((x, -0.005, 0.745), (0.11, 0.125, 0.15), SKIN, taper=(1.0, 1.0))           # fist
    h.box((x - 0.035 * (1 if side == "L" else -1), -0.07, 0.775), (0.05, 0.05, 0.07), SKIN)  # thumb
    h.box((x, 0.0, 0.825), (0.12, 0.13, 0.03), SKIN)                                 # wrist


def leg_parts(parts, side):
    x = rig.HIP_X * (1 if side == "L" else -1)
    parts["thigh_" + side].loft([(0.43, 0.085, 0.088, x, 0), (0.62, 0.10, 0.10, x, 0), (0.80, 0.112, 0.11, x, 0)],
                                sides=6, sw=TROUSERS)
    parts["shin_" + side].loft([(0.085, 0.066, 0.07, x, 0), (0.30, 0.078, 0.08, x, 0), (0.47, 0.086, 0.088, x, 0)],
                               sides=6, sw=TROUSERS)
    f = parts["foot_" + side]
    f.box((x, -0.045, 0.06), (0.13, 0.27, 0.12), SHOE, taper=(0.95, 0.85))
    f.box((x, -0.17, 0.035), (0.12, 0.06, 0.07), SHOE, taper=(1.0, 0.7))  # toe


def build_body(arm_ob):
    parts = {b: MeshBuilder() for b in ("head", "neck", "chest", "spine", "hips", "upperarm_L", "forearm_L", "hand_L",
                                        "upperarm_R", "forearm_R", "hand_R", "thigh_L", "shin_L", "foot_L",
                                        "thigh_R", "shin_R", "foot_R")}
    head_parts(parts["head"])
    torso_parts(parts)
    for s in ("L", "R"):
        arm_parts(parts, s)
        leg_parts(parts, s)
    total = 0
    for bone, mb in parts.items():
        total += mb.tris()
        ob = mb.to_object("body__" + bone, origin=rig.head(bone))
        rig.parent_to_bone(ob, arm_ob, bone)
    print("base body: %d tris" % total)


def write_anim_sets():
    path = os.path.join(palette.ROOT, "data", "art", "anim_sets.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(clips.anim_sets_json(), f, indent=1)
        f.write("\n")


def build():
    arm = rig.build_armature()
    build_body(arm)
    all_clips = clips.all_clips()
    bake.bake_all(arm, all_clips)
    print("base body: %d clips" % len(all_clips))
    write_anim_sets()


ASSETS = [{"id": "base_body", "category": "characters", "build": build, "animations": True}]
