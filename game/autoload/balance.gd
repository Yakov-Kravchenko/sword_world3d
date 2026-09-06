extends Node
## Загруженный balance.json (08-architecture.md, раздел 3).
## Все числа релиза живут здесь, а не в коде — иначе путь к акту III закрыт.

var data: BalanceData

func _ready() -> void:
	reload()

func reload() -> void:
	data = ContentIndex.load_balance()
