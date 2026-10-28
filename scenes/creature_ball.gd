class_name CreatureBall
extends RigidBody3D
## Шар-существо. До раскрытия виден шар, после open_up() - фигурка (капсула + рог).

signal settled(ball: CreatureBall, world_pos: Vector3)

const RADIUS := 0.35  # ~1/17 длины карты
const SLOW_SPEED := 0.15
const SLOW_ANG := 1.0
const SLOW_TIME := 0.15
const TIMEOUT := 9.0

var uid: int = -1
var def: CreatureDef = null
var slot: int = -1

var _built := false
var _shape: CollisionShape3D
var _visual: Node3D
var _ball_mesh: MeshInstance3D
var _figure: Node3D
var _anim: CreatureAnim
var _label: Label3D
var _open := false
var _prev_vel := Vector3.ZERO
var _label_allowed := true
var _halves: Array[MeshInstance3D] = []
var _open_tween: Tween
var _launched := false
var _done := false
var _t := 0.0
var _slow := 0.0
var _pending_impulse := Vector3.ZERO
var _has_pending := false
## Визуальная дуга полёта: физика катит шар по полу (точность бросков не меняется),
## а видимый шар летит над ним по параболе и подскакивает при касании.
var _air_t := -1.0
var _air_dur := 0.0
var _air_h := 0.0
var _label_near_hidden := false
var _sparks: CPUParticles3D
var _streak: CPUParticles3D


func _init() -> void:
	_ensure_built()


func _ready() -> void:
	_ensure_built()
	add_to_group(&"creature_balls")


## Существо раскрыто и видно (камера облетает такие фигуры, а не проходит сквозь них).
func is_figure_shown() -> bool:
	return _open and visible and _figure.visible and is_inside_tree()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	mass = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 1.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 1.5
	continuous_cd = true
	can_sleep = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true

	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.2
	physics_material_override = pm

	_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS
	_shape.shape = sph
	add_child(_shape)

	_visual = Node3D.new()
	add_child(_visual)

	_ball_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	_ball_mesh.mesh = sm
	_visual.add_child(_ball_mesh)

	_figure = Node3D.new()
	_figure.visible = false
	_visual.add_child(_figure)
	# Модель существа подставляется в setup() (CreatureModels), основание фигуры — на уровне пола.

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.0036 * Arena.WORLD
	_label.font_size = 40
	_label.outline_size = 10
	_label.position = Vector3(0, 1.75, 0)
	_label.no_depth_test = true
	_label.visible = false
	_visual.add_child(_label)


func setup(d: CreatureDef, u: int) -> void:
	_ensure_built()
	def = d
	uid = u
	var c := VisualUtil.NEUTRAL_COLOR
	var txt := "?"
	if d != null:
		c = d.color
		txt = "%s\n%s %d" % [d.display_name, VisualUtil.attr_name(d.attribute), d.base_power]
	_ball_mesh.material_override = VisualUtil.make_material(c, 0.35, 0.25)
	VisualUtil.clear_children(_figure)
	var model := CreatureModels.build(d)
	if model != null:
		# аниматор стоит в основании модели (пол), фигура вращается/масштабируется вокруг центра шара
		_anim = CreatureAnim.new()
		_figure.add_child(_anim)
		_anim.set_base(Vector3(0, -RADIUS, 0))
		_anim.set_model(model, d)
		_label.position = Vector3(0, float(model.get_meta("height", 1.5)) - RADIUS + 0.35 * Arena.WORLD, 0)
	else:
		_anim = null
	_label.text = txt


## Разрешить/спрятать подпись (на крупных планах видны только подписи участников).
func set_label_allowed(on: bool) -> void:
	_label_allowed = on
	_label.visible = _open and on and (_open_tween == null or not _open_tween.is_running())


## Повернуть фигурку лицом к точке (по XZ). Модели смотрят вдоль +Z.
func face_toward(target: Vector3) -> void:
	var d := target - global_position if is_inside_tree() else target - position
	if Vector2(d.x, d.z).length() > 0.001:
		_figure.rotation.y = atan2(d.x, d.z)


## Сдвиг подписи на экране (в пикселях шрифта), чтобы в бою подписи двух существ не накладывались.
func set_label_shift(px: float) -> void:
	_label.offset = Vector2(px, 0.0)


var _trail: CPUParticles3D


