"""The shared character skeleton (ASSETS.md section 6).

Every character and every gear piece is built around these rest positions. Blender coordinates: Z up,
the character faces -Y, the character's left side is +X. Units are game tiles. Bone names use underscores
because Godot does not allow '.' in node names.
"""
import bpy
from mathutils import Matrix, Vector

SHOULDER_X = 0.31
HIP_X = 0.12

# name: (parent, head, tail)
BONES = {
    "root":           (None,          (0.0, 0.0, 0.0),            (0.0, 0.0, 0.15)),
    "hips":           ("root",        (0.0, 0.0, 0.82),           (0.0, 0.0, 0.92)),
    "spine":          ("hips",        (0.0, 0.0, 0.92),           (0.0, 0.0, 1.10)),
    "chest":          ("spine",       (0.0, 0.0, 1.10),           (0.0, 0.0, 1.38)),
    "neck":           ("chest",       (0.0, 0.0, 1.38),           (0.0, 0.0, 1.46)),
    "head":           ("neck",        (0.0, 0.0, 1.46),           (0.0, 0.0, 1.84)),
    "upperarm_L":     ("chest",       (SHOULDER_X, 0.0, 1.33),    (SHOULDER_X, 0.0, 1.07)),
    "forearm_L":      ("upperarm_L",  (SHOULDER_X, 0.0, 1.07),    (SHOULDER_X, 0.0, 0.83)),
    "hand_L":         ("forearm_L",   (SHOULDER_X, 0.0, 0.83),    (SHOULDER_X, 0.0, 0.70)),
    "socket_offhand": ("hand_L",      (SHOULDER_X, 0.0, 0.745),   (SHOULDER_X, -0.12, 0.745)),
    "upperarm_R":     ("chest",       (-SHOULDER_X, 0.0, 1.33),   (-SHOULDER_X, 0.0, 1.07)),
    "forearm_R":      ("upperarm_R",  (-SHOULDER_X, 0.0, 1.07),   (-SHOULDER_X, 0.0, 0.83)),
    "hand_R":         ("forearm_R",   (-SHOULDER_X, 0.0, 0.83),   (-SHOULDER_X, 0.0, 0.70)),
    "socket_weapon":  ("hand_R",      (-SHOULDER_X, 0.0, 0.745),  (-SHOULDER_X, -0.12, 0.745)),
    "socket_back":    ("chest",       (0.0, 0.14, 1.34),          (0.0, 0.26, 1.34)),
    "thigh_L":        ("hips",        (HIP_X, 0.0, 0.82),         (HIP_X, 0.0, 0.45)),
    "shin_L":         ("thigh_L",     (HIP_X, 0.0, 0.45),         (HIP_X, 0.0, 0.10)),
    "foot_L":         ("shin_L",      (HIP_X, 0.0, 0.10),         (HIP_X, -0.16, 0.03)),
    "thigh_R":        ("hips",        (-HIP_X, 0.0, 0.82),        (-HIP_X, 0.0, 0.45)),
    "shin_R":         ("thigh_R",     (-HIP_X, 0.0, 0.45),        (-HIP_X, 0.0, 0.10)),
    "foot_R":         ("shin_R",      (-HIP_X, 0.0, 0.10),        (-HIP_X, -0.16, 0.03)),
}


def head(bone):
    return Vector(BONES[bone][1])


def tail(bone):
    return Vector(BONES[bone][2])


def is_socket(bone):
    return bone.startswith("socket_")


def build_armature(name="Armature"):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = {}
    for bname, (parent, h, t) in BONES.items():
        eb = arm.edit_bones.new(bname)
        eb.head = h
        eb.tail = t
        # Roll so every bone's local X points along the character's left (+X): consistent axes.
        eb.align_roll(Vector((0.0, -1.0, 0.0)) if abs(Vector(t).z - Vector(h).z) > 1e-4 else Vector((0.0, 0.0, 1.0)))
        if parent:
            eb.parent = ebs[parent]
            eb.use_connect = False
        ebs[bname] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def parent_to_bone(ob, arm_ob, bone):
    """Parent a mesh object to one bone (rigid segment), keeping its world placement."""
    bpy.context.view_layer.update()  # matrix_world is stale until the depsgraph updates
    world = ob.matrix_world.copy()
    ob.parent = arm_ob
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    ob.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    ob.matrix_world = world
