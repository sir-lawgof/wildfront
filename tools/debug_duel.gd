extends SceneTree
## Debug helper: runs one bot duel and prints a per-tick trace summary.
##   godot --headless --path . --script res://tools/debug_duel.gd -- a=warrior b=warrior
func _init() -> void:
	var args := {"a": "warrior", "b": "warrior", "lv": "1", "seed": "5", "trace": "40"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DB.ensure_loaded()
	var core := MatchServerCore.new()
	core.setup({"mode": "duel", "map": "castle_courtyard", "seed": int(args["seed"]), "pre_ticks": 1, "player": {}})
	var sim := core.sim
	var fl: Array = sim.fighters.values()
	var lv := int(args["lv"])
	for i in range(2):
		var f: Fighter = fl[i]
		f.unlocked = Progression.unlocked_set({"melee": lv, "ranged": lv, "magic": lv})
		f.loadout = Loadout.build(DB.classes["defaults"][args["a"] if i == 0 else args["b"]], f.unlocked, {"supply": "full"})
		sim.spawn(f)
	(fl[0] as Fighter).pos = Vector2i(20, 24)
	(fl[1] as Fighter).pos = Vector2i(27, 24)
	var attacks := {}
	var dmg := {}
	var eats := {}
	for t in range(400):
		core.tick()
		for e in sim.events:
			if e["type"] == "attack":
				attacks[e["id"]] = int(attacks.get(e["id"], 0)) + 1
			elif e["type"] == "splat" and e["kind"] == "hit":
				dmg[e["target"]] = int(dmg.get(e["target"], 0)) + int(e["amount"])
			elif e["type"] == "consume":
				eats[e["id"]] = int(eats.get(e["id"], 0)) + 1
		if t < int(args["trace"]) or t % 25 == 0:
			var s := "t%3d " % sim.tick
			for f in fl:
				var fi: Fighter = f
				s += "| %s %s hp%3d pr%2d pos%s tgt%d tmr%d ovh=%s spell=%s/%s  " % [fi.name.left(5), fi.weapon_style().left(3), fi.hp, fi.prayer_points, fi.pos, fi.target_id, fi.attack_timer, fi.overhead().left(9), fi.autocast, fi.pending_spell]
			print(s)
		if sim.rules.round_over_ticks > 0 or sim.phase == "over":
			print("round over at tick ", sim.tick)
			break
	print("attacks ", attacks, " damage taken ", dmg, " eats ", eats)
	quit(0)
