class_name CreatureBall
extends RigidBody3D
## Шар-существо. До раскрытия виден шар, после open_up() - фигурка (капсула + рог).
## Оболочка — сложенный механизм (BallShell): лакированные пластины-лепестки со швами, эмблема стихии на полюсах,
## светящаяся сердцевина, кольцо цвета владельца на экваторе. Видимый шар крупнее физического (VIS_SCALE):
## физика и точность бросков прежние, а шар читается с камеры погони. Эффекты — BallFx / BallTrail.

signal settled(ball: CreatureBall, world_pos: Vector3)

const ElementIcon := preload("res://scenes/element_icon.gd")

const RADIUS := 0.35  # ~1/17 масштаба существ Arena.FIG_H
const SLOW_SPEED := 0.15
const SLOW_ANG := 1.0
const SLOW_TIME := 0.15
const TIMEOUT := 9.0
## Видимый радиус оболочки = RADIUS × VIS_SCALE (низ оболочки стоит на полу, как у физического шара).
const VIS_SCALE := 2.2
## Цвет кольца владельца: игрок (бросает от +Z), соперник.
const OWNER_GLOW := [Color(0.35, 0.62, 1.0), Color(1.0, 0.32, 0.28)]
## Ободок раскрытого существа по владельцу (next_pass материалов модели): свои — мягкий синий, чужие — красный.
const RIM_STRENGTH := [0.12, 0.22]
## Ободок: аддитивный френель по силуэту (вспышки CreatureAnim идут через material_overlay и его не трогают).
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.3, 0.25, 1.0);
uniform float strength = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.6);
	ALBEDO = col.rgb * strength;
	ALPHA = clamp(f * (0.85 + 0.15 * sin(TIME * 2.2)), 0.0, 1.0);
}
"""
## Кольцо владельца на полу под раскрытым существом: мягкое свечение с бегущими штрихами.
const FOOT_RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.3, 0.25, 1.0);
uniform float strength = 1.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ring = smoothstep(0.075, 0.0, abs(r - 0.86));
	float halo = smoothstep(1.0, 0.86, r) * smoothstep(0.55, 0.86, r) * 0.35;
	float ang = atan(p.y, p.x);
	float dash = smoothstep(0.3, 0.6, sin(ang * 18.0 - TIME * 1.5)) * smoothstep(0.03, 0.0, abs(r - 0.95));
	float inner = smoothstep(0.86, 0.0, r) * 0.12;
	ALBEDO = col.rgb * strength;
	ALPHA = clamp(ring * 0.9 + halo + dash * 0.6 + inner, 0.0, 1.0);
}
"""
static var _rim_mats: Array = []
static var _ring_mats: Array = []

var uid: int = -1
var def: CreatureDef = null
var slot: int = -1

var _built := false
var _shape: CollisionShape3D
var _visual: Node3D
var _ball_mesh: MeshInstance3D  ## закрытая оболочка одним мешем
var _shell: Node3D              ## оболочка (масштаб VIS_SCALE, центр над физическим шаром)
var _core: MeshInstance3D
var _figure: Node3D
var _anim: CreatureAnim
var _label: Label3D
var _icon: Sprite3D             ## значок стихии слева от подписи (дочерний подписи: прячется вместе с ней)
var _foot_ring: MeshInstance3D  ## кольцо владельца на полу под раскрытым существом
var _open := false
var _prev_vel := Vector3.ZERO
var _label_allowed := true
var _halves: Array[MeshInstance3D] = []  ## части оболочки для раскрытия (лепестки, крышки, пояс)
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
var _sparks: CPUParticles3D   ## частицы стихии от контакта с полом
var _streak: CPUParticles3D   ## светящийся след по полу
var _trail: CPUParticles3D    ## частицы стихии в полёте
var _ribbon: BallTrail        ## лента следа
var _el := -1
var _home := Vector3.ZERO     ## откуда бросали (туда сфера улетает при возврате)
var _home_set := false
var _drive := false           ## визуал ведёт анимация (возврат к владельцу), а не дуга


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

	_shell = Node3D.new()
	_shell.scale = Vector3.ONE * _shell_r()
	_shell.position = Vector3(0, _shell_r() - RADIUS, 0)
	_visual.add_child(_shell)

	_ball_mesh = MeshInstance3D.new()
	_ball_mesh.mesh = BallShell.closed_mesh()
	_ball_mesh.material_override = BallShell.shell_material()
	_shell.add_child(_ball_mesh)

	_core = MeshInstance3D.new()
	_core.mesh = BallShell.core_mesh()
	_core.material_override = BallShell.core_material()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.add_child(_core)

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

	_icon = Sprite3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.shaded = false
	_icon.double_sided = false
	_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.pixel_size = _label.pixel_size * 1.05
	_icon.render_priority = 1
	_label.add_child(_icon)

	_foot_ring = MeshInstance3D.new()
	var rq := PlaneMesh.new()
	rq.size = Vector2.ONE * 2.0
	_foot_ring.mesh = rq
	_foot_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_foot_ring.position = Vector3(0, -RADIUS + 0.035, 0)
	_figure.add_child(_foot_ring)


