extends SceneTree
## Прогон всех тестов headless:
##   godot --headless --path . --script res://tests/run_tests.gd
## Отчёт дублируется в user://test_report.txt — stdout при headless буферизуется.

const SUITES := [
	"res://tests/unit/test_dice.gd",
	"res://tests/unit/test_rng.gd",
	"res://tests/unit/test_grid.gd",
	"res://tests/unit/test_resolver.gd",
	"res://tests/unit/test_statuses.gd",
	"res://tests/unit/test_inventory.gd",
	"res://tests/unit/test_items.gd",
	"res://tests/unit/test_dungeon.gd",
	"res://tests/integration/test_combat.gd",
	"res://tests/integration/test_save.gd",
]

var _report: FileAccess

func _initialize() -> void:
	_report = FileAccess.open("user://test_report.txt", FileAccess.WRITE)
	var total_passed := 0
	var total_failed := 0
	var total_checks := 0
	var all_failures: Array[String] = []
	_say("===== Sword World 3D: тесты =====")
	for path: String in SUITES:
		var script: Script = load(path)
		if script == null:
			_say("  [ПРОПУСК] %s — не загрузился" % path)
			total_failed += 1
			continue
		var started := Time.get_ticks_msec()
		var suite: TestCase = script.new()
		var result: Dictionary = suite.run()
		var elapsed := (Time.get_ticks_msec() - started) / 1000.0
		total_passed += int(result["passed"])
		total_failed += int(result["failed"])
		total_checks += int(result["checks"])
		var mark := "OK  " if int(result["failed"]) == 0 else "СБОЙ"
		_say("  [%s] %-26s тестов: %2d  проверок: %5d  %5.1f с" % [mark, result["suite"],
			int(result["passed"]) + int(result["failed"]), int(result["checks"]), elapsed])
		for f: String in result["failures"]:
			all_failures.append("%s: %s" % [result["suite"], f])
	_say("---------------------------------")
	_say("Пройдено: %d, провалено: %d, проверок: %d" % [total_passed, total_failed, total_checks])
	for f: String in all_failures:
		_say("  ! " + f)
	_say("=================================")
	if _report != null:
		_report.close()
	quit(1 if total_failed > 0 else 0)

func _say(line: String) -> void:
	print(line)
	if _report != null:
		_report.store_line(line)
		_report.flush()
