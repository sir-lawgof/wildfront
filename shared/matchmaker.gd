class_name Matchmaker
extends RefCounted
## U3 combat-level matchmaking (GDD 5 "Combat level brackets"). Casual queues group players within a combat-level
## window that starts at rules.json matchmaking.window and widens the longer someone waits. Pure logic, so a
## future online queue uses the same rules; today it also picks bot levels for matches against bots.


static func cfg() -> Dictionary:
	return DB.rule("matchmaking", {"window": 8, "widen_every_s": 15, "widen_by": 4, "max_window": 40})


## Allowed combat-level gap for someone who has waited wait_s seconds.
static func window(wait_s: float) -> int:
	var c := cfg()
	var steps := int(floor(maxf(0.0, wait_s) / maxf(1.0, float(c.get("widen_every_s", 15)))))
	return mini(int(c.get("window", 8)) + steps * int(c.get("widen_by", 4)), int(c.get("max_window", 40)))


## Two players can share a lobby when their levels fit the narrower of their two windows.
static func compatible(a: Dictionary, b: Dictionary) -> bool:
	var w := mini(window(float(a.get("wait_s", 0))), window(float(b.get("wait_s", 0))))
	return absi(int(a["cl"]) - int(b["cl"])) <= w


## Forms full lobbies from a queue of {id, cl, wait_s}. Longest-waiting players anchor first.
## Returns {"lobbies": [[ids]], "waiting": [ids]}.
static func form_lobbies(queue: Array, size: int) -> Dictionary:
	var pool: Array = queue.duplicate()
	pool.sort_custom(func(x, y): return float(x.get("wait_s", 0)) > float(y.get("wait_s", 0)))
	var lobbies: Array = []
	var used := {}
	for anchor in pool:
		if used.has(anchor["id"]):
			continue
		var group: Array = [anchor]
		var cands: Array = pool.filter(func(p): return not used.has(p["id"]) and p["id"] != anchor["id"])
		cands.sort_custom(func(x, y): return absi(int(x["cl"]) - int(anchor["cl"])) < absi(int(y["cl"]) - int(anchor["cl"])))
		for c in cands:
			if group.size() >= size:
				break
			var ok := true
			for g in group:
				if not compatible(g, c):
					ok = false
					break
			if ok:
				group.append(c)
		if group.size() >= size:
			var ids: Array = []
			for g in group:
				ids.append(g["id"])
				used[g["id"]] = true
			lobbies.append(ids)
	var waiting: Array = []
	for p in pool:
		if not used.has(p["id"]):
			waiting.append(p["id"])
	return {"lobbies": lobbies, "waiting": waiting}


## [low, high] combat levels a player at cl is matched with right now.
static func range_for(cl: int, wait_s: float = 0.0) -> Array:
	var w := window(wait_s)
	return [maxi(3, cl - w), mini(Progression.combat_level(40, 40, 40), cl + w)]


## Gear tier of a loadout: the average tier of the weapon and worn armour (what the loading screen shows).
static func gear_tier(equipment: Dictionary) -> float:
	var total := 0
	var n := 0
	for slot in ["weapon", "head", "body", "legs", "shield"]:
		var it := DB.item(str(equipment.get(slot, "")))
		if it.has("tier") and not bool(it.get("unique", false)):
			total += int(it["tier"])
			n += 1
	return float(total) / n if n > 0 else 1.0
