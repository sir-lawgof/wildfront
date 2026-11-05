class_name TestCase
extends RefCounted
## Minimal unit-test base. Methods named test_* are run by tests/run_tests.gd.

var failures: Array[String] = []
var current: String = ""


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, what])


func eq(actual: Variant, expected: Variant, what: String = "") -> void:
	if actual != expected:
		failures.append("%s: %s expected %s, got %s" % [current, what, str(expected), str(actual)])


func near(actual: float, expected: float, tol: float, what: String = "") -> void:
	if absf(actual - expected) > tol:
		failures.append("%s: %s expected %.4f +/- %.4f, got %.4f" % [current, what, expected, tol, actual])


## Helper: a 1v1 sim on a fresh map with given class ids.
static func make_duel(class_a: String = "warrior", class_b: String = "warrior", seed: int = 1) -> Sim:
	DB.ensure_loaded()
	var sim := Sim.new()
	sim.setup("duel", "castle_courtyard", {"seed": seed, "pre_ticks": 1})
	var unl := Progression.unlocked_set({"melee": 1, "ranged": 1, "magic": 1})
	sim.add_fighter("A", 0, false, Loadout.build(DB.classes["defaults"][class_a], unl, {"supply": "full"}), unl)
	sim.add_fighter("B", 1, false, Loadout.build(DB.classes["defaults"][class_b], unl, {"supply": "full"}), unl)
	sim.step()  # leave pre-match
	for f in sim.fighters.values():
		(f as Fighter).spawn_shield = 0  # raw-mechanic tests; protected states are covered in test_fairness.gd
	return sim