static func _shell_r() -> float:
	return RADIUS * VIS_SCALE


func setup(d: CreatureDef, u: int) -> void:
	_ensure_built()
	def = d
	uid = u
	var txt := "?"
	_el = -1
	if d != null:
		_el = d.attribute
		txt = "%s\n%s %d" % [d.display_name, VisualUtil.attr_name(d.attribute), d.base_power]
	_shell_param("element", maxi(_el, 0))
	_shell_param("owner_col", OWNER_GLOW[0] if not _home_set else _owner_color())
	_core.set_instance_shader_parameter("col", _ecol())
	_set_glow(0.0)
	for c in _figure.get_children():
		if c != _foot_ring:  # кольцо владельца живёт с шаром, меняется только модель
			_figure.remove_child(c)
			c.queue_free()
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
	_icon.texture = ElementIcon.badge(_el) if _el >= 0 else null
	_sync_icon()
	var rr: float = clampf((_anim.get_extent() if _anim != null else Arena.FIG_W) * 0.55, Arena.FIG_W * 0.35, Arena.FIG_H / 3.0 * 0.95)
	_foot_ring.scale = Vector3(rr, 1.0, rr)


## Значок стихии слева от текста подписи, с тем же сдвигом подписи на экране (set_label_shift).
func _sync_icon() -> void:
	if _icon == null or _icon.texture == null:
		return
	var font: Font = _label.font if _label.font != null else ThemeDB.fallback_font
	var w := 0.0
	for line in _label.text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _label.font_size).x)
	var k: float = _label.pixel_size / _icon.pixel_size  # пиксели подписи → пиксели значка
	var half: float = ElementIcon.SIZE * 0.5
	_icon.offset = Vector2((_label.offset.x - w * 0.5 - _label.outline_size - 10.0) * k - half, _label.offset.y * k)


## Метки владельца раскрытого существа: ободок по силуэту модели и кольцо на полу (синие — свои, красные — чужие).
func _apply_owner_marks() -> void:
	var side: int = 1 if _home_set and _home.z < 0.0 else 0
	if _rim_mats.is_empty():
		var sh := Shader.new()
		sh.code = RIM_SHADER
		var rs := Shader.new()
		rs.code = FOOT_RING_SHADER
		for k in range(2):
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("col", OWNER_GLOW[k])
			m.set_shader_parameter("strength", RIM_STRENGTH[k])
			_rim_mats.append(m)
			var rm := ShaderMaterial.new()
			rm.shader = rs
			rm.set_shader_parameter("col", OWNER_GLOW[k])
			rm.set_shader_parameter("strength", 1.0 if k == 1 else 0.7)
			_ring_mats.append(rm)
	_foot_ring.material_override = _ring_mats[side]
	if _anim != null:
		_set_rim(_anim, _rim_mats[side])


## next_pass на материалы модели (материалы у каждого экземпляра свои — CreatureModels дублирует их).
static func _set_rim(n: Node, rim: Material) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var m := mi.get_surface_override_material(i)
			if m == null:
				var src := mi.get_active_material(i)
				if src == null:
					continue
				m = src.duplicate()
				mi.set_surface_override_material(i, m)
			if m.next_pass != rim:
				m.next_pass = rim
	for c in n.get_children():
		_set_rim(c, rim)


## Яркий цвет стихии (оболочка, сердцевина, частицы).
func _ecol() -> Color:
	return BallFx.elem_color(_el) if _el >= 0 else Color(0.9, 0.9, 0.9)


