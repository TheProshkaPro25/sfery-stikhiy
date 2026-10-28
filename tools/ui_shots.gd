extends "res://tools/autoplay.gd"
## Снимки каждого экрана интерфейса (по разу): godot -s res://tools/ui_shots.gd -- <папка>

var out_dir := "user://ui_shots"
var taken := {}
var hold := 0
var hold_kind := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_lock_fps()
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 240
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	bot = AIPlayer.new(0, 777)
	for _i in range(40):
		await process_frame
	_save("0_menu")
	main.team_menu.pick_random_and_start()
	await process_frame
	main.ctrl.creature_returned.connect(func(uid, reason): _ret(uid, reason))
	main.ctrl.creature_stood.connect(func(uid, slot): _land(uid, true))
	main.ctrl.battle_started.connect(func(s, a, d): battles += 1; _land(a, true))

func _save(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, n])
	taken[n] = true

func _kind() -> String:
	if main.battle_overlay._open: return "4_battle"
	if main.setup_panel._panel.visible: return "1_setup"
	if main.hud._creature_panel.visible: return "2_creature"
	if main.ability_panel._panel.visible: return "3_ability"
	if main._game_over: return "5_gameover"
	return ""

func _process(d: float) -> bool:
	frames += 1
	if main == null or main.ctrl == null:
		return false
	if frames == 400 and not taken.has("6_play"):
		_save("6_play")
	var k := _kind()
	if k != "" and not taken.has(k):
		if hold_kind != k:
			hold_kind = k; hold = 45
		hold -= 1
		if k == "1_setup" and hold == 20:
			var cv = main.setup_panel._cards_box.get_child(0)
			cv.button_pressed = true
			main.setup_panel._on_card_pressed(cv.card_id)
		if hold <= 0:
			_save(k)
			if k == "5_gameover" or taken.size() >= 7:
				quit(0)
		return false
	if main._game_over:
		return false
	if frames > 30000:
		quit(0)
	return super._process(d)
