extends Node
## Корень игры: владеет MatchController и AIPlayer, строит 3D-мир и UI, связывает сигналы.
## Все сигналы контроллера -> EventPlayer. Ввод/ход ИИ - только после drained (см. _pump).

const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const BALL_SCENE: PackedScene = preload("res://scenes/creature_ball.tscn")
const CARD_SCENE: PackedScene = preload("res://scenes/arena_card_node.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const SETUP_SCENE: PackedScene = preload("res://scenes/ui/setup_panel.tscn")
const ABILITY_SCENE: PackedScene = preload("res://scenes/ui/ability_panel.tscn")
const BATTLE_SCENE: PackedScene = preload("res://scenes/ui/battle_overlay.tscn")
const GAMEOVER_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")
const TEAM_MENU_SCENE: PackedScene = preload("res://scenes/ui/team_menu.tscn")

const HUMAN := 0
const AI_PLAYER := 1
const THROW_Z := 5.9 * Arena.WORLD
const BALL_Y := 0.36

var ctrl: MatchController
var ai: AIPlayer
var rng := RandomNumberGenerator.new()

var world: Node3D
var arena: Arena
var cam: CameraRig
var events: EventPlayer
var throw_ctl: ThrowController
var ui_layer: CanvasLayer
var hud: HudUI
var battle_hud: BattleHud
var setup_panel: SetupPanel
var ability_panel: AbilityPanel
var battle_overlay: BattleOverlay
var game_over_ui: GameOverUI
var team_menu: TeamMenu

var balls: Dictionary = {}        # uid -> CreatureBall
var card_nodes: Dictionary = {}   # slot -> ArenaCardNode
var captures: Array[int] = [0, 0]
var _defs: Dictionary = {}        # uid -> CreatureDef (строится один раз из get_view)
var _owners: Dictionary = {}      # uid -> int (владелец)
var _pending: Dictionary = {}
var _active_ball: CreatureBall = null
var _ai_target_slot: int = -1
var _turn: int = 0
var _active: int = 0
var _game_over := false
var _player_ids: Array[StringName] = []
var _player_deck: Array = []  # [существа, ворота, способности] из конструктора колоды


func _ready() -> void:
	SoundFx.i()
	rng.randomize()
	_build_world()
	_build_ui()
	team_menu.deck_chosen.connect(_on_deck_chosen)


# ---------------------------------------------------------------- построение

const SKY_SHADER := """
shader_type sky;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
void sky() {
	vec3 d = EYEDIR;
	float n = fbm(d * 2.2 + vec3(0.0, TIME * 0.01, 0.0));
	float n2 = fbm(d * 4.5 + vec3(5.0));
	vec3 deep = vec3(0.012, 0.012, 0.03);
	vec3 neb1 = vec3(0.28, 0.08, 0.38);
	vec3 neb2 = vec3(0.04, 0.22, 0.32);
	vec3 col = deep + neb1 * smoothstep(0.45, 0.85, n) * 0.9 + neb2 * smoothstep(0.5, 0.9, n2) * 0.7;
	float band = exp(-abs(d.y - 0.05) * 7.0);
	col += vec3(0.25, 0.12, 0.3) * band * 0.35 * n;
	float st = step(0.9975, hash(floor(d * 420.0)));
	col += vec3(0.9, 0.9, 1.0) * st * (0.5 + 0.5 * sin(TIME * 2.0 + hash(floor(d * 420.0)) * 30.0));
	col *= smoothstep(-0.35, 0.05, d.y) * 0.85 + 0.15;
	COLOR = col;
}
"""


func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	# Небо-туманность: пространство боя вне обычного мира (по мотивам аниме)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_strength = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.5  # большой радиус чернил впадины на моделях
	env.ssao_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.30, 0.34)
	env.fog_density = 0.008 / Arena.WORLD
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	# Чёткие тени под размер поля: мягкий PCSS (1.5°) на огромной арене давал шумные кляксы.
	sun.light_angular_distance = 0.4
	sun.shadow_blur = 1.0
	sun.shadow_normal_bias = 1.5
	sun.shadow_opacity = 0.6  # тень от крыльев на теле не чернит модель целиком
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 22.0 * Arena.WORLD
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.55
	world.add_child(fill)

	cam = CameraRig.new()
	cam.position = CameraRig.OVERVIEW_POS
	world.add_child(cam)
	cam.look_at(CameraRig.OVERVIEW_LOOK, Vector3.UP)
	cam.current = true

	arena = ARENA_SCENE.instantiate() as Arena
	world.add_child(arena)

	events = EventPlayer.new()
	add_child(events)
	throw_ctl = ThrowController.new()
	add_child(throw_ctl)


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	# Тёмная виньетка по краям кадра (под интерфейсом)
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsh := Shader.new()
	vsh.code = "shader_type canvas_item;\nvoid fragment() { vec2 q = UV - 0.5; float v = smoothstep(0.35, 0.85, length(q * vec2(1.25, 1.0))); COLOR = vec4(0.0, 0.0, 0.02, v * 0.6); }"
	var vmat := ShaderMaterial.new()
	vmat.shader = vsh
	vig.material = vmat
	ui_layer.add_child(vig)
	battle_hud = BattleHud.new()
	ui_layer.add_child(battle_hud)
	hud = HUD_SCENE.instantiate() as HudUI
	ui_layer.add_child(hud)
	setup_panel = SETUP_SCENE.instantiate() as SetupPanel
	ui_layer.add_child(setup_panel)
	ability_panel = ABILITY_SCENE.instantiate() as AbilityPanel
	ui_layer.add_child(ability_panel)
	battle_overlay = BATTLE_SCENE.instantiate() as BattleOverlay
	ui_layer.add_child(battle_overlay)
	game_over_ui = GAMEOVER_SCENE.instantiate() as GameOverUI
	ui_layer.add_child(game_over_ui)
	team_menu = TEAM_MENU_SCENE.instantiate() as TeamMenu
	ui_layer.add_child(team_menu)


