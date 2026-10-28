class_name BallTrail
extends MeshInstance3D
## Светящаяся лента следа за летящей сферой: точки пути за последние LIFE секунд, лента повёрнута к камере,
## сужается и гаснет к хвосту. Меш (ImmediateMesh) пересобирается каждый кадр только пока след виден.

const RIBBON_SHADER: Shader = preload("res://scenes/shaders/fx_ribbon.gdshader")
const LIFE := 0.32
const MAX_PTS := 28

static var _mat: ShaderMaterial

var target: Node3D
var color := Color.WHITE
var width := 0.6
var emitting := false:
	set(v):
		emitting = v
		if v:
			set_process(true)
var _pts: Array = []   # [Vector3, время]
var _im: ImmediateMesh
var _t := 0.0


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = RIBBON_SHADER
	material_override = _mat


func clear() -> void:
	_pts.clear()
	_im.clear_surfaces()


func _process(delta: float) -> void:
	_t += delta
	if emitting and target != null and is_instance_valid(target):
		var p := target.global_position
		if _pts.is_empty() or (_pts[-1][0] as Vector3).distance_to(p) > width * 0.15:
			_pts.append([p, _t])
			if _pts.size() > MAX_PTS:
				_pts.pop_front()
		else:
			_pts[-1][0] = p
	while not _pts.is_empty() and _t - float(_pts[0][1]) > LIFE:
		_pts.pop_front()
	_im.clear_surfaces()
	if _pts.size() < 2:
		if not emitting:
			_pts.clear()
			set_process(false)  # след догорел — не тратить кадры
		return
	global_transform = Transform3D.IDENTITY
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var n := _pts.size()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	# от головы (u=0) к хвосту (u=1)
	for k in n:
		var i := n - 1 - k
		var p: Vector3 = _pts[i][0]
		var q: Vector3 = _pts[maxi(i - 1, 0)][0] if i > 0 else p
		var nx: Vector3 = _pts[mini(i + 1, n - 1)][0]
		var tan := (nx - q)
		if tan.length() < 0.0001:
			tan = Vector3.FORWARD
		var to_cam := (cp - p).normalized()
		var side := tan.cross(to_cam).normalized()
		# лента, видимая с торца (камера погони смотрит вдоль полёта), гаснет — иначе белое пятно
		var edge_on := smoothstep(0.2, 0.6, tan.normalized().cross(to_cam).length())
		var u := float(k) / float(n - 1)
		var age := clampf((_t - float(_pts[i][1])) / LIFE, 0.0, 1.0)
		var w := width * (1.0 - u * 0.75)
		var c := Color(color.r, color.g, color.b, (1.0 - age) * edge_on)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(u, 0.0))
		_im.surface_add_vertex(p + side * w * 0.5)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(u, 1.0))
		_im.surface_add_vertex(p - side * w * 0.5)
	_im.surface_end()
