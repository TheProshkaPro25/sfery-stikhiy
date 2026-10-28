class_name MenuTraffic
extends Node3D
## Транспорт пейзажа меню. Узлов — единицы, всё MultiMesh:
##   машины — низкополигональные меши (кузов, кабина-стекло, колёса, фары и стопы) на всех дорогах и мостах,
##     по полосам в обе стороны; едут прямо в вершинном шейдере (vehicle.gdshader), CPU их не трогает;
##   метро — два поезда по эстакаде вдоль городской набережной (эстакаду строит MenuCity);
##   река — катера, речные трамваи и баржи (след на воде рисует water.gdshader по массиву boats);
##   небо — самолёт и вертолёт над центром; их огни (и огни лодок) — билборды light_dot.gdshader.
## На CPU каждый кадр — несколько десятков трансформов (поезда, лодки, воздух, огоньки).

const RAIL_Z := 25.0         # ось эстакады метро (над водой у городской набережной)
const RAIL_Y := 6.0          # верх настила (под мостами: низ их пролёта ~10.3)
const RAIL_X := Vector2(-620.0, 1020.0)
const TRAIN_CARS := 5
const TRAIN_CAR_LEN := 20.0
const BOAT_X := Vector2(-760.0, 1120.0)   # петля лодок: за краями кадра
const MAX_BOATS := 16

## Доля машин по уровню графики (Низкие, Средние, Высокие).
const CAR_SHARE := [0.35, 0.65, 1.0]

var _rng := RandomNumberGenerator.new()
var _car_mat: ShaderMaterial
var _craft_mat: ShaderMaterial
var _dot_mat: ShaderMaterial
var _cars: MultiMesh
var _car_total := 0
var _train_mm: MultiMesh
var _boat_mm: Array[MultiMesh] = []   # по типам: катер, речной трамвай, баржа
var _plane_mm: MultiMesh
var _heli_mm: MultiMesh
var _rotor_mm: MultiMesh
var _dots: MultiMesh
var _trains: Array = []   # {dir, z, v, phase, paint}
var _boats: Array = []    # {type, idx, z, dir, v, phase, half_len}
var _wakes := PackedVector4Array()


## roads: [Vector2 a, Vector2 b, ширина, полос в одну сторону, y, множитель скорости]; cam — позиция камеры.
func build(roads: Array, cam: Vector3) -> void:
	_rng.seed = 7311
	_car_mat = _mat(true)
	_craft_mat = _mat(false)
	_build_cars(roads, cam)
	_build_trains()
	_build_boats()
	_build_air()