func _on_deck_chosen(creatures: Array[StringName], arena_ids: Array[StringName], abilities: Array[StringName]) -> void:
	_player_ids = creatures
	_player_deck = [creatures, arena_ids, abilities]
	_build_logic()
	call_deferred("_start_game")


func _build_logic() -> void:
	CardDB.load_all()
	var decks: Array[DeckDef] = _build_decks()
	var seed_value: int = int(rng.randi())
	ctrl = MatchController.new(decks[0], decks[1], seed_value)
	ai = AIPlayer.new(AI_PLAYER, seed_value + 1)
	_index_creatures()

	ctrl.phase_changed.connect(_on_phase_changed)
	ctrl.setup_requested.connect(_on_setup_requested)
	ctrl.arena_card_placed.connect(_on_arena_card_placed)
	ctrl.throw_requested.connect(_on_throw_requested)
	ctrl.creature_selected.connect(_on_creature_selected)
	ctrl.creature_returned.connect(_on_creature_returned)
	ctrl.creature_stood.connect(_on_creature_stood)
	ctrl.battle_started.connect(_on_battle_started)
	ctrl.card_revealed.connect(_on_card_revealed)
	ctrl.ability_window.connect(_on_ability_window)
	ctrl.ability_played.connect(_on_ability_played)
	ctrl.ability_cancelled.connect(_on_ability_cancelled)
	ctrl.battle_resolved.connect(_on_battle_resolved)
	ctrl.creature_eliminated.connect(_on_creature_eliminated)
	ctrl.card_captured.connect(_on_card_captured)
	ctrl.turn_started.connect(_on_turn_started)
	ctrl.game_over.connect(_on_game_over)

	events.drained.connect(_pump)
	throw_ctl.throw_committed.connect(_on_throw_committed)
	hud.creature_chosen.connect(_on_creature_chosen)
	setup_panel.placed.connect(_on_setup_placed)
	setup_panel.skipped.connect(_on_setup_skipped)
	ctrl.creature_relocated.connect(func(uid: int, a: int, b: int) -> void: events.push(_anim_relocated.bind(uid, a, b)))
	ctrl.gates_recycled.connect(func() -> void: events.push(func() -> void:
		hud.flash("Ворота кончились: выигранные карты вернулись в руки")
		await _wait(1.2)
		hud.clear_flash()))
	ctrl.creatures_refilled.connect(func(p: int) -> void: events.push(_anim_refilled.bind(p)))
	ctrl.standoff.connect(func(a: int, d: int) -> void: events.push(func() -> void:
		hud.flash("Бросать некому — %s идёт на %s!" % [_cname(a), _cname(d)])
		await _wait(1.4)
		hud.clear_flash()))
	ctrl.turn_skipped.connect(func(p: int) -> void: events.push(func() -> void:
		hud.flash("Все ваши существа на воротах — ход переходит сопернику" if p == HUMAN else "Все существа соперника на воротах — ваш ход")
		await _wait(1.2)
		hud.clear_flash()))
	ability_panel.ability_chosen.connect(_on_ability_chosen)
	ability_panel.passed.connect(_on_ability_passed)
	game_over_ui.restart_requested.connect(_on_restart)


func _start_game() -> void:
	hud.set_hint("Сферы Стихий")
	ctrl.start()
	_refresh_hand()
	ability_panel.set_dock_visible(true)


