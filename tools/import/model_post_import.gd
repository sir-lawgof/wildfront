@tool
extends EditorScenePostImport
## Runs on every .glb import (set as the project's scene import default; ASSETS.md section 5):
##  - replaces every material with the shared palette material (env.tres for assets/models/env/),
##  - loops clips whose names end in -loop / _loop (Godot strips the suffix: "idle-loop" -> "idle"),
##  - saves the base body's clips as the shared AnimationLibrary,
##  - prints a warning for naming or triangle-budget problems (tools/dev/check_assets.gd fails on them).

const LOOP_CLIPS := ["idle", "walk", "run"]


func _post_import(scene: Node) -> Object:
	var path := get_source_file()
	var mat: Material = load(AssetRules.material_for(path))
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			mi.mesh.surface_set_material(s, mat)
	for n in scene.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for clip in lib.get_animation_list():
				var a := lib.get_animation(clip)
				var base := str(clip).trim_suffix("-loop").trim_suffix("_loop")
				var stance := base.get_slice("@", 0)  # stance variants: "idle@staff"
				if str(clip) != base or stance in LOOP_CLIPS:
					a.loop_mode = Animation.LOOP_LINEAR
		if path == AssetRules.BASE_BODY and ap.has_animation_library(""):
			var shared: AnimationLibrary = ap.get_animation_library("").duplicate(true)
			var err := ResourceSaver.save(shared, AssetRules.ANIM_LIBRARY)
			if err != OK:
				push_warning("Could not save %s (error %d)" % [AssetRules.ANIM_LIBRARY, err])
	for p in AssetRules.check_scene(scene, path):
		push_warning("[assets] " + p)
	return scene
