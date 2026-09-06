class_name Result
extends RefCounted
## Возврат «значение или ошибка» вместо null и исключений (08-architecture.md §10).

var ok: bool = false
var value: Variant = null
var error: String = ""

static func good(v: Variant = null) -> Result:
	var r := Result.new()
	r.ok = true
	r.value = v
	return r

static func fail(message: String) -> Result:
	var r := Result.new()
	r.ok = false
	r.error = message
	return r

func unwrap_or(fallback: Variant) -> Variant:
	return value if ok else fallback