## Подписи существ: только перечисленные uid (пустой список - все).
## В бою (два uid) остальные существа скрываются: бой изолирован, как в аниме.
func _focus_labels(uids: Array) -> void:
	for u in balls.keys():
		var b: CreatureBall = balls[u]
		b.set_label_allowed(uids.is_empty() or (uids.has(u) and uids.size() < 2))
		b.visible = uids.size() < 2 or uids.has(u)


## 3D-эффект способности у своего существа (и у соперника, если карта бьёт по нему).
func _ability_fx(player: int, def: CardDef) -> void:
	if def == null or _battle_uids.size() != 2:
		return
	var mine: int = _battle_uids[0] if _owner_of(_battle_uids[0]) == player else _battle_uids[1]
	var foe: int = _battle_uids[1] if mine == _battle_uids[0] else _battle_uids[0]
	var mb: CreatureBall = balls.get(mine)
	var fb: CreatureBall = balls.get(foe)
	if mb == null:
		return
	mb.ability_pulse()
	var h: float = Arena.CARD_H * 0.7
	var r: float = Arena.CARD_W * 0.32
	var base: Vector3 = mb.global_position - Vector3(0, CreatureBall.RADIUS, 0)
	var foe_base: Vector3 = fb.global_position - Vector3(0, CreatureBall.RADIUS, 0) if fb != null else base
	var cls: StringName = CardDB.card_class(def)
	var eff := String(def.effect_id)
	if CardEffects.is_fusion(def):
		var tc := UiTheme.FUSION_GLOW
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), tc, r * 2.2, 0.6)
		get_tree().create_timer(0.2).timeout.connect(func() -> void: VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), tc, r * 3.0, 0.7))
		VisualUtil.spiral(world, base, tc, h, r, 1.0)
	elif cls == &"red":
		var lock: int = CardEffects.lock_attr(def)
		var ec: Color = VisualUtil.attr_color(lock if lock >= 0 else _creature_def(mine).attribute).lightened(0.25)
		VisualUtil.light_pillar(mb, Vector3(0, -CreatureBall.RADIUS, 0), ec, h * 1.8, r * 0.9, 0.9)
		VisualUtil.spiral(world, base, ec, h * 1.2, r * 1.2, 1.1)
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), ec, r * 3.0, 0.7)
		if eff == "drain" or eff == "absorb" or eff == "strip":
			VisualUtil.burst(world, foe_base + Vector3(0, h * 0.5, 0), Color(0.8, 0.15, 0.2), Arena.WORLD * 0.7)
	elif cls == &"blue":
		if eff == "weaken_foe":
			VisualUtil.spiral(world, foe_base, Color(0.85, 0.15, 0.2), h, r, 1.0)
			VisualUtil.burst(world, foe_base + Vector3(0, h * 0.5, 0), Color(0.8, 0.1, 0.15), Arena.WORLD * 0.7)
		else:
			VisualUtil.spiral(world, base, Color(1.0, 0.8, 0.35), h * 1.1, r, 1.0)
			VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), Color(1.0, 0.75, 0.3), r * 2.5, 0.6)
	else:
		var gc := Color(0.4, 1.0, 0.6)
		match eff:
			"shield", "rescue":
				VisualUtil.dome(world, base, gc, r * 1.9, 1.6)
			"nullify_arena":
				var cardpos: Vector3 = (base + foe_base) * 0.5
				VisualUtil.ring_wave(world, cardpos + Vector3(0, 0.1, 0), Color(0.9, 0.95, 1.0), Arena.CARD_H * 0.9, 0.8)
				VisualUtil.burst(world, cardpos + Vector3(0, 0.5, 0), Color(0.8, 0.9, 1.0), Arena.WORLD)
			"swap_base", "steal_arena":
				VisualUtil.spiral(world, base, gc, h, r, 1.0)
				if fb != null:
					VisualUtil.spiral(world, foe_base, gc, h, r, 1.0)
			_:
				VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), gc, r * 2.5, 0.7)


## Крик существа по uid (с задержкой, чтобы совпасть с анимацией).
func _cry(uid: int, kind: String, delay: float = 0.0, db: float = -1.0) -> void:
	var d: CreatureDef = _creature_def(uid)
	if d != null:
		SoundFx.i().cry(d.id, kind, delay, db)


## Рука способностей игрока внизу справа.
func _refresh_hand() -> void:
	if ctrl == null:
		return
	ability_panel.set_hand(ctrl.get_view(HUMAN).players[HUMAN].ability_hand)


func _on_restart() -> void:
	SoundFx.i().stop_music(0.4)
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- колоды и справочник uid

## Колоды строит ядро: пресет игрока и случайная колода ИИ из общего пула (CardDB).
func _build_decks() -> Array[DeckDef]:
	var mine: DeckDef = null
	if _player_deck.size() == 3 and CardDB.deck_error(_player_deck[0], _player_deck[1], _player_deck[2]) == "":
		mine = CardDB.build_deck(_player_deck[0], _player_deck[1], _player_deck[2])
	if mine == null:
		push_warning("Недопустимая команда, берётся пресет")
		mine = CardDB.preset_deck(0)
	return [mine, CardDB.random_deck(rng)]


