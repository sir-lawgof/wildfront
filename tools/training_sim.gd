extends SceneTree
## U1 tuning: win rate of a drill-trained student bot (graduation_target.student_skill) against both exams.
##   godot --headless --path . --script res://tools/training_sim.gd
func _init() -> void:
	DB.ensure_loaded()
	var n := 60
	for tid in ["graduation", "instructors_challenge"]:
		var w := 0
		var ticks := 0
		for i in range(n):
			var core := MatchServerCore.new()
			core.setup({"training": tid, "seed": 100 + i, "pre_ticks": 2, "player": {"name": "S", "class_def": DB.classes["defaults"]["warrior"], "levels": {"melee": 40, "ranged": 40, "magic": 40}}})
			var me := core.sim.get_fighter(core.player_id)
			core.bots[me.id] = BotBrain.new(me.id, float(DB.training["graduation_target"]["student_skill"]), (100 + i) * 31 + 7)
			for k in range(4000):
				core.tick()
				if core.sim.phase == "over":
					break
			ticks += core.sim.live_ticks
			if core.training.status == "passed":
				w += 1
		print(tid, " ", float(w) / n, " avg ticks ", ticks / n)
	quit(0)
