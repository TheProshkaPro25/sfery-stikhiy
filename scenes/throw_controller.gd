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
var _power_label: Label3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_line = MeshInstance3D.new()
	_line.mesh = _mesh
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_power_label = Label3D.new()
	_power_label.top_level = true
	_power_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_power_label.no_depth_test = true
	_power_label.fixed_size = true
	_power_label.pixel_size = 0.0012
	_power_label.font_size = 34
	_power_label.outline_size = 10
	_power_label.visible = false
	add_child(_power_label)


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
	# направление в осях камеры (экран «вверх» = вперёд по взгляду): прицел верен при любом ракурсе
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var r := cam.global_transform.basis.x
		var f := -cam.global_transform.basis.z
		r.y = 0.0
		f.y = 0.0
		if r.length() > 0.01 and f.length() > 0.01:
			right = r.normalized()
			fwd = f.normalized()
	var dir := (right * dir2.x - fwd * dir2.y).normalized()
	return dir * (pull / MAX_PULL_PX * MAX_SPEED)


func _clear_line() -> void:
	if _mesh != null:
		_mesh.clear_surfaces()
	if _power_label != null:
		_power_label.visible = false


## Цвет силы: зелёный → жёлтый → красный.
static func power_color(k: float) -> Color:
	return Color(0.35, 1.0, 0.45).lerp(Color(1.0, 0.9, 0.25), clampf(k * 2.0, 0.0, 1.0)).lerp(Color(1.0, 0.3, 0.2), clampf(k * 2.0 - 1.0, 0.0, 1.0))


## Прицел: дуга полёта (как у видимого шара), точка падения с кольцом, шкала силы вокруг шара и процент.
func _update_line(impulse: Vector3) -> void:
	_clear_line()
	if _ball == null or impulse.length() <= 0.0 or _mesh == null:
		return
	var k := clampf(impulse.length() / MAX_SPEED, 0.0, 1.0)
	var pc := power_color(k)
	var start := _ball.global_position
	start.y = 0.15
	var dist := impulse.length() / SPEED_PER_DIST
	var dir := impulse.normalized()
	var arc := CreatureBall.arc_for_speed(impulse.length())
	# доля пути, пройденная за время дуги (затухание скорости ~ exp(-t))
	var air_frac := 1.0 - exp(-arc.x)
	var side := dir.cross(Vector3.UP)
	var w := 0.12 * Arena.WORLD
	# дуга полёта лентой из треугольников, гаснущая к концу, затем прямая до точки падения
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
	var n := 24
	var prev := Vector3.ZERO
	for i in range(n + 1):
		var s := float(i) / n
		var along := dist * air_frac * s
		var p := start + dir * along + Vector3(0.0, 4.0 * arc.y * s * (1.0 - s), 0.0)
		if i > 0 and i % 2 == 1:
			_quad(prev, p, side * w * 0.5, Color(pc.r, pc.g, pc.b, 0.9 - 0.4 * s))
		prev = p
	var land := start + dir * dist * air_frac
	var end := start + dir * dist
	_quad(land, end, side * w * 0.35, Color(pc.r, pc.g, pc.b, 0.55))
	# стрелка в точке остановки
	var tip := end + dir * w * 2.5
	_tri(end + side * w * 1.4, end - side * w * 1.4, tip, Color(pc.r, pc.g, pc.b, 0.95))
	# кольцо в месте касания
	_ring(land, 0.55 * Arena.WORLD, 0.06 * Arena.WORLD, 0.0, 1.0, Color(pc.r, pc.g, pc.b, 0.6))
	# шкала силы вокруг шара: фон и заполненная дуга
	var rr := 0.75 * Arena.WORLD
	_ring(start, rr, 0.09 * Arena.WORLD, 0.0, 1.0, Color(0.05, 0.05, 0.08, 0.55))
	_ring(start, rr, 0.09 * Arena.WORLD, 0.0, k, Color(pc.r, pc.g, pc.b, 0.95))
	_mesh.surface_end()
	_power_label.text = "СИЛА %d%%" % roundi(k * 100.0)
	_power_label.modulate = pc
	_power_label.global_position = start + Vector3(0.0, 0.55 * Arena.WORLD, 0.0)
	_power_label.visible = true


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(v)


func _quad(a: Vector3, b: Vector3, half: Vector3, col: Color) -> void:
	_tri(a - half, a + half, b + half, col)
	_tri(a - half, b + half, b - half, col)


## Плоское кольцо (сектор от f0 до f1 полного круга, начиная «сверху» по −Z) на высоте точки c.
func _ring(c: Vector3, r: float, width: float, f0: float, f1: float, col: Color) -> void:
	var segs := maxi(2, int(48 * (f1 - f0)))
	for i in range(segs):
		var a0 := TAU * lerpf(f0, f1, float(i) / segs) - PI * 0.5
		var a1 := TAU * lerpf(f0, f1, float(i + 1) / segs) - PI * 0.5
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		var p0 := c + o0 * (r - width * 0.5)
		var p1 := c + o0 * (r + width * 0.5)
		var p2 := c + o1 * (r + width * 0.5)
		var p3 := c + o1 * (r - width * 0.5)
		_tri(p0, p1, p2, col)
		_tri(p0, p2, p3, col)


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
