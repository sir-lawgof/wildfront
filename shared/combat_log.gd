class_name CombatLog
extends RefCounted
## Per-match fight log recorded by the Sim (U6 death recap / fight report, U11 telemetry).
## Entries are small dictionaries with "k" (kind) and "tick":
##   hit    a, d, style, weapon, spec, ward (target's ward when the attack was made), dmg, splash
##   dmg    a, d, style, weapon, dmg          (damage that didn't come from an attack: meteors, poison, rebuke...)
##   eat    f, item, heal, wasted
##   ward   f, ward                           (protection prayer changed; "" = none)
##   freeze a, d, ticks
##   spec   f                                 (special attack used)
##   death  v, killer, ttk, spec_left, food_left
##   spawn  f
## Analysis only ever uses what the player could see: hits on them, their own actions and prayers,
## and attacks they made. Nothing about enemies' HP, food or prayers off-screen.

var entries: Array = []


func add(e: Dictionary) -> void:
	entries.append(e)


# ---------------------------------------------------------------- death recap

## Everything that happened to `fid` in their life ending at `death_tick` (or the latest life).
## Returns {hits: [{tick, attacker, style, weapon, dmg, ward, wrong_ward, splash, spec}], eats: [...],
##          wasted_heal, killer, ticks}
func recap(fid: int, death_tick: int = -1) -> Dictionary:
	var start := 0
	var end := death_tick
	var killer := -1
	for e in entries:
		var k := str(e["k"])
		if k == "spawn" and int(e["f"]) == fid and (end == -1 or int(e["tick"]) <= end):
			start = int(e["tick"])
		if k == "death" and int(e["v"]) == fid:
			if death_tick == -1 or int(e["tick"]) == death_tick:
				end = int(e["tick"])
				killer = int(e["killer"])
	if end == -1:
		end = 1 << 30
	var hits: Array = []
	var eats: Array = []
	var wasted := 0
	for e in entries:
		var t := int(e["tick"])
		if t < start or t > end:
			continue
		match str(e["k"]):
			"hit":
				if int(e["d"]) == fid:
					var style := str(e["style"])
					var ward := str(e["ward"])
					hits.append({"tick": t, "attacker": int(e["a"]), "style": style, "weapon": str(e["weapon"]), "dmg": int(e["dmg"]),
						"ward": ward, "wrong_ward": DB.STYLES.has(style) and ward != style, "splash": bool(e.get("splash", false)),
						"spec": bool(e.get("spec", false))})
			"dmg":
				if int(e["d"]) == fid and int(e["dmg"]) > 0:
					hits.append({"tick": t, "attacker": int(e["a"]), "style": str(e["style"]), "weapon": str(e["weapon"]), "dmg": int(e["dmg"]),
						"ward": "", "wrong_ward": false, "splash": false, "spec": false})
			"eat":
				if int(e["f"]) == fid:
					eats.append({"tick": t, "item": str(e["item"]), "heal": int(e["heal"]), "wasted": int(e["wasted"])})
					wasted += int(e["wasted"])
	return {"hits": hits, "eats": eats, "wasted_heal": wasted, "killer": killer, "start": start, "end": end}


# ---------------------------------------------------------------- fight report

