class_name Ranked
extends RefCounted
## U4 ranked play and seasons (data/ranked.json). Pure functions on a plain state Dictionary, so the local profile
## keeps it now and a future online server can own the same data. Rating is Glicko-2 (one match = one rating
## period); the visible rank is a band + division; points are earned every match toward cosmetic rewards.

const SCALE := 173.7178


static func cfg() -> Dictionary:
	return DB.ranked


static func new_state(season: int) -> Dictionary:
	var g: Dictionary = cfg()["glicko"]
	return {"season": season, "rating": float(g["rating"]), "rd": float(g["rd"]), "vol": float(g["vol"]),
		"matches": 0, "wins": 0, "points": 0, "peak": 0.0, "history": [], "rewards": [], "week": -1, "week_matches": 0,
		"leave_times": []}


# ---------------------------------------------------------------- Glicko-2

## One rating period against several results: [{rating, rd, score (1 win / 0.5 draw / 0 loss)}].
## Returns {rating, rd, vol}. Follows Glickman's "Example of the Glicko-2 system".
static func glicko2(rating: float, rd: float, vol: float, results: Array, tau: float = -1.0) -> Dictionary:
	if tau < 0.0:
		tau = float(cfg()["glicko"]["tau"])
	var mu := (rating - 1500.0) / SCALE
	var phi := rd / SCALE
	if results.is_empty():
		return {"rating": rating, "rd": minf(sqrt(phi * phi + vol * vol) * SCALE, float(cfg()["glicko"]["max_rd"])), "vol": vol}
	var v_inv := 0.0
	var dsum := 0.0
	for r in results:
		var mu_j := (float(r["rating"]) - 1500.0) / SCALE
		var phi_j := float(r["rd"]) / SCALE
		var g := 1.0 / sqrt(1.0 + 3.0 * phi_j * phi_j / (PI * PI))
		var e := 1.0 / (1.0 + exp(-g * (mu - mu_j)))
		v_inv += g * g * e * (1.0 - e)
		dsum += g * (float(r["score"]) - e)
	var v := 1.0 / v_inv
	var delta := v * dsum
	# New volatility (Illinois algorithm).
	var a := log(vol * vol)
	var eps := 0.000001
	var f := func(x: float) -> float:
		var ex := exp(x)
		return ex * (delta * delta - phi * phi - v - ex) / (2.0 * pow(phi * phi + v + ex, 2)) - (x - a) / (tau * tau)
	var A := a
	var B := 0.0
	if delta * delta > phi * phi + v:
		B = log(delta * delta - phi * phi - v)
	else:
		var k := 1
		while float(f.call(a - k * tau)) < 0.0:
			k += 1
		B = a - k * tau
	var fA: float = f.call(A)
	var fB: float = f.call(B)
	var guard := 0
	while absf(B - A) > eps and guard < 100:
		guard += 1
		var C := A + (A - B) * fA / (fB - fA)
		var fC: float = f.call(C)
		if fC * fB <= 0.0:
			A = B
			fA = fB
		else:
			fA = fA / 2.0
		B = C
		fB = fC
	var new_vol := exp(A / 2.0)
	var phi_star := sqrt(phi * phi + new_vol * new_vol)
	var new_phi := 1.0 / sqrt(1.0 / (phi_star * phi_star) + 1.0 / v)
	var new_mu := mu + new_phi * new_phi * dsum
	return {"rating": new_mu * SCALE + 1500.0, "rd": new_phi * SCALE, "vol": new_vol}


## Win chance for a against b (for matchmaking display and the season simulation).
static func expected(ra: float, rd_a: float, rb: float, rd_b: float) -> float:
	var phi := sqrt(rd_a * rd_a + rd_b * rd_b) / SCALE
	var g := 1.0 / sqrt(1.0 + 3.0 * phi * phi / (PI * PI))
	return 1.0 / (1.0 + exp(-g * (ra - rb) / SCALE))


# ---------------------------------------------------------------- ranks

static func placed(state: Dictionary) -> bool:
	return int(state["matches"]) >= int(cfg()["placement_matches"])


