class_name Telemetry
extends RefCounted
## U11 playtest telemetry. record() turns a finished match into a small JSON-safe dictionary with no
## personal data (no names, no machine info): mode, map, bracket, classes, length, time-to-kill,
## ward accuracy, leavers and Lab votes. report() summarises many records as Markdown for the pitch.
## The client writes one record per match to user://telemetry/ unless Options -> Telemetry is off.

const SCHEMA := 1
const DIR := "user://telemetry"


static func record(sim: Sim, playlist: String, extra: Dictionary = {}) -> Dictionary:
	var fighters: Array = []
	var ward_in := 0
	var ward_ok := 0
	var human_in := 0
	var human_ok := 0
	var leavers := 0
	for f in sim.fighters.values():
		var fi: Fighter = f
		if fi.npc_kind != "":
			continue
		var r := sim.clog.report(fi.id, sim.live_ticks)
		var inc := int(r["incoming"])
		var ok := int(round(float(r["ward_accuracy"]) * inc)) if inc > 0 else 0
		ward_in += inc
		ward_ok += ok
		var human := not fi.is_bot or fi.left_match
		if human:
			human_in += inc
			human_ok += ok
		if fi.left_match:
			leavers += 1
		var my_ttk: Array = []
		for e in sim.clog.entries:
			if str(e["k"]) == "death" and int(e["killer"]) == fi.id:
				my_ttk.append(int(e["ttk"]))
		var ttk_avg := -1.0
		if not my_ttk.is_empty():
			var tsum := 0
			for t in my_ttk:
				tsum += int(t)
			ttk_avg = float(tsum) / my_ttk.size()
		fighters.append({
			"ttk_avg": ttk_avg,
			"class": str(fi.loadout.get("name", "")), "style": str(fi.loadout.get("style", "")), "team": fi.team,
			"bot": fi.is_bot and not fi.left_match, "left": fi.left_match, "kills": fi.kills, "deaths": fi.deaths,
			"damage": fi.damage_dealt, "cl": fi.combat_level, "ward_accuracy": r["ward_accuracy"],
			"reaction_avg": r["reaction_avg"],
		})
	var ttk: Array = []
	for e in sim.clog.entries:
		if str(e["k"]) == "death" and int(e["killer"]) != -1:
			ttk.append(int(e["ttk"]))
	var out := {
		"schema": SCHEMA, "version": str(ProjectSettings.get_setting("application/config/version", "dev")),
		"mode": sim.mode_id, "mode_type": sim.rules.type, "map": sim.map.id, "bracket": playlist,
		"ticks": sim.live_ticks, "minutes": snappedf(sim.live_ticks * float(DB.rule("tick_seconds", 0.6)) / 60.0, 0.01),
		"winner": int(sim.result.get("winner", -1)), "scores": sim.scores.duplicate(),
		"fighters": fighters, "ttk_ticks": ttk,
		"ward_accuracy": (float(ward_ok) / ward_in) if ward_in > 0 else -1.0,
		"human_ward_accuracy": (float(human_ok) / human_in) if human_in > 0 else -1.0,
		"leavers": leavers,
	}
	for k in extra:
		out[k] = extra[k]
	return out


