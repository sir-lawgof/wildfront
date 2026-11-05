class_name Tournament
extends RefCounted
## U8 tournament helper for private matches and community nights: single- and double-elimination brackets.
## A tournament is a plain Dictionary (saved as JSON by the client). Each match has two slots; a slot is
## {"e": entrant index}, {"w": match id} (its winner), {"l": match id} (its loser) or {"bye": true}.
## Byes are decided automatically. Double elimination ends with a grand final and, if the losers-bracket
## player wins it, a reset match ("if_needed").

const BYE := -2
const UNKNOWN := -1


static func create(names: Array, kind: String = "single") -> Dictionary:
	var n := names.size()
	var size := 1
	while size < n:
		size *= 2
	var t := {"kind": kind, "entrants": names.duplicate(), "matches": [], "size": size}
	var seeds := _seed_order(size)
	# Winners bracket round 1 (seed 1 vs seed N ...); missing seeds are byes.
	var prev: Array = []
	for i in range(0, size, 2):
		var a: Dictionary = {"e": seeds[i]} if seeds[i] < n else {"bye": true}
		var b: Dictionary = {"e": seeds[i + 1]} if seeds[i + 1] < n else {"bye": true}
		prev.append(_add(t, "W", 1, a, b))
	var wb_rounds: Array = [prev]
	var r := 2
	while prev.size() > 1:
		var cur: Array = []
		for i in range(0, prev.size(), 2):
			cur.append(_add(t, "W", r, {"w": prev[i]}, {"w": prev[i + 1]}))
		prev = cur
		wb_rounds.append(cur)
		r += 1
	if kind != "double" or size < 4:
		t["final"] = prev[0]
		_resolve(t)
		return t
	# Losers bracket: round 1 pairs WB round-1 losers; then alternate "drop-in" rounds (LB winners vs the next
	# WB round's losers) and "consolidation" rounds (LB winners vs each other).
	var lb: Array = []
	var w1: Array = wb_rounds[0]
	for i in range(0, w1.size(), 2):
		lb.append(_add(t, "L", 1, {"l": w1[i]}, {"l": w1[i + 1]}))
	var lr := 2
	for k in range(1, wb_rounds.size()):
		var drops: Array = wb_rounds[k]
		var cur: Array = []
		for i in range(lb.size()):
			# Drop losers in reverse order so rematches are delayed.
			cur.append(_add(t, "L", lr, {"w": lb[i]}, {"l": drops[drops.size() - 1 - i]}))
		lb = cur
		lr += 1
		if lb.size() > 1:
			var con: Array = []
			for i in range(0, lb.size(), 2):
				con.append(_add(t, "L", lr, {"w": lb[i]}, {"w": lb[i + 1]}))
			lb = con
			lr += 1
	var gf := _add(t, "GF", 1, {"w": prev[0]}, {"w": lb[0]})
	var reset := _add(t, "GF", 2, {"w": gf}, {"l": gf})
	t["matches"][reset]["if_needed"] = true
	t["grand_final"] = gf
	t["final"] = reset
	_resolve(t)
	return t


## Standard bracket seeding order for a power-of-two size: [0, size-1, ...] so top seeds meet last.
static func _seed_order(size: int) -> Array:
	var order: Array = [0]
	while order.size() < size:
		var m := order.size() * 2
		var nxt: Array = []
		for s in order:
			nxt.append(s)
			nxt.append(m - 1 - int(s))
		order = nxt
	return order


static func _add(t: Dictionary, bracket: String, round: int, a: Dictionary, b: Dictionary) -> int:
	var mid: int = (t["matches"] as Array).size()
	t["matches"].append({"id": mid, "bracket": bracket, "round": round, "a": a, "b": b, "winner": UNKNOWN, "loser": UNKNOWN})
	return mid


## The entrant in a slot: index, BYE, or UNKNOWN (not decided yet).
static func slot_entrant(t: Dictionary, slot: Dictionary) -> int:
	if slot.has("e"):
		return int(slot["e"])
	if slot.has("bye"):
		return BYE
	if slot.has("w"):
		return int(t["matches"][int(slot["w"])]["winner"])
	if slot.has("l"):
		return int(t["matches"][int(slot["l"])]["loser"])
	return UNKNOWN


