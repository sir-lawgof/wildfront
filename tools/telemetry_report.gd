extends SceneTree
## U11: summarises exported telemetry into a Markdown report for the pitch.
##   godot --headless --path . --script res://tools/telemetry_report.gd -- [dir=PATH] [out=FILE.md]
## dir holds match_*.json files and/or exported .zip files (default: user://telemetry).
## Sample data: tools/telemetry_sample/ (regenerate with `-- make_sample=N`).

func _init() -> void:
	var args := {"dir": Telemetry.DIR, "out": ""}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DB.ensure_loaded()
	if args.has("make_sample"):
		_make_sample(int(args["make_sample"]))
		quit(0)
		return
	var recs := Telemetry.load_dir(str(args["dir"]))
	var md := Telemetry.report(recs)
	if str(args["out"]) != "":
		var f := FileAccess.open(str(args["out"]), FileAccess.WRITE)
		f.store_string(md)
		print("Wrote %s (%d matches)" % [args["out"], recs.size()])
	else:
		print(md)
	quit(0)


## Writes N short bot-match records to tools/telemetry_sample/ so the report can be tried without playtests.
func _make_sample(n: int) -> void:
	var modes := ["duel", "clan_clash", "ffa", "last_stand"]
	DirAccess.make_dir_recursive_absolute("res://tools/telemetry_sample")
	for i in range(n):
		var mode: String = modes[i % modes.size()]
		var core := MatchServerCore.new()
		core.setup({"mode": mode, "map": str(DB.modes["modes"][mode]["maps"][0]), "seed": 100 + i, "pre_ticks": 1})
		for t in range(1200):
			core.tick()
			if core.sim.phase == "over":
				break
		var rec := Telemetry.record(core.sim, "standard")
		rec["feedback"] = {"rating": 3 + i % 3, "text": "Sample comment %d." % (i + 1)}
		var f := FileAccess.open("res://tools/telemetry_sample/match_sample_%02d.json" % i, FileAccess.WRITE)
		f.store_string(JSON.stringify(rec, "\t"))
	print("Wrote %d sample records." % n)