## uid -> определение и владелец. Существа в get_view не маскируются, uid не меняются за матч.
func _index_creatures() -> void:
	var view: MatchState = ctrl.get_view(HUMAN)
	for p in range(2):
		for uid in view.players[p].creature_uids:
			var cs: CreatureState = view.creature(uid)
			_defs[uid] = CardDB.creature(cs.def_id)
			_owners[uid] = cs.owner


func _creature_def(uid: int) -> CreatureDef:
	return _defs.get(uid) as CreatureDef


func _owner_of(uid: int) -> int:
	return int(_owners.get(uid, -1))


func _cname(uid: int) -> String:
	var d: CreatureDef = _creature_def(uid)
	if d == null:
		return "Существо #%d" % uid
	return d.display_name


func _names_for(r: BattleResult) -> Dictionary:
	var out: Dictionary = {}
	for u in [r.attacker_uid, r.defender_uid]:
		var d: CreatureDef = _creature_def(u)
		if d != null:
			out[u] = "%s (%s)" % [d.display_name, VisualUtil.attr_name(d.attribute)]
	return out


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- обработчики сигналов контроллера
# Состояние контроллера уже изменено; здесь только ставим анимации в очередь.

func _on_phase_changed(phase: int, active_player: int) -> void:
	events.push(_anim_phase.bind(phase, active_player))


func _on_setup_requested(player: int) -> void:
	events.push(_anim_set_pending.bind({"kind": "setup", "player": player}))


func _on_arena_card_placed(player: int, slot: int) -> void:
	events.push(_anim_card_placed.bind(player, slot))


func _on_throw_requested(player: int) -> void:
	events.push(_anim_set_pending.bind({"kind": "throw", "player": player}))


func _on_creature_selected(player: int, uid: int, recalled: bool) -> void:
	events.push(_anim_selected.bind(player, uid, recalled))


func _on_creature_returned(uid: int, reason: StringName) -> void:
	events.push(_anim_returned.bind(uid, reason))


func _on_creature_stood(uid: int, slot: int) -> void:
	events.push(_anim_stood.bind(uid, slot))


func _on_battle_started(slot: int, attacker_uid: int, defender_uid: int) -> void:
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	events.push(_anim_battle_started.bind(slot, attacker_uid, defender_uid, pw))


func _on_card_revealed(slot: int, card_id: StringName) -> void:
	events.push(_anim_card_revealed.bind(slot, card_id))


func _on_ability_window(player: int, _options: Array) -> void:
	# Список карт берётся при ответе из ctrl.legal_abilities(player).
	events.push(_anim_set_pending.bind({"kind": "ability", "player": player}))


func _on_ability_played(player: int, card_id: StringName) -> void:
	_refresh_hand()
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	events.push(_anim_ability_msg.bind(player, card_id, false, pw))


func _on_ability_cancelled(player: int, card_id: StringName) -> void:
	events.push(_anim_ability_msg.bind(player, card_id, true))


func _on_battle_resolved(result: BattleResult) -> void:
	_refresh_hand()
	events.push(_anim_battle_resolved.bind(result))


func _on_creature_eliminated(uid: int) -> void:
	events.push(_anim_remove_ball.bind(uid, true))


func _on_card_captured(player: int, slot: int, _card_id: StringName) -> void:
	events.push(_anim_captured.bind(player, slot))


func _on_turn_started(player: int, turn: int) -> void:
	_refresh_hand()
	events.push(_anim_turn.bind(player, turn))


func _on_game_over(winner: int, reason: StringName) -> void:
	ability_panel.set_dock_visible(false)
	events.push(_anim_game_over.bind(winner, reason))


# ---------------------------------------------------------------- анимации (выполняются EventPlayer)

var _alive: Array[int] = [3, 3]
var _battle_uids: Array[int] = []  # [атакующий, защитник] текущего боя (для эффектов способностей)  # живые существа по ходу анимаций (для строки статуса)


func _refresh_status() -> void:
	hud.set_status(_turn, _active, _alive[0], _alive[1])


func _anim_phase(_phase: int, active_player: int) -> void:
	_active = active_player
	_refresh_status()


func _anim_turn(player: int, turn: int) -> void:
	_active = player
	_turn = turn
	_refresh_status()
	if turn > 0:
		SoundFx.i().play("turn_start", -8.0 if player == HUMAN else -12.0)


func _anim_set_pending(p: Dictionary) -> void:
	_pending = p