func _owner_color() -> Color:
	return OWNER_GLOW[0] if _home.z >= 0.0 else OWNER_GLOW[1]


## Параметр оболочки — на закрытый меш и все части (общий материал, значения — на экземпляр).
func _shell_param(n: StringName, v: Variant) -> void:
	_ball_mesh.set_instance_shader_parameter(n, v)
	for h in _halves:
		h.set_instance_shader_parameter(n, v)


## Яркость сердцевины и швов (0 — обычная пульсация, 2–3 — вспышка).
func _set_glow(v: float) -> void:
	_shell_param("glow", v)
	_core.set_instance_shader_parameter("glow", v)


func _set_dim(v: float) -> void:
	_shell_param("dim", v)
	_core.set_instance_shader_parameter("dim", v)


func _set_crack(v: float) -> void:
	_shell_param("crack", v)


## Мир, куда кладутся одноразовые эффекты (переживают сам шар).
func _fx_parent() -> Node:
	var p := get_parent()
	return p if p != null else self


## Центр видимой оболочки в мире.
func _shell_center() -> Vector3:
	return _shell.global_position if _shell.is_inside_tree() else global_position


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
	_sync_icon()


## След летящего шара: лента цвета стихии и частицы стихии; при первом броске — ещё и наземные эффекты.
func _start_trail() -> void:
	var el := maxi(_el, 0)
	if _trail == null:
		_trail = BallFx.particles(el, "trail", _shell_r())
		_visual.add_child(_trail)
		_ribbon = BallTrail.new()
		_ribbon.target = _shell
		_ribbon.color = _ecol()
		_ribbon.width = _shell_r() * 1.5
		add_child(_ribbon)
	_trail.emitting = true
	_ribbon.emitting = true
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


## Частицы стихии из-под катящегося шара и светящийся след по полю (частицы в мировых координатах).
func _build_ground_fx() -> void:
	var c := _ecol()
	_sparks = BallFx.particles(maxi(_el, 0), "roll", _shell_r())
	_sparks.top_level = true
	add_child(_sparks)

	_streak = CPUParticles3D.new()
	_streak.top_level = true
	_streak.local_coords = false
	_streak.emitting = false
	_streak.amount = maxi(24, int(90 * BallFx.level_k()))
	_streak.lifetime = 1.4
	_streak.gravity = Vector3.ZERO
	_streak.initial_velocity_min = 0.0
	_streak.initial_velocity_max = 0.0
	_streak.scale_amount_min = 1.0
	_streak.scale_amount_max = 1.0
	_streak.color_ramp = _streak_ramp(c)
	_streak.mesh = _streak_mesh()
	add_child(_streak)


static var _streak_meshes: Dictionary = {}


## След по полу: плоский мягкий круг (общий меш на все шары).
static func _streak_mesh() -> PlaneMesh:
	if not _streak_meshes.has("mesh"):
		var pl := PlaneMesh.new()  # лежит на полу
		pl.size = Vector2(RADIUS * 3.2, RADIUS * 3.2)
		var pmat := StandardMaterial3D.new()
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pmat.vertex_color_use_as_albedo = true
		pmat.albedo_texture = VisualUtil.soft_dot()
		pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		pmat.disable_receive_shadows = true
		pl.material = pmat
		_streak_meshes["mesh"] = pl
	return _streak_meshes["mesh"]


