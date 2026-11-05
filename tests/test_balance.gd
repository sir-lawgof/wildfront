extends TestCase
## U9: the balance simulator runs with the tests. No default class (own unlocks, at each standard level) and no
## bracket kit may win more than balance_check.max_win_rate of its duels against the other classes.
## Duels are mirrored (sides swap every other duel) and seeded, so the result is the same on every run.


func test_no_dominant_class_or_kit() -> void:
	DB.ensure_loaded()
	var cfg: Dictionary = DB.rule("balance_check", {})
	var limit := float(cfg.get("max_win_rate", 0.6))
	var n := int(cfg.get("duels_per_pair", 20))
	var runs: Array = []
	for lv in cfg.get("standard_levels", [40]):
		runs.append(["", int(lv)])
	for bid in Brackets.ids():
		runs.append([str(bid), 40])
	var summary := ""
	for r in runs:
		var m := Balance.matrix(n, str(r[0]), int(r[1]))
		var label := ("standard level %d" % int(r[1])) if str(r[0]) == "" else Brackets.display_name(str(r[0]))
		summary += "\n    %-18s" % label
		for c in m["_overall"]:
			var w := float(m["_overall"][c])
			summary += " %s %d%%" % [str(c).left(4), int(round(w * 100))]
			check(w <= limit, "%s: %s wins %d%% of duels (limit %d%%)" % [label, c, int(round(w * 100)), int(round(limit * 100))])
	print("    balance:" + summary)
