class_name MenuOrbs
extends Node3D
## Полночь в меню: высоко над городом по одному загораются шесть шаров стихий (цвета VisualUtil.attr_color),
## собираются в наклонное кольцо, медленно вращаются, вокруг — искры; ~20 с держатся и гаснут к концу окна.
## Шары — билборды orb.gdshader (аддитивно, glow даёт ореол), искры — light_dot.gdshader; всё — два MultiMesh.
## В воде отражаются через water.gdshader (orbs / orb_cols). Вне окна полуночи инстансы сжаты в точку и ничего
## не считается; узел не скрывается — шейдеры компилируются при старте меню, а не рывком в полночь.

## Центр кольца — впереди-справа от камеры, ближе высоток центра (шары не прячутся за ними), в свободном небе.
const CENTER := Vector3(167.0, 173.0, -85.0)
const RADIUS := 85.0
const TILT := 0.6            # наклон кольца от горизонтали, рад (эллипс с перспективой, весь в кадре)
const ORB_R := 14.0          # радиус шара, м
const SPARKS := 10           # искр на шар (на Низких — нет)
## Окно вокруг полуночи (фаза 0): первый шар загорается в START, шары — через STEP, угасание FADE_A..FADE_B.
const START := -0.046
const STEP := 0.0075
const FADE_A := 0.058
const FADE_B := 0.10

var _mm: MultiMesh
var _sparks: MultiMesh
var _sparks_mi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _spark_mat: ShaderMaterial
var _cols: Array[Color] = []
var _pos := PackedVector4Array()
var _vcols := PackedVector3Array()
var _active := true


func _ready() -> void:
	for a in range(6):
		_cols.append(VisualUtil.attr_color(a))
		_vcols.append(Vector3(_cols[a].r, _cols[a].g, _cols[a].b))
	_pos.resize(6)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scenes/menu/orb.gdshader")
	_mm = _make(6, _mat).multimesh
	_spark_mat = ShaderMaterial.new()
	_spark_mat.shader = load("res://scenes/menu/light_dot.gdshader")
	_spark_mat.set_shader_parameter("night", 1.0)
	_sparks_mi = _make(6 * SPARKS, _spark_mat)
	_sparks = _sparks_mi.multimesh
	_hide_all()


func _hide_all() -> void:
	for mm in [_mm, _sparks]:
		for i in range(mm.instance_count):
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), CENTER))
			mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	_active = false


func _make(n: int, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(CENTER - Vector3.ONE * 300.0, Vector3.ONE * 600.0)
	add_child(mi)
	return mi


func apply_quality(level: int) -> void:
	_sparks_mi.visible = level != GraphicsSettings.Level.LOW


## Яркость i-го шара на фазе p (0 вне окна): загорание по очереди со вспышкой, угасание к FADE_B.
static func orb_level(p: float, i: int) -> float:
	var q := fposmod(p + 0.5, 1.0) - 0.5
	var t0 := START + i * STEP
	var on := smoothstep(t0, t0 + 0.006, q)
	var flash := exp(-pow((q - t0 - 0.004) / 0.0025, 2.0)) * 0.8
	return (on + flash) * (1.0 - smoothstep(FADE_A, FADE_B, q))


## Каждый кадр из MenuCity; water — материал воды (отражения).
func update(p: float, t: float, water: ShaderMaterial) -> void:
	var total := 0.0
	for i in range(6):
		total += orb_level(p, i)
	if total < 0.001:
		if _active:
			_hide_all()
			water.set_shader_parameter("orbs_on", 0.0)
		return
	_active = true
	_mat.set_shader_parameter("anim_t", t)
	_spark_mat.set_shader_parameter("anim_t", t)
	var q := fposmod(p + 0.5, 1.0) - 0.5
	var spin := t * 0.12
	# кольцо развёрнуто к камере (MenuCity.CAM_POS) и наклонено
	var to_cam := MenuCity.CAM_POS - CENTER
	var tilt := Basis(Vector3.UP, atan2(to_cam.x, to_cam.z)) * Basis(Vector3.RIGHT, TILT)
	for i in range(6):
		var lv := orb_level(p, i)
		# шар загорается чуть ниже и всплывает на место
		var rise := 1.0 - smoothstep(START + i * STEP, START + i * STEP + 0.012, q)
		var a := spin + TAU * i / 6.0
		var c := CENTER + tilt * Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS) + Vector3(0.0, sin(t * 0.7 + i) * 3.0 - rise * 45.0, 0.0)
		var pulse := 1.0 + 0.06 * sin(t * 2.1 + i * 1.3)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * ORB_R * pulse * (0.6 + 0.4 * minf(lv, 1.0))), c))
		var col := _cols[i]
		_mm.set_instance_custom_data(i, Color(col.r, col.g, col.b, lv))
		_pos[i] = Vector4(c.x, c.y, c.z, lv)
		# искры: кружат вокруг шара и тянутся вверх, мерцая
		for k in range(SPARKS):
			var sk := float(k) / SPARKS
			var life := fposmod(t * (0.25 + 0.1 * sk) + sk * 3.7 + i * 0.31, 1.0)
			var ang := sk * TAU * 3.0 + t * (0.8 + sk) + i
			var rad := ORB_R * (1.4 + 1.8 * life)
			var sp := c + Vector3(cos(ang) * rad, (life - 0.3) * ORB_R * 4.0, sin(ang) * rad)
			var fade := sin(life * PI) * minf(lv, 1.0)
			_sparks.set_instance_transform(i * SPARKS + k, Transform3D(Basis.from_scale(Vector3.ONE * 0.9), sp))
			var sc := col.lightened(0.35) * fade * 1.4
			_sparks.set_instance_custom_data(i * SPARKS + k, Color(sc.r, sc.g, sc.b, 0.0))
	water.set_shader_parameter("orbs_on", 1.0)
	water.set_shader_parameter("orbs", _pos)
	water.set_shader_parameter("orb_cols", _vcols)