func _mat(road: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/menu/vehicle.gdshader")
	m.set_shader_parameter("road_anim", road)
	return m


func apply_quality(level: int) -> void:
	if _cars != null:
		_cars.visible_instance_count = int(_car_total * float(CAR_SHARE[clampi(level, 0, 2)]))


## Каждый кадр: огни/плотность по суткам, поезда, лодки, воздух. water — материал воды (след лодок).
func update(t: float, night: float, traffic: float, water: ShaderMaterial) -> void:
	for m: ShaderMaterial in [_car_mat, _craft_mat]:
		m.set_shader_parameter("anim_t", t)
		m.set_shader_parameter("night", night)
	_car_mat.set_shader_parameter("traffic", traffic)
	_dot_mat.set_shader_parameter("anim_t", t)
	_dot_mat.set_shader_parameter("night", night)
	var di := 0
	_update_trains(t)
	di = _update_boats(t, night, di)
	di = _update_air(t, di)
	water.set_shader_parameter("boats", _wakes)
	water.set_shader_parameter("boat_n", _boats.size())


# ---------------------------------------------------------------- меши

## Сборщик мешей с плоскими гранями; часть меша (см. vehicle.gdshader) — в COLOR.r.
class MeshKit:
	var st := SurfaceTool.new()
	## оттенок в COLOR.g (у деревьев — светлее/темнее отдельные шары кроны)
	var shade := 0.0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Треугольник; inside — точка внутри тела (по ней выбирается наружная сторона).
	func tri(a: Vector3, b: Vector3, c: Vector3, part: int, inside: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			var tv := b
			b = c
			c = tv
			var tu := ub
			ub = uc
			uc = tu
			n = -n
		n = n.normalized()
		var col := Color(part / 10.0, shade, 0.0)
		# в Godot лицевая сторона — по часовой стрелке
		for v: Array in [[a, ua], [c, uc], [b, ub]]:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(v[1])
			st.add_vertex(v[0])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, part: int, inside: Vector3) -> void:
		tri(a, b, c, part, inside)
		tri(a, c, d, part, inside)

	func box(mn: Vector3, mx: Vector3, part: int) -> void:
		var c := (mn + mx) * 0.5
		var p := func(i: int) -> Vector3: return Vector3(mx.x if i & 1 else mn.x, mx.y if i & 2 else mn.y, mx.z if i & 4 else mn.z)
		for f: Array in [[0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 5, 4], [2, 3, 7, 6], [0, 1, 3, 2], [4, 5, 7, 6]]:
			quad(p.call(f[0]), p.call(f[1]), p.call(f[2]), p.call(f[3]), part, c)

	## Выпуклая призма: грань pts, вытянутая на ext.
	func prism(pts: Array, ext: Vector3, part: int) -> void:
		var c := Vector3.ZERO
		for q: Vector3 in pts:
			c += q
		c = c / pts.size() + ext * 0.5
		var n := pts.size()
		for i in range(1, n - 1):
			tri(pts[0], pts[i], pts[i + 1], part, c)
			tri(pts[0] + ext, pts[i] + ext, pts[i + 1] + ext, part, c)
		for i in range(n):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % n]
			quad(a, b, b + ext, a + ext, part, c)

	## Икосаэдр (20 граней) с полуосями r вокруг c — шар кроны дерева, бак водобашни.
	func ico(c: Vector3, r: Vector3, part: int) -> void:
		var f := (1.0 + sqrt(5.0)) * 0.5
		var v := [Vector3(-1, f, 0), Vector3(1, f, 0), Vector3(-1, -f, 0), Vector3(1, -f, 0), Vector3(0, -1, f), Vector3(0, 1, f),
			Vector3(0, -1, -f), Vector3(0, 1, -f), Vector3(f, 0, -1), Vector3(f, 0, 1), Vector3(-f, 0, -1), Vector3(-f, 0, 1)]
		var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
			[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
		var p: Array[Vector3] = []
		for q: Vector3 in v:
			p.append(c + q.normalized() * r)
		for fc: Array in faces:
			tri(p[fc[0]], p[fc[1]], p[fc[2]], part, c)

	## Фара на торце x = fx (наружу — по знаку out): UV — угол квада (−1..1) для «роста» огня издалека.
	func lamp(fx: float, out: float, cy: float, cz: float, hy: float, hz: float, part: int) -> void:
		var x := fx + out * 0.03
		var inside := Vector3(x - out, cy, cz)
		var a := Vector3(x, cy - hy, cz - hz)
		var b := Vector3(x, cy - hy, cz + hz)
		var c := Vector3(x, cy + hy, cz + hz)
		var d := Vector3(x, cy + hy, cz - hz)
		tri(a, b, c, part, inside, Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1))
		tri(a, c, d, part, inside, Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1))

	## Корпус лодки: корма прямоугольная, нос клином; палуба на высоте h, днище — −draft.
	func hull(len: float, w: float, h: float, draft: float, bow: float, part: int) -> void:
		var x0 := -len * 0.5
		var xb := len * 0.5 - bow
		var xt := len * 0.5
		var S1 := Vector3(x0, h, -w * 0.5)
		var S2 := Vector3(x0, h, w * 0.5)
		var B1 := Vector3(xb, h, -w * 0.5)
		var B2 := Vector3(xb, h, w * 0.5)
		var T := Vector3(xt, h + 0.25, 0.0)
		var s1 := Vector3(x0, -draft, -w * 0.35)
		var s2 := Vector3(x0, -draft, w * 0.35)
		var b1 := Vector3(xb, -draft, -w * 0.35)
		var b2 := Vector3(xb, -draft, w * 0.35)
		var t := Vector3(xt - bow * 0.35, -draft * 0.3, 0.0)
		var c := Vector3(0.0, (h - draft) * 0.5, 0.0)
		quad(S1, S2, B2, B1, 7, c)
		tri(B1, B2, T, 7, c)
		quad(S1, S2, s2, s1, part, c)
		quad(S1, B1, b1, s1, part, c)
		quad(S2, B2, b2, s2, part, c)
		quad(B1, T, t, b1, part, c)
		quad(B2, T, t, b2, part, c)
		quad(s1, s2, b2, b1, 4, c)
		tri(b1, b2, t, 4, c)

	func commit() -> ArrayMesh:
		return st.commit()


