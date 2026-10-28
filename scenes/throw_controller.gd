class_name ThrowController
extends Node
## Drag-to-aim (рогатка): тянем мышь назад от шара, отпускаем - бросок в противоположную сторону.

signal throw_committed(impulse: Vector3)

const MAX_PULL_PX := 220.0
const MIN_PULL_PX := 24.0
const MAX_SPEED := 18.0 * Arena.WORLD
## Начальная скорость на единицу желаемой дистанции (при linear_damp = 1.0 шара; подбирается на тесте).
const SPEED_PER_DIST := 1.34
const ANGLE_SIGMA := 0.2
const DIST_SIGMA := 0.25

var _ball: CreatureBall = null
var _enabled := false
var _dragging := false
var _drag_start := Vector2.ZERO
var _line: MeshInstance3D
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.95, 0.3)
	_line = MeshInstance3D.new()
	_line.mesh = _mesh
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func enable(ball: CreatureBall) -> void:
	_ball = ball
	_enabled = true
	_dragging = false
	_clear_line()


func disable() -> void:
	_enabled = false
	_dragging = false
	_ball = null
	_clear_line()


func is_enabled() -> bool:
	return _enabled


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or _ball == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
			elif _dragging:
				_dragging = false
				var imp := _impulse_from(mb.position)
				if imp.length() > 0.0:
					disable()
					throw_committed.emit(imp)
				else:
					_clear_line()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_dragging = false
			_clear_line()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_update_line(_impulse_from(mm.position))


## Импульс (масса шара 1) из текущего положения мыши; нулевой, если тянуть меньше порога.
func _impulse_from(pos: Vector2) -> Vector3:
	var d := pos - _drag_start
	var dl := d.length()
	if dl < MIN_PULL_PX:
		return Vector3.ZERO
	var pull := minf(dl, MAX_PULL_PX)
	var dir2 := -d / dl
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	return dir * (pull / MAX_PULL_PX * MAX_SPEED)


func _clear_line() -> void:
	if _mesh != null:
		_mesh.clear_surfaces()


func _update_line(impulse: Vector3) -> void:
	_clear_line()
	if _ball == null or impulse.length() <= 0.0 or _mesh == null:
		return
	var start := _ball.global_position
	start.y = 0.2
	var dist := impulse.length() / SPEED_PER_DIST
	var dir := impulse.normalized()
	var end := start + dir * dist
	var side := dir.cross(Vector3.UP) * 0.2 * Arena.WORLD
	var back := -dir * 0.3
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	_mesh.surface_add_vertex(start)
	_mesh.surface_add_vertex(end)
	_mesh.surface_add_vertex(end)
	_mesh.surface_add_vertex(end + back + side)
	_mesh.surface_add_vertex(end)
	_mesh.surface_add_vertex(end + back - side)
	_mesh.surface_end()


## Импульс для ИИ: цель + гауссов разброс по углу и дальности, масштабируемый error.
static func impulse_for_target(from: Vector3, to: Vector3, error: float, rng: RandomNumberGenerator) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := flat.length()
	if dist < 0.01:
		return Vector3.ZERO
	var ang := rng.randfn(0.0, error * ANGLE_SIGMA)
	var dir := flat.normalized().rotated(Vector3.UP, ang)
	var dist2 := maxf(0.5, dist * (1.0 + rng.randfn(0.0, error * DIST_SIGMA)))
	return dir * (dist2 * SPEED_PER_DIST)
