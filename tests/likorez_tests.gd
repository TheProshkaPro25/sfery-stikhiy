extends SceneTree
## Процедурная геометрия, все конечности и контракт CreatureAnim при 30/60/120 FPS.
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	CardDB.load_all()
	var d := CardDB.creature(&"creature_likorez_shadow")
	check(d != null, "Ликорез зарегистрирован")
	if d == null:
		quit(1)
		return
	CreatureModels.preload_match([d])
	var model := CreatureModels.build(d)
	check(model != null and model.get_meta("height", 0) > 0, "Процедурная модель имеет размеры")
	var actor := CreatureAnim.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_model(model, d)
	var creature := model.find_child("Likorez", true, false) as Node3D
	var player := creature.get_node("AnimationPlayer") as AnimationPlayer
	for clip in ["idle", "attack", "hit", "roar", "stance"]:
		check(player.has_animation(clip), "Клип " + clip)
	for face in ["CentralFace", "LeftFace", "RightFace", "CrownFace", "BackFace"]:
		check(creature.has_node("Body/Head/" + face + "/Scream"), "Лицо на едином черепе: " + face)
	var eye := creature.get_node("Body/Head/CentralFace/Eye") as MeshInstance3D
	check(not (eye.material_override as StandardMaterial3D).emission_enabled, "Глаза матовые, без свечения")
	var limb_paths: Array[String] = []
	for row in range(3):
		for side in ["L", "R"]:
			var path := "Body/Arm%d_%s" % [row, side]
			limb_paths.append(path)
			check(creature.has_node(path + "/Elbow/Hand/Blade"), "Отдельный клинок: " + path)
	for side in ["L", "R"]:
		limb_paths.append("Body/Leg" + side)
		limb_paths.append("Body/Leg" + side + "/Knee")
	for clip in ["idle", "attack"]:
		player.play(clip, 0)
		player.advance(0)
		var start := {}
		var motion := {}
		for path in limb_paths:
			start[path] = creature.get_node(path).quaternion
			motion[path] = 0.0
		var floor_min := INF
		var floor_max := -INF
		for sample in range(97):
			player.seek(sample / 96.0 * player.get_animation(clip).length, true)
			for path in limb_paths:
				motion[path] = maxf(motion[path], (start[path] as Quaternion).angle_to(creature.get_node(path).quaternion))
			var bounds := CreatureModels.world_aabb(model)
			floor_min = minf(floor_min, bounds.position.y)
			floor_max = maxf(floor_max, bounds.position.y)
		for path in limb_paths:
			check(motion[path] > 0.015, "%s двигает %s" % [clip, path])
		check(floor_min > -actor.get_height() * 0.012, "%s не проваливается: %.4f" % [clip, floor_min])
		check(floor_max - floor_min < actor.get_height() * 0.04, "%s сохраняет опору: %.4f" % [clip, floor_max - floor_min])
		print("FLOOR ", clip, " ", floor_min, " .. ", floor_max)
	var contacts: Array[Vector3] = []
	actor.strike_contact.connect(func() -> void: contacts.append(actor.fx_pos))
	for fps in [30, 60, 120]:
		actor.reset()
		var before := contacts.size()
		actor.lunge(actor.get_height() * 0.2)
		var minimum := INF
		for frame in range(fps * 3):
			actor._process(1.0 / float(fps))
			minimum = minf(minimum, CreatureModels.world_aabb(model).position.y)
		check(minimum > -actor.get_height() * 0.02, "Опора полного CreatureAnim при %d FPS: %.4f" % [fps, minimum])
		check(contacts.size() == before + 1, "Один контакт при %d FPS" % fps)
		check(actor._action == &"" and actor.fx_pos.is_equal_approx(Vector3.ZERO), "Возврат в idle при %d FPS" % fps)
	check(contacts.size() == 3 and contacts[0].distance_to(contacts[2]) < 0.001, "Контакт не зависит от FPS")
	actor.free()
	CreatureModels.clear()
	print("Ликорез: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)
