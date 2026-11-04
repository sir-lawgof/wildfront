class_name Progression
extends RefCounted
## Style levels, XP curve, titles, unlocks and match XP (GDD 5).

const ROMAN := ["I", "II", "III", "IV", "V"]


## XP needed to go from level L to L + 1.
static func xp_for_next(level: int) -> int:
	var base := float(DB.levels.get("xp_base", 600))
	var growth := float(DB.levels.get("xp_growth", 1.07))
	var rnd := float(DB.levels.get("round_to", 10))
	return int(round(base * pow(growth, level - 1) / rnd) * rnd)


## Total XP needed to reach `level` from level 1.
static func total_xp_for(level: int) -> int:
	var t := 0
	for l in range(1, level):
		t += xp_for_next(l)
	return t


static func max_level() -> int:
	return int(DB.levels.get("max_level", 40))


static func level_for_xp(xp: int) -> int:
	var lvl := 1
	var need := 0
	while lvl < max_level():
		need += xp_for_next(lvl)
		if xp < need:
			break
		lvl += 1
	return lvl


## Progress (0..1) through the current level.
static func level_progress(xp: int) -> float:
	var lvl := level_for_xp(xp)
	if lvl >= max_level():
		return 1.0
	var start := total_xp_for(lvl)
	return float(xp - start) / float(xp_for_next(lvl))


static func combat_level(melee: int, ranged: int, magic: int) -> int:
	return int(floor((melee + ranged + magic) / 3.0))


static func title(cl: int) -> String:
	var titles: Array = DB.levels.get("titles", [])
	var name := "Recruit"
	var from := 1
	for t in titles:
		if cl >= int(t["from"]):
			name = str(t["name"])
			from = int(t["from"])
	if cl >= max_level():
		return name
	var step := cl - from
	return "%s %s" % [name, ROMAN[clampi(step, 0, 4)]]


static func custom_class_slots(cl: int) -> int:
	var n := 0
	for e in DB.levels.get("class_slots", []):
		if cl >= int(e["level"]):
			n = int(e["slots"])
	return n


## Everything unlocked at these levels: id -> true. Includes features ("feature:x").
static func unlocked_set(levels: Dictionary) -> Dictionary:
	var out := {}
	var cl := combat_level(int(levels.get("melee", 1)), int(levels.get("ranged", 1)), int(levels.get("magic", 1)))
	var lv := levels.duplicate()
	lv["combat"] = cl
	for track in ["melee", "ranged", "magic", "combat"]:
		var per: Dictionary = DB.unlocks.get(track, {})
		for l in per:
			if int(l) <= int(lv.get(track, 1)):
				for entry in per[l]:
					var e := str(entry)
					out[e] = true
					for x in DB.expand_unlock(e):
						out[str(x)] = true
	return out


## Unlock entries gained at exactly this level of a track.
static func unlocks_at(track: String, level: int) -> Array:
	return DB.unlocks.get(track, {}).get(level, [])


static func unlock_label(entry: String) -> String:
	if entry.begins_with("feature:"):
		var f := entry.substr(8)
		return {
			"forbidden_book": "Forbidden spellbook", "kill_streaks": "Kill streak rewards",
			"create_a_class": "Create-a-class", "combat_potions": "Combat potions (each life starts boosted)",
			"ranked": "Ranked playlists", "grandmaster": "Grandmaster title and banner",
		}.get(f, f.capitalize())
	if entry.begins_with("set:"):
		var ids: Array = DB.expand_unlock(entry)
		if ids.is_empty():
			return entry
		var first := DB.item(str(ids[0]))
		var key := entry.substr(4)
		if key.contains(":"):
			var cls := key.split(":")[0]
			var tier := int(key.split(":")[1])
			var fam: String = {"plate": "metal", "hide": "hide", "robe": "robe"}[cls]
			var word: String = {"plate": "armour", "hide": "armour", "robe": "robes"}[cls]
			return "%s %s set" % [DB.tier_name(tier, fam), word]
		return str(first.get("name", key)).split(" ")[0] + " set"
	if DB.items.has(entry):
		return str(DB.items[entry]["name"])
	if DB.spells.has(entry):
		return str(DB.spells[entry]["name"]) + " (spell)"
	if DB.prayers.has(entry):
		return str(DB.prayers[entry]["name"]) + " (prayer)"
	if DB.perks.has(entry):
		return str(DB.perks[entry]["name"]) + " (perk)"
	return entry


# ---------------------------------------------------------------- match XP

## Computes XP for one fighter at match end. Returns
## {"melee": int, "ranged": int, "magic": int, "lines": [{label, amount, style}]}.
## won: true/false; primary_style: style of the class's primary weapon.
static func match_xp(f: Fighter, won: bool, rounds_won: int, primary_style: String) -> Dictionary:
	var x: Dictionary = DB.levels.get("xp", {})
	var out := {"melee": 0, "ranged": 0, "magic": 0, "lines": []}
	var lines: Array = out["lines"]
	for s in DB.STYLES:
		var dmg := int(f.damage_by_style.get(s, 0))
		if dmg > 0:
			_add(out, s, dmg * int(x.get("per_damage", 4)), "Damage dealt (%s)" % s.capitalize())
		var k := int(f.kill_styles.get(s, 0))
		if k > 0:
			_add(out, s, k * int(x.get("kill", 100)), "%d %s kill%s" % [k, s, "" if k == 1 else "s"])
		var a := int(f.assist_styles.get(s, 0))
		if a > 0:
			_add(out, s, a * int(x.get("assist", 30)), "%d assist%s (%s)" % [a, "" if a == 1 else "s", s])
		var sk := int(f.spec_kills.get(s, 0))
		if sk > 0:
			_add(out, s, sk * int(x.get("spec_kill_bonus", 50)), "Special attack kills (%s)" % s)
		var rk := int(f.revenge_kills.get(s, 0))
		if rk > 0:
			_add(out, s, rk * int(x.get("revenge_bonus", 50)), "Revenge kills (%s)" % s)
	# Split XP: by damage share this match, or to the class's primary style if no damage.
	var split := 0
	var split_lines: Array = []
	if f.captures > 0:
		split += f.captures * int(x.get("capture", 150))
		split_lines.append("%d captures" % f.captures)
	if f.guardian_kills > 0:
		split += f.guardian_kills * int(x.get("guardian_kill", 100))
		split_lines.append("Guardian kills")
	if rounds_won > 0:
		split += rounds_won * int(x.get("round_win", 300))
		split_lines.append("%d round wins" % rounds_won)
	split += int(x.get("match_win", 1000)) if won else int(x.get("match_loss", 300))
	split_lines.append("Match " + ("win" if won else "completed"))
	var total_dmg := 0
	for s in DB.STYLES:
		total_dmg += int(f.damage_by_style.get(s, 0))
	var shares := {}
	for s in DB.STYLES:
		if total_dmg > 0:
			shares[s] = float(f.damage_by_style.get(s, 0)) / float(total_dmg)
		else:
			shares[s] = 1.0 if s == primary_style else 0.0
	var given := 0
	var top := primary_style
	for s in DB.STYLES:
		var amt := int(floor(split * float(shares[s])))
		given += amt
		out[s] += amt
		if float(shares[s]) > float(shares[top]):
			top = s
	out[top] += split - given
	lines.append({"label": ", ".join(split_lines) + " (split by damage)", "amount": split, "style": "split"})
	return out


static func _add(out: Dictionary, style: String, amount: int, label: String) -> void:
	out[style] += amount
	(out["lines"] as Array).append({"label": label, "amount": amount, "style": style})