## Легковая: ось X — вперёд, длина 4.4 м.
func _car_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(-2.2, 0.34, -0.9), Vector3(2.2, 0.95, 0.9), 0)
	for ax in [-1.35, 1.35]:
		k.box(Vector3(ax - 0.33, 0.0, -0.93), Vector3(ax + 0.33, 0.62, 0.93), 4)
	# кабина-трапеция: стекло, крыша — в цвет кузова
	var lo := [Vector3(-1.35, 0.95, -0.84), Vector3(0.95, 0.95, -0.84), Vector3(0.95, 0.95, 0.84), Vector3(-1.35, 0.95, 0.84)]
	var hi := [Vector3(-1.0, 1.45, -0.7), Vector3(0.35, 1.45, -0.7), Vector3(0.35, 1.45, 0.7), Vector3(-1.0, 1.45, 0.7)]
	var c := Vector3(-0.25, 1.2, 0.0)
	for i in range(4):
		k.quad(lo[i], lo[(i + 1) % 4], hi[(i + 1) % 4], hi[i], 1, c)
	k.quad(hi[0], hi[1], hi[2], hi[3], 0, c)
	for z in [-0.6, 0.6]:
		k.lamp(2.2, 1.0, 0.78, z, 0.09, 0.2, 2)
		k.lamp(-2.2, -1.0, 0.8, z, 0.08, 0.2, 3)
	return k.commit()


func _train_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var hl := TRAIN_CAR_LEN * 0.5
	k.box(Vector3(-hl + 0.4, 0.0, -1.4), Vector3(hl - 0.4, 0.75, 1.4), 4)
	k.box(Vector3(-hl, 0.75, -1.5), Vector3(hl, 1.7, 1.5), 0)
	k.box(Vector3(-hl, 1.7, -1.5), Vector3(hl, 2.8, 1.5), 1)
	k.box(Vector3(-hl, 2.8, -1.5), Vector3(hl, 3.3, 1.5), 5)
	k.box(Vector3(-hl + 0.6, 3.3, -1.25), Vector3(hl - 0.6, 3.55, 1.25), 6)
	for z in [-0.95, 0.95]:
		k.lamp(hl, 1.0, 1.25, z, 0.14, 0.22, 2)
		k.lamp(-hl, -1.0, 1.25, z, 0.14, 0.22, 3)
	return k.commit()


func _boat_meshes() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	# катер
	var k := MeshKit.new()
	k.hull(9.0, 2.8, 0.9, 0.5, 3.0, 5)
	k.box(Vector3(-1.6, 0.9, -1.0), Vector3(0.9, 1.9, 1.0), 1)
	k.box(Vector3(-1.75, 1.9, -1.1), Vector3(1.0, 2.05, 1.1), 0)
	out.append(k.commit())
	# речной трамвай: длинная надстройка с окнами
	k = MeshKit.new()
	k.hull(32.0, 7.0, 1.4, 1.0, 6.0, 0)
	k.box(Vector3(-12.0, 1.4, -3.0), Vector3(8.0, 2.0, 3.0), 5)
	k.box(Vector3(-12.0, 2.0, -3.0), Vector3(8.0, 3.6, 3.0), 1)
	k.box(Vector3(-12.3, 3.6, -3.2), Vector3(8.3, 4.0, 3.2), 5)
	k.box(Vector3(3.5, 4.0, -1.6), Vector3(7.0, 5.6, 1.6), 1)
	k.box(Vector3(3.3, 5.6, -1.8), Vector3(7.2, 5.85, 1.8), 5)
	out.append(k.commit())
	# баржа-сухогруз: трюм в краске, рубка на корме
	k = MeshKit.new()
	k.hull(70.0, 11.0, 1.6, 1.5, 8.0, 6)
	k.box(Vector3(-25.0, 1.6, -4.6), Vector3(22.0, 3.4, 4.6), 0)
	k.box(Vector3(-34.0, 1.6, -3.0), Vector3(-28.0, 5.8, 3.0), 5)
	k.box(Vector3(-34.0, 5.8, -3.0), Vector3(-28.0, 7.0, 3.0), 1)
	k.box(Vector3(-34.3, 7.0, -3.3), Vector3(-27.7, 7.3, 3.3), 5)
	out.append(k.commit())
	return out