static func _streak_ramp(c: Color) -> Gradient:
	var key := c.to_html()
	if not _streak_meshes.has(key):
		var tg := Gradient.new()
		tg.set_color(0, Color(c.r, c.g, c.b, 0.75).lightened(0.4))
		tg.add_point(0.25, Color(c.r, c.g, c.b, 0.4))
		tg.set_color(tg.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
		_streak_meshes[key] = tg
	return _streak_meshes[key]


## Рост существа в раскрытом виде (м), для кадрирования камерой.
func figure_height() -> float:
	if _anim != null:
		return _anim.get_height()
	return Arena.FIG_H * 0.8


## Масштаб кадра для камеры: наибольшее из роста и размера по полу (длинные и широкие существа).
func figure_size() -> float:
	if _anim != null:
		return maxf(_anim.get_height(), _anim.get_extent())
	return Arena.FIG_H * 0.8


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
	_throw_fx(impulse)


## Бросок: вспышка, кольцо ускорения поперёк полёта, сердцевина вспыхивает и успокаивается.
func _throw_fx(impulse: Vector3) -> void:
	if not is_inside_tree():
		return
	var c := _ecol()
	var w := _fx_parent()
	var p := _shell_center()
	BallFx.flash(w, p, c, _shell_r() * 7.0, 0.3)
	var dir := Vector3(impulse.x, impulse.length() * 0.25, impulse.z)
	BallFx.speed_ring(w, p + dir.normalized() * _shell_r() * 1.5, dir, c, _shell_r() * 3.0, 0.32)
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if is_inside_tree():
			BallFx.speed_ring(w, _shell_center(), dir, c.lightened(0.4), _shell_r() * 2.0, 0.25))
	var tw := create_tween()
	tw.tween_method(_set_glow, 2.2, 0.0, 0.6).set_ease(Tween.EASE_OUT)


## Касание пола после дуги: ударная волна пыли по полу и разлёт частиц стихии.
func _touchdown_fx() -> void:
	if not is_inside_tree():
		return
	var w := _fx_parent()
	var fp := Vector3(global_position.x, 0.06, global_position.z)
	VisualUtil.ring_wave(w as Node3D, fp, _ecol(), _shell_r() * 4.5, 0.45)
	BallFx.one_shot(w, fp + Vector3(0, _shell_r() * 0.3, 0), maxi(_el, 0), "burst", _shell_r() * 0.8)


func open_up() -> Signal:
	return open_animated()


## Раскрытие: сердцевина вспыхивает, лепестки откидываются наружу, крышка с эмблемой взлетает и кружится,
## знак стихии вспыхивает на карте, столб света и вихрь частиц стихии; существо вырастает из света.
## pose — существо встаёт в боевую стойку с рёвом (CreatureAnim.appear); в бою вместо неё рёв по сигналу.
func open_animated(pose: bool = true) -> Signal:
	if _open:
		var t0 := create_tween()
		t0.tween_interval(0.01)
		return t0.finished
	_open = true
	_kill_open_tween()
	_drive = false
	var pc := _ecol()
	var el := maxi(_el, 0)
	VisualUtil.light_pillar(self, Vector3(0, -RADIUS, 0), pc, Arena.FIG_H * 2.0, Arena.FIG_W * 0.16, 0.9)
	if is_inside_tree():
		var w := _fx_parent()
		var fp := Vector3(global_position.x, 0.07, global_position.z)
		BallFx.sigil_flash(w, fp, el, Arena.FIG_W * 0.85, 1.2)
		BallFx.flash(w, _shell_center(), pc, _shell_r() * 4.5, 0.35)
		BallFx.light_flash(w, fp + Vector3(0, Arena.FIG_W * 0.35, 0), pc, 1.5, Arena.FIG_W * 1.4, 0.5)
		BallFx.one_shot(w, fp, el, "open", Arena.FIG_W * 0.24)
	_ball_mesh.visible = false
	_shell.visible = true
	_figure.visible = true
	_figure.scale = Vector3(0.01, 0.01, 0.01)
	_label.visible = false
	_apply_owner_marks()
	_make_halves()
	_pose_halves(0.0)
	var tw := create_tween()
	_open_tween = tw
	tw.set_parallel(true)
	tw.tween_method(_set_glow, 3.0, 0.4, 0.55)
	tw.tween_method(_pose_halves, 0.0, 1.0, 0.42).set_delay(0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_shell_burst).set_delay(0.5)
	tw.tween_property(_shell, "scale", Vector3.ONE * 0.001, 0.22).set_delay(0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(_figure, "scale", Vector3.ONE, 0.4).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_finish_open)
	if _anim != null:
		_anim.reset()
		_anim.appear(pose)
	return tw.finished


## Пластины рассыпаются искрами стихии.
func _shell_burst() -> void:
	if is_inside_tree():
		BallFx.one_shot(_fx_parent(), _shell_center(), maxi(_el, 0), "burst", _shell_r())


func _finish_open() -> void:
	for h in _halves:
		h.visible = false
	_shell.visible = false
	_shell.scale = Vector3.ONE * _shell_r()
	_set_glow(0.0)
	_label.visible = _open and _label_allowed


