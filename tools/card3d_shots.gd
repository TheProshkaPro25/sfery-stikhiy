extends SceneTree
## Снимки карт ворот на арене с игровых ракурсов: godot -s res://tools/card3d_shots.gd -- <папка>
## Кладёт на 6 слотов открытые карты разных типов, свою закрытую (с подписью) и закрытую соперника;
## снимает общий план (overview) и прицел игрока (aim). Перед снимком — RenderingServer.force_draw.

const FACE_NAMES := ["Поле Пламени", "Логово Драгнара", "Обоюдный удар", "Воронка"]

var out_dir := "user://card3d"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 60
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in range(20):
		await process_frame
	main.team_menu.pick_random_and_start()
	for _i in range(30):
		await process_frame
	var defs: Array = []
	for n in FACE_NAMES:
		for id in CardDB.arena_ids():
			if CardDB.card(id).display_name == n:
				defs.append(CardDB.card(id))
	var scene: PackedScene = load("res://scenes/arena_card_node.tscn")
	for slot in range(6):
		var node := scene.instantiate() as ArenaCardNode
		main.world.add_child(node)
		node.position = main.arena.slot_position(slot) + Vector3(0, 0.02, 0)
		if slot < defs.size():
			node.show_face(defs[slot])
		elif slot == 4:
			node.show_facedown(0, CardDB.card(CardDB.arena_ids()[10]))
		else:
			node.show_facedown(1, null)
	for n in ["setup_panel", "ability_panel"]:
		var p = main.get(n)
		if p != null and p.get("_panel") != null:
			p._panel.visible = false
	main.cam.snap_overview()
	for _i in range(50):
		await process_frame
	await _save("overview")
	main.cam.aim_view(Vector3(0, 0, main.THROW_Z), 1.0, true)
	for _i in range(50):
		await process_frame
	await _save("aim")
	quit()


func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)  # окно может быть скрыто — кадр всё равно рисуем
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, n])
