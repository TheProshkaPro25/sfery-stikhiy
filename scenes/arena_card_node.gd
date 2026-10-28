class_name ArenaCardNode
extends Node3D
## Плоская карта арены на слоте. Рубашкой вверх: цвет владельца, "?"; своя карта подписана.

const SIZE := Vector3(Arena.CARD_W, 0.05, Arena.CARD_H)
const OWNER_COLORS = [Color(0.18, 0.30, 0.55), Color(0.55, 0.20, 0.20)]
const TRAY_X := 8.4 * Arena.UNIT

const FACE_SHADER := """
shader_type spatial;
uniform vec4 base : source_color = vec4(0.18, 0.3, 0.55, 1.0);
uniform vec4 glow : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform vec4 flash_col : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform vec2 dims = vec2(2.0, 2.1);
uniform float mode = 0.0;
uniform float flash = 0.0;

float ring(float r, float rad, float w) { return smoothstep(w, 0.0, abs(r - rad)); }

void fragment() {
	vec2 p = (UV - 0.5) * dims;
	vec2 q = dims * 0.5 - abs(p);
	float d = min(q.x, q.y);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float border = smoothstep(0.075, 0.04, d) * step(0.0, d);
	float border2 = smoothstep(0.025, 0.0, abs(d - 0.2));
	// ромбовая решётка
	vec2 dp = vec2(p.x + p.y, p.x - p.y) * 3.2;
	vec2 g = abs(fract(dp) - 0.5);
	float lattice = smoothstep(0.05, 0.0, min(g.x, g.y));
	float fade = smoothstep(0.25, 0.9, d + 0.3);
	// центральная эмблема: кольца и лучи
	float star = pow(abs(cos(ang * 4.0 + TIME * 0.0)), 14.0) * smoothstep(0.62, 0.0, r);
	float emblem = ring(r, 0.42, 0.04) + ring(r, 0.28, 0.025) * 0.9 + star * 0.8;
	emblem += smoothstep(0.1, 0.0, r) * 1.2;
	float runes = step(0.5, fract(ang * 8.0 / 3.14159 + 0.25)) * ring(r, 0.56, 0.025);
	float shimmer = 0.5 + 0.5 * sin(TIME * 1.6 + p.x * 2.0 + p.y * 3.0);
	vec3 col;
	vec3 emit;
	if (mode < 0.5) {
		vec3 bg = base.rgb * (0.55 + 0.25 * (1.0 - r * 0.6));
		col = bg * (1.0 - lattice * 0.35 * fade) + glow.rgb * lattice * 0.25 * fade;
		float e = border + border2 * 0.6 + emblem + runes * 0.8 + lattice * 0.35 * fade;
		col = mix(col, glow.rgb, clamp(e, 0.0, 1.0));
		emit = glow.rgb * (e * (1.3 + 0.6 * shimmer)) + base.rgb * 0.3;
	} else {
		vec3 bg = mix(base.rgb * 1.25, base.rgb * 0.45, smoothstep(0.0, 1.3, r));
		col = bg;
		float e = border + border2 * 0.5 + emblem * 0.5 + runes * 0.6;
		col = mix(col, vec3(1.0, 0.92, 0.65), clamp(border + border2 * 0.5, 0.0, 1.0));
		emit = vec3(1.0, 0.85, 0.5) * (border * 1.4 + border2 * 0.6) + glow.rgb * (emblem * 1.0 + runes * 0.6) + base.rgb * 0.35;
	}
	float fl = flash * (0.6 + 0.8 * smoothstep(1.4, 0.0, r));
	ALBEDO = col;
	EMISSION = emit + flash_col.rgb * fl * 2.5;
	ROUGHNESS = 0.45;
	METALLIC = 0.2;
}
"""

var slot: int = -1
var owner_player: int = 0
var tray_offset: float = 0.0

var _box: MeshInstance3D
var _face: MeshInstance3D
var _mat: ShaderMaterial
var _flash_tw: Tween
var _label: Label3D
var _built := false