func _kill_open_tween() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = null


## Части оболочки (общие меши BallShell), создаются у шара один раз — при первом раскрытии.
func _make_halves() -> void:
	if _halves.is_empty():
		for part in BallShell.parts():
			var m := MeshInstance3D.new()
			m.mesh = part["mesh"]
			m.material_override = BallShell.shell_material()
			m.set_meta("part", part)
			_shell.add_child(m)
			_halves.append(m)
		_shell_param("element", maxi(_el, 0))
		_shell_param("owner_col", _owner_color() if _home_set else OWNER_GLOW[0])
	for h in _halves:
		h.visible = true
		h.scale = Vector3.ONE
	_ball_mesh.visible = false


## Поза раскрытия всех частей: 0 — закрыт, 1 — раскрыт.
func _pose_halves(t: float) -> void:
	for h in _halves:
		h.transform = BallShell.part_transform(h.get_meta("part"), t)


## Шар снова цельный (закрытый меш вместо частей).
func _show_closed() -> void:
	for h in _halves:
		h.visible = false
	_ball_mesh.visible = true
	_shell.visible = true
	_shell.scale = Vector3.ONE * _shell_r()


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
	_show_closed()
	_set_glow(0.0)
	_set_dim(0.0)
	_set_crack(0.0)
	_visual.scale = Vector3.ONE
	if is_inside_tree():
		BallFx.flash(_fx_parent(), _shell_center(), _ecol(), _shell_r() * 4.0, 0.25)


## Фиксирует тело в точке (без вращения); используется и для удержания шара перед броском.
## Замороженный шар не сталкивается с катящимися: иначе в слот с существом нельзя попасть (отскок).
func freeze_at(pos: Vector3) -> void:
	if _anim != null:
		_anim.reset()
	if not _home_set:
		# первая фиксация — точка броска владельца: туда шар вернётся, по ней же цвет кольца владельца
		_home = pos
		_home_set = true
		_shell_param("owner_col", _owner_color())
	_label.offset = Vector2.ZERO
	_sync_icon()
	collision_layer = 0
	collision_mask = 0
	_launched = false
	_has_pending = false
	_air_t = -1.0
	_drive = false
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
			_touchdown_fx()
		var y := arc_height(_air_t, _air_dur, _air_h)
		if _air_t > arc_total(_air_dur) or not _launched:
			_air_t = -1.0
			y = 0.0
		_visual.global_position = global_position + Vector3(0.0, y, 0.0)
		if _trail != null:
			_trail.emitting = _launched and y > 0.3
	elif not _drive and _visual.position != Vector3.ZERO:
		_visual.position = Vector3.ZERO
	# оболочка крупнее физического шара: её низ стоит на полу (центр поднят по мировой вертикали)
	if _shell.visible:
		_shell.global_position = _visual.global_position + Vector3(0.0, _shell.scale.x - RADIUS, 0.0)
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


