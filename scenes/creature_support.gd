extends RefCounted
## Опора и двухзвенная кинематика ног/лап после скелетного клипа.
## Цели опорной фазы заданы вне движущегося корпуса; длины костей не растягиваются.
var actor
var skeleton: Skeleton3D
var limbs: Array[Dictionary] = []
var saved: Dictionary = {}
var hip := -1
var hip_offset := Vector3.ZERO
var stance_extra := 0.0
var last_parent := Vector3.ZERO
var travel_phase := 0.0
var last_ground_errors: Array[float] = []

func configure(owner: Node3D, model: Node3D) -> void:
	actor = owner
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			skeleton = n
			break
		for child in n.get_children(): stack.append(child)
	if skeleton == null: return
	hip = skeleton.find_bone("hips")
	var to_actor: Transform3D = actor.global_transform.affine_inverse() * skeleton.global_transform
	var families: Array = [["thigh.", "shin.", "foot.", false]]
	if actor._species in [&"klykar", &"rogozhuk"]:
		families.append(["arm.", "forearm.", "hand.", true])
	for family in families:
		for side in ["L", "R"]:
			var a := skeleton.find_bone(family[0] + side)
			var b := skeleton.find_bone(family[1] + side)
			var c := skeleton.find_bone(family[2] + side)
			if a < 0 or b < 0 or c < 0: continue
			var start := to_actor * skeleton.get_bone_global_rest(a).origin
			var mid := to_actor * skeleton.get_bone_global_rest(b).origin
			var end := to_actor * skeleton.get_bone_global_rest(c).origin
			var pole := mid - start.lerp(end, start.distance_to(mid) / maxf(start.distance_to(mid) + mid.distance_to(end), 0.001))
			if pole.length() < 0.001: pole = Vector3(0, 0, -1 if family[3] else 1)
			limbs.append({"a":a,"b":b,"c":c,"anchor":end,"pole":mid+pole.normalized()*actor.get_height()*0.3,"side":side,"front":family[3],"basis":(to_actor.basis*skeleton.get_bone_global_rest(c).basis).orthonormalized()})
	last_parent = _parent_transform().origin
	if not actor._flyer and not limbs.is_empty(): _collect_soles(model)

func restore() -> void:
	if skeleton == null: return
	for index in saved:
		skeleton.set_bone_pose(index, saved[index])
	saved.clear()

func reset() -> void:
	restore()
	hip_offset = Vector3.ZERO
	travel_phase = 0.0
	if actor != null and actor.is_inside_tree(): last_parent = _parent_transform().origin

func _save(index: int) -> void:
	if not saved.has(index): saved[index] = skeleton.get_bone_pose(index)

