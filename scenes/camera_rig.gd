class_name CameraRig
extends Camera3D
## Камера с плавным слежением: обзор, следование за шаром, наезд на слот, ракурс боя.

const OVERVIEW_POS := Vector3(0.0, 12.6, 9.4) * Arena.WORLD
const OVERVIEW_LOOK := Vector3(0.0, 0.0, -0.2) * Arena.WORLD
const FOV := 55.0
const SMOOTH := 4.0

var _goal_pos := OVERVIEW_POS
var _goal_look := OVERVIEW_LOOK
var _look := OVERVIEW_LOOK
var _follow: Node3D = null
var _shake := 0.0
var _shake_t := 0.0


func _ready() -> void:
	fov = FOV
	snap_overview()


func _process(delta: float) -> void:
	if _follow != null and is_instance_valid(_follow) and _follow.is_inside_tree():
		var p := _follow.global_position
		_goal_look = p
		_goal_pos = p + Vector3(0.0, 6.5, 6.5) * Arena.WORLD
	var k := 1.0 - exp(-SMOOTH * delta)
	position = position.lerp(_goal_pos, k)
	_look = _look.lerp(_goal_look, k)
	if position.distance_to(_look) > 0.01:
		look_at(_look, Vector3.UP)
	if _shake_t > 0.0:
		_shake_t -= delta
		var a := _shake * Arena.WORLD * 0.12 * clampf(_shake_t * 3.0, 0.0, 1.0)
		h_offset = randf_range(-a, a)
		v_offset = randf_range(-a, a)
	else:
		h_offset = 0.0
		v_offset = 0.0


## Тряска камеры (удар в бою).
func shake(amount: float, dur: float) -> void:
	_shake = amount
	_shake_t = dur


func snap_overview() -> void:
	_follow = null
	_goal_pos = OVERVIEW_POS
	_goal_look = OVERVIEW_LOOK
	_look = OVERVIEW_LOOK
	position = OVERVIEW_POS
	if is_inside_tree():
		look_at(_look, Vector3.UP)


func overview() -> void:
	_follow = null
	_goal_pos = OVERVIEW_POS
	_goal_look = OVERVIEW_LOOK


func follow(n: Node3D) -> void:
	_follow = n


func zoom_slot(p: Vector3) -> void:
	_follow = null
	_goal_look = p + Vector3(0.0, 1.3, 0.0) * Arena.WORLD
	_goal_pos = p + Vector3(0.0, 4.6, 6.4) * Arena.WORLD


func battle_view(p: Vector3) -> void:
	_follow = null
	# низкий ракурс снизу вверх: существа выглядят огромными
	_goal_look = p + Vector3(0.0, 1.05, 0.0) * Arena.WORLD
	_goal_pos = p + Vector3(3.3, 0.5, 0.35) * Arena.WORLD


func is_overview() -> bool:
	return _follow == null and _goal_pos.is_equal_approx(OVERVIEW_POS) and position.distance_to(OVERVIEW_POS) < 0.05