## Уход с поля. Раскрытое существо втягивается в свет, пластины захлопываются; затем шар улетает
## к владельцу (knockout = false) или трескается и гаснет (knockout = true — нокаут, выбывание).
func vanish(knockout: bool = false) -> Signal:
	_launched = false
	_shape.disabled = true
	freeze = true
	_kill_open_tween()
	_stop_fx()
	_label.visible = false
	var tw := create_tween()
	_open_tween = tw
	var pc := _ecol()
	if _open and _figure.visible:
		_open = false
		# существо втягивается в свет
		VisualUtil.light_pillar(self, Vector3(0, -RADIUS, 0), pc.lightened(0.4), figure_height() * 1.3, Arena.FIG_W * 0.14, 0.6)
		_make_halves()
		_pose_halves(1.0)
		_shell.visible = true
		_shell.scale = Vector3.ONE * 0.001
		_set_glow(2.5)
		tw.set_parallel(true)
		tw.tween_property(_figure, "scale", Vector3(0.01, 0.01, 0.01), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(_shell, "scale", Vector3.ONE * _shell_r(), 0.22).set_delay(0.08).set_ease(Tween.EASE_OUT)
		# пластины захлопываются
		tw.tween_method(_pose_halves, 1.0, 0.0, 0.22).set_delay(0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_method(_set_glow, 2.5, 0.6, 0.4).set_delay(0.1)
		tw.set_parallel(false)
		tw.tween_callback(_snapped_shut)
	if knockout:
		_knockout_steps(tw)
	else:
		_fly_home_steps(tw)
	return tw.finished


## Пластины сомкнулись: цельный шар, вспышка и кольцо.
func _snapped_shut() -> void:
	_figure.visible = false
	_show_closed()
	if is_inside_tree():
		var w := _fx_parent()
		BallFx.flash(w, _shell_center(), _ecol(), _shell_r() * 5.0, 0.25)
		VisualUtil.ring_wave(w as Node3D, Vector3(global_position.x, 0.06, global_position.z), _ecol(), _shell_r() * 3.5, 0.35)


## Возврат: шар подпрыгивает и по дуге улетает к точке броска владельца, уменьшаясь и оставляя след.
func _fly_home_steps(tw: Tween) -> void:
	tw.tween_callback(func() -> void:
		_drive = true
		_show_closed()
		if _ribbon == null:
			_start_trail()
			_stop_fx()
		_ribbon.emitting = true
		if is_inside_tree():
			BallFx.speed_ring(_fx_parent(), _shell_center(), Vector3.UP, _ecol(), _shell_r() * 2.5, 0.3))
	var from := global_position
	var to := _home + Vector3(0, 1.5, 0) if _home_set else from + Vector3(0, 12.0, 0)
	var h := clampf(from.distance_to(to) * 0.25, 2.0, 9.0)
	tw.tween_method(func(t: float) -> void:
		if is_inside_tree():
			_visual.global_position = from.lerp(to, t) + Vector3(0, sin(t * PI) * h, 0)
		_shell.scale = Vector3.ONE * _shell_r() * lerpf(1.0, 0.35, t * t)
		_set_glow(t * 1.5), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if _ribbon != null:
			_ribbon.emitting = false
		if is_inside_tree():
			BallFx.flash(_fx_parent(), _shell_center(), _ecol(), _shell_r() * 3.0, 0.2)
		_shell.visible = false)
	tw.tween_interval(0.05)


## Нокаут: по оболочке бегут трещины, сердцевина мигает и гаснет, шар разлетается осколками.
func _knockout_steps(tw: Tween) -> void:
	tw.tween_callback(func() -> void:
		_drive = true
		_show_closed()
		_set_glow(1.5))
	var base := Vector3.ZERO
	tw.tween_method(func(t: float) -> void:
		_set_crack(t)
		_set_glow(1.5 * (1.0 - t) + (0.8 if fmod(t * 9.0, 1.0) < 0.5 else 0.0))
		_visual.position = base + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.05 * t, 0.0, 1.0, 0.45)
	tw.tween_method(_set_dim, 0.0, 1.0, 0.25)
	tw.tween_callback(func() -> void:
		if is_inside_tree():
			var w := _fx_parent()
			var p := _shell_center()
			BallFx.one_shot(w, p, BallFx.STONE, "burst", _shell_r() * 1.2)
			BallFx.one_shot(w, p, maxi(_el, 0), "burst", _shell_r())
			BallFx.flash(w, p, Color(1.0, 0.95, 0.9), _shell_r() * 5.0, 0.2)
		# пластины разлетаются
		_make_halves())
	tw.tween_method(func(t: float) -> void:
		_pose_halves(t * 0.6)
		for h in _halves:
			h.position += (h.get_meta("part")["hinge"] as Vector3) * t * 0.08
			h.scale = Vector3.ONE * (1.0 - t)
		_set_dim(1.0), 0.0, 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _shell.visible = false)


func _stop_fx() -> void:
	SoundFx.i().set_roll(0.0)
	if _trail != null:
		_trail.emitting = false
	if _ribbon != null:
		_ribbon.emitting = false
	if _sparks != null:
		_sparks.emitting = false
		_streak.emitting = false


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
		_sparks.emitting = on_ground and hs > 3.0
		_streak.emitting = on_ground and hs > 1.2
		if hs > 0.1:
			_sparks.direction = Vector3(-v.x / hs, 1.2, -v.z / hs)
		if _ribbon != null:
			_ribbon.emitting = hs > 4.0 or not on_ground

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
	_stop_fx()
	_done = true
	_launched = false
	if global_position.y >= -1.0:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	settled.emit(self, global_position)
