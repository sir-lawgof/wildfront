extends SceneTree
## Asset check (ASSETS.md sections 3, 5, 8): naming, palette material, triangle budgets, the full-character
## budget, data coverage of data/art/gear_visuals.json against the item data, and required animation clips.
## Run: godot --headless --path . --script res://tools/dev/check_assets.gd [-- --skip-coverage]
## Exit code 1 if anything fails.

const GEAR_SLOTS := ["weapon", "shield", "head", "body", "legs", "feet", "hands", "cape", "ammo"]

var problems: Array[String] = []
var warnings: Array[String] = []


func _init() -> void:
	var skip_cov := "--skip-coverage" in OS.get_cmdline_user_args()
	DB.ensure_loaded()
	var models := _list_models(AssetRules.MODELS_DIR)
	var slot_max: Dictionary = {}
	var body_bones: Dictionary = {}
	for path in models:
		var ps: PackedScene = load(path)
		if ps == null:
			problems.append("%s: failed to load" % path)
			continue
		var scene := ps.instantiate()
		var stats := {}
		problems.append_array(AssetRules.check_scene(scene, path, stats))
		var per: Dictionary = stats.get("per_slot", {})
		for slot in per:
			slot_max[slot] = maxi(int(slot_max.get(slot, 0)), int(per[slot]))
		if path == AssetRules.BASE_BODY:
			for n in scene.find_children("*", "MeshInstance3D", true, false):
				var parts := AssetRules.split_name(str(n.name))
				if parts.size() == 2 and parts[0] == "body":
					body_bones[parts[1]] = AssetRules.mesh_tris((n as MeshInstance3D).mesh)
		scene.free()
	print("CHECK %d models" % models.size())
	_check_full_character(slot_max, body_bones)
	if not skip_cov:
		_check_coverage()
	_check_anims()
	for w in warnings:
		print("WARN " + w)
	for p in problems:
		print("FAIL " + p)
	if problems.is_empty():
		print("OK assets pass (%d models)" % models.size())
	quit(1 if not problems.is_empty() else 0)


func _list_models(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_list_models(dir + "/" + sub))
	for f in d.get_files():
		if f.ends_with(".glb") and not f.begins_with("_"):
			out.append(dir + "/" + f)
	out.sort()
	return out


func _check_full_character(slot_max: Dictionary, body_bones: Dictionary) -> void:
	if body_bones.is_empty():
		return
	## Worst case: each gear slot either shows its heaviest model or the body segments it would hide.
	var hidden_by: Dictionary = {}
	for slot in AssetRules.HIDES:
		for b in AssetRules.HIDES[slot]:
			hidden_by[b] = slot
	var total := 0
	var grouped: Dictionary = {}
	for b in body_bones:
		if hidden_by.has(b):
			grouped[hidden_by[b]] = int(grouped.get(hidden_by[b], 0)) + int(body_bones[b])
		else:
			total += int(body_bones[b])
	for slot in ["armour_body", "armour_legs", "boots", "gloves"]:
		total += maxi(int(grouped.get(slot, 0)), int(slot_max.get(slot, 0)))
	total += maxi(int(grouped.get("helm_full", 0)), 0) + int(slot_max.get("helm", 0))
	for slot in ["weapon", "offhand", "cape"]:
		total += int(slot_max.get(slot, 0))
	print("CHECK worst-case full character: %d tris (max %d)" % [total, AssetRules.BUDGET_FULL_CHARACTER])
	if total > AssetRules.BUDGET_FULL_CHARACTER:
		problems.append("worst-case full character is %d tris (max %d)" % [total, AssetRules.BUDGET_FULL_CHARACTER])


func _check_coverage() -> void:
	var f := FileAccess.open("res://data/art/gear_visuals.json", FileAccess.READ)
	if f == null:
		problems.append("data/art/gear_visuals.json is missing")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var vis: Dictionary = data.get("items", {})
	var covered := 0
	for id in DB.items:
		var slot := str((DB.items[id] as Dictionary).get("slot", ""))
		if not slot in GEAR_SLOTS:
			continue
		if not vis.has(id):
			problems.append("item '%s' (%s) has no visual in gear_visuals.json" % [id, slot])
		else:
			covered += 1
	for id in vis:
		if not DB.items.has(id):
			problems.append("gear_visuals.json: '%s' isn't an item" % id)
			continue
		var model := str((vis[id] as Dictionary).get("model", id))
		var p := "%s/gear/%s.glb" % [AssetRules.MODELS_DIR, model]
		if not ResourceLoader.exists(p):
			problems.append("gear_visuals.json: '%s' model %s doesn't exist (run the build)" % [id, p])
	print("CHECK coverage: %d equippable items have visuals" % covered)


func _check_anims() -> void:
	var f := FileAccess.open("res://data/art/anim_sets.json", FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	if not ResourceLoader.exists(AssetRules.ANIM_LIBRARY):
		problems.append("animation library %s is missing" % AssetRules.ANIM_LIBRARY)
		return
	var lib: AnimationLibrary = load(AssetRules.ANIM_LIBRARY)
	var need: Dictionary = {}
	for c in data.get("required", []):
		need[str(c)] = true
	for set_name in data.get("sets", {}):
		var s: Dictionary = data["sets"][set_name]
		for k in ["idle", "walk", "run", "block"]:
			if s.has(k):
				need[str(s[k])] = true
		for k in ["attack", "spec"]:
			if s.has(k):
				need[str((s[k] as Dictionary)["clip"])] = true
	for c in need:
		if not lib.has_animation(c):
			problems.append("animation clip '%s' is missing from %s" % [c, AssetRules.ANIM_LIBRARY])
	print("CHECK animations: %d clips required, library has %d" % [need.size(), lib.get_animation_list().size()])