func _anim_card_placed(player: int, slot: int) -> void:
	var node := CARD_SCENE.instantiate() as ArenaCardNode
	world.add_child(node)
	var pos := arena.slot_position(slot)
	node.position = pos
	node.slot = slot
	# В виде игрока своя закрытая карта имеет card_id, чужая замаскирована (пустой id -> null).
	var cdef: CardDef = CardDB.card(ctrl.get_view(HUMAN).slots[slot].card_id)
	node.show_facedown(player, cdef)
	SoundFx.i().play("card_place")
	card_nodes[slot] = node
	await _wait(0.3)


func _spawn_ball(uid: int) -> CreatureBall:
	var b := BALL_SCENE.instantiate() as CreatureBall
	world.add_child(b)
	b.setup(_creature_def(uid), uid)
	b.settled.connect(_on_ball_settled)
	balls[uid] = b
	return b


func _start_pos(player: int) -> Vector3:
	return Vector3(0.0, BALL_Y, THROW_Z if player == HUMAN else -THROW_Z)


func _anim_selected(player: int, uid: int, recalled: bool) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		b = _spawn_ball(uid)
	elif recalled:
		b.unfreeze()
		b.close_up()
		b.slot = -1
	b.freeze_at(_start_pos(player))
	cam.overview()
	_focus_labels([])
	_active_ball = b
	_pending = {"kind": "launch", "player": player, "uid": uid}
	await _wait(0.25)


## Существо уходит в зону использованных: промах, после боя или со своих засчитанных ворот.
func _anim_returned(uid: int, reason: StringName) -> void:
	match reason:
		&"miss":
			SoundFx.i().play("miss", -2.0)
			hud.set_hint("Промах: %s уходит в зону использованных" % _cname(uid))
		&"gate_won":
			hud.set_hint("Свои ворота: карта засчитана")
		&"rescued":
			hud.set_hint("Спасение: %s не выбывает" % _cname(uid))
		&"lost":
			await _anim_remove_ball(uid, true)
			return
	cam.overview()
	_focus_labels([])
	await _anim_remove_ball(uid)


