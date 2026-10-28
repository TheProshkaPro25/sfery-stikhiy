extends SceneTree
## Автоигра: человек управляется AIPlayer(0), реальная физика и UI. Считаем матчи, броски, попадания.

const MATCHES := 2
var main: Node
var bot: AIPlayer
var target := -1
var done := 0
var throws := {0: 0, 1: 0}
var hits := {0: 0, 1: 0}
var misses := {0: 0, 1: 0}
var frames := 0
var battles := 0
var reasons := {}
var match_frames := 0
var acted_key := ""

func _initialize() -> void:
	_lock_fps()
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	_new_match()

## Проверки (кроме замеров производительности) идут с лимитом 60 fps — без записи в settings.cfg.
## perf.gd снимает лимит после super._initialize().
func _lock_fps() -> void:
	GraphicsSettings.max_fps = 60
	Engine.max_fps = 60


func _new_match() -> void:
	if main != null:
		main.queue_free()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	bot = AIPlayer.new(0, 12345 + done)
	match_frames = 0
	await process_frame
	main.team_menu.pick_random_and_start()
	await process_frame
	main.ctrl.creature_returned.connect(func(uid, reason): _ret(uid, reason))
	main.ctrl.creature_stood.connect(func(uid, slot): _land(uid, true))
	main.ctrl.battle_started.connect(func(s, a, d): battles += 1; _land(a, true))

func _owner(uid): return main._owner_of(uid)
func _land(uid, ok):
	var p = _owner(uid); throws[p] += 1; hits[p] += 1
func _ret(uid, reason):
	var p = _owner(uid); throws[p] += 1
	reasons[reason] = reasons.get(reason, 0) + 1
	if reason == &"miss": misses[p] += 1

func _process(_d: float) -> bool:
	frames += 1
	match_frames += 1
	if main == null or main.ctrl == null:
		return false
	if main._game_over:
		done += 1
		print("Матч %d: победитель %d, ход %d, захваты %s" % [done, main.ctrl.winner, main.ctrl.get_turn(), str(main.captures)])
		if done >= MATCHES:
			_report(); quit(0); return false
		_new_match(); return false
	if match_frames > 60 * 60 * 6:
		print("ЗАВИСАНИЕ: фаза %d, pending %s, busy %s" % [main.ctrl.get_phase(), str(main._pending), str(main.events.is_busy())])
		_report(); quit(1); return false
	if main.battle_overlay._open:
		main.battle_overlay._close()
	var view = main.ctrl.get_view(0)
	if main.setup_panel._panel.visible:
		var c = bot.choose_setup(view, main.ctrl.legal_setup_slots(), main.ctrl.can_skip_gate())
		main.setup_panel.hide_panel()
		if c.is_empty():
			main._on_setup_skipped()
		else:
			main._on_setup_placed(c["card_id"], int(c["slot"]))
	elif main.hud._creature_panel.visible:
		var c = bot.choose_throw(view)
		target = int(c["target_slot"])
		main._on_creature_chosen(int(c["uid"]))
	elif main.throw_ctl.is_enabled():
		var b = main._active_ball
		var to = main.arena.slot_position(target) if target >= 0 else Vector3(0, 0, -6)
		var imp = ThrowController.impulse_for_target(b.global_position, to, 0.6, main.rng)
		main.throw_ctl.disable()
		main._on_throw_committed(imp)
	elif main.ability_panel._panel.visible:
		var cid: StringName = &""
		if main.ctrl.get_ability_moment() == &"battle":
			cid = bot.choose_ability(view, main.ctrl.get_battle_preview(), main.ctrl.legal_abilities(0))
		elif main.ctrl.get_ability_moment() == &"after_landing":
			cid = bot.choose_attach(view, main.ctrl.get_landed_uid(), main.ctrl.legal_abilities(0))
		else:
			return false  # до броска окно только подсказка
		if cid == &"": main._on_ability_passed()
		else: main._on_ability_chosen(cid)
	return false

func _report() -> void:
	print("боёв %d, возвраты %s" % [battles, str(reasons)])
	for p in [0, 1]:
		print("Игрок %d: бросков %d, приземлений в слот %d (%.0f%%), промахов %d" % [p, throws[p], hits[p], 100.0 * hits[p] / maxf(1, throws[p]), misses[p]])

