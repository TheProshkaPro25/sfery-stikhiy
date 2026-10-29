extends RefCounted
## Ликорез: шесть отдельных вооружённых рук, сросшаяся корона лиц и собственные клипы.
## Лицом к +Z. AnimationPlayer управляется вручную существующим CreatureAnim.

static func build() -> Node3D:
	var model := Node3D.new()
	model.name = "Likorez"
	var skin := _mat(Color("514664"))
	var dark := _mat(Color("201e30"))
	var bone := _mat(Color("cec4ba"))
	var blade := _mat(Color("77778c"))
	var edge := _mat(Color("c9c4d8"))
	var eye := _mat(Color("b65883"))
	var body := _node(model, "Body", Vector3(0, 0.91, 0))
	_ellipsoid(body, "Pelvis", Vector3(0, 0.02, 0), Vector3(0.27, 0.19, 0.19), dark)
	_ellipsoid(body, "Waist", Vector3(0, 0.23, 0), Vector3(0.16, 0.46, 0.14), skin)
	_ellipsoid(body, "Ribcage", Vector3(0, 0.56, 0), Vector3(0.39, 0.49, 0.23), skin)
	_segment(body, "Spine", Vector3(0, 0.14, -0.09), Vector3(0, 0.82, -0.08), 0.033, bone)
	for i in range(5):
		var y := 0.43 + i * 0.065
		for side in [-1.0, 1.0]:
			_segment(body, "Rib%d_%d" % [i, int(side)], Vector3(side * 0.035, y - 0.025, 0.115), Vector3(side * (0.14 + i * 0.006), y + 0.024, 0.07), 0.013, bone)
	_segment(body, "Neck", Vector3(0, 0.75, 0), Vector3(0, 1.0, 0), 0.055, skin)
	# Пять масок срастаются в один череп, а не висят на отдельных шеях.
	var head := _node(body, "Head", Vector3(0, 1.0, 0))
	_ellipsoid(head, "SharedSkull", Vector3(0, 0.08, -0.015), Vector3(0.40, 0.43, 0.31), dark)
	_face(head, "CentralFace", Vector3(0, 0.035, 0.085), 0.0, 1.0, bone, dark, eye)
	_face(head, "LeftFace", Vector3(-0.155, 0.045, 0.005), -0.88, 0.79, bone, dark, eye)
	_face(head, "RightFace", Vector3(0.155, 0.045, 0.005), 0.88, 0.79, bone, dark, eye)
	_face(head, "CrownFace", Vector3(0, 0.235, 0.11), 0.0, 0.62, bone, dark, eye)
	_face(head, "BackFace", Vector3(0, 0.08, -0.15), PI, 0.75, bone, dark, eye)
	for side in [-1.0, 1.0]:
		_segment(head, "CrownSpike", Vector3(side * 0.12, 0.22, -0.07), Vector3(side * 0.20, 0.48, -0.12), 0.035, dark, 0.0)
	# Три ряда плеч и локти на каждой стороне. Любой клинок принадлежит своей кисти.
	for row in range(3):
		for side in [-1.0, 1.0]:
			var suffix := "%d_%s" % [row, "L" if side < 0 else "R"]
			var arm := _node(body, "Arm" + suffix, Vector3(side * 0.19, 0.72 - row * 0.16, -row * 0.035))
			_ellipsoid(arm, "Shoulder", Vector3.ZERO, Vector3(0.13, 0.12, 0.13), bone)
			_segment(arm, "UpperArm", Vector3.ZERO, Vector3(0, -0.32, 0), 0.036, skin, 0.024)
			var elbow := _node(arm, "Elbow", Vector3(0, -0.32, 0))
			_ellipsoid(elbow, "Joint", Vector3.ZERO, Vector3(0.075, 0.075, 0.075), bone)
			_segment(elbow, "Forearm", Vector3.ZERO, Vector3(0, -0.32, 0), 0.03, skin, 0.022)
			var hand := _node(elbow, "Hand", Vector3(0, -0.34, 0))
			_ellipsoid(hand, "Grip", Vector3.ZERO, Vector3(0.065, 0.10, 0.072), bone)
			for f in range(3):
				_segment(hand, "Finger%d" % f, Vector3(-0.025 + f * 0.025, -0.015, 0.027), Vector3(-0.025 + f * 0.025, -0.075, 0.04), 0.008, skin)
			_sword(hand, row, blade, edge, dark)
		var hip := _node(body, "Leg" + ("L" if row == 0 else "R"), Vector3(-0.12 if row == 0 else 0.12, -0.02, 0)) if row < 2 else null
		if hip != null:
			_segment(hip, "Thigh", Vector3.ZERO, Vector3(0, -0.44, 0), 0.042, skin, 0.027)
			var knee := _node(hip, "Knee", Vector3(0, -0.44, 0))
			_ellipsoid(knee, "Kneecap", Vector3(0, 0, 0.013), Vector3(0.08, 0.09, 0.09), bone)
			_segment(knee, "Shin", Vector3.ZERO, Vector3(0, -0.44, 0), 0.028, skin, 0.018)
			var foot := _node(knee, "Foot", Vector3(0, -0.44, 0))
			_ellipsoid(foot, "FootMesh", Vector3(0, 0, 0.045), Vector3(0.10, 0.075, 0.23), dark)
	# Несколько узких оборванных полотнищ сохраняют костлявый силуэт ног.
	for i in range(5):
		var angle := i * TAU / 5.0
		var strip := _node(body, "Tatter%d" % i, Vector3(sin(angle) * 0.12, -0.015, cos(angle) * 0.09))
		strip.rotation = Vector3(cos(angle) * 0.19, angle, -sin(angle) * 0.16)
		_segment(strip, "Cloth", Vector3.ZERO, Vector3(0, -0.34 - (i % 2) * 0.1, 0), 0.055, dark, 0.001)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	model.add_child(player)
	var library := AnimationLibrary.new()
	for clip in ["idle", "attack", "hit", "roar", "stance"]:
		library.add_animation(clip, _animation(clip))
	player.add_animation_library("", library)
	# И вне дерева модель уже имеет выразительную исходную позу и корректный AABB.
	var initial := _pose("idle", 0.0)
	for path in initial:
		var pair: Array = String(path).split(":")
		model.get_node(pair[0]).set(pair[1], initial[path])
	return model