## Узкофюзеляжный лайнер ~36 м, ось X — вперёд.
func _plane_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3(-15.0, -1.9, -1.9), Vector3(13.0, 1.9, 1.9), 5)
	# нос и хвостовой конус
	var c := Vector3(10.0, 0.0, 0.0)
	var r := [Vector3(13.0, -1.9, -1.9), Vector3(13.0, -1.9, 1.9), Vector3(13.0, 1.9, 1.9), Vector3(13.0, 1.9, -1.9)]
	var nose := Vector3(18.0, -0.6, 0.0)
	for i in range(4):
		k.tri(r[i], r[(i + 1) % 4], nose, 5, c)
	c = Vector3(-17.0, 0.0, 0.0)
	r = [Vector3(-15.0, -1.9, -1.9), Vector3(-15.0, -1.9, 1.9), Vector3(-15.0, 1.9, 1.9), Vector3(-15.0, 1.9, -1.9)]
	var tail := Vector3(-21.0, 1.2, 0.0)
	for i in range(4):
		k.tri(r[i], r[(i + 1) % 4], tail, 5, c)
	# окна кабины
	k.box(Vector3(14.2, 0.3, -1.3), Vector3(15.4, 1.0, 1.3), 1)
	# крылья, стабилизатор, киль
	for s in [-1.0, 1.0]:
		k.prism([Vector3(4.0, -0.8, 1.6 * s), Vector3(-4.0, -0.8, 1.6 * s), Vector3(-10.0, -0.2, 17.0 * s), Vector3(-7.0, -0.2, 17.0 * s)], Vector3(0, 0.45, 0), 5)
		k.prism([Vector3(-14.0, 0.6, 1.2 * s), Vector3(-18.0, 0.6, 1.2 * s), Vector3(-20.5, 0.9, 6.5 * s), Vector3(-19.0, 0.9, 6.5 * s)], Vector3(0, 0.3, 0), 5)
		k.box(Vector3(-2.0, -2.6, 5.5 * s - 1.0), Vector3(2.5, -0.9, 5.5 * s + 1.0), 6)   # двигатели
	k.prism([Vector3(-13.0, 1.9, 0.0), Vector3(-19.5, 1.9, 0.0), Vector3(-21.5, 8.5, 0.0), Vector3(-18.5, 8.5, 0.0)], Vector3(0, 0, 0.5), 0)
	return k.commit()


func _heli_meshes() -> Array[ArrayMesh]:
	var k := MeshKit.new()
	k.box(Vector3(-2.5, 0.6, -1.2), Vector3(2.0, 2.8, 1.2), 0)
	k.box(Vector3(2.0, 0.9, -1.05), Vector3(3.4, 2.4, 1.05), 1)
	k.box(Vector3(-9.5, 1.8, -0.3), Vector3(-2.5, 2.3, 0.3), 0)
	k.prism([Vector3(-8.5, 2.3, 0.0), Vector3(-9.6, 2.3, 0.0), Vector3(-10.0, 4.0, 0.0), Vector3(-9.2, 4.0, 0.0)], Vector3(0, 0, 0.2), 0)
	k.box(Vector3(-0.6, 2.8, -0.3), Vector3(0.6, 3.2, 0.3), 6)
	for s in [-1.0, 1.0]:
		k.box(Vector3(-2.6, 0.0, 1.1 * s - 0.1), Vector3(2.4, 0.15, 1.1 * s + 0.1), 4)
	var body := k.commit()
	k = MeshKit.new()
	k.box(Vector3(-6.0, -0.05, -0.22), Vector3(6.0, 0.05, 0.22), 6)
	k.box(Vector3(-0.22, -0.05, -6.0), Vector3(0.22, 0.05, 6.0), 6)
	return [body, k.commit()]


