class_name TestCase
extends RefCounted
## Минимальный каркас тестов: запускается headless без сторонних аддонов.
## Совместим по духу с GUT — методы вида test_*.

var failures: Array[String] = []
var checks: int = 0
var current: String = ""

func suite_name() -> String:
	return "TestCase"

func before_each() -> void:
	pass

func run() -> Dictionary:
	var passed := 0
	var failed := 0
	for method: Dictionary in get_method_list():
		var name := String(method.get("name", ""))
		if not name.begins_with("test_"):
			continue
		current = name
		var before := failures.size()
		before_each()
		callv(name, [])
		if failures.size() == before:
			passed += 1
		else:
			failed += 1
	return {"suite": suite_name(), "passed": passed, "failed": failed,
		"checks": checks, "failures": failures}

func _fail(message: String) -> void:
	failures.append("%s :: %s" % [current, message])

func assert_true(value: bool, message: String = "") -> void:
	checks += 1
	if not value:
		_fail("ожидалось true. %s" % message)

func assert_false(value: bool, message: String = "") -> void:
	checks += 1
	if value:
		_fail("ожидалось false. %s" % message)

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	checks += 1
	if actual != expected:
		_fail("получено %s, ожидалось %s. %s" % [actual, expected, message])

func assert_ne(actual: Variant, expected: Variant, message: String = "") -> void:
	checks += 1
	if actual == expected:
		_fail("значения совпали (%s), а не должны. %s" % [actual, message])

func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	checks += 1
	if actual <= threshold:
		_fail("%s не больше %s. %s" % [actual, threshold, message])

func assert_ge(actual: float, threshold: float, message: String = "") -> void:
	checks += 1
	if actual < threshold:
		_fail("%s меньше %s. %s" % [actual, threshold, message])

func assert_le(actual: float, threshold: float, message: String = "") -> void:
	checks += 1
	if actual > threshold:
		_fail("%s больше %s. %s" % [actual, threshold, message])

func assert_between(actual: float, low: float, high: float, message: String = "") -> void:
	checks += 1
	if actual < low or actual > high:
		_fail("%s вне диапазона [%s, %s]. %s" % [actual, low, high, message])

func assert_not_null(value: Variant, message: String = "") -> void:
	checks += 1
	if value == null:
		_fail("значение null. %s" % message)