## Markdown summary of many records (tools/telemetry_report.gd).
static func report(records: Array) -> String:
	var n := records.size()
	var md := "# Wildfront playtest telemetry\n\n"
	if n == 0:
		return md + "No matches recorded.\n"
	var minutes := 0.0
	var by_mode := {}
	var by_bracket := {}
	var classes := {}   # name -> {picks, wins, kills, deaths}
	var ttk: Array = []
	var ward_sum := 0.0
	var ward_n := 0
	var all_ward_sum := 0.0
	var all_ward_n := 0
	var leavers := 0
	var players := 0
	var votes := {}     # mutator -> {keep, change, drop}
	var ratings: Array = []
	var comments: Array = []
	for rec in records:
		var r: Dictionary = rec
		minutes += float(r.get("minutes", 0.0))
		by_mode[str(r.get("mode", "?"))] = int(by_mode.get(str(r.get("mode", "?")), 0)) + 1
		by_bracket[str(r.get("bracket", "?"))] = int(by_bracket.get(str(r.get("bracket", "?")), 0)) + 1
		for t in r.get("ttk_ticks", []):
			ttk.append(int(t))
		if float(r.get("human_ward_accuracy", -1.0)) >= 0.0:
			ward_sum += float(r["human_ward_accuracy"])
			ward_n += 1
		if float(r.get("ward_accuracy", -1.0)) >= 0.0:
			all_ward_sum += float(r["ward_accuracy"])
			all_ward_n += 1
		leavers += int(r.get("leavers", 0))
		var winner := int(r.get("winner", -1))
		for f in r.get("fighters", []):
			var fd: Dictionary = f
			players += 1
			var cn := str(fd.get("class", "?"))
			if not classes.has(cn):
				classes[cn] = {"picks": 0, "wins": 0, "kills": 0, "deaths": 0}
			classes[cn]["picks"] += 1
			classes[cn]["kills"] += int(fd.get("kills", 0))
			classes[cn]["deaths"] += int(fd.get("deaths", 0))
			if winner >= 0 and int(fd.get("team", -2)) == winner:
				classes[cn]["wins"] += 1
		var lab: Dictionary = r.get("lab", {})
		if lab.has("mutator") and lab.has("vote"):
			var m := str(lab["mutator"])
			if not votes.has(m):
				votes[m] = {"keep": 0, "change": 0, "drop": 0}
			if (votes[m] as Dictionary).has(str(lab["vote"])):
				votes[m][str(lab["vote"])] += 1
		var fb: Dictionary = r.get("feedback", {})
		if fb.has("rating"):
			ratings.append(int(fb["rating"]))
		if str(fb.get("text", "")).strip_edges() != "":
			comments.append(str(fb["text"]).strip_edges().left(300))
	md += "- Matches: **%d** (%.1f hours of play)\n" % [n, minutes / 60.0]
	md += "- Average match length: %.1f min\n" % (minutes / n)
	if not ttk.is_empty():
		ttk.sort()
		var s := 0
		for t in ttk:
			s += int(t)
		md += "- Time to kill: median %.1f s, average %.1f s (%d kills)\n" % [ttk[ttk.size() / 2] * 0.6, s * 0.6 / ttk.size(), ttk.size()]
	if ward_n > 0:
		md += "- Player ward accuracy (incoming hits prayed against correctly): %d%%\n" % int(round(ward_sum / ward_n * 100.0))
	if all_ward_n > 0:
		md += "- Ward accuracy, all fighters including bots: %d%%
" % int(round(all_ward_sum / all_ward_n * 100.0))
	md += "- Leavers: %d of %d player slots (%.1f%%)\n" % [leavers, players, 100.0 * leavers / maxi(players, 1)]
	if not ratings.is_empty():
		var rs := 0
		for x in ratings:
			rs += int(x)
		md += "- Feedback rating: %.2f / 5 from %d responses\n" % [float(rs) / ratings.size(), ratings.size()]
	md += "\n## Modes\n\n| Mode | Matches |\n| --- | ---: |\n"
	for k in _sorted_keys(by_mode):
		md += "| %s | %d |\n" % [str(DB.modes["modes"].get(k, {}).get("name", k)), int(by_mode[k])]
	md += "\n## Brackets and playlists\n\n| Bracket | Matches |\n| --- | ---: |\n"
	for k in _sorted_keys(by_bracket):
		md += "| %s | %d |\n" % [k, int(by_bracket[k])]
	md += "\n## Classes\n\n| Class | Pick rate | Win rate | K/D |\n| --- | ---: | ---: | ---: |\n"
	for k in _sorted_keys(classes):
		var c: Dictionary = classes[k]
		md += "| %s | %d%% | %d%% | %.2f |\n" % [k, int(round(100.0 * int(c["picks"]) / maxi(players, 1))), int(round(100.0 * int(c["wins"]) / maxi(int(c["picks"]), 1))), float(c["kills"]) / maxf(1.0, float(c["deaths"]))]
	if not votes.is_empty():
		md += "\n## The Lab votes\n\n| Mutator | Keep | Change | Drop |\n| --- | ---: | ---: | ---: |\n"
		for k in _sorted_keys(votes):
			md += "| %s | %d | %d | %d |\n" % [k, int(votes[k]["keep"]), int(votes[k]["change"]), int(votes[k]["drop"])]
	if not comments.is_empty():
		md += "\n## Playtester comments\n\n"
		for c in comments:
			md += "- %s\n" % str(c).replace("\n", " ")
	return md


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