## След летящего шара цвета стихии.
func _start_trail() -> void:
	if _trail == null:
		_trail = CPUParticles3D.new()
		_trail.amount = 40
		_trail.lifetime = 0.45
		_trail.local_coords = false
		_trail.gravity = Vector3.ZERO
		_trail.initial_velocity_min = 0.0
		_trail.initial_velocity_max = 0.2
		_trail.scale_amount_min = 0.6
		_trail.scale_amount_max = 1.0
		var c: Color = VisualUtil.attr_color(def.attribute) if def != null else Color.WHITE
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.9))
		grad.add_point(0.3, Color(c.r, c.g, c.b, 0.8))
		grad.set_color(grad.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
		_trail.color_ramp = grad
		var q := QuadMesh.new()
		q.size = Vector2(RADIUS * 1.6, RADIUS * 1.6)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = VisualUtil.soft_dot()
		q.material = m
		_trail.mesh = q
		_visual.add_child(_trail)
	_trail.emitting = true
	if _sparks == null:
		_build_ground_fx()


## Длительность и высота видимой дуги для скорости броска v (м/с): дальний бросок летит выше и дольше.
static func arc_for_speed(v: float) -> Vector2:
	return Vector2(clampf(v / 42.0, 0.3, 1.15), clampf(v * 0.13, 0.8, 7.5))


## Высота видимого шара над физическим через t секунд после броска: большая дуга и два подскока.
static func arc_height(t: float, dur: float, h: float) -> float:
	if t < 0.0:
		return 0.0
	if t < dur:
		var s := t / dur
		return 4.0 * h * s * (1.0 - s)
	var hops := [[0.38, 0.2], [0.18, 0.05]]
	var t0 := dur
	for hop in hops:
		var d: float = dur * float(hop[0])
		if t < t0 + d:
			var s2 := (t - t0) / d
			return 4.0 * h * float(hop[1]) * s2 * (1.0 - s2)
		t0 += d
	return 0.0


static func arc_total(dur: float) -> float:
	return dur * (1.0 + 0.38 + 0.18)


## Искры из-под катящегося шара и светящийся след по полю (частицы в мировых координатах).
func _build_ground_fx() -> void:
	var c: Color = VisualUtil.attr_color(def.attribute) if def != null else Color.WHITE
	_sparks = CPUParticles3D.new()
	_sparks.top_level = true
	_sparks.local_coords = false
	_sparks.emitting = false
	_sparks.amount = 48
	_sparks.lifetime = 0.45
	_sparks.direction = Vector3.UP
	_sparks.spread = 55.0
	_sparks.initial_velocity_min = 2.5
	_sparks.initial_velocity_max = 7.0
	_sparks.gravity = Vector3(0, -22.0, 0)
	_sparks.scale_amount_min = 0.4
	_sparks.scale_amount_max = 1.0
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	sg.add_point(0.4, Color(c.r, c.g, c.b, 0.9).lightened(0.3))
	sg.set_color(sg.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	_sparks.color_ramp = sg
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.5, 2.5, 2.5)
	m.albedo_texture = VisualUtil.soft_dot()
	q.material = m
	_sparks.mesh = q
	add_child(_sparks)

	_streak = CPUParticles3D.new()
	_streak.top_level = true
	_streak.local_coords = false
	_streak.emitting = false
	_streak.amount = 120
	_streak.lifetime = 1.6
	_streak.gravity = Vector3.ZERO
	_streak.initial_velocity_min = 0.0
	_streak.initial_velocity_max = 0.0
	_streak.scale_amount_min = 1.0
	_streak.scale_amount_max = 1.0
	var tg := Gradient.new()
	tg.set_color(0, Color(c.r, c.g, c.b, 0.9).lightened(0.4))
	tg.add_point(0.25, Color(c.r, c.g, c.b, 0.55))
	tg.set_color(tg.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	_streak.color_ramp = tg
	var pl := PlaneMesh.new()  # лежит на полу
	pl.size = Vector2(RADIUS * 2.2, RADIUS * 2.2)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pmat.vertex_color_use_as_albedo = true
	pmat.albedo_texture = VisualUtil.soft_dot()
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pl.material = pmat
	_streak.mesh = pl
	add_child(_streak)


## Рост существа в раскрытом виде (м), для кадрирования камерой.
func figure_height() -> float:
	if _anim != null:
		return _anim.get_height()
	return Arena.CARD_H * 0.8


## Масштаб кадра для камеры: наибольшее из роста и размера по полу (длинные и широкие существа).
func figure_size() -> float:
	if _anim != null:
		return maxf(_anim.get_height(), _anim.get_extent())
	return Arena.CARD_H * 0.8


func launch(impulse: Vector3) -> void:
	_start_trail()
	var arc := arc_for_speed(impulse.length())
	_air_dur = arc.x
	_air_h = arc.y
	_air_t = 0.0
	collision_layer = 1
	collision_mask = 1
	freeze = false
	sleeping = false
	_pending_impulse = impulse
	_has_pending = true
	_launched = true
	_done = false
	_t = 0.0
	_slow = 0.0


func open_up() -> Signal:
	return open_animated()


## Анимация раскрытия капсулой: половинки разлетаются, дым цвета стихии, фигурка вырастает.
func open_animated() -> Signal:
	if _open:
		var t0 := create_tween()
		t0.tween_interval(0.01)
		return t0.finished
	_open = true
	_kill_open_tween()
	var pc: Color = VisualUtil.attr_color(def.attribute) if def != null else Color.WHITE
	VisualUtil.light_pillar(self, Vector3(0, -RADIUS, 0), pc.lightened(0.3), Arena.CARD_H * 2.0, Arena.CARD_W * 0.22, 0.9)
	_ball_mesh.visible = false
	_figure.visible = true
	_figure.scale = Vector3(0.01, 0.01, 0.01)
	_label.visible = false
	_make_halves()
	_spawn_smoke()
	var tw := create_tween()
	_open_tween = tw
	tw.set_parallel(true)
	var top: MeshInstance3D = _halves[0]
	var bot: MeshInstance3D = _halves[1]
	tw.tween_property(top, "position", Vector3(0.0, 0.5, 0.0), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(top, "rotation", Vector3(-1.2, 0.0, 0.0), 0.3)
	tw.tween_property(bot, "position", Vector3(0.0, -0.4, 0.0), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(bot, "rotation", Vector3(PI + 1.2, 0.0, 0.0), 0.3)
	tw.tween_property(top, "scale", Vector3(0.01, 0.01, 0.01), 0.25).set_delay(0.3)
	tw.tween_property(bot, "scale", Vector3(0.01, 0.01, 0.01), 0.25).set_delay(0.3)
	tw.tween_property(_figure, "scale", Vector3.ONE, 0.4).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_finish_open)
	if _anim != null:
		_anim.reset()
		_anim.appear()
	return tw.finished


func _finish_open() -> void:
	for h in _halves:
		h.visible = false
	_label.visible = _open and _label_allowed


func _kill_open_tween() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = null


func _make_halves() -> void:
	if _halves.is_empty():
		for i in 2:
			var m := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = RADIUS
			sm.height = RADIUS * 2.0
			sm.is_hemisphere = true
			m.mesh = sm
			m.material_override = _ball_mesh.material_override
			_visual.add_child(m)
			_halves.append(m)
	for i in 2:
		var h: MeshInstance3D = _halves[i]
		h.material_override = _ball_mesh.material_override
		h.visible = true
		h.position = Vector3.ZERO
		h.scale = Vector3.ONE
		h.rotation = Vector3(0.0 if i == 0 else PI, 0.0, 0.0)


func _spawn_smoke() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0.0, 0.3, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.8))
	p.scale_amount_curve = curve
	var c: Color = def.color if def != null else VisualUtil.NEUTRAL_COLOR
	var grad := Gradient.new()
	grad.set_color(0, Color(c.r, c.g, c.b, 0.8))
	grad.set_color(1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = grad
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	sm.material = mat
	p.mesh = sm
	_visual.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func close_up() -> void:
	_open = false
	_kill_open_tween()
	_ball_mesh.visible = true
	_figure.visible = false
	_figure.scale = Vector3.ONE
	_label.visible = false
	if _anim != null:
		_anim.idle_on = false
		_anim.reset()
	for h in _halves:
		h.visible = false


## Фиксирует тело в точке (без вращения); используется и для удержания шара перед броском.
## Замороженный шар не сталкивается с катящимися: иначе в слот с существом нельзя попасть (отскок).
func freeze_at(pos: Vector3) -> void:
	if _anim != null:
		_anim.reset()
	_label.offset = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	_launched = false
	_has_pending = false
	_air_t = -1.0
	_visual.position = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if is_inside_tree():
		global_transform = Transform3D(Basis(), pos)
	else:
		transform = Transform3D(Basis(), pos)


func unfreeze() -> void:
	freeze = false


## Плавно скрывает визуал и отключает коллизию; возвращает сигнал окончания.
## Рывок к цели и обратно (удар в бою). Возвращает сигнал окончания.
func lunge(target: Vector3) -> Signal:
	var d := target - global_position
	d.y = 0.0
	if _anim != null:
		_anim.lunge(d.length() * 0.45)
	var done := create_tween()
	done.tween_interval(0.3)
	return done.finished


## Ответный (короткий) рывок защитника.
func counter_lunge(target: Vector3) -> void:
	var d := target - global_position
	d.y = 0.0
	if _anim != null:
		_anim.counter(d.length() * 0.45)


## Рёв: рывок вверх/назад и возврат (delay — под момент крика).
func roar(delay: float = 0.0) -> void:
	if _anim != null:
		_anim.roar(delay)


## Отдача проигравшего с вспышкой цвета стихии победителя.
func take_hit(flash: Color) -> void:
	if _anim != null:
		_anim.hit(flash, RADIUS * 0.6)


## Импульс при игре карты способности.
func ability_pulse() -> void:
	if _anim != null:
		_anim.ability_pulse()


func _process(delta: float) -> void:
	if _air_t >= 0.0:
		var prev := _air_t
		_air_t += delta
		if prev < _air_dur and _air_t >= _air_dur:
			SoundFx.i().bounce(6.0)  # касание пола после дуги
		var y := arc_height(_air_t, _air_dur, _air_h)
		if _air_t > arc_total(_air_dur) or not _launched:
			_air_t = -1.0
			y = 0.0
		_visual.global_position = global_position + Vector3(0.0, y, 0.0)
	elif _visual.position != Vector3.ZERO:
		_visual.position = Vector3.ZERO
	# подпись прячется, когда камера почти вплотную к ней (облёт сверху), иначе закрывает кадр
	if _label.visible or _label_near_hidden:
		var cam := get_viewport().get_camera_3d()
		var near: bool = cam != null and cam.global_position.distance_to(_label.global_position) < figure_height() * 0.9
		if near and _label.visible:
			_label.visible = false
			_label_near_hidden = true
		elif not near and _label_near_hidden:
			_label_near_hidden = false
			_label.visible = _open and _label_allowed and (_open_tween == null or not _open_tween.is_running())
	# «живой простой» включается, когда существо раскрыто и вырастание закончено
	if _anim != null:
		_anim.idle_on = _open and _figure.visible and (_open_tween == null or not _open_tween.is_running())


func vanish() -> Signal:
	_launched = false
	_shape.disabled = true
	freeze = true
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	return tw.finished


func _physics_process(delta: float) -> void:
	if not _launched or _done:
		return
	if _has_pending:
		_has_pending = false
		apply_central_impulse(_pending_impulse)
		return
	_t += delta
	var v := linear_velocity
	var jolt := (v - _prev_vel).length()
	if jolt > 1.5 and _t > 0.05:
		SoundFx.i().bounce(jolt)
	_prev_vel = v
	var on_ground := arc_height(_air_t, _air_dur, _air_h) < 0.05
	var hs := Vector2(v.x, v.z).length()
	SoundFx.i().set_roll(hs if absf(v.y) < 1.0 and on_ground else 0.0)
	if _sparks != null:
		var contact := global_position + Vector3(0.0, -RADIUS + 0.04, 0.0)
		_sparks.global_position = contact
		_streak.global_position = Vector3(contact.x, 0.03, contact.z)
		_sparks.emitting = on_ground and hs > 5.0
		_streak.emitting = on_ground and hs > 1.2
		if hs > 0.1:
			_sparks.direction = Vector3(-v.x / hs, 1.2, -v.z / hs)

	if global_position.y < -1.0:
		_finish()
		return
	if linear_velocity.length() < SLOW_SPEED and angular_velocity.length() < SLOW_ANG and _t > 0.15:
		_slow += delta
	else:
		_slow = 0.0
	if _slow >= SLOW_TIME or _t >= TIMEOUT:
		_finish()


func _finish() -> void:
	SoundFx.i().set_roll(0.0)
	if _trail != null:
		_trail.emitting = false
	if _sparks != null:
		_sparks.emitting = false
		_streak.emitting = false
	_done = true
	_launched = false
	if global_position.y >= -1.0:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	settled.emit(self, global_position)