## {band, division (1 = best), label}; division 0 for single-division bands.
static func rank_for(rating: float) -> Dictionary:
	var bands: Array = cfg()["bands"]
	var idx := 0
	for i in range(bands.size()):
		if rating >= float(bands[i]["from"]):
			idx = i
	var b: Dictionary = bands[idx]
	var divs := int(b.get("divisions", cfg().get("divisions", 3)))
	if divs <= 1:
		return {"band": str(b["name"]), "division": 0, "label": str(b["name"]), "index": idx}
	var lo := float(b["from"])
	var hi := float(bands[idx + 1]["from"]) if idx + 1 < bands.size() else lo + 120.0
	var step := (hi - lo) / divs
	var d := divs - mini(divs - 1, int(floor((rating - lo) / step)))
	var roman: String = ["", "I", "II", "III", "IV", "V"][d]
	return {"band": str(b["name"]), "division": d, "label": "%s %s" % [b["name"], roman], "index": idx}


## What the player sees: "Placement 2/5" or "Gold II". The rating itself stays hidden.
static func visible_rank(state: Dictionary) -> String:
	if not placed(state):
		return "Placement %d/%d" % [int(state["matches"]), int(cfg()["placement_matches"])]
	return str(rank_for(float(state["rating"]))["label"])


# ---------------------------------------------------------------- matches

## Records a ranked match for this player. opponents: [{id, rating, rd}] (the enemy team). Rating change is reduced
## for repeated matches against the same opponent in a short window (win-trading guard).
## Returns {delta, points, mult, rewards} (rewards: points-track rewards just reached).
static func apply_match(state: Dictionary, opponents: Array, won: bool, now: int, draw: bool = false) -> Dictionary:
	if opponents.is_empty():
		return {"delta": 0.0, "points": 0, "mult": 0.0, "rewards": []}
	# Team opponents count as one: average rating, combined RD.
	var r_sum := 0.0
	var rd_sq := 0.0
	var ids: Array = []
	for o in opponents:
		r_sum += float(o["rating"])
		rd_sq += float(o["rd"]) * float(o["rd"])
		ids.append(str(o.get("id", "")))
	var opp := {"rating": r_sum / opponents.size(), "rd": sqrt(rd_sq / opponents.size()), "score": 0.5 if draw else (1.0 if won else 0.0)}
	var mult := repeat_mult(state, ids, now)
	var res := glicko2(float(state["rating"]), float(state["rd"]), float(state["vol"]), [opp])
	var delta := (float(res["rating"]) - float(state["rating"])) * mult
	state["rating"] = float(state["rating"]) + delta
	state["rd"] = clampf(float(res["rd"]), float(cfg()["glicko"]["min_rd"]), float(cfg()["glicko"]["max_rd"]))
	state["vol"] = float(res["vol"])
	state["matches"] = int(state["matches"]) + 1
	if won:
		state["wins"] = int(state["wins"]) + 1
	var pts := int(round(int(cfg()["points"]["win" if won else "loss"]) * mult))
	var before := int(state["points"])
	state["points"] = before + pts
	if placed(state):
		state["peak"] = maxf(float(state["peak"]), float(state["rating"]))
	var hist: Array = state["history"]
	hist.append({"t": now, "opp": ids, "won": won})
	if hist.size() > 60:
		hist.pop_front()
	var week := week_of(now)
	if int(state.get("week", -1)) != week:
		state["week"] = week
		state["week_matches"] = 0
	state["week_matches"] = int(state["week_matches"]) + 1
	var new_rewards: Array = []
	for r in cfg()["points_rewards"]:
		if before < int(r["points"]) and int(state["points"]) >= int(r["points"]):
			new_rewards.append(str(r["reward"]))
			(state["rewards"] as Array).append(str(r["reward"]))
	return {"delta": delta, "points": pts, "mult": mult, "rewards": new_rewards}


## Rating multiplier from how often we've met these opponents within integrity.repeat_window_min.
static func repeat_mult(state: Dictionary, ids: Array, now: int) -> float:
	var ig: Dictionary = cfg()["integrity"]
	var window := int(ig["repeat_window_min"]) * 60
	var n := 0
	for h in state["history"]:
		if now - int(h["t"]) > window:
			continue
		for i in ids:
			if str(i) != "" and (h["opp"] as Array).has(i):
				n += 1
				break
	var mults: Array = ig["repeat_mults"]
	return float(mults[mini(n, mults.size() - 1)])


# ---------------------------------------------------------------- seasons and decay

static func season_of(now: int) -> int:
	var s: Dictionary = cfg()["season"]
	var epoch := int(Time.get_unix_time_from_datetime_string(str(s["epoch"])))
	return int(floor(float(now - epoch) / (604800.0 * int(s["weeks"]))))


static func week_of(now: int) -> int:
	var epoch := int(Time.get_unix_time_from_datetime_string(str(cfg()["season"]["epoch"])))
	return int(floor(float(now - epoch) / 604800.0))


