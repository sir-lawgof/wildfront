"""Turns pose-library clips into Blender actions on the shared armature (one action per clip)."""
import math

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

from .poses import BONES_ANIMATED

FPS = 30
EASE = {
    "linear": ("LINEAR", "AUTO"),
    "in": ("SINE", "EASE_IN"),
    "out": ("SINE", "EASE_OUT"),
    "inout": ("SINE", "EASE_IN_OUT"),
    "const": ("CONSTANT", "AUTO"),
}


def _fcurves(action):
    try:
        return list(action.fcurves)
    except AttributeError:  # Blender 5: layered actions
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
        return out


def _local_rot(bone, deg):
    """World-axis rotation (pose convention, see poses.py) -> pose-bone local quaternion."""
    rw = Euler([math.radians(a) for a in deg], "XYZ").to_matrix()
    b = bone.matrix_local.to_3x3()
    return (b.inverted() @ rw @ b).to_quaternion()


def bake_clip(arm_ob, clip):
    action = bpy.data.actions.new(clip.export_name)
    action.use_fake_user = True
    arm_ob.animation_data_create()
    arm_ob.animation_data.action = action
    pbs = arm_ob.pose.bones
    for pb in pbs:
        pb.rotation_mode = "QUATERNION"
    hips_rest = arm_ob.data.bones["hips"].matrix_local.to_3x3()
    prev_q = {}
    frame_ease = {}
    for t, pose, ease in clip.keys:
        frame = int(round(t * FPS))
        frame_ease[frame] = ease
        for name in BONES_ANIMATED:
            pb = pbs[name]
            q = _local_rot(pb.bone, pose.get(name, (0.0, 0.0, 0.0)))
            if name in prev_q and prev_q[name].dot(q) < 0.0:
                q.negate()  # stay in one hemisphere so interpolation takes the short way
            prev_q[name] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        loc = Vector(pose.get("loc", (0.0, 0.0, 0.0)))
        pbs["hips"].location = hips_rest.inverted() @ loc
        pbs["hips"].keyframe_insert("location", frame=frame, group="hips")
    # Easing: Blender stores a segment's interpolation on its first key; ours describes arrival at a key.
    frames = sorted(frame_ease)
    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            f = int(round(kp.co.x))
            if f in frames:
                i = frames.index(f)
                nxt = frames[i + 1] if i + 1 < len(frames) else None
                interp, easing = EASE[frame_ease[nxt]] if nxt is not None else EASE["linear"]
                kp.interpolation = interp
                kp.easing = easing
    action.use_frame_range = True
    action.frame_range = (0, int(round(clip.length * FPS)))
    return action


def bake_all(arm_ob, clips):
    for c in clips:
        bake_clip(arm_ob, c)
    arm_ob.animation_data.action = None
    for pb in arm_ob.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
