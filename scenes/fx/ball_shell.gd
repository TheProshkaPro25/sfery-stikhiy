class_name BallShell
extends RefCounted
## Геометрия и материалы оболочки сферы существа (общие на все шары, строятся один раз).
## Сфера единичного радиуса: 2 полусферы, в каждой 4 пластины-лепестка и полярная крышка с эмблемой,
## между полусферами — экваторный пояс с кольцом цвета владельца. Между пластинами — щели (швы), под ними
## светящаяся сердцевина. Закрытый шар рисуется одним мешем (closed_mesh), для раскрытия/сворачивания —
## отдельные части (parts) с шарнирами: лепесток поворачивается вокруг своей нижней кромки.
## Вершинные атрибуты для ball_shell.gdshader: UV — дуга (рад) до ближайшего края пластины по долготе/широте,
## UV2.x — вид части (0 лепесток, 1 крышка, 2 пояс).

const SHELL_SHADER: Shader = preload("res://scenes/shaders/ball_shell.gdshader")
const CORE_SHADER: Shader = preload("res://scenes/shaders/ball_core.gdshader")

const GAP := 0.032            ## ширина шва (рад)
const BELT := 0.045           ## полуширина экваторного пояса (рад)
const CAP_LAT := deg_to_rad(62.0)  ## нижняя кромка полярной крышки
const NO_EDGE := 9.0          ## «края нет» в UV

enum Kind { PETAL, CAP, BELT }

static var _closed: ArrayMesh
static var _core: SphereMesh
static var _shell_mat: ShaderMaterial
static var _core_mat: ShaderMaterial
## Части для анимации: {mesh, kind, top, hinge: Vector3, axis: Vector3, sign: float}
static var _parts: Array = []


static func shell_material() -> ShaderMaterial:
	if _shell_mat == null:
		_shell_mat = ShaderMaterial.new()
		_shell_mat.shader = SHELL_SHADER
	return _shell_mat


static func core_material() -> ShaderMaterial:
	if _core_mat == null:
		_core_mat = ShaderMaterial.new()
		_core_mat.shader = CORE_SHADER
	return _core_mat


static func core_mesh() -> SphereMesh:
	if _core == null:
		_core = SphereMesh.new()
		_core.radius = 0.95
		_core.height = 1.9
		_core.radial_segments = 20
		_core.rings = 10
	return _core


static func closed_mesh() -> ArrayMesh:
	_build()
	return _closed


static func parts() -> Array:
	_build()
	return _parts


static func _sph(lon: float, lat: float) -> Vector3:
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))