func apply(delta: float) -> void:
	if skeleton == null or limbs.is_empty() or actor._species == &"levian": return
	var h: float = actor.get_height()
	var action: StringName = actor._action if actor._elapsed >= actor._delay else &""
	var phase: float = clampf(actor._attack_progress(maxf(actor._elapsed-actor._delay,0)),0,1) if action == &"attack" else 0.0
	var parent: Transform3D = _parent_transform()
	var parent_velocity: Vector3 = (parent.origin-last_parent)/maxf(delta,0.001)
	last_parent = parent.origin
	var travel_speed := Vector2(parent_velocity.x,parent_velocity.z).length()
	travel_phase += travel_speed * delta / maxf(h*0.2,0.01) * 0.6
	var crouch := Vector3.ZERO
	if not actor._flyer:
		crouch.y = -h*0.03-stance_extra
		if action == &"attack":
			var load := sin(minf(phase/0.22,1.0)*PI*0.5) * (1.0-_ease((phase-0.4)/0.6))
			crouch.y -= h*0.035*load
			crouch.x = -h*0.012*sin(phase*TAU)*sin(phase*PI)
		elif action == &"hit":
			crouch.y -= h*0.035*sin(clampf((actor._elapsed-actor._delay)/actor._duration,0,1)*PI)
		else:
			crouch.x = h*0.006*sin(actor._clock*1.3)
	hip_offset = hip_offset.lerp(crouch,1.0-exp(-18.0*delta))
	if hip >= 0:
		_save(hip)
		var par := skeleton.get_bone_parent(hip)
		var basis := skeleton.global_transform.basis * (skeleton.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY)
		var world_offset: Vector3 = parent.basis * hip_offset
		skeleton.set_bone_pose_position(hip,skeleton.get_bone_pose_position(hip)+basis.inverse()*world_offset)
	last_ground_errors.clear()
	for limb in limbs:
		var offset := Vector3.ZERO
		var anchor: Vector3 = limb.anchor
		var airborne: bool = actor._flyer
		if airborne:
			# Лапы убраны в полёте и выносятся к цели при ударе.
			var reach := sin(phase*PI) if action == &"attack" else 0.0
			offset.y = h*(0.10-0.075*reach)
			offset.z = h*(-0.065+0.17*reach)
		elif action == &"attack":
			var distance: float = actor._distance
			if actor._species == &"klykar":
				var launch := _ease((phase-0.1)/0.25)
				var recover := _ease((phase-0.57)/0.43)
				var air := sin(clampf((phase-0.12)/0.54,0,1)*PI)
				offset.z = distance*launch*(1-recover)
				offset.y = h*(0.055 if limb.front else 0.075)*air
			elif actor._species == &"rogozhuk":
				var drive := _ease((phase-0.12)/0.21)*(1-_ease((phase-0.56)/0.44))
				offset.z = distance*drive
				offset.y = h*0.025*sin(clampf((phase-(0.1 if limb.front else 0.18))/0.28,0,1)*PI)
			else:
				var lead: bool = limb.side == "L"
				var step := _ease((phase-0.12)/0.21)
				var back := _ease((phase-0.58)/0.42)
				offset.z = distance*(0.92 if lead else 0.18)*step*(1-back)
				var swing := clampf((phase-0.12)/0.21,0,1)
				offset.y = h*(0.065 if lead else 0.018)*sin(swing*PI)
				offset.y += h*(0.045 if lead else 0.01)*sin(back*PI)
		var target: Vector3
		if airborne:
			target = actor.global_transform*(anchor+offset)
		else:
			target = parent*(actor._base+anchor+offset)
			if travel_speed > 0.01 and action != &"attack":
				var gait := fposmod(travel_phase+(0.5 if limb.side == "R" else 0.0)+(0.5 if limb.front else 0.0),1.0)
				var stride: float = h*0.2
				var forward: float = stride*(0.5-gait/0.6) if gait < 0.6 else stride*(-0.5+_ease((gait-0.6)/0.4))
				target += parent_velocity.normalized()*forward
				if gait >= 0.6: target.y += h*0.035*sin((gait-0.6)/0.4*PI)
		var pole: Vector3 = parent*(actor._base+limb.pole)
		_solve(limb,target,pole)
		# Опорная стопа сохраняет ориентацию относительно пола, а не наклоняется с туловищем.
		if not airborne:
			var desired: Basis = skeleton.global_basis.inverse()*parent.basis*limb.basis
			_set_global_rotation(limb.c,desired.orthonormalized())
			if limb.has("sole") and not limb.sole.is_empty():
				var floor_y: float = (parent*actor._base).y + offset.y
				# Исправляем опору по поверхности подошвы, а не по центру кости голеностопа.
				var ground_error := _sole_height(limb)-floor_y
				for iteration in range(4):
					if absf(ground_error) < h*0.001: break
					target.y -= clampf(ground_error,-h*0.06,h*0.06)*0.85
					_solve(limb,target,pole)
					_set_global_rotation(limb.c,desired.orthonormalized())
					ground_error = _sole_height(limb)-floor_y
				last_ground_errors.append(ground_error)

	# Варианты одного вида имеют разные пропорции. Короткая нога требует немного
	# более низкой стойки; дополнительная посадка калибруется по подошвам без растяжения костей.
	if not airborne_species() and action == &"" and not last_ground_errors.is_empty():
		var gap: float = maxf(0.0,last_ground_errors.max()-h*0.001)
		stance_extra = minf(h*0.035,stance_extra+gap*(1.0-exp(-20.0*delta)))

func airborne_species() -> bool:
	return actor._flyer or actor._species == &"levian"

static func _ease(value: float) -> float:
	var t := clampf(value,0,1)
	return t*t*(3-2*t)

func _set_global_rotation(index: int, basis: Basis) -> void:
	_save(index)
	var p := skeleton.get_bone_parent(index)
	var parent := skeleton.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index,(parent.inverse()*basis).orthonormalized().get_rotation_quaternion())

