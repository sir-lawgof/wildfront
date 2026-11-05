extends TestCase
## U11 telemetry: per-match record, save/amend/export and the Markdown report.


func _bot_match(mode: String = "duel", ticks: int = 400) -> MatchServerCore:
	DB.ensure_loaded()
	var core := MatchServerCore.new()
	core.setup({"mode": mode, "map": str(DB.modes["modes"][mode]["maps"][0]), "seed": 11, "pre_ticks": 1})
	for i in range(ticks):
		core.tick()
		if core.sim.phase == "over":
			break
	return core


func test_record_has_fields_and_no_names() -> void:
	var core := _bot_match()
	var rec := Telemetry.record(core.sim, "standard")
	for k in ["schema", "mode", "map", "bracket", "ticks", "fighters", "ttk_ticks", "ward_accuracy", "leavers"]:
		check(rec.has(k), "record has " + k)
	var txt := JSON.stringify(rec)
	for f in core.sim.fighters.values():
		check(not txt.contains("\"%s\"" % (f as Fighter).name), "no player names in telemetry")
	check(float(rec["ward_accuracy"]) >= 0.0, "bots took hits, so ward accuracy is measured")


func test_save_amend_export_roundtrip() -> void:
	var core := _bot_match("duel", 50)
	var path := Telemetry.save(Telemetry.record(core.sim, "standard"))
	check(path != "" and FileAccess.file_exists(path), "record written to user://telemetry")
	Telemetry.amend(path, {"feedback": {"rating": 4, "text": "fun"}})
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	eq(int(j["feedback"]["rating"]), 4, "feedback saved into the record")
	var zip := Telemetry.export_zip("user://")
	check(zip != "" and FileAccess.file_exists(zip), "export zip written")
	var found := false
	for r in Telemetry.load_dir("user://"):
		if (r as Dictionary).has("feedback") and str(r["feedback"].get("text", "")) == "fun":
			found = true
	check(found, "zip can be read back")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(zip)


func test_report_runs_on_sample_data() -> void:
	DB.ensure_loaded()
	var recs := Telemetry.load_dir("res://tools/telemetry_sample")
	check(recs.size() >= 4, "sample records present")
	var md := Telemetry.report(recs)
	for h in ["# Wildfront playtest telemetry", "## Modes", "## Classes", "Time to kill", "Feedback rating"]:
		check(md.contains(h), "report has " + h)
	check(Telemetry.report([]).contains("No matches"), "empty report")