## Decides bye matches and a reset final that isn't needed, until nothing changes.
static func _resolve(t: Dictionary) -> void:
	var changed := true
	while changed:
		changed = false
		for m in t["matches"]:
			if int(m["winner"]) != UNKNOWN:
				continue
			# Grand-final reset: not needed when the winners-bracket player won the first final.
			if bool(m.get("if_needed", false)):
				var gf: Dictionary = t["matches"][int(t["grand_final"])]
				if int(gf["winner"]) >= 0 and int(gf["winner"]) == slot_entrant(t, gf["a"]):
					m["winner"] = int(gf["winner"])
					m["loser"] = int(gf["loser"])
					m["skipped"] = true
					changed = true
					continue
			var a := slot_entrant(t, m["a"])
			var b := slot_entrant(t, m["b"])
			if a == UNKNOWN or b == UNKNOWN:
				continue
			if a == BYE or b == BYE:
				m["winner"] = b if a == BYE else a
				m["loser"] = BYE
				m["bye"] = true
				changed = true


## Matches that can be played now: both players known, not decided.
static func ready_matches(t: Dictionary) -> Array:
	var out: Array = []
	for m in t["matches"]:
		if int(m["winner"]) == UNKNOWN and slot_entrant(t, m["a"]) >= 0 and slot_entrant(t, m["b"]) >= 0:
			out.append(int(m["id"]))
	return out


## Records a result. winner must be one of the match's two entrants.
static func report(t: Dictionary, mid: int, winner: int) -> bool:
	var m: Dictionary = t["matches"][mid]
	var a := slot_entrant(t, m["a"])
	var b := slot_entrant(t, m["b"])
	if int(m["winner"]) != UNKNOWN or a < 0 or b < 0 or (winner != a and winner != b):
		return false
	m["winner"] = winner
	m["loser"] = b if winner == a else a
	_resolve(t)
	return true


static func is_done(t: Dictionary) -> bool:
	return int(t["matches"][int(t["final"])]["winner"]) >= 0


static func champion(t: Dictionary) -> int:
	return int(t["matches"][int(t["final"])]["winner"]) if is_done(t) else UNKNOWN


## Final placings: [[place, entrant], ...], champion first. An entrant is out at their first loss (single) or
## second loss (double); later eliminations place higher, and entrants out in the same round share a place.
static func standings(t: Dictionary) -> Array:
	if not is_done(t):
		return []
	var needed := 2 if str(t["kind"]) == "double" else 1
	var losses := {}
	var out_match := {}
	for m in t["matches"]:
		var l := int(m["loser"])
		if l < 0 or bool(m.get("skipped", false)):
			continue
		losses[l] = int(losses.get(l, 0)) + 1
		if int(losses[l]) == needed:
			out_match[l] = int(m["id"])
	var champ := champion(t)
	var elim: Array = []
	for l in out_match:
		if int(l) != champ:
			elim.append([int(out_match[l]), int(l)])
	elim.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
	var res: Array = [[1, champ]]
	var place := 2
	var shared := 2
	var last_key := ""
	for e in elim:
		var m: Dictionary = t["matches"][int(e[0])]
		var key := "%s%d" % [m["bracket"], int(m["round"])]
		if key != last_key:
			shared = place
			last_key = key
		res.append([shared, int(e[1])])
		place += 1
	return res


static func match_label(t: Dictionary, mid: int) -> String:
	var m: Dictionary = t["matches"][mid]
	var names: Array = t["entrants"]
	var nm := func(e: int) -> String:
		return "BYE" if e == BYE else ("?" if e < 0 else str(names[e]))
	var where: String = {"W": "Winners", "L": "Losers", "GF": "Grand final"}.get(str(m["bracket"]), "")
	if str(t["kind"]) != "double" and str(m["bracket"]) == "W":
		where = "Round"
	return "%s %d: %s vs %s" % [where, int(m["round"]), nm.call(slot_entrant(t, m["a"])), nm.call(slot_entrant(t, m["b"]))]