func _solve(limb: Dictionary, world_target: Vector3, world_pole: Vector3) -> void:
	var inv := skeleton.global_transform.affine_inverse()
	var target := inv*world_target
	var pole := inv*world_pole
	var a: Transform3D = skeleton.get_bone_global_pose(limb.a)
	var b: Transform3D = skeleton.get_bone_global_pose(limb.b)
	var c: Transform3D = skeleton.get_bone_global_pose(limb.c)
	var l1 := a.origin.distance_to(b.origin)
	var l2 := b.origin.distance_to(c.origin)
	if minf(l1,l2) < 0.00001: return
	var difference := target-a.origin
	var distance := clampf(difference.length(),absf(l1-l2)+0.0001,l1+l2-0.0001)
	var axis := difference.normalized()
	if axis.length_squared() < 0.5: return
	var bend := pole-a.origin
	bend -= axis*bend.dot(axis)
	if bend.length_squared() < 0.000001: bend = axis.cross(Vector3.RIGHT)
	if bend.length_squared() < 0.000001: bend = axis.cross(Vector3.FORWARD)
	bend = bend.normalized()
	var along := clampf((l1*l1+distance*distance-l2*l2)/(2*distance),-l1,l1)
	var knee := a.origin+axis*along+bend*sqrt(maxf(0,l1*l1-along*along))
	var rotation := Quaternion((b.origin-a.origin).normalized(),(knee-a.origin).normalized())
	_set_global_rotation(limb.a,Basis(rotation)*a.basis.orthonormalized())
	b = skeleton.get_bone_global_pose(limb.b)
	c = skeleton.get_bone_global_pose(limb.c)
	var end := a.origin+axis*distance
	rotation = Quaternion((c.origin-b.origin).normalized(),(end-b.origin).normalized())
	_set_global_rotation(limb.b,Basis(rotation)*b.basis.orthonormalized())


func _collect_soles(model: Node) -> void:
	var stack: Array[Node] = [model]
	var candidate_lists: Array = []
	for limb in limbs: candidate_lists.append([])
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if not node is MeshInstance3D: continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or mesh_node.skin == null: continue
		var skin := mesh_node.skin
		var mapping: Array[int] = []
		for bind in range(skin.get_bind_count()):
			var index := skin.get_bind_bone(bind)
			if index < 0: index = skeleton.find_bone(skin.get_bind_name(bind))
			mapping.append(index)
		var transform: Transform3D = actor.global_transform.affine_inverse()*mesh_node.global_transform
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or binds.is_empty(): continue
			var stride := weights.size()/vertices.size()
			for v in range(vertices.size()):
				var point: Vector3 = transform*vertices[v]
				if point.y > actor.get_height()*0.18: continue
				for l in range(limbs.size()):
					var influence := 0.0
					for k in range(stride):
						var slot := binds[v*stride+k]
						if slot < 0 or slot >= mapping.size(): continue
						var bone: int = mapping[slot]
						while bone >= 0:
							if bone == limbs[l].a:
								influence += weights[v*stride+k]
								break
							bone = skeleton.get_bone_parent(bone)
					if influence < 0.65: continue
					var bones: Array[int] = []
					var poses: Array[Transform3D] = []
					var factors: Array[float] = []
					for k in range(stride):
						var slot := binds[v*stride+k]
						if weights[v*stride+k] <= 0 or slot < 0 or slot >= mapping.size() or mapping[slot] < 0: continue
						bones.append(mapping[slot]);poses.append(skin.get_bind_pose(slot));factors.append(weights[v*stride+k])
					candidate_lists[l].append({"point":vertices[v],"rest":point,"bones":bones,"poses":poses,"weights":factors,"mesh":mesh_node})
	for l in range(limbs.size()):
		var candidates: Array = candidate_lists[l]
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.rest.y < b.rest.y)
		var samples: Array = []
		var cells: Dictionary = {}
		for point in candidates:
			var cell := Vector2i(roundi(point.rest.x/(actor.get_height()*0.012)),roundi(point.rest.z/(actor.get_height()*0.012)))
			if cells.has(cell): continue
			cells[cell] = true
			samples.append(point)
			if samples.size() >= 12: break
		limbs[l]["sole"] = samples
		if not samples.is_empty():
			limbs[l]["anchor"].y -= samples[0].rest.y


func _sole_height(limb: Dictionary) -> float:
	var lowest := INF
	var matrices: Dictionary = {}
	for sample in limb.sole:
		var point := Vector3.ZERO
		for k in range(sample.bones.size()):
			var bone: int = sample.bones[k]
			if not matrices.has(bone): matrices[bone] = skeleton.get_bone_global_pose(bone)
			point += ((matrices[bone] as Transform3D)*sample.poses[k]*sample.point)*sample.weights[k]
		var world: Vector3 = sample.mesh.global_transform*point
		lowest = minf(lowest,world.y)
	return lowest


func _parent_transform() -> Transform3D:
	var parent := actor.get_parent() as Node3D
	return parent.global_transform if parent != null else Transform3D.IDENTITY
