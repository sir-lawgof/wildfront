extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 0 when every test passes, 1 otherwise. Script errors raised inside
## a test (which GDScript otherwise just prints) also count as failures.

const SUITES := [
	"res://tests/test_data.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_pathfinding.gd",
	"res://tests/test_progression.gd",
	"res://tests/test_sim.gd",
	"res://tests/test_challenges.gd",
	"res://tests/test_environment.gd",
]


class ErrorCounter extends Logger:
	var count: int = 0
	var last: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		last = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	DB.ensure_loaded()
	var total := 0
	var failed: Array[String] = []
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed.append("Could not load " + path)
			continue
		var suite: TestCase = script.new()
		for m in suite.get_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			total += 1
			suite.current = path.get_file() + "::" + mname
			var before := suite.failures.size()
			var errs_before := counter.count
			suite.call(mname)
			if counter.count > errs_before:
				suite.failures.append("%s: script error: %s" % [suite.current, counter.last])
			if suite.failures.size() == before:
				print("  ok   ", suite.current)
			else:
				print("  FAIL ", suite.current)
		failed.append_array(suite.failures)
	print("")
	if failed.is_empty():
		print("All %d tests passed." % total)
		quit(0)
	else:
		for f in failed:
			print("  - ", f)
		print("%d failure(s) in %d tests." % [failed.size(), total])
		quit(1)