## U9 meta report: per bracket (playlist) and class: player slots, pick rate, win rate, average time-to-kill (s).
## Returns {bracket: {class: {picks, pick_rate, win_rate, ttk_s}}} from saved records (bots included).
static func meta(records: Array) -> Dictionary:
	var out := {}
	var slots := {}
	for rec in records:
		var r: Dictionary = rec
		if r.has("training"):
			continue
		var b := str(r.get("bracket", "standard"))
		if not out.has(b):
			out[b] = {}
			slots[b] = 0
		var winner := int(r.get("winner", -1))
		for f in r.get("fighters", []):
			var fd: Dictionary = f
			var cn := str(fd.get("class", "?"))
			slots[b] = int(slots[b]) + 1
			if not out[b].has(cn):
				out[b][cn] = {"picks": 0, "wins": 0, "ttk_sum": 0.0, "ttk_n": 0}
			var c: Dictionary = out[b][cn]
			c["picks"] += 1
			if winner >= 0 and int(fd.get("team", -2)) == winner:
				c["wins"] += 1
			if float(fd.get("ttk_avg", -1.0)) >= 0.0:
				c["ttk_sum"] += float(fd["ttk_avg"])
				c["ttk_n"] += 1
	for b in out:
		for cn in out[b]:
			var c: Dictionary = out[b][cn]
			c["pick_rate"] = float(c["picks"]) / maxf(1.0, float(slots[b]))
			c["win_rate"] = float(c["wins"]) / maxf(1.0, float(c["picks"]))
			c["ttk_s"] = (float(c["ttk_sum"]) / int(c["ttk_n"]) * float(DB.rule("tick_seconds", 0.6))) if int(c["ttk_n"]) > 0 else -1.0
	return out


## Loads every record from a folder of .json files and/or exported .zip files.
static func load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		var full := path.path_join(f)
		if f.ends_with(".json"):
			var j = JSON.parse_string(FileAccess.get_file_as_string(full))
			if j is Dictionary:
				out.append(j)
		elif f.ends_with(".zip"):
			var z := ZIPReader.new()
			if z.open(full) == OK:
				for zf in z.get_files():
					if zf.ends_with(".json"):
						var j2 = JSON.parse_string(z.read_file(zf).get_string_from_utf8())
						if j2 is Dictionary:
							out.append(j2)
				z.close()
	return out


## Zips every record in user://telemetry into one file and returns its path ("" if nothing to export).
static func export_zip(dest_dir: String = "user://") -> String:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return ""
	var files := dir.get_files()
	if files.is_empty():
		return ""
	var path := dest_dir.path_join("wildfront_telemetry_%s.zip" % Time.get_datetime_string_from_system().replace(":", "-"))
	var z := ZIPPacker.new()
	if z.open(path) != OK:
		return ""
	for f in files:
		if not f.ends_with(".json"):
			continue
		z.start_file(f)
		z.write_file(FileAccess.get_file_as_bytes(DIR.path_join(f)))
		z.close_file()
	z.close()
	return path


## Writes one match record; returns its path.
static func save(rec: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("match_%d_%04d.json" % [int(Time.get_unix_time_from_system()), randi() % 10000])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(rec, "\t"))
	return path


## Adds fields (feedback, Lab vote) to a saved record.
static func amend(path: String, fields: Dictionary) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary):
		return
	for k in fields:
		j[k] = fields[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(j, "\t"))