## Match-long numbers for one fighter. live_ticks = how long the match ran (for per-tick rates).
func report(fid: int, live_ticks: int) -> Dictionary:
	var incoming := {"melee": 0, "ranged": 0, "magic": 0}
	var correct := {"melee": 0, "ranged": 0, "magic": 0}
	var dmg_by_style := {"melee": 0, "ranged": 0, "magic": 0}
	var specs_used := 0
	var specs_unused := 0
	var food_unused := 0
	var freeze_ticks := 0
	var deaths := 0
	var wasted := 0
	var ward_changes: Array = []    # [tick, ward] for fid
	var attacks_on_me: Array = []   # [tick, attacker, style]
	for e in entries:
		match str(e["k"]):
			"hit":
				var style := str(e["style"])
				if int(e["d"]) == fid and DB.STYLES.has(style):
					incoming[style] += 1
					if str(e["ward"]) == style:
						correct[style] += 1
					attacks_on_me.append([int(e["tick"]), int(e["a"]), style])
				if int(e["a"]) == fid and DB.STYLES.has(style):
					dmg_by_style[style] += int(e["dmg"])
			"spec":
				if int(e["f"]) == fid:
					specs_used += 1
			"freeze":
				if int(e["a"]) == fid:
					freeze_ticks += int(e["ticks"])
			"eat":
				if int(e["f"]) == fid:
					wasted += int(e["wasted"])
			"ward":
				if int(e["f"]) == fid:
					ward_changes.append([int(e["tick"]), str(e["ward"])])
			"death":
				if int(e["v"]) == fid:
					deaths += 1
					specs_unused += int(e.get("spec_left", 0)) / 50
					food_unused += int(e.get("food_left", 0))
	var total_in := 0
	var total_ok := 0
	var acc_by_style := {}
	for s in incoming:
		total_in += int(incoming[s])
		total_ok += int(correct[s])
		acc_by_style[s] = (float(correct[s]) / float(incoming[s])) if int(incoming[s]) > 0 else -1.0
	var reactions := _reactions(attacks_on_me, ward_changes)
	var avg_reaction := -1.0
	if not reactions.is_empty():
		var sum := 0
		for r in reactions:
			sum += int(r)
		avg_reaction = float(sum) / reactions.size()
	var dpt := {}
	for s in dmg_by_style:
		dpt[s] = float(dmg_by_style[s]) / float(maxi(live_ticks, 1))
	return {
		"incoming": total_in, "ward_accuracy": (float(total_ok) / total_in) if total_in > 0 else -1.0,
		"ward_accuracy_by_style": acc_by_style, "incoming_by_style": incoming,
		"reaction_avg": avg_reaction, "reaction_samples": reactions.size(),
		"specs_used": specs_used, "specs_available": specs_used + specs_unused,
		"freeze_uptime": float(freeze_ticks) / float(maxi(live_ticks, 1)), "food_unused": food_unused,
		"wasted_heal": wasted, "dmg_per_tick": dpt, "deaths": deaths,
	}


## Ticks from an attacker switching style (seen as their next attack on you) until your ward matches it.
## A change that you never answered within 20 ticks counts as 20.
func _reactions(attacks: Array, wards: Array) -> Array:
	var out: Array = []
	var last_style := {}
	for at in attacks:
		var tick := int(at[0])
		var aid := int(at[1])
		var style := str(at[2])
		if last_style.has(aid) and str(last_style[aid]) != style:
			var ward_now := _ward_at(wards, tick)
			if ward_now == style:
				out.append(0)
			else:
				var r := 20
				for w in wards:
					if int(w[0]) > tick and str(w[1]) == style:
						r = mini(20, int(w[0]) - tick)
						break
				out.append(r)
		last_style[aid] = style
	return out


func _ward_at(wards: Array, tick: int) -> String:
	var cur := ""
	for w in wards:
		if int(w[0]) <= tick:
			cur = str(w[1])
		else:
			break
	return cur


## One-line tip from the weakest stat in a report (U6).
static func tip(r: Dictionary) -> String:
	var worst_style := ""
	var worst := 2.0
	var by: Dictionary = r.get("ward_accuracy_by_style", {})
	var n: Dictionary = r.get("incoming_by_style", {})
	for s in by:
		if float(by[s]) >= 0.0 and int(n.get(s, 0)) >= 4 and float(by[s]) < worst:
			worst = float(by[s])
			worst_style = s
	if worst_style != "" and worst < 0.6:
		return "You prayed the wrong ward against %d%% of %s hits." % [int(round((1.0 - worst) * 100.0)), worst_style]
	if float(r.get("reaction_avg", -1.0)) > 4.0:
		return "You took %.1f ticks on average to switch wards after an enemy changed style. Aim for 1-2." % float(r["reaction_avg"])
	if int(r.get("specs_available", 0)) > 0 and int(r.get("specs_used", 0)) * 2 < int(r.get("specs_available", 0)):
		return "You used %d of %d special attacks. Spec when they're low." % [int(r["specs_used"]), int(r["specs_available"])]
	if int(r.get("food_unused", 0)) >= 6 and int(r.get("deaths", 0)) > 0:
		return "You died with %d food left over. Eat earlier and combo-eat under pressure." % int(r["food_unused"])
	if int(r.get("wasted_heal", 0)) >= 60:
		return "%d healing was wasted by eating near full HP." % int(r["wasted_heal"])
	return "Solid fight. Try the Instructor's Challenge in the Proving Grounds."
