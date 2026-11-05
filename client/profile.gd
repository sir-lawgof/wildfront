class_name Profile
extends RefCounted
## Local player account: style XP, prestige, custom classes, challenges and settings,
## saved to user://profile.json. (GDD M8 asks for SQLite accounts on a server; this
## prototype keeps one local profile. See docs/DECISIONS.md.)

const PATH := "user://profile.json"

var data: Dictionary = {}


static func load_or_create() -> Profile:
	DB.ensure_loaded()
	var p := Profile.new()
	if FileAccess.file_exists(PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if j is Dictionary:
			p.data = j
	p._defaults()
	return p


func _defaults() -> void:
	var d := {
		"name": "Adventurer",
		"xp": {"melee": 0, "ranged": 0, "magic": 0},
		"prestige": {"melee": 0, "ranged": 0, "magic": 0},
		"custom_classes": [],
		"selected_class": "warrior",
		"settings": {
			"tick_sound": false, "switch_hotkeys": true, "minimap_size": 200, "colorblind": false,
			"tick_visual": false, "telemetry": true,
			"short_countdown": false, "volume": 0.7, "bot_skill": 0.55, "show_tile_grid": true, "placeholder_map_art": false,
		},
		"stats": {"matches": 0, "wins": 0, "kills": 0, "deaths": 0, "assists": 0, "damage": 0},
		"challenges": {},
		"completed": [],
		"unlocked_mods": {},
		"kits": {},
		"titles": [],
		"banners": [],
		"selected_title": "",
	}
	for k in d:
		if not data.has(k):
			data[k] = d[k]
		elif d[k] is Dictionary:
			for k2 in d[k]:
				if not (data[k] as Dictionary).has(k2):
					data[k][k2] = d[k][k2]
	# U4: a random, non-personal id (for the win-trading guard) and this season's ranked state.
	if not data.has("player_id"):
		data["player_id"] = "%08x%08x" % [randi(), randi()]
	if not data.has("ranked"):
		data["ranked"] = Ranked.new_state(Ranked.season_of(int(Time.get_unix_time_from_system())))


## Playtest build (U11): `-- --playtest` on the command line or project setting wildfront/playtest_build.
static func playtest_build() -> bool:
	return OS.get_cmdline_user_args().has("--playtest") or bool(ProjectSettings.get_setting("wildfront/playtest_build", false))


## Adds a cosmetic reward ("title:X", "banner:X", "cape_trim:X"). Returns a label, or "" if already owned.
func grant_cosmetic(reward: String) -> String:
	var parts := reward.split(":", true, 1)
	if parts.size() < 2:
		return ""
	var key: String = {"title": "titles", "banner": "banners", "cape_trim": "cape_trims"}.get(parts[0], "")
	if key == "":
		return ""
	if not data.has(key):
		data[key] = []
	if (data[key] as Array).has(parts[1]):
		return ""
	data[key].append(parts[1])
	return "%s: %s" % [{"title": "Title", "banner": "Banner", "cape_trim": "Cape trim"}[parts[0]], parts[1].replace("_", " ").capitalize()]


## U4: season rollover (end-of-season rewards, soft reset) and weekly decay. Returns lines to show the player.
func ranked_housekeeping() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var st: Dictionary = data["ranked"]
	var out: Array = []
	var lost := Ranked.apply_decay(st, now)
	if lost > 0.0:
		out.append("Ranked: inactive last week, rating decayed (play %d matches a week to avoid it)." % int(DB.ranked["decay"]["min_matches_per_week"]))
	var rolled := Ranked.roll_season(st, now)
	if str(rolled["previous_peak"]) != "":
		out.append("New ranked season! Last season's peak: %s." % str(rolled["previous_peak"]))
	for r in rolled["rewards"]:
		var l := grant_cosmetic(str(r))
		if l != "":
			out.append("Season reward - " + l)
	save()
	return out


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func setting(key: String) -> Variant:
	return data["settings"].get(key)


func set_setting(key: String, v: Variant) -> void:
	data["settings"][key] = v
	save()


# ---------------------------------------------------------------- levels

func xp(style: String) -> int:
	return int(data["xp"].get(style, 0))


func level(style: String) -> int:
	return Progression.level_for_xp(xp(style))


func levels() -> Dictionary:
	return {"melee": level("melee"), "ranged": level("ranged"), "magic": level("magic")}


func combat_level() -> int:
	var l := levels()
	return Progression.combat_level(l["melee"], l["ranged"], l["magic"])


func title() -> String:
	var sel := str(data.get("selected_title", ""))
	return sel if sel != "" else Progression.title(combat_level())


func unlocked() -> Dictionary:
	return Progression.unlocked_set(levels())


func prestige(style: String) -> int:
	return int(data["prestige"].get(style, 0))


func can_prestige(style: String) -> bool:
	return level(style) >= Progression.max_level() and prestige(style) < int(DB.levels.get("max_prestige", 10))


## Resets one style to level 1 and bumps its prestige (GDD 5 Prestige).
func do_prestige(style: String) -> void:
	if not can_prestige(style):
		return
	data["prestige"][style] = prestige(style) + 1
	data["xp"][style] = 0
	save()


## Adds XP per style; returns [{style, from, to, unlocks: [labels]}] for level-ups.
func add_xp(gains: Dictionary) -> Array:
	var ups: Array = []
	var cl_before := combat_level()
	for s in ["melee", "ranged", "magic"]:
		var g := int(gains.get(s, 0))
		if g <= 0:
			continue
		var before := level(s)
		data["xp"][s] = xp(s) + g
		var after := level(s)
		if after > before:
			var labels: Array = []
			for l in range(before + 1, after + 1):
				for e in Progression.unlocks_at(s, l):
					labels.append(Progression.unlock_label(str(e)))
			ups.append({"style": s, "from": before, "to": after, "unlocks": labels})
	var cl_after := combat_level()
	if cl_after > cl_before:
		var labels: Array = []
		for l in range(cl_before + 1, cl_after + 1):
			for e in Progression.unlocks_at("combat", l):
				labels.append(Progression.unlock_label(str(e)))
		ups.append({"style": "combat", "from": cl_before, "to": cl_after, "unlocks": labels})
	save()
	return ups


# ---------------------------------------------------------------- classes

func class_list() -> Array:
	## [{key, name, def, custom: bool}]
	var out: Array = []
	for k in DB.classes["defaults"]:
		out.append({"key": k, "name": DB.classes["defaults"][k]["name"], "def": DB.classes["defaults"][k], "custom": false})
	if unlocked().has("feature:create_a_class"):
		var slots := Progression.custom_class_slots(combat_level())
		var cc: Array = data["custom_classes"]
		for i in range(mini(slots, cc.size())):
			out.append({"key": "custom:%d" % i, "name": cc[i]["name"], "def": cc[i], "custom": true})
	return out


func class_def(key: String) -> Dictionary:
	for c in class_list():
		if c["key"] == key:
			return c["def"]
	return DB.classes["defaults"]["warrior"]


func selected_class_def() -> Dictionary:
	return class_def(str(data.get("selected_class", "warrior")))