func _init() -> void:
	_ensure_built()


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE
	_box.mesh = bm
	_box.position = Vector3(0, SIZE.y * 0.5, 0)
	_box.material_override = VisualUtil.make_material(Color(0.75, 0.6, 0.25), 0.35, 0.9)
	add_child(_box)

	# Лицевая поверхность с шейдером: узор рубашки / стихия + руны + вспышка.
	_face = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE.x - 0.0, SIZE.z - 0.0)
	_face.mesh = pm
	_face.position = Vector3(0, SIZE.y + 0.002, 0)
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = FACE_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("dims", Vector2(SIZE.x, SIZE.z) / Arena.UNIT)
	_face.material_override = _mat
	add_child(_face)

	_label = Label3D.new()
	_label.pixel_size = 0.005 * Arena.UNIT
	_label.font_size = 36
	_label.outline_size = 8
	_label.width = 440.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.rotation_degrees = Vector3(-90, 0, 0)
	_label.position = Vector3(0, SIZE.y + 0.01, 0)
	add_child(_label)


func show_facedown(owner_pl: int, visible_to_owner_def: CardDef) -> void:
	_ensure_built()
	owner_player = owner_pl
	var oc: Color = OWNER_COLORS[clampi(owner_pl, 0, 1)]
	# тёмный металл с гравировкой; цвет владельца только в светящихся линиях
	_mat.set_shader_parameter("base", Color(0.07, 0.075, 0.09).lerp(oc, 0.25))
	_mat.set_shader_parameter("glow", oc.lightened(0.35))
	_mat.set_shader_parameter("mode", 0.0)
	if visible_to_owner_def != null:
		_label.text = "[%s]" % visible_to_owner_def.display_name
		_label.font_size = 28
	else:
		_label.text = "?"
		_label.font_size = 64


func reveal(def: CardDef) -> void:
	_ensure_built()
	if def == null:
		return
	var col := _card_color(def)
	var flash_col := col.lightened(0.5) if _has_attr(def) else Color(1.0, 0.85, 0.4)
	_label.visible = false
	# Переворот: поворот ребром, смена лица, поворот обратно, затем вспышка.
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", PI * 0.5, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "position:y", position.y + 0.6 * Arena.WORLD, 0.22)
	tw.tween_callback(func():
		_mat.set_shader_parameter("base", col.darkened(0.55))
		_mat.set_shader_parameter("glow", flash_col)
		VisualUtil.light_pillar(self, Vector3(0, 0.1, 0), flash_col, Arena.CARD_H * 0.9, Arena.CARD_W * 0.35, 0.7)
		VisualUtil.ring_wave(self, global_position + Vector3(0, 0.1, 0), flash_col, Arena.CARD_H * 0.75, 0.7)
		_mat.set_shader_parameter("mode", 1.0)
		_label.visible = true
		_label.font_size = 30
		_label.text = "%s\n%s" % [def.display_name, def.text]
		rotation.z = -PI * 0.5)
	tw.tween_property(self, "rotation:z", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(self, "position:y", position.y, 0.25)
	tw.tween_callback(func():
		_mat.set_shader_parameter("flash_col", flash_col)
		if _flash_tw != null:
			_flash_tw.kill()
		_flash_tw = create_tween()
		_flash_tw.tween_method(func(v: float): _mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))


## Движение в "лоток" захваченных карт игрока; возвращает сигнал завершения твина.
func play_capture(to_player: int) -> Signal:
	var z := 2.6 * Arena.UNIT if to_player == 0 else -2.6 * Arena.UNIT
	z += (-tray_offset if to_player == 0 else tray_offset)
	var target := Vector3(TRAY_X, 0.15, z)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", target, 0.8)
	tw.tween_property(self, "scale", Vector3(0.5, 0.5, 0.5), 0.8)
	return tw.finished


func _has_attr(def: CardDef) -> bool:
	return def.params.has("attribute") or def.params.has("attr")


func _card_color(def: CardDef) -> Color:
	var a: int = -1
	var params: Dictionary = def.params
	if params.has("attribute"):
		a = int(params["attribute"])
	elif params.has("attr"):
		a = int(params["attr"])
	if a >= 0:
		return VisualUtil.attr_color(a).darkened(0.1)
	return Color(0.55, 0.50, 0.40)