static func season_days_left(now: int) -> int:
	var s: Dictionary = cfg()["season"]
	var epoch := int(Time.get_unix_time_from_datetime_string(str(s["epoch"])))
	var end := epoch + (season_of(now) + 1) * 604800 * int(s["weeks"])
	return int(ceil((end - now) / 86400.0))


## Weekly decay for players who played fewer than min_matches_per_week (never below the floor). Call once per
## week rollover with the number of whole weeks missed. Players who keep playing never decay.
static func apply_decay(state: Dictionary, now: int) -> float:
	var d: Dictionary = cfg()["decay"]
	var week := week_of(now)
	var last := int(state.get("week", -1))
	if last < 0 or week <= last:
		return 0.0
	var lost := 0.0
	for w in range(last, week):
		var played := int(state["week_matches"]) if w == last else 0
		if placed(state) and played < int(d["min_matches_per_week"]):
			var drop := minf(float(d["rating_per_week"]), maxf(0.0, float(state["rating"]) - float(d["floor"])))
			state["rating"] = float(state["rating"]) - drop
			lost += drop
	state["week"] = week
	state["week_matches"] = 0
	return lost


## New season: end-of-season rewards from the peak rank, then a soft reset toward the start rating.
## Returns {rewards, previous_peak}. Does nothing if the state is already this season.
static func roll_season(state: Dictionary, now: int) -> Dictionary:
	var cur := season_of(now)
	if int(state["season"]) >= cur:
		return {"rewards": [], "previous_peak": ""}
	var rewards: Array = []
	var peak_label := ""
	if float(state["peak"]) > 0.0:
		var peak := rank_for(float(state["peak"]))
		peak_label = str(peak["label"])
		var bands: Array = cfg()["bands"]
		var pr: Dictionary = cfg()["peak_rewards"]
		for i in range(int(peak["index"]) + 1):
			var bn := str(bands[i]["name"])
			if pr.has(bn):
				rewards.append(str(pr[bn]))
	var s: Dictionary = cfg()["season"]
	var start := float(cfg()["glicko"]["rating"])
	state["rating"] = start + (float(state["rating"]) - start) * float(s["soft_reset"])
	state["rd"] = maxf(float(state["rd"]), float(s["reset_rd"]))
	state["season"] = cur
	state["matches"] = 0
	state["wins"] = 0
	state["points"] = 0
	state["peak"] = 0.0
	state["rewards"] = []
	return {"rewards": rewards, "previous_peak": peak_label}


## The playlist that plays this week's featured bracket (ranked always uses it).
static func featured_playlist(now: int = -1) -> String:
	var feat := Brackets.featured(now)
	for pk in DB.modes.get("playlists", {}):
		var pl: Dictionary = DB.modes["playlists"][pk]
		if str(pl.get("bracket", "")) == feat and not bool(pl.get("lab", false)):
			return str(pk)
	return "warlord"


# ---------------------------------------------------------------- earn rate

## Average points an hour for a player who wins win_rate of their matches, at the data's match lengths.
static func points_per_hour(win_rate: float = 0.5) -> float:
	var p: Dictionary = cfg()["points"]
	var per_match := win_rate * float(p["win"]) + (1.0 - win_rate) * float(p["loss"])
	var mins: Dictionary = cfg()["minutes_per_match"]
	var avg := 0.0
	for m in mins:
		avg += float(mins[m])
	avg /= maxf(1.0, float(mins.size()))
	return per_match * 60.0 / avg


static func mid_reward() -> Dictionary:
	for r in cfg()["points_rewards"]:
		if bool(r.get("mid", false)):
			return r
	return {}


static func validate(errors: Array[String]) -> void:
	var c := cfg()
	for k in ["modes", "glicko", "bands", "season", "points", "points_rewards", "integrity", "decay", "minutes_per_match"]:
		if not c.has(k):
			errors.append("ranked.json: missing '%s'" % k)
			return
	for m in c["modes"]:
		if not (DB.modes["modes"] as Dictionary).has(str(m)):
			errors.append("ranked.json: unknown mode %s" % m)
	var last := -1.0
	for b in c["bands"]:
		if float(b["from"]) <= last:
			errors.append("ranked.json: bands must rise")
		last = float(b["from"])
	for r in c["points_rewards"]:
		var kind := str(r["reward"]).split(":")[0]
		if not ["banner", "title", "cape_trim"].has(kind):
			errors.append("ranked.json: reward %s must be a banner, title or cape_trim" % r["reward"])
	if mid_reward().is_empty():
		errors.append("ranked.json: no points reward marked mid")
