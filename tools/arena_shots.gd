extends SceneTree
## Снимки арены с крупными воротами: godot -s res://tools/arena_shots.gd -- <папка>
## empty — пустое поле (мест под ворота не видно); ghosts — выбор места (силуэты, место 5 под курсором);
## field — ворота и раскрытые существа обоих игроков (подписи со значками стихий, ободки, кольца);
## close — бой двух существ на одной карте; aim — прицел игрока с подсветкой ворот-целей.

var out_dir := "user://arena_shots"
var main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 60
	GraphicsSettings.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(20)
	main.team_menu.pick_random_and_start()
	await _frames(30)
	# автоматические ходы не мешают: останавливаем поток событий матча
	main.set_process(false)
	for n in ["setup_panel", "ability_panel"]:
		var p = main.get(n)
		if p != null and p.get("_panel") != null:
			p._panel.visible = false
	main.hud.set_hint("")
	main.cam.snap_overview()
	await _frames(40)
	await _save("empty")
	main.arena.set_highlight([0, 1, 2, 3, 4, 5], true)
	main.arena.set_hover(4)
	await _frames(40)
	await _save("ghosts")
	main.arena.set_highlight([])
	# ворота и существа
	var scene: PackedScene = load("res://scenes/arena_card_node.tscn")
	var ids: Array = CardDB.arena_ids()
	for slot in [0, 2, 4, 5]:
		var node := scene.instantiate() as ArenaCardNode
		main.world.add_child(node)
		node.position = main.arena.slot_position(slot) + Vector3(0, 0.02, 0)
		if slot == 4:
			node.show_face(CardDB.card(ids[3]))
		else:
			node.show_facedown(0 if slot > 2 else 1, CardDB.card(ids[slot]) if slot > 2 else null)
	var view: MatchState = main.ctrl.get_view(0)
	var mine: Array = view.players[0].creature_uids
	var foe: Array = view.players[1].creature_uids
	var y := Vector3(0, main.BALL_Y + 0.02, 0)
	var put := func(uid: int, player: int, pos: Vector3, look: Vector3) -> CreatureBall:
		var b: CreatureBall = main.balls.get(uid)
		if b == null:
			b = main._spawn_ball(uid)
		b.freeze_at(Vector3(0, main.BALL_Y, main.THROW_Z if player == 0 else -main.THROW_Z))
		b.freeze_at(pos + y)
		b.global_position = pos + y
		b.face_toward(look)
		b.open_animated(false)
		return b
	put.call(mine[0], 0, main.arena.slot_position(5), main.arena.slot_position(0))
	put.call(foe[0], 1, main.arena.slot_position(0), main.arena.slot_position(5))
	var base: Vector3 = main.arena.slot_position(4)
	var dz: float = Arena.FIG_H / 3.0
	var a: CreatureBall = put.call(mine[1], 0, base + Vector3(0, 0, dz), base)
	var d: CreatureBall = put.call(foe[1], 1, base - Vector3(0, 0, dz), base)
	await _frames(90)
	main.cam.snap_overview()
	await _frames(60)
	await _save("field")
	a.set_label_shift(-110.0)
	d.set_label_shift(110.0)
	main.cam.battle_view(base, maxf(a.figure_height(), d.figure_height()))
	await _frames(60)
	await _save("close")
	main.cam.aim_view(Vector3(0, 0, main.THROW_Z), 1.0, true)
	main.arena.set_highlight([0, 2, 4, 5])
	main.arena.set_hover(2)
	await _frames(50)
	await _save("aim")
	quit()


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, n])