func _mm(mesh: Mesh, count: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# инстансы двигаются в шейдере/каждый кадр — границы на весь пейзаж, чтобы не отсекались
	mi.custom_aabb = AABB(Vector3(-3000, -50, -3000), Vector3(6000, 1200, 6000))
	add_child(mi)
	return mm


# ---------------------------------------------------------------- машины

func _build_cars(roads: Array, cam: Vector3) -> void:
	var items: Array = []   # [Transform3D, Color]
	for r: Array in roads:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var width: float = r[2]
		var lanes: int = r[3]
		var y: float = r[4]
		var spd: float = r[5]
		var half_w := width * 0.5
		var lane_w := (half_w - 0.6) / lanes
		for side in [0, 1]:
			var s0 := a if side == 0 else b
			var s1 := b if side == 0 else a
			for lane in range(lanes):
				var off := 0.3 + (lane + 0.5) * lane_w
				# ближняя к осевой полоса — быстрее
				var v := _rng.randf_range(8.0, 14.0) * spd * (1.0 + 0.22 * (lanes - 1 - lane))
				_fill_lane(items, s0, s1, off, y, v, lanes > 1, cam)
	# перемешать: на слабых уровнях графики рисуется начало массива — машины убывают равномерно
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Array = items[i]
		items[i] = items[j]
		items[j] = tmp
	_car_total = items.size()
	_cars = _mm(_car_mesh(), _car_total, _car_mat)
	for i in range(_car_total):
		_cars.set_instance_transform(i, items[i][0])
		_cars.set_instance_custom_data(i, items[i][1])


## Полоса от s0 к s1 со смещением off вправо: машины с промежутками; вся полоса едет с одной скоростью — без наездов.
func _fill_lane(items: Array, s0: Vector2, s1: Vector2, off: float, y: float, v: float, avenue: bool, cam: Vector3) -> void:
	var d := s1 - s0
	var L := d.length()
	if L < 20.0:
		return
	d /= L
	var fwd := Vector3(d.x, 0.0, d.y)
	var right := Vector3(-d.y, 0.0, d.x)
	var basis := Basis(Vector3.UP, -atan2(d.y, d.x))
	var start := Vector3(s0.x, y, s0.y) + right * off
	var s := _rng.randf_range(0.0, 30.0)
	while s < L - 12.0:
		var r := _rng.randf()
		var sc := Vector3.ONE
		var len := 4.4
		if avenue and r < 0.05:
			sc = Vector3(2.6, 1.45, 1.3)   # автобус
			len = 11.5
		elif r < 0.17:
			sc = Vector3(1.15, 1.2, 1.05)   # фургон
			len = 5.1
		var seed := _rng.randf()
		items.append([Transform3D(basis * Basis.from_scale(sc), start), Color(L, v, s / L, seed)])
		# дальние улицы реже (там машины меньше пикселя)
		var dist := (start + fwd * s).distance_to(cam)
		s += len + _rng.randf_range(7.0, 34.0) * lerpf(1.0, 2.2, smoothstep(700.0, 1500.0, dist))


# ---------------------------------------------------------------- метро

func _build_trains() -> void:
	_train_mm = _mm(_train_mesh(), TRAIN_CARS * 2, _craft_mat)
	_trains = [
		{"dir": 1.0, "z": RAIL_Z + 2.1, "v": 21.0, "phase": 0.0, "paint": 0.37},
		{"dir": -1.0, "z": RAIL_Z - 2.1, "v": 19.0, "phase": 0.55, "paint": 0.61},
	]


func _update_trains(t: float) -> void:
	var span := RAIL_X.y - RAIL_X.x + TRAIN_CARS * (TRAIN_CAR_LEN + 1.0) + 200.0
	var i := 0
	for tr: Dictionary in _trains:
		var dir: float = tr.dir
		var u := fposmod(float(tr.phase) * span + float(tr.v) * t, span)
		var head := RAIL_X.x + u if dir > 0.0 else RAIL_X.y - u
		var basis := Basis.IDENTITY if dir > 0.0 else Basis(Vector3.UP, PI)
		for c in range(TRAIN_CARS):
			var x := head - dir * (TRAIN_CAR_LEN * 0.5 + c * (TRAIN_CAR_LEN + 1.0))
			var mask := 1.0 if c == 0 else (2.0 if c == TRAIN_CARS - 1 else 0.0)
			# за пределами эстакады вагон прячется (масштаб 0)
			var on := x > RAIL_X.x + 10.0 and x < RAIL_X.y - 10.0
			var b := basis if on else basis.scaled(Vector3.ZERO)
			_train_mm.set_instance_transform(i, Transform3D(b, Vector3(x, RAIL_Y + 0.25, tr.z)))
			_train_mm.set_instance_custom_data(i, Color(tr.paint, mask, 1.0, 1.0))
			i += 1


# ---------------------------------------------------------------- река

func _build_boats() -> void:
	var meshes := _boat_meshes()
	# [тип, z полосы, направление, скорость м/с, полудлина, сколько на петле]
	var lanes := [
		[0, 38.0, 1.0, 9.0, 4.5, 2], [0, 108.0, -1.0, 11.0, 4.5, 2],
		[1, 62.0, -1.0, 4.5, 16.0, 2], [1, 84.0, 1.0, 5.0, 16.0, 1],
		[2, 72.0, 1.0, 2.6, 35.0, 1], [2, 92.0, -1.0, 3.0, 35.0, 1],
	]
	var counts := [0, 0, 0]
	for l: Array in lanes:
		for k in range(int(l[5])):
			_boats.append({"type": l[0], "idx": counts[l[0]], "z": l[1] + _rng.randf_range(-2.0, 2.0), "dir": l[2],
				"v": l[3] * _rng.randf_range(0.85, 1.15), "phase": (k + _rng.randf_range(0.1, 0.6)) / float(l[5]), "half": l[4]})
			counts[l[0]] += 1
	for ti in range(3):
		_boat_mm.append(_mm(meshes[ti], counts[ti], _craft_mat))
	_wakes.resize(MAX_BOATS)


func _update_boats(t: float, night: float, di: int) -> int:
	var span := BOAT_X.y - BOAT_X.x
	for bi in range(_boats.size()):
		var bt: Dictionary = _boats[bi]
		var dir: float = bt.dir
		var u := fposmod(float(bt.phase) * span + float(bt.v) * t, span)
		var x := BOAT_X.x + u if dir > 0.0 else BOAT_X.y - u
		var z: float = bt.z
		var ty: int = bt.type
		var heave := sin(t * 1.3 + bi * 1.7) * (0.12 if ty == 0 else 0.05)
		var basis := Basis(Vector3.UP, 0.0 if dir > 0.0 else PI)
		basis = basis * Basis(Vector3.FORWARD, sin(t * 1.1 + bi) * (0.03 if ty == 0 else 0.008))
		basis = basis * Basis(Vector3.RIGHT, sin(t * 0.9 + bi * 2.3) * (0.025 if ty == 0 else 0.006))
		var pos := Vector3(x, 0.05 + heave, z)
		_boat_mm[ty].set_instance_transform(bt.idx, Transform3D(basis, pos))
		var paint: float = [0.62, 0.66, 0.55][ty] + bi * 0.013
		_boat_mm[ty].set_instance_custom_data(bt.idx, Color(paint, 3.0 if ty == 0 else 0.0, 1.0 if ty == 1 else 0.6, 1.0))
		_wakes[bi] = Vector4(x, z, dir * float(bt.v), float(bt.half))
		# огни: белый на мачте/рубке
		var top := pos + basis * Vector3(-float(bt.half) * (0.85 if ty == 2 else 0.2), [2.4, 6.3, 7.8][ty], 0.0)
		_dot(di, top, Color(1.0, 0.92, 0.8) * (0.4 + night), 0.5, 0.0)
		di += 1
	return di


# ---------------------------------------------------------------- самолёт, вертолёт

const PLANE_PERIOD := 70.0
const PLANE_A := Vector3(2300.0, 420.0, -1000.0)
const PLANE_B := Vector3(-2100.0, 330.0, -380.0)


func _build_air() -> void:
	_plane_mm = _mm(_plane_mesh(), 1, _craft_mat)
	var hm := _heli_meshes()
	_heli_mm = _mm(hm[0], 1, _craft_mat)
	_rotor_mm = _mm(hm[1], 1, _craft_mat)
	_plane_mm.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 0.0))
	_heli_mm.set_instance_custom_data(0, Color(0.52, 0.0, 0.0, 1.0))
	_rotor_mm.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 0.0))
	_dots = MultiMesh.new()
	_dots.transform_format = MultiMesh.TRANSFORM_3D
	_dots.use_custom_data = true
	_dots.mesh = QuadMesh.new()
	_dots.instance_count = MAX_BOATS + 8
	for i in range(_dots.instance_count):
		_dots.set_instance_custom_data(i, Color(0, 0, 0, 3.0))
	_dot_mat = ShaderMaterial.new()
	_dot_mat.shader = load("res://scenes/menu/light_dot.gdshader")
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _dots
	mi.material_override = _dot_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-3000, -50, -3000), Vector3(6000, 1200, 6000))
	add_child(mi)