## Участок сферы lat0..lat1 × lon0..lon1 (обход по часовой снаружи — лицевая сторона в Godot).
## edge_lon/edge_lo/edge_hi — есть ли у пластины край по долготе / снизу / сверху (для окантовки).
static func _patch(st: SurfaceTool, lat0: float, lat1: float, lon0: float, lon1: float, nlat: int, nlon: int,
		kind: int, edge_lon: bool, edge_lo: bool, edge_hi: bool, r: float = 1.0) -> void:
	var grid: Array = []
	for j in nlat + 1:
		var lat := lerpf(lat0, lat1, float(j) / nlat)
		var row: Array = []
		for i in nlon + 1:
			var lon := lerpf(lon0, lon1, float(i) / nlon)
			var p := _sph(lon, lat)
			var du := minf(lon - lon0, lon1 - lon) * cos(lat) if edge_lon else NO_EDGE
			var dv := NO_EDGE
			if edge_lo:
				dv = minf(dv, lat - lat0)
			if edge_hi:
				dv = minf(dv, lat1 - lat)
			row.append([p, Vector2(du, dv)])
		grid.append(row)
	for j in nlat:
		for i in nlon:
			var a: Array = grid[j][i]
			var b: Array = grid[j][i + 1]
			var c: Array = grid[j + 1][i + 1]
			var d: Array = grid[j + 1][i]
			for v in [a, b, c, a, c, d]:
				var p: Vector3 = v[0]
				st.set_normal(p)
				st.set_uv(v[1])
				st.set_uv2(Vector2(kind, 0.0))
				st.add_vertex(p * r)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _build() -> void:
	if _closed != null:
		return
	var all := _begin()
	_parts.clear()
	var g := GAP * 0.5
	for top in [true, false]:
		var sgn := 1.0 if top else -1.0
		var lon_off := 0.0 if top else PI * 0.25
		# лепестки: от пояса до крышки
		var lo := BELT + g
		var hi := CAP_LAT - g
		for k in 4:
			var l0 := lon_off + k * PI * 0.5 + g
			var l1 := lon_off + (k + 1) * PI * 0.5 - g
			var la0 := lo if top else -hi
			var la1 := hi if top else -lo
			var st := _begin()
			for s in [st, all]:
				_patch(s, la0, la1, l0, l1, 8, 8, Kind.PETAL, true, true, true)
			var mid := (l0 + l1) * 0.5
			var hinge := _sph(mid, lo * sgn)
			var axis := Vector3(-sin(mid), 0.0, cos(mid))
			# знак поворота: центр лепестка должен уходить от оси шара (раскрытие наружу)
			var centre := _sph(mid, (lo + hi) * 0.5 * sgn)
			var rot := Basis(axis, 0.3)
			var moved := rot * (centre - hinge) + hinge
			var sign := 1.0 if Vector2(moved.x, moved.z).length() > Vector2(centre.x, centre.z).length() else -1.0
			_parts.append({"mesh": st.commit(), "kind": Kind.PETAL, "top": top, "hinge": hinge, "axis": axis, "sign": sign})
		# полярная крышка с эмблемой
		var stc := _begin()
		for s in [stc, all]:
			if top:
				_patch(s, CAP_LAT + g, PI * 0.5, 0.0, TAU, 4, 24, Kind.CAP, false, true, false)
			else:
				_patch(s, -PI * 0.5, -CAP_LAT - g, 0.0, TAU, 4, 24, Kind.CAP, false, false, true)
		_parts.append({"mesh": stc.commit(), "kind": Kind.CAP, "top": top, "hinge": Vector3(0, sgn, 0), "axis": Vector3.UP, "sign": 1.0})
	# экваторный пояс (чуть выступает)
	var stb := _begin()
	for s in [stb, all]:
		_patch(s, -BELT + g * 0.3, BELT - g * 0.3, 0.0, TAU, 1, 40, Kind.BELT, false, false, false, 1.012)
	_parts.append({"mesh": stb.commit(), "kind": Kind.BELT, "top": true, "hinge": Vector3.ZERO, "axis": Vector3.UP, "sign": 1.0})
	_closed = all.commit()


## Поза части при раскрытии t (0 — закрыта, 1 — раскрыта): лепестки откидываются наружу вокруг кромки,
## верхняя крышка поднимается и вращается, пояс расширяется.
static func part_transform(part: Dictionary, t: float) -> Transform3D:
	var kind: int = part["kind"]
	var top: bool = part["top"]
	match kind:
		Kind.PETAL:
			var ang: float = float(part["sign"]) * t * (2.1 if top else 1.25)
			var b := Basis(part["axis"], ang)
			var h: Vector3 = part["hinge"]
			# в начале — небольшой «разжим» (пластины отходят от сердцевины)
			var push := h * 0.06 * clampf(t * 4.0, 0.0, 1.0)
			return Transform3D(b, h - b * h + push)
		Kind.CAP:
			if top:
				return Transform3D(Basis(Vector3.UP, t * 2.4), Vector3(0, t * 1.1, 0))
			return Transform3D(Basis(), Vector3(0, -t * 0.15, 0))
	var s := 1.0 + t * 0.35
	return Transform3D(Basis().scaled(Vector3(s, 1.0, s)), Vector3.ZERO)
