"""Scene reset and glTF export with the project's fixed settings (checked against Blender 5.2's exporter)."""
import os

import bpy


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 30
    sc.frame_start = 0
    sc.frame_end = 0


def export_glb(path, animations=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_yup=True,                 # Blender Z-up -> glTF/Godot Y-up; never hand-rotate.
        export_apply=False,
        export_materials="NONE",        # Godot's import script applies the shared palette material.
        export_texcoords=True,
        export_normals=True,             # flat faces -> split normals.
        export_vertex_color="ACTIVE",    # environment pieces carry baked AO in vertex colours
        export_animations=animations,
        export_animation_mode="ACTIONS",  # each Blender action = one glTF animation (clip).
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_reset_pose_bones=True,
        export_skins=True,
        export_def_bones=False,
    )


def export_manual(blend_path, out_path, animations):
    """Manual override: export a hand-made .blend with the same settings."""
    bpy.ops.wm.open_mainfile(filepath=blend_path)
    export_glb(out_path, animations=animations)
