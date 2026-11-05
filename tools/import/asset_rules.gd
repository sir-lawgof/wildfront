class_name AssetRules
extends RefCounted
## Shared rules for generated models (ASSETS.md sections 3, 5 and 6), used by the import script
## (warnings on every import) and tools/dev/check_assets.gd (fails the build).

const PALETTE_MATERIAL := "res://assets/materials/palette.tres"
const ENV_MATERIAL := "res://assets/materials/env.tres"
const ENV_MODULES := "res://data/art/env_modules.json"
## Environment budgets per module role (docs/ENVIRONMENT.md section 9).
const ENV_BUDGET := {"wall": 150, "face": 60, "rampart": 250, "pillar": 250, "block": 400, "structure": 1200,
	"border": 150, "decor": 60, "water_decor": 120, "scatter": 500, "backdrop": 2000, "marker": 200,
	"marker_base": 150, "objective": 300, "wall_top": 80}
const MODELS_DIR := "res://assets/models"
const ANIM_LIBRARY := "res://assets/animations/character.res"
const BASE_BODY := "res://assets/models/characters/base_body.glb"

## Mesh-node slot prefixes allowed in characters/ and gear/ files: "<slot>__<bone>".
const SLOTS := ["body", "helm", "armour_body", "armour_legs", "boots", "gloves", "weapon", "offhand", "cape", "ammo", "fx"]

const BONES := ["root", "hips", "spine", "chest", "neck", "head", "upperarm_L", "forearm_L", "hand_L",
	"socket_offhand", "upperarm_R", "forearm_R", "hand_R", "socket_weapon", "socket_back",
	"thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]

## Triangle budgets (max). Base body is 800-1200 in the doc; only the max is enforced.
const BUDGET_BASE_BODY := 1200
const BUDGET_FULL_CHARACTER := 2500
const BUDGET_SLOT := {"weapon": 250, "offhand": 300, "helm": 300, "armour_body": 300, "armour_legs": 300,
	"boots": 300, "gloves": 300, "cape": 300, "ammo": 120, "fx": 300}
const BUDGET_PROP := 500
const BUDGET_FX := 300

## Body segments hidden by each gear slot (section 6 table). Helms only hide the head if "full".
const HIDES := {
	"armour_body": ["chest", "spine", "upperarm_L", "upperarm_R", "forearm_L", "forearm_R"],
	"armour_legs": ["hips", "thigh_L", "thigh_R", "shin_L", "shin_R"],
	"boots": ["foot_L", "foot_R"],
	"gloves": ["hand_L", "hand_R"],
	"helm_full": ["head"],
}


static func material_for(path: String) -> String:
	return ENV_MATERIAL if category_of(path) == "env" else PALETTE_MATERIAL


static func split_name(node_name: String) -> PackedStringArray:
	## "armour_body__chest" -> ["armour_body", "chest"]; [] if it doesn't follow the rule.
	var i := node_name.find("__")
	if i <= 0:
		return PackedStringArray()
	return PackedStringArray([node_name.substr(0, i), node_name.substr(i + 2)])


static func mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.size() > 0:
			n += idx.size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func category_of(path: String) -> String:
	## res://assets/models/<category>/<id>.glb -> category
	return path.get_base_dir().get_file()


## Returns a list of problems for one imported model scene (empty = OK) and fills stats.
static func check_scene(scene: Node, path: String, stats: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	var cat := category_of(path)
	var total := 0
	var per_slot: Dictionary = {}
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var t := mesh_tris(mi.mesh)
		total += t
		if cat in ["characters", "gear"]:
			var parts := split_name(str(mi.name))
			if parts.is_empty():
				problems.append("%s: mesh '%s' doesn't follow <slot>__<bone>" % [path.get_file(), mi.name])
				continue
			if not parts[0] in SLOTS:
				problems.append("%s: mesh '%s' has unknown slot '%s'" % [path.get_file(), mi.name, parts[0]])
			if not parts[1] in BONES:
				problems.append("%s: mesh '%s' has unknown bone '%s'" % [path.get_file(), mi.name, parts[1]])
			per_slot[parts[0]] = int(per_slot.get(parts[0], 0)) + t
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m == null or m.resource_path != material_for(path):
					problems.append("%s: mesh '%s' doesn't use the %s material" % [path.get_file(), mi.name, material_for(path).get_file()])
					break
	stats["tris"] = total
	stats["per_slot"] = per_slot
	match cat:
		"characters":
			var body := int(per_slot.get("body", 0))
			if body > BUDGET_BASE_BODY:
				problems.append("%s: base body has %d tris (max %d)" % [path.get_file(), body, BUDGET_BASE_BODY])
		"gear":
			for slot in per_slot:
				var cap := int(BUDGET_SLOT.get(slot, 300))
				if int(per_slot[slot]) > cap:
					problems.append("%s: %s has %d tris (max %d)" % [path.get_file(), slot, per_slot[slot], cap])
		"props":
			if total > BUDGET_PROP:
				problems.append("%s: prop has %d tris (max %d)" % [path.get_file(), total, BUDGET_PROP])
		"fx":
			if total > BUDGET_FX:
				problems.append("%s: effect has %d tris (max %d)" % [path.get_file(), total, BUDGET_FX])
	return problems
