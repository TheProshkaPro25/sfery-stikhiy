extends SceneTree
## Проверки контакта, прерываний, возврата в стойку и независимости от частоты кадров.
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	CardDB.load_all()
	# Каждый игровой вариант проходит полный цикл, включая общий ресурс светлого Колоссара.
	for definition in CardDB.all_creatures():
		var actor := CreatureAnim.new()
		root.add_child(actor)
		actor.set_process(false)
		actor.set_model(CreatureModels.build(definition), definition)
		actor.idle_on = true
		var count := [0]
		var points: Array[Vector3] = []
		actor.strike_contact.connect(func() -> void:
			count[0] += 1
			points.append(actor.fx_pos))
		for fps in [30, 60, 120]:
			actor.reset()
			actor.lunge(actor.get_height())
			for frame in range(fps * 2):
				actor._process(1.0 / float(fps))
			check(actor.fx_pos.is_equal_approx(Vector3.ZERO) and actor._action == &"", "%s: возврат после атаки при %d fps" % [definition.id, fps])
		check(count[0] == 3, "%s: один контакт на атаку" % definition.id)
		if points.size() == 3:
			check(points[0].distance_to(points[2]) < 0.001, "%s: одинаковая поза контакта при 30/120 fps" % definition.id)
			check(points[0].z <= actor.get_height() * 0.241, "%s: ограничение сближения" % definition.id)
		actor.roar(0.4)
		actor.hit(Color.WHITE, actor.get_height() * 0.07)
		for frame in range(35):
			actor._process(1.0 / 60.0)
		check(actor._action == &"hit", "%s: отложенный рёв не перебивает попадание" % definition.id)
		for frame in range(40):
			actor._process(1.0 / 60.0)
		check(actor.fx_pos.is_equal_approx(Vector3.ZERO) and is_zero_approx(actor.fx_roll), "%s: нет остаточного крена после прерывания" % definition.id)
		actor.lunge(1.0)
		actor._process(0.2)
		var before := actor.fx_pos
		var age := actor._elapsed
		actor.hold_impact(0.06)
		actor._process(0.03)
		check(actor.fx_pos == before and actor._elapsed == age, "%s: остановка контакта не сдвигает позу" % definition.id)
		actor.reset()
		actor.free()
		CreatureModels.clear()
		await process_frame
	var ball := load("res://scenes/creature_ball.tscn").instantiate() as CreatureBall
	root.add_child(ball)
	ball.setup(CardDB.creature(&"creature_klykar_fire"), 0)
	ball.freeze_at(Vector3(0, 0.36, 0))
	var destination := Vector3(5, 0.36, 0)
	var target := Vector3(10, 0.36, -10)
	var staged := ball.stage_at(destination, target)
	check(ball.global_position.distance_to(Vector3(0, 0.36, 0)) < 0.001, "выход на позицию начинается без телепорта")
	await staged
	check(ball.global_position.distance_to(destination) < 0.001, "выход на позицию завершается в нужной точке")
	check(absf(angle_difference(ball._figure.rotation.y, atan2(5.0, -10.0))) < 0.001, "плавный разворот заканчивается лицом к сопернику")
	ball.queue_free()
	await process_frame
	print("Анимации: моделей 48, проверок %d, ошибок %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
