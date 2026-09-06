class_name ActorAnimator
extends Node
## Анимации существ поверх суставов ActorModel: замах и удар, сотворение
## заклинания, вздрагивание от урона, падение. Работает через Tween — отдельного
## AnimationPlayer и авторских клипов у нас нет.
##
## Анимация ничего не решает: состояние уже изменено движком боя, здесь только
## показ (08-architecture.md, раздел 6).

const SPEED_DEFAULT := 1.5

var model: Node3D
var speed: float = SPEED_DEFAULT
var _torso: Node3D
var _arm_right: Node3D
var _arm_left: Node3D
var _legs: Array[Node3D] = []
var _busy: bool = false
var _player: AnimationPlayer

static func attach(target: Node3D) -> ActorAnimator:
	var animator := ActorAnimator.new()
	animator.name = "Animator"
	animator.model = target
	target.add_child(animator)
	animator._bind()
	return animator

## Если модель пришла со своим AnimationPlayer, играем её клипы: это лучше
## самодельных твинов по суставам. Иначе работаем по суставам, как раньше.
func _find_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child
		var nested := _find_player(child)
		if nested != null:
			return nested
	return null

func _clip(candidates: Array[String]) -> String:
	if _player == null:
		return ""
	var list := _player.get_animation_list()
	for wanted: String in candidates:
		for name: String in list:
			if name.to_lower().contains(wanted):
				return name
	return ""

func _play_clip(candidates: Array[String], loop: bool = false) -> bool:
	var name := _clip(candidates)
	if name.is_empty():
		return false
	_player.speed_scale = speed
	_player.play(name)
	if not loop:
		_busy = true
		var duration := _player.get_animation(name).length / maxf(0.1, speed)
		model.get_tree().create_timer(duration).timeout.connect(func() -> void:
			_busy = false
			var idle := _clip(["idle"])
			if not idle.is_empty() and is_instance_valid(_player):
				_player.play(idle))
	return true

func _bind() -> void:
	_player = _find_player(model)
	if _player != null:
		var idle := _clip(["idle"])
		if not idle.is_empty():
			_player.play(idle)
	_torso = model.get_node_or_null("Torso")
	if _torso != null:
		_arm_right = _torso.get_node_or_null("ShoulderR")
		_arm_left = _torso.get_node_or_null("ShoulderL")
	for tag: String in ["HipL", "HipR"]:
		var leg := model.get_node_or_null(tag)
		if leg != null:
			_legs.append(leg)

func is_busy() -> bool:
	return _busy

## Разворот корпуса к цели перед действием.
func face(target: Vector3) -> void:
	var to := target - model.global_position
	if Vector2(to.x, to.z).length_squared() < 0.01:
		return
	model.rotation.y = atan2(-to.x, -to.z)

## Замах и удар оружием.
func play_attack(target: Vector3, crit: bool = false) -> void:
	face(target)
	if _play_clip(["attack", "hit", "punch"]):
		return
	if _arm_right == null:
		return
	_busy = true
	var swing := deg_to_rad(150.0 if crit else 120.0)
	var tween := model.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_arm_right, "rotation:x", -swing * 0.55, 0.16 / speed)
	tween.parallel().tween_property(_torso, "rotation:y", deg_to_rad(18.0), 0.16 / speed)
	tween.tween_property(_arm_right, "rotation:x", swing * 0.45, 0.1 / speed)
	tween.parallel().tween_property(_torso, "rotation:y", deg_to_rad(-14.0), 0.1 / speed)
	tween.tween_property(_arm_right, "rotation:x", 0.0, 0.22 / speed)
	tween.parallel().tween_property(_torso, "rotation:y", 0.0, 0.22 / speed)
	tween.tween_callback(func() -> void: _busy = false)

## Сотворение заклинания: руки вверх и вспышка между ладонями.
func play_cast(target: Vector3, color: Color = Color(0.6, 0.7, 1.0)) -> void:
	face(target)
	var spark := _make_spark(color)
	if _play_clip(["attack", "cast", "interact"]):
		model.get_tree().create_timer(0.6 / maxf(0.1, speed)).timeout.connect(func() -> void:
			if is_instance_valid(spark):
				spark.queue_free())
		return
	if _arm_right == null or _arm_left == null:
		if is_instance_valid(spark):
			spark.queue_free()
		return
	_busy = true
	var tween := model.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_arm_right, "rotation:x", deg_to_rad(-95.0), 0.22 / speed)
	tween.parallel().tween_property(_arm_left, "rotation:x", deg_to_rad(-95.0), 0.22 / speed)
	tween.parallel().tween_property(spark, "scale", Vector3.ONE * 1.6, 0.22 / speed)
	tween.tween_interval(0.1 / speed)
	tween.tween_property(spark, "scale", Vector3.ONE * 0.05, 0.18 / speed)
	tween.parallel().tween_property(_arm_right, "rotation:x", 0.0, 0.26 / speed)
	tween.parallel().tween_property(_arm_left, "rotation:x", 0.0, 0.26 / speed)
	tween.tween_callback(func() -> void:
		_busy = false
		if is_instance_valid(spark):
			spark.queue_free())

func _make_spark(color: Color) -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3(0.0, 1.55, -0.35)
	node.scale = Vector3.ONE * 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	model.add_child(node)
	return node

## Вздрагивание от урона.
func play_hurt() -> void:
	if _torso == null:
		return
	var tween := model.create_tween()
	tween.tween_property(_torso, "rotation:x", deg_to_rad(-18.0), 0.08 / speed)
	tween.tween_property(_torso, "rotation:x", 0.0, 0.2 / speed)

## Падение: фигура заваливается вперёд и оседает.
func play_die() -> void:
	_busy = true
	var tween := model.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(model, "rotation:x", deg_to_rad(-88.0), 0.4 / speed)
	tween.parallel().tween_property(model, "position:y", model.position.y - 0.25, 0.4 / speed)

## Шаг: лёгкое покачивание ногами на время перемещения.
func play_step(duration: float) -> void:
	if _play_clip(["walk", "run"], true):
		model.get_tree().create_timer(duration).timeout.connect(func() -> void:
			var idle := _clip(["idle"])
			if not idle.is_empty() and is_instance_valid(_player):
				_player.play(idle))
		return
	if _legs.is_empty():
		return
	var swing := deg_to_rad(26.0)
	var tween := model.create_tween()
	tween.set_loops(maxi(1, int(duration / 0.24)))
	tween.tween_property(_legs[0], "rotation:x", swing, 0.12)
	tween.parallel().tween_property(_legs[1], "rotation:x", -swing, 0.12)
	tween.tween_property(_legs[0], "rotation:x", -swing, 0.12)
	tween.parallel().tween_property(_legs[1], "rotation:x", swing, 0.12)
	var reset := model.create_tween()
	reset.tween_interval(duration)
	reset.tween_property(_legs[0], "rotation:x", 0.0, 0.1)
	reset.parallel().tween_property(_legs[1], "rotation:x", 0.0, 0.1)