## Попадание на свои ворота: существо переходит на другие ворота.
func _anim_relocated(uid: int, _from: int, to: int) -> void:
	var b: CreatureBall = balls.get(uid)
	hud.set_hint("Свои ворота: %s переходит на другие" % _cname(uid))
	if b == null:
		return
	var target := arena.slot_position(to) + Vector3(0.0, BALL_Y + 0.02, 0.0)
	b.freeze_at(b.global_position)
	cam.overview()
	var tw := b.create_tween()
	tw.tween_property(b, "global_position", target + Vector3(0, Arena.CARD_W * 0.4, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "global_position", target, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	b.freeze_at(target)


func _anim_refilled(player: int) -> void:
	hud.coach("used", "Зона использованных: существа после промаха или боя отдыхают. Когда бросать некого, они все возвращаются в руку.")
	hud.flash("Существа вернулись из зоны использованных" if player == HUMAN else "У соперника вернулись существа")
	await _wait(1.0)
	hud.clear_flash()


func _anim_remove_ball(uid: int, eliminated: bool = false) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		return
	SoundFx.i().play("eliminated" if eliminated else "vanish", -2.0 if eliminated else -6.0)
	if eliminated:
		_alive[_owner_of(uid)] -= 1
		_refresh_status()
		VisualUtil.burst(world, b.global_position + Vector3(0, Arena.CARD_H * 0.2, 0), _creature_def(uid).color, Arena.WORLD * 0.8)
	balls.erase(uid)
	if b == _active_ball:
		_active_ball = null
	await b.vanish()
	b.queue_free()


func _anim_stood(uid: int, slot: int) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		return
	b.slot = slot
	hud.set_hint("%s встаёт на карту" % _cname(uid))
	b.freeze_at(arena.slot_position(slot) + Vector3(0.0, BALL_Y + 0.02, 0.0))
	b.face_toward(b.global_position + Vector3(0.0, 0.0, -1.0 if _owner_of(uid) == HUMAN else 1.0))
	cam.zoom_slot(arena.slot_position(slot))
	_focus_labels([uid])
	SoundFx.i().play("ball_land", -3.0)
	VisualUtil.ring_wave(world, arena.slot_position(slot) + Vector3(0, 0.08, 0), VisualUtil.attr_color(_creature_def(uid).attribute), Arena.CARD_W * 0.7, 0.55)
	SoundFx.i().play_later("capsule_open", 0.05)
	_cry(uid, "appear", 0.4)
	b.open_animated()
	b.roar(0.65)
	get_tree().create_timer(0.8).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	await _wait(0.85)


func _anim_battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = []) -> void:
	arena.set_highlight([slot])
	var atk: CreatureBall = balls.get(attacker_uid)
	var dfn: CreatureBall = balls.get(defender_uid)
	var base := arena.slot_position(slot)
	cam.battle_view(base)
	hud.set_battle_mode(true)
	_battle_uids = [attacker_uid, defender_uid]
	if powers.size() == 2:
		battle_hud.open([_cname(attacker_uid), _cname(defender_uid)], [_creature_def(attacker_uid).attribute, _creature_def(defender_uid).attribute], powers)
	_focus_labels([attacker_uid, defender_uid])
	# Атакующий и защитник делят карту: по трети длины каждому, треть пустоты между ними.
	# Камера боя смотрит с +X, поэтому +Z на экране слева: атакующий всегда слева, под плашкой «АТАКА».
	var dz: float = Arena.CARD_H / 3.0
	var y := Vector3(0.0, BALL_Y + 0.02, 0.0)
	if atk != null:
		atk.freeze_at(base + y + Vector3(0.0, 0.0, dz))
		atk.set_label_shift(-110.0 * signf(dz))
		atk.face_toward(base - Vector3(0.0, 0.0, dz))
		atk.open_animated()
	if dfn != null:
		dfn.freeze_at(base + y - Vector3(0.0, 0.0, dz))
		dfn.set_label_shift(110.0 * signf(dz))
		dfn.face_toward(base + Vector3(0.0, 0.0, dz))
		dfn.open_animated()
	hud.set_hint("Бой: %s против %s" % [_cname(attacker_uid), _cname(defender_uid)])
	SoundFx.i().play("battle_start")
	_cry(attacker_uid, "attack", 0.45)
	_cry(defender_uid, "attack", 0.9, -4.0)
	if atk != null:
		atk.roar(0.45)
	if dfn != null:
		dfn.roar(0.9)
	get_tree().create_timer(0.55).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	await _wait(1.1)


func _anim_card_revealed(slot: int, card_id: StringName) -> void:
	var node: ArenaCardNode = card_nodes.get(slot)
	if node != null:
		node.reveal(CardDB.card(card_id))
		SoundFx.i().play("card_flip")
	await _wait(1.0)


func _anim_ability_msg(player: int, card_id: StringName, cancelled: bool, powers: Array = []) -> void:
	if powers.size() == 2:
		battle_hud.set_powers(powers)
	var c: CardDef = CardDB.card(card_id)
	var cname: String = c.display_name if c != null else str(card_id)
	SoundFx.i().play("ability_cancel" if cancelled else "ability_play")
	if not cancelled:
		ability_panel.show_played(card_id, player != HUMAN)
		_ability_fx(player, c)
	if cancelled:
		hud.flash("%s «%s» отменена" % ["Ваша карта" if player == HUMAN else "Карта соперника", cname])
	else:
		hud.flash(("Вы играете «%s»" if player == HUMAN else "Соперник играет «%s»") % cname)
	await _wait(1.1)
	hud.clear_flash()


func _anim_battle_resolved(result: BattleResult) -> void:
	arena.set_highlight([])
	battle_hud.set_powers([result.powers[0], result.powers[1]])
	await _wait(0.6)
	# удар: победитель бросается на соперника, вспышка, тряска, проигравший рассыпается
	var wb: CreatureBall = balls.get(result.winner_uid)
	var lb: CreatureBall = balls.get(result.loser_uid)
	_cry(result.winner_uid, "attack", 0.0)
	if wb != null and lb != null:
		lb.counter_lunge(wb.global_position)
		await wb.lunge(lb.global_position)
		lb.take_hit(VisualUtil.attr_color(_creature_def(result.winner_uid).attribute).lightened(0.2))
		var mid: Vector3 = (wb.global_position + lb.global_position) * 0.5 + Vector3(0, Arena.CARD_H * 0.25, 0)
		var wc: Color = VisualUtil.attr_color(_creature_def(result.winner_uid).attribute)
		VisualUtil.burst(world, mid, wc.lightened(0.3), Arena.WORLD)
		VisualUtil.light_pillar(lb, Vector3(0, -CreatureBall.RADIUS, 0), wc, Arena.CARD_H * 1.2, Arena.CARD_W * 0.3, 0.5)
	SoundFx.i().play("clash")
	cam.shake(1.0, 0.45)
	hud.screen_flash(Color(1, 1, 1, 0.55))
	battle_hud.resolve(0 if result.winner_uid == result.attacker_uid else 1)
	SoundFx.i().play_later("battle_win" if _owner_of(result.winner_uid) == HUMAN else "battle_lose", 0.35, -2.0)
	await _wait(1.1)
	battle_hud.close()
	hud.set_battle_mode(false)
	cam.overview()
	_focus_labels([])
	await battle_overlay.show_result(result, _names_for(result))


func _anim_captured(player: int, slot: int) -> void:
	var node: ArenaCardNode = card_nodes.get(slot)
	cam.overview()
	_focus_labels([])
	captures[player] += 1
	_refresh_status()
	if node == null:
		return
	card_nodes.erase(slot)
	SoundFx.i().play("card_capture")
	node.tray_offset = float(captures[player] - 1) * 1.0 * Arena.WORLD
	await node.play_capture(player)


func _reason_text(reason: StringName) -> String:
	match reason:
		&"knockout":
			return "Все три существа проигравшего выбиты"
		&"turn_limit":
			return "Лимит ходов (%d): по числу оставшихся существ" % MatchController.MAX_TURNS
		&"stalemate", &"no_gates":
			return "Бросать больше некому: по числу оставшихся существ"
	return String(reason)


func _anim_game_over(winner: int, reason: StringName) -> void:
	_game_over = true
	_pending = {}
	throw_ctl.disable()
	hud.hide_creatures()
	setup_panel.hide_panel()
	ability_panel.hide_panel()
	SoundFx.i().stop_music(1.0)
	SoundFx.i().play("victory" if winner == HUMAN else "defeat")
	game_over_ui.show_result(winner, _reason_text(reason))


# ---------------------------------------------------------------- физика / ввод

func _on_throw_committed(impulse: Vector3) -> void:
	hud.set_hint("Шар катится...")
	if _active_ball != null:
		cam.follow(_active_ball)
		SoundFx.i().play("ball_throw")
		_active_ball.launch(impulse)


func _on_ball_settled(ball: CreatureBall, world_pos: Vector3) -> void:
	if ball != _active_ball:
		return
	_active_ball = null
	var slot: int = arena.slot_at(world_pos)
	if slot >= 0:
		cam.zoom_slot(arena.slot_position(slot))
	else:
		cam.overview()
		_focus_labels([])
	call_deferred("_report", ball.uid, slot)


func _report(uid: int, slot: int) -> void:
	if _game_over:
		return
	ctrl.report_landing(uid, slot)


# ---------------------------------------------------------------- ответы игроков (только после drained)

func _pump() -> void:
	if _game_over or events.is_busy() or _pending.is_empty():
		return
	var phase: int = ctrl.get_phase()
	if phase == MatchController.Phase.GAME_OVER:
		return
	var p: Dictionary = _pending
	_pending = {}
	var player: int = int(p["player"])
	var want: int = -1
	match str(p["kind"]):
		"setup":
			want = MatchController.Phase.SETUP
		"throw":
			want = MatchController.Phase.AWAIT_THROW
		"launch":
			want = MatchController.Phase.AWAIT_LANDING
		"ability":
			want = MatchController.Phase.ABILITY_WINDOW
	if phase != want or (str(p["kind"]) != "launch" and ctrl.get_active_player() != player):
		push_warning("Пропущен запрос %s: фаза %d, активный игрок %d" % [str(p["kind"]), phase, ctrl.get_active_player()])
		return
	match str(p["kind"]):
		"setup":
			_do_setup(player)
		"throw":
			_do_throw_select(player)
		"launch":
			_do_launch(player)
		"ability":
			_do_ability(player)


func _do_setup(player: int) -> void:
	if player == HUMAN:
		var cards: Array = []
		for cid in ctrl.get_view(HUMAN).players[HUMAN].arena_hand:
			var c: CardDef = CardDB.card(cid)
			cards.append({"id": c.id, "name": c.display_name, "text": c.text})
		var legal: Array[int] = ctrl.legal_setup_slots()
		arena.set_highlight(legal)
		hud.set_hint("Карта ворот на поле? Положите карту или пропустите" if ctrl.can_skip_gate() else "Положите карту ворот на поле")
		setup_panel.begin(cards, legal, ctrl.can_skip_gate())
		hud.coach("gate", "Карты ворот — это поле боя. Выбери карту и место (подсвечено). Соперник не видит, что на ней: карта откроется только в бою. Наведи мышь на карту, чтобы узнать, что она даёт.")
	else:
		hud.set_hint("Соперник выбирает карту ворот...")
		var choice: Dictionary = ai.choose_setup(ctrl.get_view(AI_PLAYER), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
		var err: int = OK
		if choice.is_empty():
			err = ctrl.skip_gate(AI_PLAYER)
		else:
			err = ctrl.place_arena_card(AI_PLAYER, choice["card_id"], int(choice["slot"]))
		if err != OK:
			push_error("ИИ: выкладка ворот вернула ошибку %d" % err)


func _do_throw_select(player: int) -> void:
	if player == HUMAN:
		var view: MatchState = ctrl.get_view(HUMAN)
		var entries: Array = []
		for u in ctrl.legal_creatures(HUMAN):
			var d: CreatureDef = _creature_def(u)
			var note := "(отозвать с карты)" if view.creature(u).slot >= 0 else ""
			entries.append({"uid": u, "def": d, "text": "Существо #%d" % u, "note": note})
		hud.set_hint("Ваш бросок: выберите существо")
		hud.show_creatures(entries)
	else:
		hud.set_hint("Соперник бросает...")
		var c: Dictionary = ai.choose_throw(ctrl.get_view(AI_PLAYER))
		_ai_target_slot = int(c["target_slot"])
		var err: int = ctrl.select_creature(AI_PLAYER, int(c["uid"]))
		if err != OK:
			push_error("ИИ: select_creature вернул ошибку %d" % err)


func _do_launch(player: int) -> void:
	var uid: int = ctrl.get_selected_uid()
	var b: CreatureBall = balls.get(uid)
	if b == null:
		push_error("Нет шара для uid %d" % uid)
		return
	_active_ball = b
	if player == HUMAN:
		cam.snap_overview()
		_focus_labels([])
		hud.set_hint("Потяните мышь назад от шара и отпустите (ПКМ - отмена)")
		hud.coach("throw", "Бросок как из рогатки: зажми левую кнопку, потяни мышь назад от шара и отпусти. Чем дальше тянешь, тем сильнее бросок. Цель — попасть на карту ворот.")
		throw_ctl.enable(b)
	else:
		cam.overview()
		_focus_labels([])
		var to := Vector3(0.0, 0.0, 6.0)
		if _ai_target_slot >= 0:
			to = arena.slot_position(_ai_target_slot)
		var imp := ThrowController.impulse_for_target(b.global_position, to, ai.get_aim_error(), rng)
		SoundFx.i().play("ball_throw", -3.0)
		b.launch(imp)
		cam.follow(b)


func _do_ability(player: int) -> void:
	var preview: BattleResult = ctrl.get_battle_preview()
	if preview == null:
		push_error("Окно способностей без предпросмотра боя")
		return
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		var hdr := "Бой: %s (%d) против %s (%d). Сыграйте способность или пас" % [
			_cname(preview.attacker_uid), preview.powers[0], _cname(preview.defender_uid), preview.powers[1]]
		var fusion_only := not entries.is_empty()
		for e in entries:
			if not CardEffects.is_fusion(CardDB.card(e["id"])):
				fusion_only = false
		if fusion_only:
			hdr = "Слияние: добавьте карту поверх своей способности (%d против %d) или пас" % [preview.powers[0], preview.powers[1]]
		hud.set_hint("Слияние?" if fusion_only else "Ваша способность?")
		hud.coach("ability", "Бой! Ворота ещё закрыты. Можно сыграть одну карту способности снизу (светящиеся доступны) или нажать «Пас». Каждая карта играется один раз за игру — береги сильные.")
		ability_panel.show_options(entries, hdr)
	else:
		hud.set_hint("Соперник думает...")
		var cid: StringName = ai.choose_ability(ctrl.get_view(AI_PLAYER), preview, ctrl.legal_abilities(AI_PLAYER))
		var err: int = OK
		if cid == &"":
			err = ctrl.pass_ability(AI_PLAYER)
		else:
			err = ctrl.play_ability(AI_PLAYER, cid)
		if err != OK:
			push_error("ИИ: ошибка способности %d" % err)


func _on_creature_chosen(uid: int) -> void:
	hud.hide_creatures()
	var err: int = ctrl.select_creature(HUMAN, uid)
	if err != OK:
		hud.set_hint("Нельзя выбрать это существо")
		_pending = {"kind": "throw", "player": HUMAN}
		_pump()


func _on_setup_skipped() -> void:
	if ctrl.skip_gate(HUMAN) != OK:
		hud.set_hint("Ворот на поле нет: карту нужно положить")
		_pending = {"kind": "setup", "player": HUMAN}
		_pump()
		return
	setup_panel.hide_panel()
	arena.set_highlight([])


func _on_setup_placed(card_id: StringName, slot: int) -> void:
	var err: int = ctrl.place_arena_card(HUMAN, card_id, slot)
	if err != OK:
		hud.set_hint("Нельзя положить карту в этот слот")
		_pending = {"kind": "setup", "player": HUMAN}
		_pump()
		return
	setup_panel.hide_panel()
	arena.set_highlight([])


func _on_ability_chosen(card_id: StringName) -> void:
	ability_panel.hide_panel()
	var err: int = ctrl.play_ability(HUMAN, card_id)
	if err != OK:
		hud.set_hint("Эту способность сейчас нельзя сыграть")
		_pending = {"kind": "ability", "player": HUMAN}
		_pump()


func _on_ability_passed() -> void:
	ability_panel.hide_panel()
	ctrl.pass_ability(HUMAN)
