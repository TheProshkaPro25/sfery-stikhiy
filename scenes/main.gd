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
var hover_tips: HoverTips
var _env: Environment
var _sun: DirectionalLight3D

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
var _gate_pick: Dictionary = {}   # «ворота + бросок»: выбранные карта и слот, ждём выбора существа
var _pip_idx: Dictionary = {}     # uid -> номер шарика на плашке бойца
var _stats: Dictionary = {"wins": [0, 0], "abilities": [0, 0], "traps": 0, "battles": []}  # итоги для экрана результата


## Перезапуск («ещё раз») и выход: отпускаем модели этого матча (видеопамять не копится от матча к матчу).
func _exit_tree() -> void:
	CreatureModels.clear()


func _ready() -> void:
	SoundFx.i()
	rng.randomize()
	_build_world()
	_build_ui()
	team_menu.deck_chosen.connect(_on_deck_chosen)


# ---------------------------------------------------------------- построение

## Небо статично (без TIME): иначе Godot пересчитывает кубическую карту отражений каждый кадр.
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
	float n = fbm(d * 2.2);
	float n2 = fbm(d * 4.5 + vec3(5.0));
	vec3 deep = vec3(0.012, 0.012, 0.03);
	vec3 neb1 = vec3(0.28, 0.08, 0.38);
	vec3 neb2 = vec3(0.04, 0.22, 0.32);
	vec3 col = deep + neb1 * smoothstep(0.45, 0.85, n) * 0.9 + neb2 * smoothstep(0.5, 0.9, n2) * 0.7;
	float band = exp(-abs(d.y - 0.05) * 7.0);
	col += vec3(0.25, 0.12, 0.3) * band * 0.35 * n;
	float st = step(0.9975, hash(floor(d * 420.0)));
	col += vec3(0.9, 0.9, 1.0) * st * (0.5 + 0.5 * sin(hash(floor(d * 420.0)) * 30.0));
	col *= smoothstep(-0.35, 0.05, d.y) * 0.85 + 0.15;
	COLOR = col;
}
"""


## Экспозиция кадра (подобрана по контактным листам: средняя яркость ~0.25–0.35 без пересвета).
const LIGHT_EXPOSURE := 1.0


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
	# без TIME в шейдере небо (и карта отражений) считается один раз, а не каждый кадр (режим REALTIME)
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.5
	# Ясный аниме-свет: заполняющий ambient — ровный холодно-лиловый цвет (тёмное небо почти не светит)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.52, 0.64)
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = LIGHT_EXPOSURE
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0  # без общего «молочного» ореола на ярком кадре
	env.glow_hdr_threshold = 1.1
	env.glow_strength = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.5  # большой радиус чернил впадины на моделях
	env.ssao_intensity = 1.0
	# туман к горизонту: поле без краёв, дальние ориентиры тонут в дымке цвета неба
	env.fog_enabled = true
	env.fog_light_color = Color(0.15, 0.13, 0.25)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	# Чёткие тени под размер поля: мягкий PCSS (1.5°) на огромной арене давал шумные кляксы.
	sun.light_angular_distance = 0.4
	sun.shadow_blur = 1.0
	sun.shadow_normal_bias = 1.5
	sun.shadow_opacity = 0.6  # тень от крыльев на теле не чернит модель целиком
	# каскады и дальность теней, SSAO, сглаживание — по уровню графики (GraphicsSettings, apply_graphics)
	world.add_child(sun)
	_env = env
	_sun = sun

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.9
	world.add_child(fill)

	cam = CameraRig.new()
	world.add_child(cam)
	cam.snap_overview()
	cam.current = true

	arena = ARENA_SCENE.instantiate() as Arena
	world.add_child(arena)
	apply_graphics()

	events = EventPlayer.new()
	add_child(events)
	throw_ctl = ThrowController.new()
	add_child(throw_ctl)


## Применить уровень графики (при старте и после смены в меню команды).
func apply_graphics() -> void:
	GraphicsSettings.apply_world(get_viewport(), _env, _sun)
	if arena != null:
		arena.apply_quality()


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
	hover_tips = HoverTips.new()
	hover_tips.resolver = _tip_at
	ui_layer.add_child(hover_tips)
	ui_layer.move_child(hover_tips, ui_layer.get_child_count() - 2)  # под меню, над остальным интерфейсом


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
	ctrl.landing_window = true  # окно прикрепления способности после приземления на пустые ворота
	ai = AIPlayer.new(AI_PLAYER, seed_value + 1, -1.0, TeamMenu.difficulty)
	_index_creatures()
	CreatureModels.preload_match(_defs.values())  # 6 моделей матча — в фоне, до первого раскрытия

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
	ctrl.ability_attached.connect(_on_ability_attached)
	ctrl.attach_window.connect(_on_attach_window)
	ctrl.gate_thrown.connect(_on_gate_thrown)
	ctrl.gate_trap_triggered.connect(_on_gate_trap)
	ctrl.momentum_changed.connect(_on_momentum_changed)
	ctrl.final_round_started.connect(_on_final_round)

	events.drained.connect(_pump)
	throw_ctl.throw_committed.connect(_on_throw_committed)
	hud.creature_chosen.connect(_on_creature_chosen)
	setup_panel.placed.connect(_on_setup_placed)
	setup_panel.skipped.connect(_on_setup_skipped)
	setup_panel.placed_throw.connect(_on_setup_placed_throw)
	hud.creature_cancelled.connect(_on_gate_throw_cancelled)
	ctrl.creature_relocated.connect(func(uid: int, a: int, b: int) -> void:
		_log("%s переходит на другие ворота" % _cname(uid))
		events.push(_anim_relocated.bind(uid, a, b)))
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
	var view: MatchState = ctrl.get_view(HUMAN)
	var cols: Array = [[], []]
	for p in range(2):
		var idx := 0
		for uid in view.players[p].creature_uids:
			cols[p].append(VisualUtil.attr_color(_creature_def(uid).attribute))
			_pip_idx[uid] = idx
			idx += 1
	hud.setup_plates(cols[0], cols[1])
	hud.set_names("Вы", "Соперник · %s" % AIPlayer.difficulty_name(TeamMenu.difficulty))
	hud.set_captures(0, 0)
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


# ---------------------------------------------------------------- подсказки для 3D-объектов

## Что под мышью: существо/шар (ближайшее по проекции) или карта ворот. {} — ничего.
func _tip_at(mp: Vector2) -> Dictionary:
	if ctrl == null or _game_over or hud._battle or team_menu.visible or cam == null:
		return {}
	var view: MatchState = ctrl.get_view(HUMAN)
	# существа и шар перед броском
	var best_uid := -1
	var best_d := 1e9
	for u in balls.keys():
		var b: CreatureBall = balls[u]
		if b == null or not is_instance_valid(b) or not b.visible:
			continue
		var base: Vector3 = b.global_position - Vector3(0, CreatureBall.RADIUS, 0)
		var on_field: bool = view.creature(u).slot >= 0
		var h: float = b.figure_height() if on_field else CreatureBall.RADIUS * 2.0
		var top: Vector3 = base + Vector3(0, h, 0)
		if cam.is_position_behind(base) or cam.is_position_behind(top):
			continue
		var p0: Vector2 = cam.unproject_position(base)
		var p1: Vector2 = cam.unproject_position(top)
		var rad: float = maxf(24.0, p0.distance_to(p1) * 0.22)
		var d: float = Geometry2D.get_closest_point_to_segment(mp, p0, p1).distance_to(mp)
		if d < rad and d / rad < best_d:
			best_d = d / rad
			best_uid = u
	if best_uid >= 0:
		return {"key": "c%d" % best_uid, "lines": _creature_tip(best_uid, view)}
	# карты ворот: попадание в проекцию прямоугольника карты
	for i in range(view.slots.size()):
		var sl: SlotState = view.slots[i]
		var c: Vector3 = arena.slot_position(i)
		var hw: float = Arena.CARD_W * 0.5
		var hh: float = Arena.CARD_H * 0.5
		var poly := PackedVector2Array()
		var ok := true
		for corner in [Vector3(-hw, 0, -hh), Vector3(hw, 0, -hh), Vector3(hw, 0, hh), Vector3(-hw, 0, hh)]:
			var wp: Vector3 = c + corner
			if cam.is_position_behind(wp):
				ok = false
				break
			poly.append(cam.unproject_position(wp))
		if not ok or not Geometry2D.is_point_in_polygon(mp, poly):
			continue
		var lines: Array = _slot_tip(i, sl, view)
		if not lines.is_empty():
			return {"key": "s%d:%s" % [i, str(sl.card_id) + str(sl.revealed)], "lines": lines}
	return {}


func _slot_tip(i: int, sl: SlotState, view: MatchState) -> Array:
	if not sl.has_card:
		if ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == HUMAN and ctrl.legal_setup_slots().has(i):
			return ["Свободное место", "Выкладка ворот", UiTheme.GOLD, "Сюда можно положить карту ворот: рядом с уже лежащими картами.", "Бросок на пустое место — промах.", "", ""]
		return []
	var mine: bool = sl.card_owner == HUMAN
	var occ := ""
	if sl.occupant_uid >= 0:
		occ = "На воротах стоит: %s (%s)." % [_cname(sl.occupant_uid), "ваше" if _owner_of(sl.occupant_uid) == HUMAN else "существо соперника"]
	var def: CardDef = CardDB.card(sl.card_id)
	if def == null:
		return ["Закрытые ворота соперника", "Ворота · рубашкой вверх", UiTheme.GOLD_DIM,
			"Карту видно только в бою, когда ворота открываются. Там может быть бонус силы или ловушка.", "Закрытая карта соперника.", "", occ]
	var lines: Array = UiTheme.card_help(def)
	if not sl.revealed:
		lines[1] = "%s · ваша закрытая карта" % lines[1] if mine else lines[1]
		lines[5] = "Соперник не видит эту карту до боя. " + str(lines[5]) if mine else lines[5]
	lines[6] = (str(lines[6]) + "\n" + occ).strip_edges() if occ != "" else lines[6]
	return lines


func _creature_tip(uid: int, view: MatchState) -> Array:
	var d: CreatureDef = _creature_def(uid)
	var cs: CreatureState = view.creature(uid)
	var lines: Array = UiTheme.creature_help(d)
	var mine: bool = _owner_of(uid) == HUMAN
	lines[1] = "%s · %s" % [lines[1], "ваше существо" if mine else "существо соперника"]
	var power: int = d.base_power
	var extra: Array[String] = ["Базовая сила: %d" % power]
	if cs.slot >= 0:
		var sl: SlotState = view.slots[cs.slot]
		var cd: CardDef = CardDB.card(sl.card_id)
		# сила с воротами: бонус открытой карты своей стихии (те же правила, что в PowerCalc — CardEffects.arena_delta)
		if sl.revealed and cd != null:
			var gate: int = CardEffects.arena_delta(cd, false, d.attribute, power, power, PowerCalc._owner_attr(view, sl.card_owner))
			if gate != 0:
				extra.append("Сила %d %s %d ворота = %d" % [power, "+" if gate > 0 else "−", absi(gate), power + gate])
			else:
				extra.append("Сила %d (ворота бонуса не дают)" % power)
		else:
			extra.append("Сила %d (ворота закрыты)" % power)
		extra.append("Стоит на воротах №%d%s" % [cs.slot + 1, (": «%s»" % cd.display_name) if cd != null else " (карта закрыта)"])
	else:
		extra.append("Шар: потяни мышь назад и отпусти, чтобы бросить" if mine else "Шар соперника")
	if not cs.attached.is_empty():
		var names: Array[String] = []
		for a in cs.attached:
			names.append("«%s»" % _card_name(StringName(a[1])))
		extra.append("Прикреплено: " + ", ".join(names))
	lines[6] = "\n".join(extra)
	return lines


## Строка в ленту событий — в порядке очереди анимаций.
func _log(text: String, c: Color = UiTheme.TEXT) -> void:
	events.push(func() -> void: hud.log_event(text, c))


func _say(player: int, you: String, foe: String) -> String:
	return you if player == HUMAN else foe


# ---------------------------------------------------------------- обработчики сигналов контроллера
# Состояние контроллера уже изменено; здесь только ставим анимации в очередь.

func _on_phase_changed(phase: int, active_player: int) -> void:
	events.push(_anim_phase.bind(phase, active_player))


func _on_setup_requested(player: int) -> void:
	events.push(_anim_set_pending.bind({"kind": "setup", "player": player}))


func _on_arena_card_placed(player: int, slot: int) -> void:
	_log(_say(player, "Вы кладёте карту ворот", "Соперник кладёт карту ворот"))
	events.push(_anim_card_placed.bind(player, slot))


func _on_throw_requested(player: int) -> void:
	events.push(_anim_set_pending.bind({"kind": "throw", "player": player}))


func _on_creature_selected(player: int, uid: int, recalled: bool) -> void:
	_log("%s: %s" % [_say(player, "Вы бросаете", "Соперник бросает"), _cname(uid)])
	events.push(_anim_selected.bind(player, uid, recalled))


func _on_creature_returned(uid: int, reason: StringName) -> void:
	if reason == &"miss":
		_log("Промах: %s" % _cname(uid), Color(1.0, 0.7, 0.6))
	events.push(_anim_returned.bind(uid, reason))


func _on_creature_stood(uid: int, slot: int) -> void:
	_log("%s встаёт на ворота" % _cname(uid))
	events.push(_anim_stood.bind(uid, slot))


func _on_battle_started(slot: int, attacker_uid: int, defender_uid: int) -> void:
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	var mo: Array = [pre.momentum[0], pre.momentum[1]] if pre != null else [0, 0]
	_log("Бой: %s против %s" % [_cname(attacker_uid), _cname(defender_uid)], UiTheme.GOLD)
	events.push(_anim_battle_started.bind(slot, attacker_uid, defender_uid, pw, mo))


func _on_card_revealed(slot: int, card_id: StringName) -> void:
	events.push(_anim_card_revealed.bind(slot, card_id))


func _on_ability_window(player: int, _options: Array) -> void:
	# Список карт берётся при ответе из ctrl.legal_abilities(player).
	events.push(_anim_set_pending.bind({"kind": "ability", "player": player}))


func _on_ability_played(player: int, card_id: StringName) -> void:
	_refresh_hand()
	_stats["abilities"][player] += 1
	_log("%s «%s»" % [_say(player, "Вы играете", "Соперник играет"), _card_name(card_id)], Color(0.75, 0.6, 1.0))
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	events.push(_anim_ability_msg.bind(player, card_id, false, pw))


func _on_ability_cancelled(player: int, card_id: StringName) -> void:
	events.push(_anim_ability_msg.bind(player, card_id, true))


func _on_battle_resolved(result: BattleResult) -> void:
	_refresh_hand()
	var win_p: int = _owner_of(result.winner_uid)
	var atk_won: bool = result.winner_uid == result.attacker_uid
	var wp: int = result.powers[0 if atk_won else 1]
	var lp: int = result.powers[1 if atk_won else 0]
	_stats["wins"][win_p] += 1
	_stats["battles"].append({"turn": ctrl.get_turn(), "winner": _cname(result.winner_uid), "loser": _cname(result.loser_uid),
		"wp": wp, "lp": lp, "mine": win_p == HUMAN})
	_log("Побеждает %s (%d : %d)" % [_cname(result.winner_uid), wp, lp], Color(0.6, 1.0, 0.6) if win_p == HUMAN else Color(1.0, 0.6, 0.55))
	events.push(_anim_battle_resolved.bind(result))


func _on_creature_eliminated(uid: int) -> void:
	events.push(_anim_remove_ball.bind(uid, true))
	events.push(func() -> void: hud.kill_creature(_owner_of(uid), int(_pip_idx.get(uid, -1))))


func _on_card_captured(player: int, slot: int, _card_id: StringName) -> void:
	_log("%s: ворота захвачены" % _say(player, "Вы", "Соперник"), UiTheme.GOLD)
	events.push(_anim_captured.bind(player, slot))


func _on_turn_started(player: int, turn: int) -> void:
	_refresh_hand()
	events.push(_anim_turn.bind(player, turn))


func _on_ability_attached(player: int, uid: int, card_id: StringName) -> void:
	_refresh_hand()
	_stats["abilities"][player] += 1
	_log("%s «%s» → %s" % [_say(player, "Вы прикрепляете", "Соперник прикрепляет"), _card_name(card_id), _cname(uid)], Color(0.75, 0.6, 1.0))
	events.push(_anim_attached.bind(player, uid, card_id))


func _on_attach_window(player: int, _uid: int, _options: Array) -> void:
	events.push(_anim_set_pending.bind({"kind": "attach", "player": player}))


func _on_gate_thrown(player: int, slot: int, uid: int) -> void:
	_log("%s: ворота + бросок" % _say(player, "Вы", "Соперник"), UiTheme.GOLD)
	events.push(_anim_gate_thrown.bind(player, slot, uid))


func _on_gate_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	_stats["traps"] += 1
	_log("ЛОВУШКА: %s" % _card_name(card_id), Color(1.0, 0.45, 0.35))
	events.push(_anim_trap.bind(slot, card_id, effect))


func _on_momentum_changed(player: int, value: int) -> void:
	events.push(_anim_momentum.bind(player, value))


func _on_final_round(player: int) -> void:
	_log("ФИНАЛЬНЫЙ БОЙ", Color(1.0, 0.45, 0.35))
	events.push(_anim_final_round.bind(player))


func _on_game_over(winner: int, reason: StringName) -> void:
	ability_panel.set_dock_visible(false)
	events.push(_anim_game_over.bind(winner, reason))


# ---------------------------------------------------------------- анимации (выполняются EventPlayer)

var _alive: Array[int] = [3, 3]
var _battle_uids: Array[int] = []  # [атакующий, защитник] текущего боя (для эффектов способностей)  # живые существа по ходу анимаций (для строки статуса)


func _refresh_status() -> void:
	hud.set_status(_turn, _active, _alive[0], _alive[1])
	hud.set_captures(captures[0], captures[1])


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


func _card_name(id: StringName) -> String:
	var c: CardDef = CardDB.card(id)
	return c.display_name if c != null else String(id)


## Карта прикреплена к существу вне боя: вспышка у шара, карта соперника показывается обоим.
func _anim_attached(player: int, uid: int, card_id: StringName) -> void:
	_refresh_hand()
	SoundFx.i().play("ability_play")
	ability_panel.show_played(card_id, player != HUMAN)
	var b: CreatureBall = balls.get(uid)
	if b != null:
		b.ability_pulse()
		var c: Color = VisualUtil.attr_color(_creature_def(uid).attribute).lightened(0.3)
		VisualUtil.ring_wave(world, b.global_position - Vector3(0, CreatureBall.RADIUS - 0.1, 0), c, Arena.CARD_W * 0.6, 0.6)
	hud.flash("%s «%s» к %s" % [_say(player, "Вы прикрепляете", "Соперник прикрепляет"), _card_name(card_id), _cname(uid)])
	await _wait(1.0)
	hud.clear_flash()
	if player == HUMAN and ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and throw_ctl.is_enabled():
		_show_pre_throw()


func _anim_gate_thrown(player: int, _slot: int, uid: int) -> void:
	SoundFx.i().play("card_select")
	hud.set_hint("Ворота + бросок: %s летит на новую карту" % _cname(uid))
	await hud.banner("ВОРОТА + БРОСОК", "%s: карта и бросок за один ход" % _say(player, "Вы", "Соперник"), UiTheme.GOLD, 0.55)


func _anim_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	var sub: String = "Ловушка сработала"
	match effect:
		&"seal":
			sub = "Все способности этого боя сгорают"
		&"mirror":
			sub = "Силы бойцов меняются местами"
		&"backflow":
			sub = "Преимущество стихии получает тот, кого бьют"
	SoundFx.i().play("clash", -4.0)
	SoundFx.i().play_later("power_down", 0.15, -3.0)
	cam.impact(arena.slot_position(slot) + Vector3(0, Arena.CARD_H * 0.2, 0))
	cam.shake(0.7, 0.4)
	hud.screen_flash(Color(1.0, 0.3, 0.2, 0.35))
	await hud.banner("ЛОВУШКА!  %s" % _card_name(card_id).to_upper(), sub, Color(1.0, 0.35, 0.3), 0.9)
	cam.battle_wide()


func _anim_momentum(player: int, value: int) -> void:
	hud.set_momentum(player, value)
	if value > 0:
		SoundFx.i().play("power_up", -8.0)
		hud.log_event("%s: натиск +%d к силе" % [_say(player, "Вы", "Соперник"), value * PowerCalc.MOMENTUM_STEP], Color(1.0, 0.7, 0.3))


func _anim_final_round(_player: int) -> void:
	hud.set_final_round(true)
	SoundFx.i().play("battle_start", 0.0)
	cam.shake(0.8, 0.5)
	hud.screen_flash(Color(1.0, 0.5, 0.3, 0.3))
	await hud.banner("ФИНАЛЬНЫЙ БОЙ", "Остались последние существа: преимущество стихии ×2", Color(1.0, 0.5, 0.25), 1.2)


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
	# короткий наезд после приземления (его начал _on_ball_settled), потом кат на облёт
	if cam.mode == CameraRig.Mode.STATIC and not cam.is_overview():
		await _wait(0.4)
	var facing := Vector3(0.0, 0.0, -1.0 if _owner_of(uid) == HUMAN else 1.0)
	b.freeze_at(arena.slot_position(slot) + Vector3(0.0, BALL_Y + 0.02, 0.0))
	b.face_toward(b.global_position + facing)
	var orbit_t: float = cam.reveal_orbit(arena.slot_position(slot), b.figure_height(), facing, b.figure_size())
	_focus_labels([uid])
	SoundFx.i().play("ball_land", -3.0)
	VisualUtil.ring_wave(world, arena.slot_position(slot) + Vector3(0, 0.08, 0), VisualUtil.attr_color(_creature_def(uid).attribute), Arena.CARD_W * 0.7, 0.55)
	SoundFx.i().play_later("capsule_open", 0.05)
	_cry(uid, "appear", 0.4)
	b.open_animated()
	b.roar(0.65)
	get_tree().create_timer(0.8).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	await _wait(orbit_t)
	# кат на общий план
	cam.snap_overview()
	await _wait(0.3)


func _anim_battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = [], momentum: Array = [0, 0]) -> void:
	arena.set_highlight([slot])
	var atk: CreatureBall = balls.get(attacker_uid)
	var dfn: CreatureBall = balls.get(defender_uid)
	var base := arena.slot_position(slot)
	# короткий наезд после приземления атакующего, затем кат на общий план боя
	if cam.mode == CameraRig.Mode.STATIC and not cam.is_overview():
		await _wait(0.4)
	var h: float = maxf(atk.figure_height() if atk != null else 0.0, dfn.figure_height() if dfn != null else 0.0)
	cam.battle_view(base, h)
	hud.set_battle_mode(true)
	_battle_uids = [attacker_uid, defender_uid]
	if powers.size() == 2:
		battle_hud.open([_cname(attacker_uid), _cname(defender_uid)], [_creature_def(attacker_uid).attribute, _creature_def(defender_uid).attribute], powers, momentum)
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
	# общий план лицом к лицу → кат на крупный план каждого при рёве → снова общий план
	_cry(attacker_uid, "attack", 0.85)
	_cry(defender_uid, "attack", 1.65, -4.0)
	if atk != null:
		atk.roar(0.85)
	if dfn != null:
		dfn.roar(1.65)
	get_tree().create_timer(0.95).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	get_tree().create_timer(1.75).timeout.connect(func() -> void: cam.shake(0.25, 0.2))
	await _wait(0.7)
	if atk != null and is_instance_valid(atk):
		cam.close_up(atk.global_position - Vector3(0, CreatureBall.RADIUS, 0), -Vector3(0, 0, dz), atk.figure_height(), atk.figure_size())
	await _wait(0.8)
	if dfn != null and is_instance_valid(dfn):
		cam.close_up(dfn.global_position - Vector3(0, CreatureBall.RADIUS, 0), Vector3(0, 0, dz), dfn.figure_height(), dfn.figure_size())
	await _wait(0.8)
	cam.battle_wide(true)
	await _wait(0.35)


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
		_anim_ability_cam(player)
		_ability_fx(player, c)
	if cancelled:
		hud.flash("%s «%s» отменена" % ["Ваша карта" if player == HUMAN else "Карта соперника", cname])
	else:
		hud.flash(("Вы играете «%s»" if player == HUMAN else "Соперник играет «%s»") % cname)
	await _wait(1.1)
	hud.clear_flash()
	if not cancelled and _battle_uids.size() == 2:
		cam.battle_wide()


## Кат на автора способности с рывком камеры.
func _anim_ability_cam(player: int) -> void:
	if _battle_uids.size() != 2:
		return
	var mine: int = _battle_uids[0] if _owner_of(_battle_uids[0]) == player else _battle_uids[1]
	var foe: int = _battle_uids[1] if mine == _battle_uids[0] else _battle_uids[0]
	var mb: CreatureBall = balls.get(mine)
	var fb: CreatureBall = balls.get(foe)
	if mb == null:
		return
	var facing: Vector3 = (fb.global_position - mb.global_position) if fb != null else Vector3(0, 0, 1)
	cam.ability_jerk(mb.global_position - Vector3(0, CreatureBall.RADIUS, 0), facing, mb.figure_height(), mb.figure_size())


func _anim_battle_resolved(result: BattleResult) -> void:
	arena.set_highlight([])
	battle_hud.set_powers([result.powers[0], result.powers[1]])
	await _wait(0.6)
	# удар: победитель бросается на соперника, вспышка, тряска, проигравший рассыпается
	var wb: CreatureBall = balls.get(result.winner_uid)
	var lb: CreatureBall = balls.get(result.loser_uid)
	_cry(result.winner_uid, "attack", 0.0)
	var wh: float = wb.figure_height() if wb != null else 10.0
	if wb != null and lb != null:
		# удар: быстрый наезд в точку столкновения
		cam.impact((wb.global_position + lb.global_position) * 0.5 + Vector3(0, wh * 0.45, 0))
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
	await _wait(0.5)
	# победитель: медленный облёт
	if wb != null and is_instance_valid(wb):
		var orbit_t: float = cam.winner_orbit(wb.global_position - Vector3(0, CreatureBall.RADIUS, 0), wh, wb.figure_size())
		await _wait(minf(orbit_t, 1.7))
	else:
		await _wait(0.6)
	battle_hud.close()
	hud.set_battle_mode(false)
	cam.snap_overview()  # кат на общий план после боя
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
	_stats["alive"] = [_alive[0], _alive[1]]
	_stats["captures"] = [captures[0], captures[1]]
	_stats["turns"] = ctrl.get_turn()
	game_over_ui.show_result(winner, _reason_text(reason), _stats)


# ---------------------------------------------------------------- физика / ввод

func _on_throw_committed(impulse: Vector3) -> void:
	ability_panel.hide_panel()
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
		"attach":
			want = MatchController.Phase.AFTER_LANDING
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
			if player == HUMAN:
				_show_pre_throw()
		"ability":
			_do_ability(player)
		"attach":
			_do_attach(player)


func _do_setup(player: int) -> void:
	if player == HUMAN:
		var cards: Array = []
		for cid in ctrl.get_view(HUMAN).players[HUMAN].arena_hand:
			var c: CardDef = CardDB.card(cid)
			cards.append({"id": c.id, "name": c.display_name, "text": c.text})
		var legal: Array[int] = ctrl.legal_setup_slots()
		arena.set_highlight(legal)
		hud.set_hint("Карта ворот на поле? Положите карту или пропустите" if ctrl.can_skip_gate() else "Положите карту ворот на поле")
		setup_panel.begin(cards, legal, ctrl.can_skip_gate(), not _throwable_entries().is_empty())
		hud.coach("gate", "Карта ворот — поле боя: выбери карту и место (подсвечено). Соперник не видит её до боя — там могут быть ловушки. «Ворота + бросок» — положить карту и сразу бросить на неё существо.")
	else:
		hud.set_hint("Соперник выбирает карту ворот...")
		var choice: Dictionary = ai.choose_setup(ctrl.get_view(AI_PLAYER), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
		var err: int = OK
		if choice.is_empty():
			err = ctrl.skip_gate(AI_PLAYER)
		elif int(choice.get("throw_uid", -1)) >= 0:
			# «ворота + бросок»: цель броска — только что положенная карта
			_ai_target_slot = int(choice["slot"])
			err = ctrl.throw_with_gate(AI_PLAYER, choice["card_id"], int(choice["slot"]), int(choice["throw_uid"]))
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
			var note := "с карты" if view.creature(u).slot >= 0 else ""
			entries.append({"uid": u, "def": d, "text": "Существо #%d" % u, "note": note})
		hud.set_hint("Ваш бросок: выберите шар-существо")
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
		cam.aim_view(b.global_position, 1.0)
		_focus_labels([])
		hud.set_hint("Потяните мышь назад от шара и отпустите (ПКМ - отмена)")
		hud.coach("throw", "Бросок как из рогатки: зажми левую кнопку, потяни мышь назад от шара и отпусти. Чем дальше тянешь, тем сильнее бросок. Цель — попасть на карту ворот.")
		throw_ctl.enable(b)
	else:
		# кат за спину соперника, пауза-замах, затем рывок камеры вслед за шаром
		cam.throw_view(b.global_position, -1.0)
		_focus_labels([])
		var to := Vector3(0.0, 0.0, 6.0)
		if _ai_target_slot >= 0:
			to = arena.slot_position(_ai_target_slot)
		var imp := ThrowController.impulse_for_target(b.global_position, to, ai.get_aim_error(), rng)
		await get_tree().create_timer(0.55).timeout
		if _game_over or not is_instance_valid(b) or _active_ball != b:
			return
		SoundFx.i().play("ball_throw", -3.0)
		b.launch(imp)
		cam.follow(b)


func _do_ability(player: int) -> void:
	var preview: BattleResult = ctrl.get_battle_preview()
	if preview == null:
		push_error("Окно способностей без предпросмотра боя")
		return
	battle_hud.set_chain(preview.plays, preview.passed)
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		var hdr := "Бой: %s (%d) против %s (%d). Ваша карта?" % [
			_cname(preview.attacker_uid), preview.powers[0], _cname(preview.defender_uid), preview.powers[1]]
		var fusion_only := not entries.is_empty()
		for e in entries:
			if not CardEffects.is_fusion(CardDB.card(e["id"])):
				fusion_only = false
		if fusion_only:
			hdr = "Слияние: добавьте карту поверх своей способности (%d против %d) или пас" % [preview.powers[0], preview.powers[1]]
		var my_side: int = 0 if _owner_of(preview.attacker_uid) == HUMAN else 1
		var note := "Пас окончателен: больше карт в этом бою вы не сыграете."
		if preview.passed.size() == 2 and preview.passed[1 - my_side]:
			note = "Соперник уже спасовал — отвечать будет нечем. " + note
		hud.set_hint("Слияние?" if fusion_only else "Ваша способность?")
		hud.coach("ability", "Бой! Ворота ещё закрыты. Карты играются по очереди, не больше 3 на бой. Светящиеся — доступны. «Пас» окончателен: соперник сможет доиграть, а вы уже нет.")
		ability_panel.show_options(entries, hdr, {"moment": &"battle", "used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN),
			"pass_text": "Пас", "pass_tip": "Закончить обмен картами в этом бою. Назад дороги нет.", "note": note})
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


## Окно «после приземления»: прикрепить способность к существу, что встало на пустые ворота, или завершить ход.
func _do_attach(player: int) -> void:
	var uid: int = ctrl.get_landed_uid()
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		hud.set_hint("%s на воротах: прикрепить способность?" % _cname(uid))
		hud.coach("attach", "Существо встало на пустые ворота. Можно прикрепить карту: она сработает в его следующем бою (видна сопернику). Или завершить ход без неё.")
		ability_panel.show_options(entries, "Прикрепить способность к «%s»?" % _cname(uid), {"moment": &"after_landing",
			"used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN), "pass_text": "Завершить ход",
			"pass_tip": "Не прикреплять карту — ход переходит сопернику.",
			"note": "Прикреплённая карта входит в лимит 3 карт на бой."})
	else:
		hud.set_hint("Соперник думает...")
		var cid: StringName = ai.choose_attach(ctrl.get_view(AI_PLAYER), uid, ctrl.legal_abilities(AI_PLAYER))
		var err: int = OK
		if cid == &"":
			err = ctrl.pass_ability(AI_PLAYER)
		else:
			err = ctrl.play_ability(AI_PLAYER, cid)
		if err != OK:
			push_error("ИИ: ошибка прикрепления %d" % err)


## До броска: рука приподнята, играбельные карты светятся; карта прикрепится к выбранному существу.
func _show_pre_throw() -> void:
	if _game_over or ctrl.get_phase() != MatchController.Phase.AWAIT_LANDING:
		return
	var legal: Array[StringName] = ctrl.legal_abilities(HUMAN)
	if legal.is_empty():
		return
	var entries: Array = []
	for cid in legal:
		var c: CardDef = CardDB.card(cid)
		entries.append({"id": c.id, "name": c.display_name, "text": c.text})
	var uid: int = ctrl.get_selected_uid()
	hud.coach("prethrow", "Перед броском можно прикрепить способность к шару: она сработает в его бое. Это необязательно — просто бросай.")
	ability_panel.show_options(entries, "До броска: прикрепить карту к «%s» (необязательно)" % _cname(uid), {"moment": &"pre_throw",
		"used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN), "note": ""})


## Существа, которых можно бросить в фазе выкладки (в руке, не на воротах и не в зоне использованных).
func _throwable_entries() -> Array:
	var view: MatchState = ctrl.get_view(HUMAN)
	var entries: Array = []
	for u in view.players[HUMAN].creature_uids:
		var cs: CreatureState = view.creature(u)
		if cs.alive and cs.slot < 0 and not cs.used:
			entries.append({"uid": u, "def": _creature_def(u), "text": "Существо #%d" % u, "note": ""})
	return entries


func _on_setup_placed_throw(card_id: StringName, slot: int) -> void:
	var entries: Array = _throwable_entries()
	if entries.is_empty():
		_on_setup_placed(card_id, slot)
		return
	_gate_pick = {"card": card_id, "slot": slot}
	setup_panel.hide_panel()
	arena.set_highlight([slot])
	hud.set_hint("Ворота + бросок: кого бросить на новую карту?")
	hud.show_creatures(entries, "Кого бросить на новые ворота?", true)


func _on_gate_throw_cancelled() -> void:
	_gate_pick = {}
	hud.hide_creatures()
	_do_setup(HUMAN)


func _on_creature_chosen(uid: int) -> void:
	hud.hide_creatures()
	if not _gate_pick.is_empty():
		var pick: Dictionary = _gate_pick
		_gate_pick = {}
		arena.set_highlight([])
		var gerr: int = ctrl.throw_with_gate(HUMAN, pick["card"], int(pick["slot"]), uid)
		if gerr != OK:
			hud.set_hint("Не получилось: ворота + бросок")
			_do_setup(HUMAN)
		return
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
	var moment: StringName = ctrl.get_ability_moment()
	ability_panel.hide_panel()
	var err: int = ctrl.play_ability(HUMAN, card_id)
	if err != OK:
		hud.set_hint("Эту способность сейчас нельзя сыграть")
		match moment:
			&"after_landing":
				_pending = {"kind": "attach", "player": HUMAN}
			&"pre_throw":
				_show_pre_throw()
				return
			_:
				_pending = {"kind": "ability", "player": HUMAN}
		_pump()


func _on_ability_passed() -> void:
	ability_panel.hide_panel()
	ctrl.pass_ability(HUMAN)
