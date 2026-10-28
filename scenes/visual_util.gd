class_name VisualUtil
extends RefCounted
## Общие константы и помощники визуального слоя (модуль Б).

const ATTR_NAMES = ["Пламя", "Буря", "Свет", "Камень", "Тень", "Прилив"]
const ATTR_COLORS = [
	Color(0.92, 0.32, 0.14),
	Color(0.30, 0.78, 0.62),
	Color(0.97, 0.88, 0.40),
	Color(0.55, 0.45, 0.35),
	Color(0.45, 0.28, 0.65),
	Color(0.20, 0.50, 0.90),
]
const NEUTRAL_COLOR := Color(0.6, 0.6, 0.6)


static func attr_name(a: int) -> String:
	if a < 0 or a >= ATTR_NAMES.size():
		return "?"
	return ATTR_NAMES[a]


static func attr_color(a: int) -> Color:
	if a < 0 or a >= ATTR_COLORS.size():
		return NEUTRAL_COLOR
	return ATTR_COLORS[a]


static func make_material(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _grow(a: float) -> Control.GrowDirection:
	if a < 0.25:
		return Control.GROW_DIRECTION_END
	if a > 0.75:
		return Control.GROW_DIRECTION_BEGIN
	return Control.GROW_DIRECTION_BOTH


## Привязывает Control к точке (ax, ay) в долях родителя; размер = минимальный, растёт от точки.
static func place(c: Control, ax: float, ay: float, ox: float, oy: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = _grow(ax)
	c.grow_vertical = _grow(ay)


static func full_rect_ignore(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func clear_children(n: Node) -> void:
	for ch in n.get_children():
		n.remove_child(ch)
		ch.queue_free()


static func label(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


const PILLAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float fade = 1.0;
void fragment() {
	float v = UV.y;                        // 0 верх, 1 низ
	float edge = pow(abs(sin(UV.x * 3.14159)), 1.5);
	float a = smoothstep(0.0, 0.7, v) * edge * fade;
	ALBEDO = col.rgb * (1.5 + 2.0 * v);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
static var _pillar_shader: Shader


## Столб света (появление существа, открытие карты): вспыхивает, сужается и гаснет за dur секунд.
static func light_pillar(parent: Node3D, local_pos: Vector3, c: Color, height: float, radius: float, dur: float = 0.6) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _pillar_shader == null:
		_pillar_shader = Shader.new()
		_pillar_shader.code = PILLAR_SHADER
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.6
	cm.bottom_radius = radius
	cm.height = height
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 24
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = _pillar_shader
	m.set_shader_parameter("col", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	parent.add_child(mi)
	mi.global_position = parent.to_global(local_pos) + Vector3(0, height * 0.5, 0)
	mi.scale = Vector3(0.3, 1.0, 0.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1.0, 1.0, 1.0), dur * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.75)
	tw.parallel().tween_property(mi, "scale", Vector3(0.15, 1.15, 0.15), dur * 0.75)
	tw.tween_callback(mi.queue_free)


## Вспышка-взрыв частиц (удар, выбывание): one-shot, сама удаляется.
static func burst(parent: Node3D, world_pos: Vector3, c: Color, size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 48
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 5.0 * size
	p.gravity = Vector3(0, -2.0 * size, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.25, Color(c.r, c.g, c.b, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.5, 2.5, 2.5)
	m.albedo_texture = soft_dot()
	q.material = m
	p.mesh = q
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	parent.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


static var _dot: GradientTexture2D


## Мягкая круглая точка для частиц (без квадратных краёв).
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.35, Color(1, 1, 1, 0.6))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot


const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float fade = 1.0;
void fragment() {
	float edge = sin(UV.y * 3.14159);
	ALBEDO = col.rgb * 2.5;
	ALPHA = clamp(edge * fade, 0.0, 1.0);
}
"""
static var _ring_shader: Shader


## Кольцевая ударная волна по земле: расширяется до radius и гаснет.
static func ring_wave(parent: Node3D, world_pos: Vector3, c: Color, radius: float, dur: float = 0.6) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.86
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 8
	mi.mesh = tm
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("col", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.scale = Vector3(0.1, 0.05, 0.1) * radius
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.0, 0.15, 1.0) * radius, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## Спираль искр вокруг точки вверх (сила, активация).
static func spiral(parent: Node3D, world_pos: Vector3, c: Color, height: float, radius: float, dur: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 70
	p.lifetime = dur
	p.explosiveness = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.8
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 5.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = height / dur * 0.8
	p.initial_velocity_max = height / dur * 1.2
	p.orbit_velocity_min = 0.6
	p.orbit_velocity_max = 0.9
	p.radial_accel_min = -radius * 0.6
	p.radial_accel_max = -radius * 0.3
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(c.r, c.g, c.b, 0.0))
	grad.add_point(0.15, Color(1, 1, 1, 1))
	grad.add_point(0.4, Color(c.r, c.g, c.b, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045) * Arena.WORLD
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.2, 2.2, 2.2)
	m.albedo_texture = soft_dot()
	q.material = m
	p.mesh = q
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	parent.get_tree().create_timer(dur + 0.5).timeout.connect(p.queue_free)


const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.4, 1.0, 0.6, 1.0);
uniform float fade = 1.0;
void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float hexa = step(0.92, fract(UV.x * 24.0)) + step(0.92, fract(UV.y * 12.0));
	ALBEDO = col.rgb * (1.5 + hexa * 1.5);
	ALPHA = clamp((fres * 0.9 + hexa * 0.15) * fade, 0.0, 1.0);
}
"""
static var _dome_shader: Shader


## Прозрачный купол-щит вокруг существа.
static func dome(parent: Node3D, world_pos: Vector3, c: Color, radius: float, dur: float = 1.4) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _dome_shader == null:
		_dome_shader = Shader.new()
		_dome_shader.code = DOME_SHADER
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.is_hemisphere = true
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = _dome_shader
	m.set_shader_parameter("col", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = world_pos
	mi.scale = Vector3.ONE * radius * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur * 0.5)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.4)
	tw.tween_callback(mi.queue_free)
