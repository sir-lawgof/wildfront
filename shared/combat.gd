class_name Combat
extends RefCounted
## OSRS accuracy and max-hit formulas (GDD 2 "Accuracy and damage"). Pure functions,
## unit-tested in tests/test_combat.gd.


## Effective level = floor(level * prayer multiplier) + stance bonus + 8.
static func effective_level(level: int, prayer_mult: float, stance_bonus: int) -> int:
	return int(floor(level * prayer_mult + 1e-6)) + stance_bonus + 8


## Max roll = effective level * (equipment bonus + 64).
static func max_roll(eff_level: int, bonus: int) -> int:
	return eff_level * (bonus + 64)


## If A > D: 1 - (D + 2) / (2 (A + 1)); otherwise A / (2 (D + 1)).
static func hit_chance(att_roll: int, def_roll: int) -> float:
	var a := float(maxi(att_roll, 0))
	var d := float(maxi(def_roll, 0))
	if a > d:
		return 1.0 - (d + 2.0) / (2.0 * (a + 1.0))
	return a / (2.0 * (d + 1.0))


## floor(0.5 + effective strength * (strength bonus + 64) / 640). Ranged uses the same shape.
static func max_hit(eff_strength: int, str_bonus: int) -> int:
	return int(floor(0.5 + float(eff_strength) * float(str_bonus + 64) / 640.0))


## Spell base damage scaled by magic damage % from gear.
static func magic_max_hit(base: int, dmg_pct: float) -> int:
	return int(floor(base * (1.0 + dmg_pct / 100.0) + 1e-6))


## Ticks between the attack and the hit landing (GDD 2: melee 0, ranged 1-3, magic 1-4).
static func hit_delay(style: String, distance: int) -> int:
	match style:
		"ranged":
			return clampi(1 + int(floor((3.0 + distance) / 6.0)), 1, 3)
		"magic":
			return clampi(1 + int(floor((1.0 + distance) / 3.0)), 1, 4)
	return 0


## reduction < 0 = the data value (prayers.json protect_reduction); The Lab can pass its own.
static func protect_damage(dmg: int, reduction: float = -1.0) -> int:
	if reduction < 0.0:
		reduction = DB.protect_reduction
	return int(floor(dmg * (1.0 - reduction)))


# ---------------------------------------------------------------- fighter-level helpers

static func _stance(f: Fighter, which: String) -> int:
	var b := int(DB.rule("stance_bonus", 3))
	if which == "accuracy" and f.stance == "accurate":
		return b
	if which == "strength" and f.stance == "aggressive":
		return b
	if which == "defence" and f.stance == "defensive":
		return b
	return 0


static func attack_roll(f: Fighter, style: String) -> int:
	if f.npc_kind == "guardian":
		var g: Dictionary = DB.streaks.get("guardian", {})
		return max_roll(effective_level(99, 1.0, 0), int(g.get("att_magic", 60)))
	match style:
		"melee":
			var eff := effective_level(int(f.levels["attack"]), f.prayer_mult("attack"), _stance(f, "accuracy"))
			return max_roll(eff, int(f.bonuses["att_melee"]))
		"ranged":
			var eff := effective_level(int(f.levels["ranged"]), f.prayer_mult("ranged_att"), _stance(f, "accuracy"))
			return max_roll(eff, int(f.bonuses["att_ranged"]))
		"magic":
			var eff := effective_level(int(f.levels["magic"]), f.prayer_mult("magic"), _stance(f, "accuracy"))
			return max_roll(eff, int(f.bonuses["att_magic"]))
	return 0


static func defence_roll(f: Fighter, style: String) -> int:
	var def_lvl := int(floor(int(f.levels["defence"]) * f.prayer_mult("defence") + 1e-6))
	var stance_b := _stance(f, "defence")
	match style:
		"melee":
			return max_roll(def_lvl + stance_b + 8, int(f.bonuses["def_melee"]))
		"ranged":
			return max_roll(def_lvl + stance_b + 8, int(f.bonuses["def_ranged"]))
		"magic":
			# OSRS PvP: magic defence uses 70% Magic and 30% Defence.
			var mag_lvl := int(floor(int(f.levels["magic"]) * f.prayer_mult("magic") + 1e-6))
			var eff := int(floor(mag_lvl * float(DB.rule("magic_def_magic_weight", 0.7)) + def_lvl * float(DB.rule("magic_def_defence_weight", 0.3)))) + stance_b + 8
			return max_roll(eff, int(f.bonuses["def_magic"]))
	return max_roll(def_lvl + 8, 0)


## Max hit for the fighter's next attack, including the global damage_scale.
static func fighter_max_hit(f: Fighter, style: String, spell_id: String = "") -> int:
	var raw := base_max_hit(f, style, spell_id)
	if f.npc_kind != "":
		return raw
	return int(floor(raw * float(DB.rule("damage_scale", 1.0)) + 1e-6))


## Max hit from the OSRS formulas alone (before damage_scale).
static func base_max_hit(f: Fighter, style: String, spell_id: String = "") -> int:
	if f.npc_kind == "guardian":
		return int(DB.streaks.get("guardian", {}).get("max_hit", 20))
	match style:
		"melee":
			var eff := effective_level(int(f.levels["strength"]), f.prayer_mult("strength"), _stance(f, "strength"))
			return max_hit(eff, int(f.bonuses["str_melee"]))
		"ranged":
			var eff := effective_level(int(f.levels["ranged"]), f.prayer_mult("ranged_str"), _stance(f, "strength"))
			return max_hit(eff, int(f.bonuses["str_ranged"]))
		"magic":
			var sp: Dictionary = DB.spells.get(spell_id, {})
			var base := int(sp.get("max_hit", 0))
			var pct := float(f.bonuses["dmg_magic"])
			var mods: Dictionary = f.loadout.get("spell_mods", {})
			if str(sp.get("family", "")) == "ember" and mods.has("ember_bonus"):
				pct += float(mods["ember_bonus"])
			return magic_max_hit(base, pct)
	return 0