static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return m

static func _node(parent: Node, label: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = label
	n.position = pos
	parent.add_child(n)
	return n

static func _ellipsoid(parent: Node, label: String, pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 8
	mesh.radius = 0.5
	mesh.height = 1.0
	var n := MeshInstance3D.new()
	n.name = label
	n.mesh = mesh
	n.material_override = material
	n.position = pos
	n.scale = size
	parent.add_child(n)

static func _segment(parent: Node, label: String, a: Vector3, b: Vector3, radius: float, material: Material, tip: float = -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius if tip < 0.0 else tip
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var n := MeshInstance3D.new()
	n.name = label
	n.mesh = mesh
	n.material_override = material
	n.position = (a + b) * 0.5
	n.quaternion = Quaternion(Vector3.UP, (a - b).normalized())
	parent.add_child(n)

static func _face(parent: Node, label: String, pos: Vector3, yaw: float, factor: float, bone: Material, dark: Material, eye: Material) -> void:
	var mask := _node(parent, label, pos)
	mask.rotation.y = yaw
	mask.scale = Vector3.ONE * factor
	_ellipsoid(mask, "Mask", Vector3.ZERO, Vector3(0.205, 0.30, 0.125), bone)
	for side in [-1.0, 1.0]:
		_ellipsoid(mask, "Socket", Vector3(side * 0.047, 0.025, 0.058), Vector3(0.067, 0.048, 0.025), dark)
		_ellipsoid(mask, "Eye", Vector3(side * 0.047, 0.027, 0.074), Vector3(0.032, 0.012, 0.012), eye)
		_segment(mask, "Brow", Vector3(side * 0.018, 0.065, 0.055), Vector3(side * 0.09, 0.085, 0.025), 0.011, dark)
	_ellipsoid(mask, "Scream", Vector3(0, -0.075, 0.054), Vector3(0.060, 0.091, 0.028), dark)
	_segment(mask, "Nose", Vector3(0, 0.01, 0.066), Vector3(0, -0.032, 0.08), 0.016, bone, 0.004)
	for tooth in range(3):
		_segment(mask, "Tooth", Vector3(-0.018 + tooth * 0.018, -0.043, 0.071), Vector3(-0.018 + tooth * 0.018, -0.063, 0.073), 0.005, bone, 0.0)

static func _sword(hand: Node3D, row: int, metal: Material, edge: Material, dark: Material) -> void:
	_segment(hand, "Hilt", Vector3(0, 0.06, 0), Vector3(0, -0.10, 0), 0.022, dark)
	_segment(hand, "Guard", Vector3(-0.10, -0.09, 0), Vector3(0.10, -0.09, 0), 0.016, metal)
	var length := 0.44 if row == 2 else 0.56
	# Двугранный клинок с остриём: реальная геометрия, без плоской текстуры.
	var vertices := [Vector3(-0.042, -0.11, 0), Vector3(0.042, -0.11, 0), Vector3(0, -0.11, 0.022), Vector3(0, -0.11, -0.022), Vector3(0, -0.11-length, 0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [0, 3, 2], [2, 3, 1]]:
		for index in tri: st.add_vertex(vertices[index])
	st.generate_normals()
	var n := MeshInstance3D.new()
	n.name = "Blade"
	n.mesh = st.commit()
	n.material_override = metal
	hand.add_child(n)
	_segment(hand, "CuttingEdge", vertices[0], vertices[4], 0.004, edge, 0.001)

static func _animation(clip: String) -> Animation:
	var animation := Animation.new()
	animation.length = 1.6 if clip == "idle" else 1.2
	animation.loop_mode = Animation.LOOP_LINEAR if clip == "idle" else Animation.LOOP_NONE
	var tracks := {}
	for frame in range(49):
		var t := frame / 48.0
		var pose := _pose(clip, t)
		for path in pose:
			if not tracks.has(path):
				var index := animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(index, NodePath(path))
				animation.track_set_interpolation_type(index, Animation.INTERPOLATION_LINEAR)
				tracks[path] = index
			animation.track_insert_key(tracks[path], t * animation.length, pose[path])
	return animation

static func _pose(clip: String, t: float) -> Dictionary:
	var pose := {}
	var cycle := t * TAU
	var attack := clip == "attack"
	var roar := clip == "roar" or clip == "stance"
	var hit := clip == "hit"
	# Резкая смена опорной ноги, короткий подскок и затухание, без случайного дрожания.
	var sway := sin(cycle) * 0.022 if clip == "idle" else 0.0
	var lift := pow(absf(sin(cycle)), 6.0) * 0.026 if clip == "idle" else 0.0
	var envelope := sin(t * PI)
	var strike := 0.0
	if attack:
		# Контакт CreatureAnim приходится ровно на треть клипа.
		strike = smoothstep(0.18, 1.0 / 3.0, t) * (1.0 - smoothstep(0.53, 0.94, t))
		lift = sin(clampf((t - 0.12) / 0.38, 0, 1) * PI) * 0.035
		sway = sin(t * TAU) * 0.028
	var body_pos := Vector3(sway, 0.91 + lift - (0.035 * envelope if hit else 0.0), 0)
	pose["Body:position"] = body_pos
	pose["Body:rotation"] = Vector3((-0.10 if roar else 0.08 if hit else 0.0) * envelope, -0.16 * strike, -sway * 0.8)
	pose["Body/Head:rotation"] = Vector3(-0.22 * envelope if roar else 0.05 * sin(cycle), 0.14 * sin(cycle) if clip == "idle" else 0.13 * envelope, 0.03 * sin(cycle * 2.0))
	for row in range(3):
		for side in [-1.0, 1.0]:
			var path := "Body/Arm%d_%s" % [row, "L" if side < 0 else "R"]
			var fan: float = [2.18, 1.37, 0.55][row]
			var twitch := sin(cycle + row * 0.8 + side * 0.4) * 0.065
			var windup := sin(clampf(t * 3.0, 0, 1) * PI) if attack else 0.0
			pose[path + ":rotation"] = Vector3(-0.12 + row * 0.15 + twitch - strike * (1.15 + row * 0.22) + windup * 0.65, side * (0.12 + strike * 0.30), side * (fan + twitch + (0.28 * envelope if roar else 0.0) - strike * 0.25))
			pose[path + "/Elbow:rotation"] = Vector3(0.15 + strike * 0.3, 0, side * (-0.62 + row * 0.10 + twitch - windup * 0.35))
			pose[path + "/Elbow/Hand:rotation"] = Vector3(0.12 * sin(cycle + row), 0.08 * side, side * (0.20 + row * 0.12 - strike * 0.35))
	for side in [-1.0, 1.0]:
		var leg := "Body/Leg" + ("L" if side < 0 else "R")
		var foot_lift := pow(maxf(0.0, sin(cycle) * side), 4.0) * 0.07 if clip == "idle" else 0.0
		if attack: foot_lift = sin(clampf(t / 0.33, 0, 1) * PI) * (0.09 if side < 0 else 0.025)
		var target := Vector3(side * 0.12, 0.05 + foot_lift, strike * (0.10 if side < 0 else -0.035))
		var body_basis := Basis.from_euler(pose["Body:rotation"])
		var hip := body_pos + body_basis * Vector3(side * 0.12, -0.02, 0)
		var delta := body_basis.inverse() * (target - hip)
		var distance := clampf(delta.length(), 0.1, 0.879)
		var along := delta.normalized()
		var pole := Vector3.FORWARD - along * Vector3.FORWARD.dot(along)
		# Колени направлены вперёд (+Z).
		pole = -pole.normalized()
		var knee_vector := along * distance * 0.5 + pole * sqrt(maxf(0, 0.44 * 0.44 - distance * distance * 0.25))
		var thigh_rotation := Quaternion(Vector3.DOWN, knee_vector.normalized())
		var shin_rotation := Quaternion(Vector3.DOWN, (delta - knee_vector).normalized())
		pose[leg + ":quaternion"] = thigh_rotation
		pose[leg + "/Knee:quaternion"] = thigh_rotation.inverse() * shin_rotation
		pose[leg + "/Knee/Foot:quaternion"] = shin_rotation.inverse() * body_basis.get_rotation_quaternion().inverse()
	return pose