## Огонёк: size — радиус, м (не меньше ~2 пикселей); mode — см. light_dot.gdshader.
func _dot(i: int, p: Vector3, c: Color, size: float, mode: float) -> void:
	if i >= _dots.instance_count:
		return
	_dots.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), p))
	_dots.set_instance_custom_data(i, Color(c.r, c.g, c.b, mode))


func _update_air(t: float, di: int) -> int:
	# самолёт: справа налево с лёгким снижением, раз в PLANE_PERIOD с
	var k := fposmod(t + 20.0, PLANE_PERIOD) / PLANE_PERIOD
	var p := PLANE_A.lerp(PLANE_B, k)
	var fwd := (PLANE_B - PLANE_A).normalized()
	var pb := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.UP, PI * 0.5)   # ось X меша — вперёд
	pb = pb * Basis(Vector3.RIGHT, sin(t * 0.2) * 0.06)
	_plane_mm.set_instance_transform(0, Transform3D(pb, p))
	_dot(di, p + pb * Vector3(-8.5, 0.0, -17.2), Color(1.0, 0.1, 0.05), 0.8, 0.0)
	_dot(di + 1, p + pb * Vector3(-8.5, 0.0, 17.2), Color(0.1, 1.0, 0.25), 0.8, 0.0)
	_dot(di + 2, p + pb * Vector3(-21.0, 1.2, 0.0), Color(1.0, 1.0, 1.0), 0.9, 1.0)
	_dot(di + 3, p + pb * Vector3(0.0, -2.1, 0.0), Color(1.0, 0.15, 0.08), 0.8, 2.0)
	di += 4
	# вертолёт: кружит над центром с креном внутрь
	var ang := t * 0.085
	var hc := Vector3(MenuCity.DOWNTOWN.x, 0.0, MenuCity.DOWNTOWN.y)
	var hp := hc + Vector3(cos(ang) * 320.0, 210.0 + sin(t * 0.13) * 12.0, sin(ang) * 260.0)
	var tangent := Vector3(-sin(ang) * 320.0, 0.0, cos(ang) * 260.0).normalized()
	var hb := Basis.looking_at(tangent, Vector3.UP) * Basis(Vector3.UP, PI * 0.5)
	hb = hb * Basis(Vector3.RIGHT, 0.18) * Basis(Vector3.BACK, -0.08)
	_heli_mm.set_instance_transform(0, Transform3D(hb, hp))
	_rotor_mm.set_instance_transform(0, Transform3D(hb * Basis(Vector3.UP, t * 5.3), hp + hb * Vector3(0, 3.25, 0)))
	_dot(di, hp + hb * Vector3(-10.0, 4.1, 0.0), Color(1.0, 0.12, 0.05), 0.6, 2.0)
	_dot(di + 1, hp + hb * Vector3(0.0, 0.0, 0.0), Color(1.0, 1.0, 1.0), 0.6, 1.0)
	return di + 2
