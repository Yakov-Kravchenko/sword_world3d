extends Node
## Логирование с уровнями в файл — нужно для багрепортов из Steam
## (08-architecture.md, раздел 3).

enum Level { DEBUG, INFO, WARN, ERROR }

const LOG_PATH := "user://logs/game.log"
const MAX_LINES := 5000

@export var min_level: Level = Level.DEBUG
var _file: FileAccess
var _perf: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	info("Sword World 3D — старт сессии %s" % Time.get_datetime_string_from_system())

func _exit_tree() -> void:
	if _file != null:
		_file.close()

func debug(message: String) -> void:
	_write(Level.DEBUG, message)

func info(message: String) -> void:
	_write(Level.INFO, message)

func warn(message: String) -> void:
	_write(Level.WARN, message)

func error(message: String) -> void:
	_write(Level.ERROR, message)

func _write(level: Level, message: String) -> void:
	if level < min_level:
		return
	var prefix: String = ["DEBUG", "INFO", "WARN", "ERROR"][level]
	var line := "[%s] %s" % [prefix, message]
	if level >= Level.WARN:
		push_warning(line)
	print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()

## Метка производительности вокруг генерации, ИИ и загрузки (раздел 8.4).
func perf_start(label: String) -> void:
	_perf[label] = Time.get_ticks_usec()

func perf_end(label: String) -> float:
	if not _perf.has(label):
		return 0.0
	var ms := (Time.get_ticks_usec() - int(_perf[label])) / 1000.0
	_perf.erase(label)
	debug("perf %s: %.1f мс" % [label, ms])
	return ms
