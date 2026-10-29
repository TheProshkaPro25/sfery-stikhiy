extends SceneTree
## Headless-тесты ядра. Запуск:
##   godot --headless --import            (один раз, чтобы построился кэш class_name)
##   godot --headless -s res://tests/run_tests.gd
## Код выхода: 0 — всё прошло, 1 — есть ошибки.

const SIM_MATCHES: int = 200
const SIM_STEP_CAP: int = 3000
const HIT_CHANCE: float = 0.65

## Тестовые существа по одному на стихию (порядок = Attr.A) с фиксированной БС: расчёт боя проверяется
## на них, а не на игровом составе — баланс состава можно менять, не переписывая ожидаемые числа.
## Виды тестовых существ: Пламя — Драгнар, Буря — Грифалон, Свет — Ратник, Камень — Колоссар, Тень — Горгул, Прилив — Левиан.
const ZH: StringName = &"test_fire"
const VI: StringName = &"test_gale"
const LU: StringName = &"test_light"
const GR: StringName = &"test_stone"
const SU: StringName = &"test_shadow"
const MA: StringName = &"test_tide"
const TEST_POWER: Array = [340, 300, 330, 370, 350, 320]
const TEST_SPECIES: Array = [&"dragnar", &"grifalon", &"ratnik", &"kolossar", &"gorgul", &"levian"]
## Тестовые карты (только в словаре CardDB, не в пуле): нейтральные ворота и простые способности без замков.
const NEUTRAL: StringName = &"arena_test_neutral"
const PLUS: StringName = &"ability_test_plus80"
const MINUS: StringName = &"ability_test_minus80"
const SHIELD: StringName = &"ability_test_shield"

var _failures: int = 0
var _checks: int = 0
var _go_winner: int = -2
var _go_reason: StringName = &""


## Тестовые существа и карты кладутся только в словари определений: в creature_ids()/arena_ids() и случайные колоды они не попадают.
func _add_test_creatures() -> void:
	var ids: Array[StringName] = [ZH, VI, LU, GR, SU, MA]
	for a in ids.size():
		var d: CreatureDef = CreatureDef.make(ids[a], String(ids[a]), a, TEST_POWER[a], Color.WHITE)
		d.species = TEST_SPECIES[a]
		CardDB._creatures[String(ids[a])] = d
	var rows: Array = [
		[NEUTRAL, "Нейтральные ворота", 0, &"none", {}],
		[PLUS, "Тест +80", 1, &"boost", {"amount": 80}],
		[MINUS, "Тест −80", 1, &"weaken", {"amount": 80}],
		[SHIELD, "Тест отмена", 1, &"negate", {"amount": 0}],
	]
	for row in rows:
		var c: CardDef = CardDef.make(row[0], row[1], row[2], row[3], row[4], "")
		if c.kind == CardDef.Kind.ARENA:
			c.params["g"] = [0, 0, 0, 0, 0, 0]
		CardDB._cards[String(c.id)] = c


## Колоды сценариев матча из тестовых существ: планы боёв в тестах опираются на эти БС.
func _test_deck(index: int) -> DeckDef:
	if index % 2 == 0:
		return CardDB.build_deck([ZH, LU, GR], [&"arena_field_fire", &"arena_den_dragnar", &"arena_funnel"], [PLUS, SHIELD, MINUS])
	return CardDB.build_deck([VI, SU, MA], [&"arena_field_tide", &"arena_mirror", &"arena_web"], [PLUS, SHIELD, MINUS])


func _initialize() -> void:
	CardDB.load_all()
	_add_test_creatures()
	_test_battle_foundation()
	_test_turn_draw()
	_test_model_material_isolation()
	_test_card_db()
	_test_deck_builder()
	_test_attribute_table()
	_test_tie_goes_to_defender()
	_test_gate_cards()
	_test_element_abilities()
	_test_ladder()
	_test_species_abilities()
	_test_negate_chain()
	_test_fusion_and_locks()
	_test_exchange()
	_test_attach_moments()
	_test_gate_throw()
	_test_traps_in_match()
	_test_gust()
	_test_swap_fighter()
	_test_shift_gate()
	_test_ebb()
	_test_both_lose()
	_test_hold()
	_test_revive()
	_test_marks()
	_test_recall_and_returns()
	_test_recharge()
	_test_silence_and_lockout()
	_test_momentum()
	_test_final_round()
	_test_ai_levels()
	_test_hidden_info()
	_test_used_zone_refill()
	_test_gate_placement_rules()
	_test_win_by_three_captures()
	_test_own_gate()
	_test_no_recall_and_standoff()
	_test_turn_limit()
	_test_determinism()
	_test_simulation()
	await _test_attack_fx()
	await _test_ball_owner_marks()
	print("")
	print("Проверок: %d, ошибок: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- утилиты

## Эффекты удара AttackFx: каждая стихия на каждом уровне графики создаёт узлы и все их освобождает по окончании.
func _test_attack_fx() -> void:
	var fx = load("res://scenes/attack_fx.gd")
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var old_level: int = GraphicsSettings.level
	for lvl in 3:
		GraphicsSettings.force_level(lvl)
		for attr in 6:
			var dur: float = fx.play(host, attr, Vector3(-3, 0, 0), Vector3(3, 0, 0), 4.0, 3.0, 4.0)
			_check(dur > 0.4 and dur < 1.0, "AttackFx: длительность стихии %d (уровень %d): %f" % [attr, lvl, dur])
			_check(host.get_child_count() > 0, "AttackFx: стихия %d создаёт узлы" % attr)
	await create_timer(1.6).timeout
	_check(host.get_child_count() == 0, "AttackFx: узлы освобождены (осталось %d)" % host.get_child_count())
	_check(fx.play(null, 0, Vector3.ZERO, Vector3.ONE, 1.0, 1.0) == 0.0, "AttackFx: без родителя ничего не делает")
	GraphicsSettings.level = old_level
	host.queue_free()


## Шар существа: setup (и повторный) не уничтожает кольцо владельца; раскрытие ставит ему материал без ошибок.
func _test_ball_owner_marks() -> void:
	CardDB.load_all()
	var b = load("res://scenes/creature_ball.tscn").instantiate()
	root.add_child(b)
	b.setup(CardDB.creature(CardDB.creature_ids()[0]), 1)
	b.setup(CardDB.creature(CardDB.creature_ids()[1]), 1)
	await process_frame
	_check(is_instance_valid(b._foot_ring) and b._foot_ring.get_parent() == b._figure, "CreatureBall: кольцо владельца живо после setup")
	b.freeze_at(Vector3(0, 1, -5))
	b.open_animated(false)
	await process_frame
	_check(is_instance_valid(b._foot_ring) and b._foot_ring.material_override != null, "CreatureBall: раскрытие ставит материал кольцу")
	b.queue_free()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: " + msg)


func _on_game_over(w: int, reason: StringName) -> void:
	_go_winner = w
	_go_reason = reason


## Бой uid 0 (P0, атакует) против uid 1 (P1, защищает) на воротах card в слоте 0; ворота принадлежат P1.
func _mk_state(atk_id: StringName, def_id: StringName, card_id: StringName) -> MatchState:
	var st: MatchState = MatchState.new()
	st.ruleset = MatchRules.Ruleset.LEGACY
	st.creatures[0] = CreatureState.new(0, atk_id, 0)
	st.players[0].creature_uids.append(0)
	st.creatures[1] = CreatureState.new(1, def_id, 1)
	st.players[1].creature_uids.append(1)
	st.creatures[1].slot = 0
	st.slots[0].occupant_uid = 1
	st.slots[0].card_id = card_id
	st.slots[0].card_owner = 1
	st.slots[0].has_card = card_id != &""
	return st


## Добавить в состояние существо игрока p (uid), стоящее в слоте slot (-1 — в руке); alive = false — выбывшее.
func _add_creature(st: MatchState, uid: int, def_id: StringName, p: int, slot: int = -1, alive: bool = true) -> void:
	var c: CreatureState = CreatureState.new(uid, def_id, p)
	c.alive = alive
	c.slot = slot
	st.creatures[uid] = c
	st.players[p].creature_uids.append(uid)
	if slot >= 0:
		st.slots[slot].occupant_uid = uid
		st.slots[slot].has_card = true
		if st.slots[slot].card_id == &"":
			st.slots[slot].card_id = NEUTRAL


func _calc(st: MatchState, a: StringName = &"", d: StringName = &"") -> BattleResult:
	return PowerCalc.compute(st, 0, 1, 0, a, d)


func _seq(st: MatchState, plays: Array) -> BattleResult:
	return PowerCalc.compute_seq(st, 0, 1, 0, plays)


func _expect(label: String, atk_id: StringName, def_id: StringName, card_id: StringName, a: StringName, d: StringName, e0: int, e1: int) -> BattleResult:
	var st: MatchState = _mk_state(atk_id, def_id, card_id)
	var r: BattleResult = _calc(st, a, d)
	_check(r.powers[0] == e0 and r.powers[1] == e1, "%s: ожидалось %d:%d, получено %d:%d" % [label, e0, e1, r.powers[0], r.powers[1]])
	return r


func _mk_deck(cs: Array, arena: Array, abil: Array) -> DeckDef:
	return CardDB.build_deck(cs, arena, abil)


## Белый ящик: все 6 ворот сразу на поле (P0 — слоты 0,2,4; P1 — 1,3,5), руки ворот пусты; ход P0, фаза броска.
func _setup_controller(ctrl: MatchController) -> void:
	ctrl.start()
	_check(ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == 0, "начало: P0 кладёт ворота")
	_check(not ctrl.can_skip_gate(), "без ворот на поле пропустить нельзя")
	for i in range(6):
		var p: int = i % 2
		var hand: Array[StringName] = ctrl.state.players[p].arena_hand
		var id: StringName = hand[0]
		hand.remove_at(0)
		_set_card(ctrl, i, id, p)
	_check(ctrl.skip_gate(0) == OK, "пропуск выкладки при полном поле")


func _set_card(ctrl: MatchController, slot: int, id: StringName, owner: int) -> void:
	var s: SlotState = ctrl.state.slots[slot]
	s.card_id = id
	s.card_owner = owner
	s.has_card = true


## Белый ящик: поставить существо в слот.
func _stand(ctrl: MatchController, uid: int, slot: int) -> void:
	ctrl.state.creatures[uid].slot = slot
	ctrl.state.slots[slot].occupant_uid = uid


func _throw(ctrl: MatchController, p: int, uid: int, slot: int) -> void:
	var err: Error = ctrl.select_creature(p, uid)
	_check(err == OK, "select_creature(%d,%d) ошибка %d" % [p, uid, err])
	ctrl.report_landing(uid, slot)


func _pass_windows(ctrl: MatchController) -> void:
	var guard: int = 0
	while ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and guard < 4:
		guard += 1
		ctrl.pass_ability(ctrl.get_active_player())


## Ход P1 без последствий: промах.
func _p1_idle_turn(ctrl: MatchController) -> void:
	var legal: Array[int] = ctrl.legal_creatures(1)
	_throw(ctrl, 1, legal[0], -1)


## Ход P0 без последствий: промах.
func _p0_idle(ctrl: MatchController) -> void:
	var legal: Array[int] = ctrl.legal_creatures(0)
	_throw(ctrl, 0, legal[0], -1)


## Контроллер с колодами (uid P0 — 0..2, P1 — 3..5), все 6 ворот нейтральные (P0 — 0,2,4; P1 — 1,3,5), ход P0.
func _ctrl(cs0: Array, ab0: Array, cs1: Array, ab1: Array, rng_seed: int, landing: bool = false) -> MatchController:
	var ctrl: MatchController = MatchController.new(_mk_deck(cs0, [NEUTRAL, NEUTRAL, NEUTRAL], ab0), _mk_deck(cs1, [NEUTRAL, NEUTRAL, NEUTRAL], ab1), rng_seed, MatchRules.Ruleset.LEGACY)
	ctrl.landing_window = landing
	_setup_controller(ctrl)
	return ctrl


## Бой P0 (uid atk) против стоящего P1 (uid dfn) на воротах card в слоте 1 (владелец P1); остальные ворота нейтральные.
func _battle_ctrl(abil0: Array, abil1: Array, card: StringName, atk_idx: int, def_idx: int, rng_seed: int, landing: bool = false) -> MatchController:
	var ctrl: MatchController = _ctrl([ZH, LU, GR], abil0, [VI, SU, MA], abil1, rng_seed, landing)
	_set_card(ctrl, 1, card, 1)
	if atk_idx >= 0:
		_stand(ctrl, ctrl.state.players[1].creature_uids[def_idx], 1)
		_throw(ctrl, 0, ctrl.state.players[0].creature_uids[atk_idx], 1)
	return ctrl


func _has_event(ctrl: MatchController, prefix: String) -> bool:
	return ctrl.event_log.any(func(e: String) -> bool: return e.begins_with(prefix))


# ---------------------------------------------------------------- тесты: колода

func _test_card_db() -> void:
	_check(CardDB.creature_ids().size() == GameData.SPECIES.size() * 6, "каждый вид во всех 6 стихиях")
	var per_attr: Array[int] = [0, 0, 0, 0, 0, 0]
	for d in CardDB.all_creatures():
		per_attr[d.attribute] += 1
	_check(per_attr.min() >= 3, "по 3+ существа каждой стихии: %s" % str(per_attr))
	_check(CardDB.arena_ids().size() == 25, "25 карт ворот (7 стихии + 8 вида + 10 командных): %d" % CardDB.arena_ids().size())
	_check(CardDB.ability_ids().size() == 48, "48 способностей (14 стихийных + 18 усилений + 16 видовых): %d" % CardDB.ability_ids().size())
	var counts: Dictionary = {}
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		var c: CardDef = CardDB.card(id)
		var cls: StringName = CardDB.card_class(c)
		counts[cls] = int(counts.get(cls, 0)) + 1
		_check(c.text != "" and c.text.length() <= 120, "текст карты %s короткий и непустой" % id)
	_check(counts == {&"gold": 7, &"silver": 8, &"bronze": 10, &"red": 14, &"blue": 18, &"green": 16}, "классы карт: %s" % str(counts))
	# у каждой стихии 2–3 стихийные и 3 усиления, у каждого вида 2 видовые
	for el in range(6):
		_check(CardDB.cards_of(CardDef.Kind.ABILITY, &"red", el).size() >= 2, "стихийные способности стихии %d" % el)
		_check(CardDB.cards_of(CardDef.Kind.ABILITY, &"blue", el).size() == 3, "лесенка усилений стихии %d" % el)
		_check(CardDB.cards_of(CardDef.Kind.ARENA, &"gold", el).size() == 2, "ворота стихии %d: своё Поле + Алтарь" % el)
	for row in GameData.SPECIES:
		var sp: StringName = StringName(row["id"])
		_check(CardDB.cards_of(CardDef.Kind.ABILITY, &"green", -1, [sp]).size() == 2, "2 видовые способности %s" % sp)
		_check(CardDB.cards_of(CardDef.Kind.ARENA, &"silver", -1, [sp]).size() == 1, "ворота вида %s" % sp)
	# у стихийных бонусов у каждой стихии своё число 80–150, универсальный Алтарь +300
	var amounts: Array = []
	for el in range(6):
		var f: CardDef = CardDB.card(StringName("arena_field_" + String(GameData.ATTR_KEYS[el])))
		var g: Array = f.params["g"]
		_check(int(g[el]) >= 80 and int(g[el]) <= 150 and int(g[(el + 1) % 6]) == 0, "Поле %d даёт G только своей стихии: %s" % [el, str(g)])
		amounts.append(int(g[el]))
	_check(amounts.has(80) and amounts.has(150), "бонусы полей от 80 до 150: %s" % str(amounts))
	_check(int(CardDB.card(&"arena_altar").params["amount"]) == 300, "Алтарь силы +300")
	for i in range(2):
		var d: DeckDef = CardDB.preset_deck(i)
		var cs: Array = d.creatures.map(func(x: CreatureDef) -> StringName: return x.id)
		var ar: Array = d.arena.map(func(c: CardDef) -> StringName: return c.id)
		var ab: Array = d.abilities.map(func(c: CardDef) -> StringName: return c.id)
		_check(CardDB.deck_error(cs, ar, ab) == "", "пресет %d по правилам: %s" % [i, CardDB.deck_error(cs, ar, ab)])
	_check(CardDB.card(&"nope") == null, "неизвестная карта = null")


## Конструктор колоды: классы, стихийный и видовой замки, лимит силы, случайные колоды.
func _test_deck_builder() -> void:
	var drng := RandomNumberGenerator.new()
	drng.seed = 99
	for _k in range(60):
		var dk: DeckDef = CardDB.random_deck(drng)
		var cs: Array = dk.creatures.map(func(d: CreatureDef) -> StringName: return d.id)
		var ar: Array = dk.arena.map(func(c: CardDef) -> StringName: return c.id)
		var ab: Array = dk.abilities.map(func(c: CardDef) -> StringName: return c.id)
		var e: String = CardDB.deck_error(cs, ar, ab)
		_check(e == "", "случайная колода по правилам: %s %s %s %s" % [e, cs, ar, ab])
		_check(CardDB.team_power(cs) <= CardDB.team_power_limit(), "случайная колода в лимите силы")
	var fire: Array = [&"creature_dragnar_fire", &"creature_klykar_fire", &"creature_grifalon_fire"]
	var gates: Array = [&"arena_field_fire", &"arena_den_dragnar", &"arena_funnel"]
	var abil: Array = [&"ability_fire_drain", &"ability_fire_spark", &"ability_klykar_bite"]
	_check(CardDB.deck_error(fire, gates, abil) == "", "колода Пламени годится: %s" % CardDB.deck_error(fire, gates, abil))
	_check(CardDB.team_species(fire) == [&"dragnar", &"klykar", &"grifalon"], "виды команды")
	_check(CardDB.deck_error([&"creature_dragnar_fire", &"creature_grifalon_gale", &"creature_klykar_fire"], gates, abil) != "", "смешанные стихии запрещены")
	_check(CardDB.deck_error(fire, [&"arena_field_fire", &"arena_altar", &"arena_funnel"], abil) != "", "два золотых ворот запрещены")
	_check(CardDB.deck_error(fire, [&"arena_field_gale", &"arena_den_dragnar", &"arena_funnel"], abil) != "", "Поле чужой стихии запрещено")
	_check(CardDB.deck_error(fire, [&"arena_field_fire", &"arena_den_levian", &"arena_funnel"], abil) != "", "ворота вида не из команды запрещены")
	_check(CardDB.deck_error(fire, gates, [&"ability_tide_hush", &"ability_fire_spark", &"ability_klykar_bite"]) != "", "чужая стихийная способность запрещена")
	_check(CardDB.deck_error(fire, gates, [&"ability_fire_drain", &"ability_gale_gust", &"ability_klykar_bite"]) != "", "чужое усиление запрещено")
	_check(CardDB.deck_error(fire, gates, [&"ability_fire_drain", &"ability_fire_spark", &"ability_levian_abyss"]).contains("Левиан"), "видовая не из команды запрещена")
	_check(CardDB.deck_error(fire, gates, [&"ability_fire_drain", &"ability_fire_spark", &"ability_fire_ash"]) != "", "нужна видовая (зелёная) способность")
	_check(CardDB.deck_error(fire, gates, [&"ability_fire_drain", &"ability_fire_spark"]) != "", "нужно 3 способности")
	_check(CardDB.deck_error([&"creature_kolossar_stone", &"creature_kolossar_gale", &"creature_kolossar_tide"], gates, abil) != "", "лимит силы и одна стихия")
	var red: Array[StringName] = CardDB.cards_of(CardDef.Kind.ABILITY, &"red", Attr.A.FIRE)
	_check(red.has(&"ability_fire_drain") and not red.has(&"ability_tide_hush"), "меню: красные только своей стихии")
	var green: Array[StringName] = CardDB.cards_of(CardDef.Kind.ABILITY, &"green", Attr.A.FIRE, CardDB.team_species(fire))
	_check(green.size() == 6 and green.has(&"ability_grifalon_dive") and not green.has(&"ability_levian_coil"), "меню: видовые только видов команды: %s" % str(green))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok_deck: DeckDef = CardDB.deck_from_creatures(fire, rng)
	var oa: Array = ok_deck.arena.map(func(c: CardDef) -> StringName: return c.id)
	var ob: Array = ok_deck.abilities.map(func(c: CardDef) -> StringName: return c.id)
	_check(ok_deck != null and CardDB.deck_error(fire, oa, ob) == "", "колода из выбранных существ по правилам")
	_check(CardDB.deck_from_creatures([&"creature_kolossar_stone", &"creature_kolossar_gale", &"creature_kolossar_tide"], rng) == null, "лимит БС команды")
	_check(CardDB.deck_from_creatures([&"creature_dragnar_fire", &"creature_dragnar_fire", &"creature_klykar_fire"], rng) == null, "повтор существа запрещён")


func _test_attribute_table() -> void:
	var ids: Array[StringName] = [ZH, VI, LU, GR, SU, MA]  # порядок = Attr.A
	for a in range(6):
		for b in range(6):
			var expect_beat: bool = (b == (a + 1) % 6)
			_check(Attr.beats(a, b) == expect_beat, "Attr.beats(%d,%d)" % [a, b])
			var st: MatchState = _mk_state(ids[a], ids[b], &"")
			var r: BattleResult = _calc(st)
			var ba: int = CardDB.creature(ids[a]).base_power
			var bb: int = CardDB.creature(ids[b]).base_power
			var ea: int = ba + (60 if Attr.beats(a, b) else 0)
			var eb: int = bb + (60 if Attr.beats(b, a) else 0)
			_check(r.powers[0] == ea and r.powers[1] == eb, "таблица %d vs %d: %d:%d, ожидалось %d:%d" % [a, b, r.powers[0], r.powers[1], ea, eb])


func _test_tie_goes_to_defender() -> void:
	var st: MatchState = _mk_state(ZH, ZH, &"")
	var r: BattleResult = _calc(st)
	_check(r.powers[0] == r.powers[1], "ничья: равные силы")
	_check(r.winner_uid == 1 and r.loser_uid == 0, "ничья: победил защитник")
	_check(_calc(_mk_state(GR, ZH, &"")).winner_uid == 0, "сильнейший атакующий побеждает")


# ---------------------------------------------------------------- тесты: ворота (расчёт)

## ZH (Пламя 340) атакует VI (Буря 300) на воротах P1: Пламя бьёт Бурю — без карт 400:300.
func _test_gate_cards() -> void:
	_expect("без карты", ZH, VI, &"", &"", &"", 400, 300)
	_expect("нейтральные ворота", ZH, VI, NEUTRAL, &"", &"", 400, 300)
	_expect("Поле Пламени", ZH, VI, &"arena_field_fire", &"", &"", 520, 300)
	_expect("Поле Бури", ZH, VI, &"arena_field_gale", &"", &"", 400, 450)
	_expect("Поле Света (мимо)", ZH, VI, &"arena_field_light", &"", &"", 400, 300)
	_expect("Поле Тени", SU, ZH, &"arena_field_shadow", &"", &"", 430, 340)
	_expect("Поле Камня", ZH, GR, &"arena_field_stone", &"", &"", 340, 520)
	_expect("Поле Прилива", ZH, MA, &"arena_field_tide", &"", &"", 340, 510)
	_expect("Поле Света", ZH, LU, &"arena_field_light", &"", &"", 340, 420)
	_expect("Алтарь силы: защитник-владелец +300", ZH, VI, &"arena_altar", &"", &"", 400, 600)
	var st: MatchState = _mk_state(ZH, VI, &"arena_altar")
	st.slots[0].card_owner = 0
	var r: BattleResult = _calc(st)
	_check(r.powers[0] == 400 and r.powers[1] == 300, "Алтарь: атакующему-владельцу и чужому защитнику ничего: %d:%d" % [r.powers[0], r.powers[1]])
	_expect("Логово Драгнара: БС ×2", ZH, VI, &"arena_den_dragnar", &"", &"", 740, 300)
	_expect("Гнездо Грифалона: БС ×2 защитнику", ZH, VI, &"arena_den_grifalon", &"", &"", 400, 600)
	_expect("ворота чужого вида", ZH, VI, &"arena_den_levian", &"", &"", 400, 300)
	_expect("Зеркало", ZH, VI, &"arena_mirror", &"", &"", 300, 400)
	_check(_calc(_mk_state(ZH, VI, &"arena_mirror")).mirrored, "флаг Зеркала")
	_expect("Воронка: владелец забирает 100", ZH, VI, &"arena_funnel", &"", &"", 300, 400)
	_expect("Гнёт: −100 тому, у кого 400+", ZH, VI, &"arena_weight", &"", &"", 300, 300)
	_expect("Сеть врат: +50 владельцу за каждые ворота", ZH, VI, &"arena_web", &"", &"", 400, 350)
	var hold: BattleResult = _expect("Удержание", ZH, VI, &"arena_hold", &"", &"", 400, 300)
	_check(hold.winner_stays and hold.winner_uid == 0, "Удержание: победитель остаётся")
	var clash: BattleResult = _expect("Обоюдный удар", ZH, VI, &"arena_clash", &"", &"", 400, 300)
	_check(clash.both_lose and clash.winner_uid == -1 and clash.trap_id == &"arena_clash", "Обоюдный удар: выбывают оба")
	# Предел: сильнее 400 — проигрыш; оба — выбывают оба
	var lim: BattleResult = _expect("Предел с картой +80", ZH, VI, &"arena_limit", PLUS, &"", 480, 300)
	_check(lim.winner_uid == 1 and not lim.both_lose, "Предел: атакующий 480 > 400 проигрывает")
	var lim2: BattleResult = _expect("Предел у обоих", GR, ZH, &"arena_limit", PLUS, PLUS, 450, 420)
	_check(lim2.both_lose, "Предел: оба сильнее 400 — выбывают оба")
	_check(_calc(_mk_state(ZH, VI, &"arena_limit")).winner_uid == 0, "Предел: 400 ещё можно")
	# Глухие врата: сопернику владельца (атакующему) способности запрещены
	var mute: BattleResult = _expect("Глухие врата гасят карту атакующего", ZH, VI, &"arena_mute", PLUS, PLUS, 400, 380)
	_check(mute.silenced[0] and not mute.silenced[1] and mute.cancelled_plays == [[0, PLUS]], "Глухие врата: флаги %s" % str(mute.cancelled_plays))
	# Трон сумрака: Тень побеждает
	var dusk: BattleResult = _expect("Трон сумрака", SU, GR, &"arena_dusk_throne", &"", &"", 350, 430)
	_check(dusk.winner_uid == 0 and dusk.auto_win, "Трон сумрака: Тень побеждает при меньшей силе")
	_check(_calc(_mk_state(ZH, VI, &"arena_dusk_throne")).winner_uid == 0 and not _calc(_mk_state(ZH, VI, &"arena_dusk_throne")).auto_win, "Трон сумрака без Тени — обычный бой")
	_check(_calc(_mk_state(SU, SU, &"arena_dusk_throne")).winner_uid == 1, "Трон сумрака: Тень у обоих — обычный бой")
	_expect("Зов павших в расчёте нейтрален", ZH, VI, &"arena_fallen_call", &"", &"", 400, 300)


# ---------------------------------------------------------------- тесты: способности (расчёт)

func _test_element_abilities() -> void:
	_expect("Пожирающий жар", ZH, VI, &"", &"ability_fire_drain", &"", 500, 200)
	_expect("Пепельный дождь", ZH, VI, &"", &"ability_fire_ash", &"", 400, 250)
	var st: MatchState = _mk_state(ZH, VI, &"")
	_add_creature(st, 2, MA, 1, 3)
	_add_creature(st, 3, ZH, 1, 4)
	_add_creature(st, 4, LU, 0, 5)
	var r: BattleResult = _calc(st, &"ability_fire_ash")
	_check(r.marks == [[2, {"src": &"ability_fire_ash", "delta": -50}]], "Пепельный дождь метит стоящих соперников, кроме Пламени: %s" % str(r.marks))
	_expect("Попутный шквал в бою +100", ZH, VI, &"", &"ability_gale_leap", &"", 500, 300)
	var rv: BattleResult = _expect("Возрождение", ZH, VI, &"", &"ability_light_revive", &"", 430, 300)
	_check(rv.revive == [true, false], "Возрождение помечено у атакующего")
	_expect("Очищающий луч: ворота соперника не действуют", ZH, VI, &"arena_field_gale", &"ability_light_purge", &"", 450, 300)
	var st2: MatchState = _mk_state(ZH, VI, &"arena_field_fire")
	st2.slots[0].card_owner = 0
	var r2: BattleResult = _calc(st2, &"ability_light_purge")
	_check(r2.powers[0] == 570 and not r2.arena_cancelled, "Очищающий луч свои ворота не трогает: %d" % r2.powers[0])
	var cr: BattleResult = _calc(st, &"ability_light_crown")
	_check(cr.powers[0] == 450 and cr.powers[1] == 250 and cr.marks.size() == 2, "Сияющий венец: +50/−50 и метки всем стоящим соперникам: %s" % str(cr.marks))
	var cp: BattleResult = _expect("Отпечаток в камне повторяет Жар соперника", ZH, VI, &"", &"ability_fire_drain", &"ability_stone_copy", 400, 350)
	_check(cp.copies == [[1, &"ability_stone_copy", &"ability_fire_drain"]], "запись копии: %s" % str(cp.copies))
	_expect("Отпечаток без цели: только +50", ZH, VI, &"", &"", &"ability_stone_copy", 400, 350)
	var cp2: BattleResult = _seq(_mk_state(ZH, VI, &""), [[0, SHIELD], [1, PLUS], [1, &"ability_stone_copy"]])
	_check(cp2.powers[0] == 400 and cp2.powers[1] == 350 and cp2.copies.is_empty(), "Отпечаток не повторяет отмену: %s" % cp2.to_log_string())
	var dm: BattleResult = _expect("Общая бездна при проигрыше", ZH, VI, &"", &"", &"ability_shadow_doom", 400, 300)
	_check(dm.both_lose and dm.winner_uid == -1, "Общая бездна: выбывают оба")
	var dm2: BattleResult = _expect("Общая бездна у победителя молчит", ZH, VI, &"", &"ability_shadow_doom", &"", 400, 300)
	_check(not dm2.both_lose and dm2.winner_uid == 0, "Общая бездна: победитель не жертвует")
	_expect("Затмение врат", ZH, VI, &"arena_field_gale", &"ability_shadow_eclipse", &"", 400, 250)
	var pc: BattleResult = _calc(st, &"ability_shadow_pact")
	_check(pc.powers[0] == 450 and pc.powers[1] == 250 and pc.marks == [[4, {"src": &"ability_shadow_pact", "delta": 50}]], "Тёмный пакт: +50 своим стоящим: %s" % str(pc.marks))
	var hs: BattleResult = _seq(_mk_state(ZH, VI, &""), [[0, &"ability_tide_hush"], [1, PLUS]])
	_check(hs.powers[0] == 450 and hs.powers[1] == 300 and hs.silenced[1] and hs.cancelled_plays == [[1, PLUS]], "Глубинная тишь гасит следующие карты соперника: %s" % hs.to_log_string())
	var hs2: BattleResult = _seq(_mk_state(ZH, VI, &""), [[1, PLUS], [0, &"ability_tide_hush"]])
	_check(hs2.powers[1] == 380, "Глубинная тишь не трогает сыгранное раньше")
	_expect("Отлив без свободных ворот не действует", ZH, VI, &"", &"", &"ability_tide_ebb", 400, 300)
	var st3: MatchState = _mk_state(ZH, VI, &"")
	st3.slots[2].has_card = true
	st3.slots[2].card_id = NEUTRAL
	var eb: BattleResult = _calc(st3, &"", &"ability_tide_ebb")
	_check(eb.interrupted and eb.relocate_uid == 0 and eb.relocate_to == 2 and eb.winner_uid == -1, "Отлив уносит соперника на свободные ворота: %s" % eb.to_log_string())


## Лесенка усилений: +30 (нельзя отменить) … +300 последнему; карты камбэка.
func _test_ladder() -> void:
	_expect("Искра +30", ZH, VI, &"", &"ability_fire_spark", &"", 430, 300)
	_expect("Искру нельзя отменить", ZH, VI, &"", &"ability_fire_spark", SHIELD, 430, 300)
	_expect("Жаркий натиск в атаке", ZH, VI, &"", &"ability_fire_assault", &"", 500, 300)
	_expect("Жаркий натиск в защите — 0", ZH, VI, &"", &"", &"ability_fire_assault", 400, 300)
	_expect("Светлый страж в защите", ZH, VI, &"", &"", &"ability_light_guard", 400, 400)
	_expect("Порыв +80 и +170 против бьющей стихии", ZH, VI, &"", &"", &"ability_gale_gust", 400, 550)
	_expect("Встречный вихрь: соперник сильнее по БС", ZH, VI, &"", &"", &"ability_gale_counter", 400, 420)
	_expect("Встречный вихрь: соперник слабее — 0", ZH, VI, &"", &"ability_gale_counter", &"", 400, 300)
	_expect("Порыв без бьющей стихии +80", VI, LU, &"", &"ability_gale_gust", &"", 440, 330)
	_check(CardEffects.boost_cond_ok(CardDB.card(&"ability_gale_counter"), {"my_base": 300, "foe_base": 300, "foe_beats": true}),
		"Встречный вихрь: стихия соперника бьёт твою")
	_check(not CardEffects.boost_cond_ok(CardDB.card(&"ability_gale_counter"), {"my_base": 300, "foe_base": 300, "foe_beats": false}),
		"Встречный вихрь: равные БС и нет бьющей стихии — 0")
	_expect("Опора на своих воротах", ZH, VI, &"", &"", &"ability_stone_footing", 400, 420)
	_expect("Опора на чужих воротах — 0", ZH, VI, &"", &"ability_stone_footing", &"", 400, 300)
	_expect("Последний костёр (одно существо)", ZH, VI, &"", &"ability_fire_last", &"", 600, 300)
	var st: MatchState = _mk_state(ZH, VI, &"")
	_add_creature(st, 2, LU, 0)
	_check(_calc(st, &"ability_fire_last").powers[0] == 400, "Последний костёр при двух существах — 0")
	_check(_calc(st, &"", &"ability_gale_vengeance").powers[1] == 550, "Буря мщения: у защитника меньше существ +250")
	_check(_calc(st, &"ability_stone_wrath").powers[0] == 400, "Гнев гор: у атакующего не меньше — 0")
	_check(CardEffects.returns_to_hand(CardDB.card(&"ability_tide_ninth")) and not CardEffects.returns_to_hand(CardDB.card(&"ability_tide_surf")), "карты камбэка возвращаются в руку")


func _test_species_abilities() -> void:
	var rush: BattleResult = _expect("Драконий напор", ZH, VI, &"", &"ability_dragnar_rush", &"", 500, 300)
	_check(rush.marks == [[0, {"src": &"ability_dragnar_rush", "fix": 440}]], "Драконий напор: сила 440 в следующем бою")
	var bite: BattleResult = _expect("Волчья хватка отменяет и −50", ZH, VI, &"", PLUS, &"ability_klykar_bite", 350, 300)
	_check(bite.cancelled_plays == [[0, PLUS]], "Волчья хватка отменила карту")
	_expect("Загонщик: соперник сильнее по БС", ZH, GR, &"", &"ability_klykar_hunt", &"", 540, 370)
	_expect("Пикирование в атаке", ZH, VI, &"", &"ability_grifalon_dive", &"", 600, 300)
	_expect("Взор с высоты: ворота не усиливают соперника", ZH, VI, &"arena_field_gale", &"ability_grifalon_sky", &"", 500, 300)
	_expect("Несокрушимый в защите", ZH, GR, &"", &"", &"ability_kolossar_wall", 340, 620)
	_expect("Несокрушимого нельзя отменить", ZH, GR, &"", SHIELD, &"ability_kolossar_wall", 340, 620)
	_expect("Великий сброс", ZH, VI, &"arena_field_fire", &"", &"ability_kolossar_reset", 340, 300)
	_expect("Хитиновый панцирь: не выше моей БС", ZH, VI, &"arena_field_fire", &"", &"ability_rogozhuk_shell", 300, 300)
	var ram: BattleResult = _expect("Рогатый таран", ZH, VI, &"", &"ability_rogozhuk_ram", &"", 400, 200)
	_check(ram.marks == [[1, {"src": &"ability_rogozhuk_ram", "delta": -50}]], "Рогатый таран: −50 на следующий бой")
	_expect("Кольца глубин сжигают бонусы, четверть — себе", ZH, VI, &"arena_field_fire", &"", &"ability_levian_coil", 340, 345)
	_expect("Пучина: все бонусы соперника сгорают", ZH, VI, &"arena_field_fire", &"", &"ability_levian_abyss", 340, 300)
	# «потолки» действуют на силу, набранную до них: карты, сыгранные после, прибавляются сверху
	var rs1: BattleResult = _seq(_mk_state(ZH, VI, &"arena_field_fire"), [[1, &"ability_kolossar_reset"], [0, PLUS]])
	_check(rs1.powers[0] == 420 and rs1.powers[1] == 300, "Великий сброс: карта после него действует: %s" % rs1.to_log_string())
	var rs2: BattleResult = _seq(_mk_state(ZH, VI, &"arena_field_fire"), [[0, PLUS], [1, &"ability_kolossar_reset"]])
	_check(rs2.powers[0] == 340, "Великий сброс: карта до него сгорает: %d" % rs2.powers[0])
	_check(CardEffects.is_lockout(CardDB.card(&"ability_kolossar_reset")), "после Великого сброса своя сторона не играет")
	var sh1: BattleResult = _seq(_mk_state(ZH, VI, &"arena_field_fire"), [[1, &"ability_rogozhuk_shell"], [0, PLUS]])
	_check(sh1.powers[0] == 380, "Хитиновый панцирь: карта после него сверх потолка: %d" % sh1.powers[0])
	var co1: BattleResult = _seq(_mk_state(ZH, VI, &"arena_field_fire"), [[1, &"ability_levian_coil"], [0, PLUS]])
	_check(co1.powers[0] == 420 and co1.powers[1] == 345, "Кольца глубин не трогают карты после себя: %s" % co1.to_log_string())
	_expect("Клятва стража нельзя отменить", ZH, VI, &"", &"ability_ratnik_oath", SHIELD, 500, 300)
	var rr: BattleResult = _expect("Второе дыхание", ZH, VI, &"", &"ability_ratnik_rearm", &"", 450, 300)
	_check(rr.recall == [&"ability_ratnik_rearm", &""], "Второе дыхание помечено")
	_expect("Каменный взгляд гасит Поле", ZH, VI, &"arena_field_fire", &"", &"ability_gorgul_gaze", 400, 350)
	_expect("Каменный взгляд не гасит ворота вида", ZH, VI, &"arena_den_dragnar", &"", &"ability_gorgul_gaze", 740, 350)
	_expect("Крылья ночи", ZH, VI, &"", &"ability_gorgul_night", &"", 400, 200)
	var fl: BattleResult = _seq(_mk_state(VI, ZH, &"arena_funnel"), [[1, &"ability_gorgul_night"], [1, &"ability_fire_drain"], [1, MINUS]])
	_check(fl.powers[0] == 0 and fl.powers[1] == 600 and fl.breakdown.any(func(l: Dictionary) -> bool: return l["source"] == "floor"), "нижняя граница 0: %s" % fl.to_log_string())


## Отмена в цепочке (как стопка) и её взаимодействие с отменой ворот.
func _test_negate_chain() -> void:
	var st: MatchState = _mk_state(ZH, VI, &"")
	var r1: BattleResult = _seq(st, [[0, PLUS], [1, SHIELD], [0, SHIELD]])
	_check(r1.powers[0] == 480 and r1.def_cancelled and r1.cancelled_plays == [[1, SHIELD]], "отмена на отмену возвращает карту: %s" % r1.to_log_string())
	var r2: BattleResult = _seq(st, [[0, PLUS], [1, SHIELD], [0, MINUS]])
	_check(r2.powers[0] == 400 and r2.powers[1] == 220, "карта отменена, следующая действует: %d:%d" % [r2.powers[0], r2.powers[1]])
	var r3: BattleResult = _seq(st, [[0, PLUS], [0, MINUS], [1, SHIELD]])
	_check(r3.powers[0] == 480 and r3.powers[1] == 300, "отмена бьёт только последнюю карту: %d:%d" % [r3.powers[0], r3.powers[1]])
	var r4: BattleResult = _seq(st, [[0, PLUS], [0, PLUS]])
	_check(r4.powers[0] == 560, "две карты складываются: %d" % r4.powers[0])
	var r5: BattleResult = _seq(st, [[1, SHIELD], [0, PLUS]])
	_check(r5.powers[0] == 400, "отмена без цели ждёт следующую карту соперника")
	_expect("отмена гасит Каменный взгляд — Поле действует", ZH, VI, &"arena_field_fire", SHIELD, &"ability_gorgul_gaze", 520, 300)
	var r6: BattleResult = _calc(_mk_state(ZH, VI, &"arena_field_fire"), &"", &"ability_gorgul_gaze")
	_check(r6.arena_cancelled, "Каменный взгляд: ворота отменены")
	_check(not r1.breakdown.is_empty(), "breakdown заполнен")


# ---------------------------------------------------------------- тесты: способности в матче

## Слияние «Сердце дракона» и замки: стихийный (по атрибуту) и видовой (по виду существа).
func _test_fusion_and_locks() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, &"ability_dragnar_heart", &"ability_gale_gust"], [SHIELD, MINUS, PLUS], NEUTRAL, 0, 0, 5)
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 0, "бой: обмен начинает игрок, чей ход")
	var legal: Array[StringName] = ctrl.legal_abilities(0)
	_check(legal == [PLUS], "слияние без основной карты и чужая стихия недоступны: %s" % str(legal))
	_check(ctrl.play_ability(0, &"ability_dragnar_heart") != OK, "слияние нельзя сыграть первым")
	_check(ctrl.play_ability(0, PLUS) == OK, "основная карта сыграна")
	_check(ctrl.pass_ability(1) == OK, "защитник пасует")
	_check(ctrl.legal_abilities(0) == [&"ability_dragnar_heart"], "Драгнару доступно слияние поверх своей карты")
	_check(ctrl.play_ability(0, &"ability_dragnar_heart") == OK, "слияние сыграно")
	_check(ctrl.get_active_player() == 1, "на слияние защитник может ответить")
	ctrl.pass_ability(1)
	_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "бой решён")
	_check(ctrl.state.players[0].captured.size() == 1, "Драгнар 340 + 60 + 80 + 200 побеждает")
	# видовой замок: Ратник (LU) не может сыграть карту Драгнара
	var c2: MatchController = _battle_ctrl([PLUS, &"ability_dragnar_heart", &"ability_ratnik_oath"], [SHIELD, MINUS, PLUS], NEUTRAL, 1, 0, 6)
	_check(c2.legal_abilities(0) == [PLUS, &"ability_ratnik_oath"], "видовая только своему виду: %s" % str(c2.legal_abilities(0)))
	c2.play_ability(0, PLUS)
	c2.pass_ability(1)
	_check(not c2.legal_abilities(0).has(&"ability_dragnar_heart"), "Ратнику слияние Драгнара недоступно")


## Обмен способностями: пошаговый — поочерёдно, пас пропускает ход (на карту соперника можно ответить снова),
## бой решается после двух пасов подряд; не больше 3 карт на игрока за бой.
func _test_exchange() -> void:
	var ab3: Array = [PLUS, MINUS, &"ability_fire_spark"]
	var ctrl: MatchController = _battle_ctrl(ab3, [PLUS, MINUS, SHIELD], NEUTRAL, 0, 0, 61)
	var log: Array = []
	ctrl.ability_window.connect(func(p: int, _o: Array) -> void: log.append(p))
	_check(ctrl.get_ability_moment() == &"battle" and ctrl.abilities_left(0) == 3, "в бою 3 карты на игрока")
	_check(ctrl.state.slots[1].revealed, "ворота открыты до обмена способностями")
	_check(ctrl.play_ability(1, PLUS) != OK, "не черёд защитника")
	ctrl.play_ability(0, PLUS)
	ctrl.play_ability(1, PLUS)
	ctrl.pass_ability(0)
	_check(ctrl.get_active_player() == 1 and ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "после паса атакующего ход защитника")
	ctrl.play_ability(1, MINUS)
	_check(ctrl.get_active_player() == 0 and ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "пас не окончателен: на карту соперника можно ответить")
	_check(ctrl.play_ability(0, MINUS) == OK, "спасовавший отвечает картой")
	ctrl.play_ability(1, SHIELD)
	_check(ctrl.get_active_player() == 0 and ctrl.abilities_left(1) == 0, "у защитника 3 карты — ход атакующего")
	ctrl.play_ability(0, &"ability_fire_spark")
	_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "обе стороны сыграли по 3 — бой решён")
	_check(log == [1, 0, 1, 0, 1, 0], "окна по очереди после первого: %s" % str(log))
	var c2: MatchController = _battle_ctrl(ab3, [SHIELD, MINUS, PLUS], NEUTRAL, 0, 0, 62)
	c2.pass_ability(0)
	_check(c2.get_active_player() == 1 and c2.get_phase() == MatchController.Phase.ABILITY_WINDOW, "один пас — бой ещё идёт")
	c2.play_ability(1, PLUS)
	c2.play_ability(0, PLUS)
	c2.pass_ability(1)
	_check(c2.get_active_player() == 0 and c2.get_phase() == MatchController.Phase.ABILITY_WINDOW, "после паса соперника можно доиграть")
	c2.pass_ability(0)
	_check(c2.get_phase() != MatchController.Phase.ABILITY_WINDOW, "два паса подряд — бой решён")


## Способности вне боя: до броска и после приземления карта прикрепляется к существу и срабатывает в его бою.
func _test_attach_moments() -> void:
	var deck0: DeckDef = _mk_deck([ZH, LU, GR], [NEUTRAL, NEUTRAL, NEUTRAL], [PLUS, MINUS, &"ability_fire_spark"])
	var deck1: DeckDef = _mk_deck([VI, SU, MA], [NEUTRAL, NEUTRAL, NEUTRAL], [&"ability_stone_firm", SHIELD, MINUS])
	var ctrl: MatchController = MatchController.new(deck0, deck1, 71, MatchRules.Ruleset.LEGACY)
	ctrl.landing_window = true
	_setup_controller(ctrl)
	var att: Array = []
	ctrl.ability_attached.connect(func(p: int, u: int, c: StringName) -> void: att.append([p, u, c]))
	_check(ctrl.select_creature(0, 0) == OK, "существо выбрано")
	_check(ctrl.get_ability_moment() == &"pre_throw" and ctrl.legal_abilities(0).size() == 3, "до броска можно сыграть способность")
	_check(ctrl.play_ability(0, PLUS) == OK, "карта до броска")
	_check(att == [[0, 0, PLUS]] and ctrl.state.creatures[0].attached.size() == 1, "карта прикреплена к существу")
	_check(ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING, "фаза броска не меняется")
	var wins: Array = []
	ctrl.attach_window.connect(func(p: int, u: int, _o: Array) -> void: wins.append([p, u]))
	ctrl.report_landing(0, 0)
	_check(ctrl.get_phase() == MatchController.Phase.AFTER_LANDING and wins == [[0, 0]], "окно после приземления")
	_check(ctrl.get_landed_uid() == 0 and ctrl.get_ability_moment() == &"after_landing", "запросы окна после приземления")
	_check(ctrl.pass_ability(0) == OK and ctrl.get_active_player() == 1, "пас — ход сопернику")
	_throw(ctrl, 1, 4, 0)
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 1, "бой: начинает атакующий P1")
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.powers[1] == 340 + 80 and pre.plays.size() == 1, "прикреплённая карта действует в бою: %s" % pre.to_log_string())
	ctrl.pass_ability(1)
	_check(ctrl.abilities_left(0) == 2, "прикреплённая карта занимает место в лимите")
	ctrl.pass_ability(0)
	_check(ctrl.state.creatures[0].attached.is_empty(), "после боя прикреплённые карты сняты")
	_check(ctrl.state.players[0].captured.size() == 1, "Драгнар (420) отбился от Горгула (350)")
	var c2: MatchController = MatchController.new(deck0, deck1, 72, MatchRules.Ruleset.LEGACY)
	_setup_controller(c2)
	_throw(c2, 0, 0, 0)
	_check(c2.get_active_player() == 1, "окно после приземления выключено по умолчанию")
	var c3: MatchController = MatchController.new(deck1, deck0, 73, MatchRules.Ruleset.LEGACY)
	_setup_controller(c3)
	c3.select_creature(0, 0)
	_check(not c3.legal_abilities(0).has(&"ability_stone_firm"), "чужая стихия не прикрепляется")


## Ворота-ловушки и «Зов павших» в матче.
func _test_traps_in_match() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], &"arena_mute", -1, 0, 91)
	var traps: Array = []
	ctrl.gate_trap_triggered.connect(func(sl: int, c: StringName, e: StringName) -> void: traps.append([sl, c, e]))
	var cancels: Array = []
	ctrl.ability_cancelled.connect(func(p: int, c: StringName) -> void: cancels.append([p, c]))
	_stand(ctrl, 4, 1)
	ctrl.select_creature(0, 2)
	ctrl.play_ability(0, PLUS)
	ctrl.report_landing(2, 1)
	_check(traps == [[1, &"arena_mute", &"mute"]], "событие ловушки при открытии: %s" % str(traps))
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 1, "Глухие врата: атакующему окна нет, ходит защитник")
	_check(ctrl.legal_abilities(0).is_empty(), "атакующему способности запрещены")
	ctrl.pass_ability(1)
	_check(cancels == [[0, PLUS]], "прикреплённая карта атакующего сгорела: %s" % str(cancels))
	_check(ctrl.state.players[0].captured.size() == 1, "Колоссар 430 > Горгул 350 без способностей")
	var c2: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], &"arena_fallen_call", -1, 0, 92)
	var rev: Array = []
	c2.creature_revived.connect(func(u: int) -> void: rev.append(u))
	c2.state.creatures[1].alive = false
	c2.state.creatures[5].alive = false
	_stand(c2, 4, 1)
	_throw(c2, 0, 2, 1)
	_check(rev == [1, 5], "Зов павших: выбывшие обеих сторон вернулись: %s" % str(rev))
	_check(c2.state.creatures[1].alive and c2.state.creatures[1].used and c2.state.creatures[5].alive, "вернулись в зону использованных")


## «Попутный шквал»: после приземления — перелёт к самому слабому сопернику и бой; без цели — прикрепляется.
func _test_gust() -> void:
	var ctrl: MatchController = _ctrl([VI, LU, GR], [&"ability_gale_leap", PLUS, MINUS], [ZH, SU, MA], [PLUS, MINUS, SHIELD], 131, true)
	_stand(ctrl, 4, 3)
	_stand(ctrl, 5, 5)
	_throw(ctrl, 0, 0, 0)
	_check(ctrl.get_phase() == MatchController.Phase.AFTER_LANDING and ctrl.legal_abilities(0).has(&"ability_gale_leap"), "шквал доступен после приземления")
	_check(ctrl.play_ability(0, &"ability_gale_leap") == OK, "шквал сыгран")
	_check(_has_event(ctrl, "creature_relocated(0, 0, 5)") and _has_event(ctrl, "battle_started(5, 0, 5)"), "перелёт к слабейшему (Левиан 320) и бой")
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.state.slots[0].occupant_uid == -1, "бой идёт, прежние ворота свободны")
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.powers[0] == 400 and pre.powers[1] == 320, "шквал даёт +100 в этом бою: %s" % pre.to_log_string())
	var c2: MatchController = _ctrl([VI, LU, GR], [&"ability_gale_leap", PLUS, MINUS], [ZH, SU, MA], [PLUS, MINUS, SHIELD], 132, true)
	_throw(c2, 0, 0, 0)
	c2.play_ability(0, &"ability_gale_leap")
	_check(c2.state.creatures[0].attached.size() == 1 and c2.get_phase() == MatchController.Phase.AFTER_LANDING, "без соперника на воротах шквал прикрепляется")


## «Вихревая подмена»: боец уходит в руку, сильнейшее существо не на воротах занимает его место.
func _test_swap_fighter() -> void:
	var ctrl: MatchController = _ctrl([VI, LU, GR], [&"ability_gale_swap", PLUS, MINUS], [ZH, SU, MA], [PLUS, MINUS, SHIELD], 141)
	var sw: Array = []
	ctrl.fighter_swapped.connect(func(o: int, n: int, s: int) -> void: sw.append([o, n, s]))
	_stand(ctrl, 4, 1)
	_throw(ctrl, 0, 0, 1)
	_check(ctrl.legal_abilities(0).has(&"ability_gale_swap"), "подмена доступна в бою")
	ctrl.play_ability(0, &"ability_gale_swap")
	_check(sw == [[0, 2, 1]], "Колоссар (370) заменил Грифалона: %s" % str(sw))
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.attacker_uid == 2 and pre.powers[0] == 370 + 60 + 200, "новый боец с +200: %s" % pre.to_log_string())
	_check(ctrl.state.creatures[0].slot == -1 and not ctrl.state.creatures[0].used, "прежний боец в руке")
	_pass_windows(ctrl)
	_check(ctrl.state.players[0].captured.size() == 1 and not ctrl.state.creatures[4].alive, "подменённый боец победил")
	# подмена защитника: новый боец встаёт на ворота
	var c2: MatchController = _ctrl([ZH, LU, GR], [PLUS, MINUS, SHIELD], [VI, SU, MA], [&"ability_gale_swap", PLUS, MINUS], 142)
	_stand(c2, 3, 1)
	_throw(c2, 0, 2, 1)
	c2.pass_ability(0)
	c2.play_ability(1, &"ability_gale_swap")
	_check(c2.state.slots[1].occupant_uid == 4 and c2.state.creatures[4].slot == 1 and c2.state.creatures[3].slot == -1, "защитник подменён на воротах")


## «Сдвиг плит»: ворота боя меняются со своими свободными воротами.
func _test_shift_gate() -> void:
	var ctrl: MatchController = _ctrl([GR, LU, ZH], [&"ability_stone_shift", PLUS, MINUS], [VI, SU, MA], [PLUS, MINUS, SHIELD], 151)
	_set_card(ctrl, 0, &"arena_field_stone", 0)
	_stand(ctrl, 4, 1)
	var ev: Array = []
	ctrl.gates_swapped.connect(func(a: int, b: int) -> void: ev.append([a, b]))
	_throw(ctrl, 0, 0, 1)
	_check(ctrl.legal_abilities(0).has(&"ability_stone_shift"), "сдвиг доступен: есть свои свободные ворота")
	ctrl.play_ability(0, &"ability_stone_shift")
	_check(ev == [[1, 0]] and ctrl.state.slots[1].card_id == &"arena_field_stone" and ctrl.state.slots[1].card_owner == 0, "ворота боя — Поле Камня: %s" % str(ev))
	_check(ctrl.state.slots[0].card_id == NEUTRAL and ctrl.state.slots[1].revealed, "прежние ворота ушли в слот 0, новые открыты")
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.powers[0] == 370 + 60 + 150 + 80, "Поле Камня и +80 в расчёте: %s" % pre.to_log_string())
	var c2: MatchController = _ctrl([GR, LU, ZH], [&"ability_stone_shift", PLUS, MINUS], [VI, SU, MA], [PLUS, MINUS, SHIELD], 152)
	for i in [0, 2, 4]:
		_set_card(c2, i, NEUTRAL, 1)
	_stand(c2, 4, 1)
	_throw(c2, 0, 0, 1)
	_check(not c2.legal_abilities(0).has(&"ability_stone_shift"), "без своих свободных ворот сдвиг недоступен")


## «Отлив»: бой прекращается, существо соперника уносит на свободные ворота.
func _test_ebb() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_tide_ebb", PLUS, MINUS], NEUTRAL, 0, 2, 161)
	ctrl.play_ability(0, PLUS)
	_check(ctrl.play_ability(1, &"ability_tide_ebb") == OK, "Отлив сыгран")
	_pass_windows(ctrl)
	_check(ctrl.state.creatures[0].slot == 0 and ctrl.state.slots[0].occupant_uid == 0, "атакующего унесло на свободные ворота 0")
	_check(ctrl.state.creatures[5].slot == 1 and ctrl.state.slots[1].occupant_uid == 5, "Левиан остался на воротах боя")
	_check(ctrl.state.creatures[0].alive and ctrl.state.creatures[5].alive and ctrl.state.players[0].captured.is_empty() and ctrl.state.players[1].captured.is_empty(), "никто не выбыл, карту не забрали")
	_check(ctrl.get_active_player() == 1, "ход переходит сопернику того, чей был ход")


## Выбывают оба: «Общая бездна», «Обоюдный удар»; оба последних — ничья.
func _test_both_lose() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_shadow_doom", PLUS, MINUS], NEUTRAL, 2, 1, 171)
	var disc: Array = []
	ctrl.gate_discarded.connect(func(s: int, c: StringName) -> void: disc.append([s, c]))
	ctrl.pass_ability(0)
	ctrl.play_ability(1, &"ability_shadow_doom")
	_pass_windows(ctrl)
	_check(not ctrl.state.creatures[2].alive and not ctrl.state.creatures[4].alive, "Общая бездна: выбыли оба")
	_check(disc == [[1, NEUTRAL]] and not ctrl.state.slots[1].has_card, "ворота сгорели: %s" % str(disc))
	_check(ctrl.state.players[0].captured.is_empty() and ctrl.get_active_player() == 1, "карту никто не забрал, ход сопернику")
	var c2: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], &"arena_clash", -1, 0, 172)
	for u in [1, 2, 4, 5]:
		c2.state.creatures[u].alive = false
	_go_winner = -2
	c2.game_over.connect(_on_game_over)
	_stand(c2, 3, 1)
	_throw(c2, 0, 0, 1)
	_pass_windows(c2)
	_check(c2.get_phase() == MatchController.Phase.GAME_OVER and _go_winner == -1, "оба последних выбыли — ничья: %d" % _go_winner)


## «Удержание»: победитель остаётся на воротах, карта не захвачена.
func _test_hold() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], &"arena_hold", 0, 0, 181)
	_pass_windows(ctrl)
	_check(not ctrl.state.creatures[3].alive, "проигравший выбыл")
	_check(ctrl.state.creatures[0].slot == 1 and ctrl.state.slots[1].occupant_uid == 0 and not ctrl.state.creatures[0].used, "победитель стоит на воротах")
	_check(ctrl.state.slots[1].has_card and ctrl.state.slots[1].card_id == &"arena_hold" and ctrl.state.players[0].captured.is_empty(), "карта лежит дальше")
	_check(ctrl.get_momentum(0) == 1 and ctrl.get_active_player() == 0, "натиск растёт, ходит победитель")


## «Возрождение»: после боя одно выбывшее своё существо возвращается.
func _test_revive() -> void:
	var ctrl: MatchController = _battle_ctrl([&"ability_light_revive", PLUS, MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 191)
	ctrl.state.creatures[0].alive = false
	var rev: Array = []
	ctrl.creature_revived.connect(func(u: int) -> void: rev.append(u))
	_stand(ctrl, 3, 1)
	_throw(ctrl, 0, 1, 1)  # Ратник Света 330 против Грифалона Бури 360
	ctrl.play_ability(0, &"ability_light_revive")
	_pass_windows(ctrl)
	_check(not ctrl.state.creatures[1].alive, "Ратник проиграл ничью (360:360)")
	_check(rev == [0] and ctrl.state.creatures[0].alive and ctrl.state.creatures[0].used, "Драгнар вернулся в зону использованных: %s" % str(rev))
	_check(ctrl.state.alive_count(0) == 2, "у P0 снова два существа")


## Метки на следующий бой: «Пепельный дождь», «Драконий напор».
func _test_marks() -> void:
	var ctrl: MatchController = _battle_ctrl([&"ability_fire_ash", &"ability_dragnar_rush", MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 201)
	var mk: Array = []
	ctrl.creature_marked.connect(func(u: int, c: StringName, m: Dictionary) -> void: mk.append([u, c, m]))
	_stand(ctrl, 3, 1)
	_stand(ctrl, 4, 3)
	_stand(ctrl, 5, 5)
	_throw(ctrl, 0, 0, 1)
	ctrl.play_ability(0, &"ability_fire_ash")
	ctrl.pass_ability(1)
	ctrl.play_ability(0, &"ability_dragnar_rush")
	_pass_windows(ctrl)
	_check(mk.size() == 3, "три метки: Горгул, Левиан и сила 440 Драгнару: %s" % str(mk))
	_check(ctrl.state.creatures[4].marks == [{"src": &"ability_fire_ash", "delta": -50}], "метка на Горгуле")
	_check(ctrl.state.creatures[0].marks == [{"src": &"ability_dragnar_rush", "fix": 440}], "метка силы 440 на Драгнаре")
	_throw(ctrl, 0, 2, 3)  # Колоссар против помеченного Горгула
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.powers[1] == 300 and pre.powers[0] == 470, "метка −50 в следующем бою (Колоссар с натиском): %s" % pre.to_log_string())
	_pass_windows(ctrl)
	_check(ctrl.state.creatures[2].marks.is_empty(), "метки снимаются после боя")
	var st: MatchState = _mk_state(ZH, VI, &"arena_field_fire")
	st.creatures[0].marks = [{"src": &"ability_dragnar_rush", "fix": 440}]
	_check(_calc(st, PLUS).powers[0] == 440, "фиксированная сила 440 перекрывает бонусы")


## «Второе дыхание» возвращает сыгранные карты; карты камбэка возвращаются в руку сами.
func _test_recall_and_returns() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, &"ability_ratnik_rearm", MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, 1, 1, 211)
	var rec: Array = []
	ctrl.abilities_recalled.connect(func(p: int, ids: Array) -> void: rec.append([p, ids]))
	ctrl.play_ability(0, PLUS)
	ctrl.pass_ability(1)
	ctrl.play_ability(0, &"ability_ratnik_rearm")
	_pass_windows(ctrl)
	_check(rec == [[0, [PLUS]]], "Второе дыхание вернуло карту: %s" % str(rec))
	var ps: PlayerState = ctrl.state.players[0]
	_check(ps.ability_hand.has(PLUS) and not ps.ability_hand.has(&"ability_ratnik_rearm") and ps.abilities_used == [&"ability_ratnik_rearm"], "рука после возврата: %s" % str(ps.ability_hand))
	var c2: MatchController = _battle_ctrl([&"ability_fire_last", PLUS, MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 212)
	c2.state.creatures[1].alive = false
	c2.state.creatures[2].alive = false
	_stand(c2, 3, 1)
	_throw(c2, 0, 0, 1)
	var pre0: BattleResult = c2.get_battle_preview()
	c2.play_ability(0, &"ability_fire_last")
	_check(c2.get_battle_preview().powers[0] == pre0.powers[0] + 200, "Последний костёр +200 последнему существу")
	_pass_windows(c2)
	_check(c2.state.players[0].ability_hand.has(&"ability_fire_last"), "карта камбэка снова в руке")


## Перезарядка: три карты в одном бою, отдых RECHARGE_BATTLES боёв, у последнего существа — сразу (кроме «Отлива»).
func _test_recharge() -> void:
	var ab3: Array = [PLUS, MINUS, &"ability_fire_spark"]
	var ctrl: MatchController = _battle_ctrl(ab3, [SHIELD, MINUS, PLUS], NEUTRAL, 0, 0, 231)
	var back: Array = []
	ctrl.abilities_recharged.connect(func(p: int, ids: Array) -> void: back.append([p, ids]))
	ctrl.play_ability(0, PLUS)
	ctrl.play_ability(1, SHIELD)
	ctrl.play_ability(0, MINUS)
	ctrl.pass_ability(1)
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.legal_abilities(0).size() == 1, "после паса соперника третья карта доступна")
	ctrl.play_ability(0, &"ability_fire_spark")
	ctrl.pass_ability(1)
	_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "три карты в одном бою сыграны")
	var ps: PlayerState = ctrl.state.players[0]
	_check(ps.ability_hand.is_empty() and ps.abilities_used.size() == 3, "после боя руки нет: %s" % str(ps.ability_hand))
	_check(int(ps.ability_cooldown.get(PLUS, 0)) == MatchController.RECHARGE_BATTLES, "карта отдыхает %d боя: %s" % [MatchController.RECHARGE_BATTLES, str(ps.ability_cooldown)])
	_check(back.is_empty(), "в бою розыгрыша карты не возвращаются")
	for i in range(MatchController.RECHARGE_BATTLES - 1):
		ctrl._recharge_abilities()
	_check(ps.ability_hand.is_empty(), "до конца отдыха рука пуста")
	ctrl._recharge_abilities()
	ctrl._flush()
	_check(ps.ability_hand.size() == 3 and ps.abilities_used.is_empty() and ps.ability_cooldown.is_empty(), "после отдыха карты в руке: %s" % str(ps.ability_hand))
	_check(back.size() == 2 and int(back[0][0]) == 0 and (back[0][1] as Array).size() == 3, "сигнал перезарядки: %s" % str(back))
	# у последнего существа карты возвращаются сразу, «Отлив» отдыхает полный срок
	var c2: MatchController = _battle_ctrl(ab3, [SHIELD, MINUS, PLUS], NEUTRAL, 0, 0, 232)
	var p2: PlayerState = c2.state.players[0]
	for id in [PLUS, &"ability_tide_ebb"]:
		p2.ability_hand.erase(id)
		p2.abilities_used.append(id)
	c2.state.creatures[1].alive = false
	c2.state.creatures[2].alive = false
	c2._recharge_abilities()
	_check(p2.ability_hand.has(PLUS) and not p2.ability_hand.has(&"ability_tide_ebb") and p2.ability_cooldown.has(&"ability_tide_ebb"), "последнее существо: карта сразу в руке, Отлив отдыхает: %s" % str(p2.ability_hand))
	# прикреплённая к живому существу карта не отдыхает (ещё не сыграла)
	var c3: MatchController = _battle_ctrl(ab3, [SHIELD, MINUS, PLUS], NEUTRAL, -1, 0, 233)
	var p3: PlayerState = c3.state.players[0]
	p3.ability_hand.erase(PLUS)
	p3.abilities_used.append(PLUS)
	c3.state.creatures[2].attached.append([0, PLUS])
	c3._recharge_abilities()
	_check(not p3.ability_cooldown.has(PLUS) and p3.abilities_used.has(PLUS), "прикреплённая карта ждёт своего боя")


## «Глубинная тишь» запрещает сопернику способности; «Кольца глубин» — своей стороне.
func _test_silence_and_lockout() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_tide_hush", PLUS, MINUS], NEUTRAL, 0, 2, 221)
	ctrl.play_ability(0, PLUS)
	ctrl.play_ability(1, &"ability_tide_hush")
	_check(ctrl.get_active_player() == 1 and ctrl.legal_abilities(0).is_empty(), "после тиши атакующий выбыл из обмена")
	_check(ctrl.get_battle_preview().silenced[0], "предпросмотр: атакующему запрещено")
	var c2: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_levian_coil", PLUS, MINUS], NEUTRAL, 0, 2, 222)
	c2.play_ability(0, PLUS)
	c2.play_ability(1, &"ability_levian_coil")
	c2.pass_ability(0)
	_check(c2.get_phase() != MatchController.Phase.ABILITY_WINDOW, "после Колец глубин своя сторона больше не играет — бой решён")
	_check(c2.state.players[1].captured.size() == 1, "Левиан забрал бонусы и победил")


# ---------------------------------------------------------------- механики «Боя как в аниме»

## «Натиск»: серия побед даёт +40 за победу (до 2), поражение сбрасывает.
func _test_momentum() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 101)
	var mom: Array = []
	ctrl.momentum_changed.connect(func(p: int, v: int) -> void: mom.append([p, v]))
	_stand(ctrl, 3, 1)
	_stand(ctrl, 4, 3)
	_stand(ctrl, 5, 5)
	_throw(ctrl, 0, 2, 3)  # Колоссар 370 + 60 > Горгул 350
	_pass_windows(ctrl)
	_check(mom == [[0, 1]] and ctrl.get_momentum(0) == 1, "первая победа: натиск 1: %s" % str(mom))
	_throw(ctrl, 0, 0, 1)  # Драгнар 340 + 60 + натиск 40 против Грифалона 300
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.momentum[0] == 40 and pre.powers[0] == 440, "натиск в расчёте: %s" % pre.to_log_string())
	_pass_windows(ctrl)
	_check(ctrl.get_momentum(0) == 2, "вторая победа: натиск 2")
	var st: MatchState = _mk_state(ZH, VI, &"")
	st.players[0].momentum = 5
	_check(_calc(st).powers[0] == 400 + PowerCalc.MOMENTUM_STEP * PowerCalc.MOMENTUM_MAX, "натиск не выше предела")
	st.players[0].momentum = 0
	st.players[1].momentum = 2
	_check(_calc(st).powers[1] == 380, "натиск защитника")
	var c2: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 102)
	c2.state.players[0].momentum = 2
	_stand(c2, 4, 1)
	var m2: Array = []
	c2.momentum_changed.connect(func(p: int, v: int) -> void: m2.append([p, v]))
	_throw(c2, 0, 1, 1)  # Ратник 330 + 80 = 410 > Горгул 350
	_pass_windows(c2)
	_check(c2.get_momentum(0) == 2 and m2.is_empty(), "на пределе натиск не растёт")
	var c3: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 103)
	c3.state.players[0].momentum = 1
	_stand(c3, 5, 1)
	_throw(c3, 0, 0, 1)  # Драгнар 340 + 40 против Левиана 320 + 60
	_pass_windows(c3)
	_check(c3.get_momentum(0) == 0, "поражение сбрасывает натиск")


## Финальный раунд: у кого-то осталось одно существо — объявление и преимущество стихии ×2.
func _test_final_round() -> void:
	var ctrl: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, SHIELD, MINUS], NEUTRAL, -1, 0, 111)
	var fin: Array = []
	ctrl.final_round_started.connect(func(p: int) -> void: fin.append(p))
	ctrl.state.creatures[3].alive = false  # у P1 осталось два
	_stand(ctrl, 4, 3)
	_throw(ctrl, 0, 2, 3)  # Колоссар выбивает Горгула
	_pass_windows(ctrl)
	_check(fin == [1] and ctrl.is_final_round() and ctrl.get_view(1).final_round, "финальный раунд объявлен для P1: %s" % str(fin))
	var st: MatchState = _mk_state(ZH, VI, &"")
	st.final_round = true
	var r: BattleResult = _calc(st)
	_check(r.powers[0] == 340 + 120 and r.final_round, "финальный раунд: преимущество ×2: %d" % r.powers[0])
	_check(ctrl.get_active_player() == 0, "ходит победитель")
	_throw(ctrl, 0, 0, -1)
	_check(fin.size() == 1, "объявление один раз")


## Уровни сложности ИИ и понимание новых карт.
func _test_ai_levels() -> void:
	_check(AIPlayer.new(1, 1).difficulty == AIPlayer.Difficulty.NORMAL and is_equal_approx(AIPlayer.new(1, 1).get_aim_error(), 0.42), "по умолчанию — Боец")
	_check(AIPlayer.new(1, 1, -1.0, AIPlayer.Difficulty.EASY).get_aim_error() > AIPlayer.new(1, 1, -1.0, AIPlayer.Difficulty.HARD).get_aim_error(), "мастер точнее новичка")
	_check(AIPlayer.difficulty_name(2) == "Мастер", "имя уровня")
	# приманка: на своё «Зеркало» Боец ставит слабейшее существо
	var deck1: DeckDef = _mk_deck([VI, SU, MA], [&"arena_mirror", NEUTRAL, NEUTRAL], [PLUS, SHIELD, MINUS])
	var ctrl: MatchController = MatchController.new(_test_deck(0), deck1, 121, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	for i in range(6):
		ctrl.state.slots[i].has_card = false
		ctrl.state.slots[i].card_id = &""
	_set_card(ctrl, 3, &"arena_mirror", 1)
	_p0_idle(ctrl)
	var ai := AIPlayer.new(1, 5, -1.0, AIPlayer.Difficulty.NORMAL)
	var th: Dictionary = ai.choose_throw(ctrl.get_view(1))
	_check(th["target_slot"] == 3 and th["uid"] == 3, "на Зеркало — слабейший Грифалон (300): %s" % str(th))
	# мастер разыгрывает пару, если одной карты мало: Грифалон 300 против Колоссара 370 + натиск 40
	var c2: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [PLUS, &"ability_gale_gust", MINUS], NEUTRAL, -1, 0, 122)
	c2.state.players[0].momentum = 1
	_stand(c2, 2, 3)
	_p0_idle(c2)
	_throw(c2, 1, 3, 3)
	var hard := AIPlayer.new(1, 7, -1.0, AIPlayer.Difficulty.HARD)
	var normal := AIPlayer.new(1, 7, -1.0, AIPlayer.Difficulty.NORMAL)
	var pre: BattleResult = c2.get_battle_preview()
	_check(c2.get_active_player() == 1 and pre.powers[1] - pre.powers[0] > 100 and pre.powers[1] - pre.powers[0] < 160, "Грифалон атакует и проигрывает без карт: %s" % pre.to_log_string())
	var hc: StringName = hard.choose_ability(c2.get_view(1), pre, c2.legal_abilities(1))
	var nc: StringName = normal.choose_ability(c2.get_view(1), pre, c2.legal_abilities(1))
	_check(hc != &"" and nc == &"", "мастер начинает пару карт, боец пасует: %s / %s" % [hc, nc])
	# прикрепление защиты после приземления
	var deck_g: DeckDef = _mk_deck([GR, ZH, LU], [NEUTRAL, NEUTRAL, NEUTRAL], [&"ability_stone_firm", PLUS, MINUS])
	var c3: MatchController = MatchController.new(deck_g, _test_deck(1), 123, MatchRules.Ruleset.LEGACY)
	c3.landing_window = true
	_setup_controller(c3)
	for i in range(6):
		_set_card(c3, i, NEUTRAL, i % 2)
	_throw(c3, 0, 1, 0)  # Драгнар (340) встаёт; Горгул (350) его перебьёт
	_check(c3.get_phase() == MatchController.Phase.AFTER_LANDING, "окно после приземления")
	var a0 := AIPlayer.new(0, 9, -1.0, AIPlayer.Difficulty.NORMAL)
	var pick: StringName = a0.choose_attach(c3.get_view(0), c3.get_landed_uid(), c3.legal_abilities(0))
	_check(pick == PLUS, "Боец прикрепляет +80 для защиты: %s" % pick)
	_check(AIPlayer.new(0, 9, -1.0, AIPlayer.Difficulty.EASY).choose_attach(c3.get_view(0), c3.get_landed_uid(), c3.legal_abilities(0)) == &"", "Новичок не прикрепляет защиту")
	# «Попутный шквал»: все уровни перелетают к слабому сопернику, если бой выгоден
	var c4: MatchController = _ctrl([VI, LU, GR], [&"ability_gale_leap", PLUS, MINUS], [ZH, SU, MA], [PLUS, MINUS, SHIELD], 124, true)
	_stand(c4, 5, 5)
	_throw(c4, 0, 0, 0)
	for d in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
		var ag := AIPlayer.new(0, 3, -1.0, d)
		_check(ag.choose_attach(c4.get_view(0), 0, c4.legal_abilities(0)) == &"ability_gale_leap", "ИИ %d играет шквал (420 против 320)" % d)
	# «Общая бездна»: проигрывающий ИИ меняет поражение на размен
	var c5: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_shadow_doom", PLUS, MINUS], NEUTRAL, 2, 1, 125)
	c5.pass_ability(0)
	var dp: StringName = AIPlayer.new(1, 3).choose_ability(c5.get_view(1), c5.get_battle_preview(), c5.legal_abilities(1))
	_check(dp != &"", "Боец отвечает картой, когда проигрывает: %s" % dp)
	# «Отлив»: ИИ уходит из проигранного боя
	var c6: MatchController = _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_tide_ebb", MINUS, SHIELD], NEUTRAL, 2, 2, 126)
	c6.play_ability(0, PLUS)
	var ep: StringName = AIPlayer.new(1, 3).choose_ability(c6.get_view(1), c6.get_battle_preview(), c6.legal_abilities(1))
	_check(ep == &"ability_tide_ebb", "Боец спасается Отливом: %s" % ep)
	var d1: Dictionary = _run_match(4242)
	var d2: Dictionary = _run_match(4242)
	_check(d1["log_hash"] == d2["log_hash"], "детерминизм с новыми механиками")


## «Ворота + бросок»: карта ворот ложится в момент броска, цель — эта карта.
func _test_gate_throw() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 81, MatchRules.Ruleset.LEGACY)
	ctrl.start()
	var ev: Array = []
	ctrl.gate_thrown.connect(func(p: int, sl: int, u: int) -> void: ev.append([p, sl, u]))
	var card: StringName = ctrl.state.players[0].arena_hand[0]
	_check(ctrl.throw_with_gate(0, card, 4, 0) != OK, "слот вне правил выкладки отвергается")
	_check(ctrl.throw_with_gate(0, card, 1, 3) != OK, "чужое существо отвергается")
	_check(ctrl.throw_with_gate(0, card, 1, 0) == OK, "ворота + бросок")
	_check(ev == [[0, 1, 0]] and ctrl.get_throw_gate_slot() == 1, "событие и цель броска")
	_check(ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and ctrl.get_selected_uid() == 0, "сразу фаза приземления")
	_check(ctrl.state.slots[1].has_card and ctrl.state.slots[1].card_owner == 0 and not ctrl.state.players[0].arena_hand.has(card), "карта на поле")
	ctrl.report_landing(0, 1)
	_check(ctrl.state.creatures[0].slot == 1 and ctrl.get_active_player() == 1, "существо встало на свою карту, ход сопернику")
	_check(ctrl.get_view(1).slots[1].card_id == &"", "соперник не видит карту")
	# промах с обычной погрешностью
	var c2: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 82, MatchRules.Ruleset.LEGACY)
	c2.start()
	c2.throw_with_gate(0, c2.state.players[0].arena_hand[0], 0, 1)
	c2.report_landing(1, -1)
	_check(c2.state.creatures[1].used and c2.state.slots[0].has_card, "промах: карта лежит, существо в зоне использованных")


func _test_hidden_info() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 5, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	var v0: MatchState = ctrl.get_view(0)
	var v1: MatchState = ctrl.get_view(1)
	for i in range(6):
		var real: SlotState = ctrl.state.slots[i]
		_check(real.card_id != &"", "реальная карта в слоте %d на месте" % i)
		_check(v0.slots[i].has_card and v1.slots[i].has_card, "has_card виден обоим")
		if real.card_owner == 0:
			_check(v0.slots[i].card_id == real.card_id and v1.slots[i].card_id == &"", "слот %d: P0 видит своё, P1 нет" % i)
		else:
			_check(v1.slots[i].card_id == real.card_id and v0.slots[i].card_id == &"", "слот %d: P1 видит своё, P0 нет" % i)
	for id in v0.players[1].ability_hand:
		_check(id == &"", "рука соперника скрыта (способности)")
	for id in v0.players[1].arena_hand:
		_check(id == &"", "рука соперника скрыта (арена)")
	_check(v0.players[0].ability_hand.size() == 3 and v0.players[0].ability_hand[0] != &"", "своя рука видна")
	# игра идёт: вид не меняет оригинал
	_check(ctrl.get_phase() == MatchController.Phase.AWAIT_THROW and ctrl.get_active_player() == 0, "после расстановки ход P0")


## Промах уводит существо в зону использованных; когда бросать некого, все возвращаются.
func _test_used_zone_refill() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 11, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	var refills: Array = []
	ctrl.creatures_refilled.connect(func(p: int) -> void: refills.append(p))
	_throw(ctrl, 0, 0, -1)
	_check(ctrl.state.creatures[0].used and ctrl.state.creatures[0].slot == -1, "промах: в зоне использованных")
	_check(ctrl.get_active_player() == 1, "после промаха ход соперника")
	_p1_idle_turn(ctrl)
	_check(not ctrl.legal_creatures(0).has(0), "использованное нельзя бросить")
	_throw(ctrl, 0, 1, 1)
	_check(ctrl.state.creatures[1].slot == 1 and ctrl.state.slots[1].occupant_uid == 1, "существо встало на ворота")
	_p1_idle_turn(ctrl)
	_check(ctrl.legal_creatures(0) == [2], "в руке осталось одно: %s" % str(ctrl.legal_creatures(0)))
	_throw(ctrl, 0, 2, -1)
	_p1_idle_turn(ctrl)
	_check(refills.has(0), "событие возврата использованных")
	var legal: Array[int] = ctrl.legal_creatures(0)
	_check(legal.size() == 2 and legal.has(0) and legal.has(2), "вернулись использованные: %s" % str(legal))
	_check(ctrl.state.creatures[1].slot == 1, "стоящее на воротах осталось на месте")
	_check(ctrl.select_creature(0, 99) != OK, "несуществующий uid отвергается")
	_check(ctrl.select_creature(1, 3) != OK, "не его ход")


## Выкладка ворот: сначала обязательна, дальше по желанию; рядом с лежащими, ближе к сопернику.
func _test_gate_placement_rules() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 12, MatchRules.Ruleset.LEGACY)
	ctrl.start()
	var legal0: Array[int] = ctrl.legal_setup_slots()
	_check(legal0 == [0, 1, 2], "P0 кладёт ближе к сопернику (дальний ряд): %s" % str(legal0))
	_check(ctrl.place_arena_card(0, ctrl.state.players[0].arena_hand[0], 3) != OK, "в свой ряд нельзя, пока есть место у соперника")
	_check(ctrl.place_arena_card(0, ctrl.state.players[0].arena_hand[0], 0) == OK, "P0 положил ворота в слот 0")
	_check(ctrl.get_phase() == MatchController.Phase.AWAIT_THROW and ctrl.get_active_player() == 0, "после выкладки бросок")
	_throw(ctrl, 0, 0, 0)
	_check(ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == 1, "ход P1: выкладка")
	_check(ctrl.can_skip_gate(), "ворота на поле есть: можно не класть")
	var legal1: Array[int] = ctrl.legal_setup_slots()
	_check(legal1 == [3], "P1: рядом с воротами, в ряду ближе к P0: %s" % str(legal1))
	_check(ctrl.skip_gate(1) == OK, "P1 пропускает выкладку")
	_check(ctrl.get_phase() == MatchController.Phase.AWAIT_THROW, "P1 бросает")


## Попадание на ворота со своим существом: перестановка в бой; если некуда — карта засчитывается.
## Все свои на воротах: отзыва нет, ход пропускается; у обоих все на воротах — сильнейшие стоящие дерутся.
func _test_no_recall_and_standoff() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 41, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, NEUTRAL, i % 2)
	_stand(ctrl, 0, 0)
	_stand(ctrl, 1, 2)
	_throw(ctrl, 0, 2, 4)
	_check(ctrl.state.creatures[2].slot == 4, "последнее существо P0 встало на ворота")
	_throw(ctrl, 1, 3, -1)  # P1 промахнулся
	_check(ctrl.event_log.any(func(e: String) -> bool: return e.begins_with("turn_skipped(0")), "P0 пропускает ход: бросать некого")
	_check(ctrl.get_active_player() == 1 and ctrl.get_phase() == MatchController.Phase.AWAIT_THROW, "ход перешёл к P1")
	_check(ctrl.state.creatures[0].slot == 0 and ctrl.state.creatures[1].slot == 2, "стоящие P0 не отозваны")
	var c2: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 42, MatchRules.Ruleset.LEGACY)
	_setup_controller(c2)
	for i in range(6):
		_set_card(c2, i, NEUTRAL, i % 2)
	_stand(c2, 0, 0)
	_stand(c2, 1, 2)
	_stand(c2, 3, 1)
	_stand(c2, 4, 3)
	_stand(c2, 5, 5)
	_throw(c2, 0, 2, 4)  # теперь у обоих все на воротах
	_check(c2.event_log.any(func(e: String) -> bool: return e.begins_with("standoff(2, 4")), "тупик: Гранитрог (370) идёт на Сумрачника (350)")
	_check(c2.get_phase() == MatchController.Phase.ABILITY_WINDOW, "бой в тупике идёт как обычный")
	_pass_windows(c2)
	_check(not c2.state.creatures[4].alive, "проигравший в тупике выбыл")


func _test_own_gate() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 31, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, NEUTRAL, i % 2)
	_stand(ctrl, 0, 0)
	_stand(ctrl, 3, 4)
	var moved: Array = []
	ctrl.creature_relocated.connect(func(u: int, a: int, b: int) -> void: moved.append([u, a, b]))
	_throw(ctrl, 0, 2, 0)
	_check(moved.size() == 1 and moved[0] == [2, 0, 4], "переставлено на ворота с соперником: %s" % str(moved))
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "начался бой после перестановки")
	_pass_windows(ctrl)
	_check(ctrl.state.players[0].captured.size() == 1, "Гранитрог выиграл перенесённый бой")
	var c2: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 32, MatchRules.Ruleset.LEGACY)
	_setup_controller(c2)
	for i in range(6):
		var sl: SlotState = c2.state.slots[i]
		sl.has_card = false
		sl.card_id = &""
	_set_card(c2, 2, NEUTRAL, 0)
	_stand(c2, 0, 2)
	_throw(c2, 0, 1, 2)
	_check(c2.event_log.any(func(e: String) -> bool: return e.begins_with("card_captured(0, 2")), "ворота со своими засчитаны")
	_check(c2.state.creatures[0].used and c2.state.creatures[1].used, "оба своих ушли в использованные")
	_check(not c2.state.slots[2].has_card, "карта убрана с поля")


func _test_win_by_three_captures() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 21, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, NEUTRAL, i % 2)
	_go_winner = -2
	_go_reason = &""
	ctrl.game_over.connect(_on_game_over)
	# P1: Вихрекрыл 300 (слот 1), Сумрачник 350 (слот 3), Мареолит 320 (слот 5); при Пустоте преимуществ нет
	_stand(ctrl, 3, 1)
	_stand(ctrl, 4, 3)
	_stand(ctrl, 5, 5)
	var plan := [[2, 3], [0, 1], [1, 5]]  # Гранитрог 370 > 350, Жаровик 340 > 300, Люминар 330 > 320
	for k in range(3):
		_check(ctrl.get_phase() == MatchController.Phase.AWAIT_THROW and ctrl.get_active_player() == 0, "ходит P0 — победитель прошлого боя (k=%d)" % k)
		_throw(ctrl, 0, plan[k][0], plan[k][1])
		_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "окно способностей (k=%d)" % k)
		_check(ctrl.state.slots[plan[k][1]].revealed, "ворота открыты в начале боя (k=%d)" % k)
		_pass_windows(ctrl)
		_check(ctrl.state.players[0].captured.size() == k + 1, "захвачено %d" % (k + 1))
	_check(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "матч окончен")
	_check(_go_winner == 0 and _go_reason == &"knockout", "победа P0 нокаутом: %d %s" % [_go_winner, String(_go_reason)])
	_check(not ctrl.state.creatures[3].alive, "проигравший выбыл")
	_check(ctrl.state.creatures[2].used, "победитель тоже в зоне использованных")


func _test_turn_limit() -> void:
	# A против B: суммы БС живых 1040 против 970 -> побеждает P0
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 51, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl)
	_go_winner = -2
	_go_reason = &""
	ctrl.game_over.connect(_on_game_over)
	_idle_until_end(ctrl)
	_check(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "лимит ходов: матч окончен")
	_check(_go_reason == &"turn_limit" and _go_winner == 0, "тай-брейк по сумме БС: %d %s" % [_go_winner, String(_go_reason)])
	_check(ctrl.state.turn == MatchController.MAX_TURNS, "сыграно ровно MAX_TURNS ходов, а не %d" % ctrl.state.turn)
	# зеркальные колоды -> ничья
	var ctrl2: MatchController = MatchController.new(_test_deck(0), _test_deck(0), 52, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl2)
	_go_winner = -2
	ctrl2.game_over.connect(_on_game_over)
	_idle_until_end(ctrl2)
	_check(_go_winner == -1 and _go_reason == &"turn_limit", "ничья при равенстве: %d" % _go_winner)
	# число захваченных карт важнее суммы БС
	var ctrl3: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 53, MatchRules.Ruleset.LEGACY)
	_setup_controller(ctrl3)
	ctrl3.state.creatures[0].alive = false  # у P0 на одно существо меньше
	_go_winner = -2
	ctrl3.game_over.connect(_on_game_over)
	_idle_until_end(ctrl3)
	_check(_go_winner == 1, "тай-брейк по числу живых существ: %d" % _go_winner)


func _idle_until_end(ctrl: MatchController) -> void:
	var guard: int = 0
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER and guard < 200:
		guard += 1
		var p: int = ctrl.get_active_player()
		if ctrl.get_phase() == MatchController.Phase.SETUP:
			if ctrl.can_skip_gate():
				ctrl.skip_gate(p)
			else:
				ctrl.place_arena_card(p, ctrl.state.players[p].arena_hand[0], ctrl.legal_setup_slots()[0])
			continue
		var legal: Array[int] = ctrl.legal_creatures(p)
		_throw(ctrl, p, legal[0], -1)


func _test_determinism() -> void:
	var a: Dictionary = _run_match(777)
	var b: Dictionary = _run_match(777)
	_check(a["ok"] and b["ok"], "детерминизм: матчи завершились")
	_check(a["log_hash"] == b["log_hash"] and a["log_len"] == b["log_len"], "одинаковый seed даёт одинаковый лог")
	var c: Dictionary = _run_match(778)
	_check(c["log_hash"] != a["log_hash"], "разный seed даёт другой лог")


func _test_simulation() -> void:
	for ruleset in [MatchRules.Ruleset.ANIME_INSPIRED, MatchRules.Ruleset.LEGACY]:
		for difficulty in [AIPlayer.Difficulty.EASY, AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
			for seed_value in range(1, 6):
				var smoke := _run_match(seed_value, ruleset, difficulty)
				_check(smoke["ok"], "ИИ ruleset=%d difficulty=%d seed=%d: %s" % [ruleset, difficulty, seed_value, smoke["error"]])
	var reasons: Dictionary = {}
	var wins: Array[int] = [0, 0, 0]
	var total_turns: int = 0
	var total_throws: int = 0
	var total_hits: int = 0
	var bad: int = 0
	for s in range(1, SIM_MATCHES + 1):
		var res: Dictionary = _run_match(s)
		if not res["ok"]:
			bad += 1
			print("FAIL: матч seed=%d не завершился корректно: %s" % [s, res["error"]])
			continue
		var reason: String = String(res["reason"])
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		var w: int = res["winner"]
		wins[w + 1 if w >= 0 else 0] += 1
		total_turns += int(res["turns"])
		total_throws += int(res["throws"])
		total_hits += int(res["hits"])
	_check(bad == 0, "симуляция: %d из %d матчей не завершились" % [bad, SIM_MATCHES])
	print("Симуляция %d матчей: ничьих %d, побед P0 %d, P1 %d" % [SIM_MATCHES, wins[0], wins[1], wins[2]])
	print("  причины: %s; средняя длина %.1f хода" % [str(reasons), float(total_turns) / float(SIM_MATCHES)])
	print("  доля попаданий в слот-цель: %.2f" % (float(total_hits) / float(maxi(1, total_throws))))


## ИИ против ИИ. Модель броска: с шансом HIT_CHANCE шар попадает в цель, иначе случайный слот или промах.
func _run_match(seed_value: int, ruleset: int = MatchRules.Ruleset.ANIME_INSPIRED, difficulty: int = AIPlayer.Difficulty.NORMAL) -> Dictionary:
	var out: Dictionary = {"ok": false, "error": "", "winner": -2, "reason": &"", "turns": 0, "log_hash": 0, "log_len": 0, "throws": 0, "hits": 0}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck0: DeckDef = CardDB.random_deck(rng)
	var deck1: DeckDef = CardDB.random_deck(rng)
	var ctrl: MatchController = MatchController.new(deck0, deck1, seed_value, ruleset)
	ctrl.landing_window = true
	var ais: Array[AIPlayer] = [AIPlayer.new(0, seed_value + 1, -1.0, difficulty), AIPlayer.new(1, seed_value + 2, -1.0, difficulty)]
	ctrl.start()
	var steps: int = 0
	var pending_uid: int = -1
	var pending_target: int = -1
	var throws: int = 0
	var hits: int = 0
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER:
		steps += 1
		if steps > SIM_STEP_CAP:
			out["error"] = "зависание: превышен лимит шагов"
			return out
		var p: int = ctrl.get_active_player()
		var err: Error = OK
		match ctrl.get_phase():
			MatchController.Phase.SETUP:
				var ch: Dictionary = ais[p].choose_setup(ctrl.get_view(p), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
				if ch.is_empty():
					err = ctrl.skip_gate(p)
				elif ch.has("throw_uid"):
					pending_uid = int(ch["throw_uid"])
					pending_target = int(ch["slot"])
					err = ctrl.throw_with_gate(p, ch["card_id"], ch["slot"], pending_uid)
				else:
					err = ctrl.place_arena_card(p, ch["card_id"], ch["slot"])
			MatchController.Phase.AFTER_LANDING:
				var at: StringName = ais[p].choose_attach(ctrl.get_view(p), ctrl.get_landed_uid(), ctrl.legal_abilities(p))
				err = ctrl.pass_ability(p) if at == &"" else ctrl.play_ability(p, at)
			MatchController.Phase.AWAIT_THROW:
				var th: Dictionary = ais[p].choose_throw(ctrl.get_view(p))
				pending_uid = th["uid"]
				pending_target = th["target_slot"]
				err = ctrl.select_creature(p, pending_uid)
			MatchController.Phase.AWAIT_LANDING:
				var landing: int = pending_target
				throws += 1
				if rng.randf() < HIT_CHANCE:
					hits += 1
				else:
					landing = _near_miss(pending_target, rng)
				ctrl.report_landing(pending_uid, landing)
				if ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING:
					out["error"] = "report_landing не сменил фазу"
					return out
			MatchController.Phase.ABILITY_WINDOW:
				var pre: BattleResult = ctrl.get_battle_preview()
				var pick: StringName = ais[p].choose_ability(ctrl.get_view(p), pre, ctrl.legal_abilities(p))
				if pick == &"":
					err = ctrl.pass_ability(p)
				else:
					err = ctrl.play_ability(p, pick)
			_:
				out["error"] = "неожиданная фаза %d" % ctrl.get_phase()
				return out
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW and ctrl.state.battle_context != null:
			out["error"] = "контекст боя остался после завершения"
			return out
		if err != OK:
			out["error"] = "ошибка действия %d в фазе %d (игрок %d, шаг %d)" % [err, ctrl.get_phase(), p, steps]
			return out
	if ctrl.winner < -1 or ctrl.winner > 1:
		out["error"] = "некорректный победитель %d" % ctrl.winner
		return out
	out["ok"] = true
	out["winner"] = ctrl.winner
	out["reason"] = ctrl.game_over_reason
	out["turns"] = ctrl.state.turn
	out["log_hash"] = "\n".join(ctrl.event_log).hash()
	out["log_len"] = ctrl.event_log.size()
	out["throws"] = throws
	out["hits"] = hits
	return out


## Промах как у физики: соседний по сетке 2x3 слот или вылет за пределы слотов.
func _near_miss(target: int, rng: RandomNumberGenerator) -> int:
	if target < 0 or rng.randf() < 0.5:
		return -1
	var col: int = target % 3
	var row: int = target / 3
	var near: Array[int] = []
	if col > 0: near.append(target - 1)
	if col < 2: near.append(target + 1)
	near.append((1 - row) * 3 + col)
	return near[rng.randi_range(0, near.size() - 1)]



func _test_battle_foundation() -> void:
	var context := BattleContext.new()
	context.slot = 3
	for i in range(4):
		_check(context.add(BattleParticipant.new(10 + i, 100 + i, i % 2, i % 2 + 50)), "добавление участника %d" % i)
		if i == 2:
			_check(context.clone().participants.size() == 3, "снимок боя на троих")
	_check(context.players_on_side(0) == [10, 12], "два игрока на стороне, id не равен стороне")
	_check(context.for_player(13).team_id == 51, "команда отдельно от id игрока")
	var triple := BattleContext.new()
	_check(triple.add(BattleParticipant.new(0, 100, 0)) and triple.add(BattleParticipant.new(0, 101, 0)) and triple.add(BattleParticipant.new(1, 102, 1)), "бой 2v1: три бойца двух игроков")
	_check(triple.participants_for_player(0).size() == 2 and triple.players_on_side(0) == [0], "все бойцы игрока и уникальные игроки стороны")
	_check(triple.clone().participants.size() == 3, "копия 2v1 сохраняет всех бойцов")
	_check(not context.add(BattleParticipant.new(99, 100, 2)), "повторный боец отклонён")
	var state4 := MatchState.new(4)
	state4.battle_context = context
	state4.players[3].ability_hand.append(PLUS)
	var view := state4.duplicate_view(3)
	_check(view.players.size() == 4 and view.players[3].ability_hand == [PLUS], "снимок четырёх игроков")
	view.battle_context.participants[0].creature_uid = 888
	_check(context.participants[0].creature_uid == 100, "контекст снимка изолирован")
	for count in [3, 4]:
		var many := MatchState.new(count)
		many.battle_context = BattleContext.new()
		for player in range(count):
			many.players[player].ability_hand.append(PLUS)
			many.players[player].arena_hand.append(NEUTRAL)
			many.creatures[100 + player] = CreatureState.new(100 + player, ZH, player)
			many.players[player].creature_uids.append(100 + player)
			many.battle_context.add(BattleParticipant.new(player, 100 + player, (player + 1) % 2))
		var masked := many.duplicate_view(count - 1)
		var full := many.duplicate_full()
		_check(masked.battle_context.participants.size() == count and full.players.size() == count, "состав и полная копия %d игроков" % count)
		for player in range(count):
			_check(masked.players[player].ability_hand[0] == (PLUS if player == count - 1 else &""), "маскировка руки P%d из %d игроков" % [player, count])
			_check(full.players[player].ability_hand == [PLUS], "полная рука P%d из %d игроков" % [player, count])
		full.players[count - 1].ability_hand.clear()
		full.creatures[100 + count - 1].alive = false
		_check(not many.players[count - 1].ability_hand.is_empty() and many.creatures[100 + count - 1].alive, "полная копия %d игроков изолирована" % count)
	var st := _mk_state(ZH, VI, NEUTRAL)
	var legacy := PowerCalc.compute(st, 0, 1, 0, &"", &"")
	_check(legacy.context.players_on_side(0) == [0] and legacy.context.players_on_side(1) == [1], "дуэль сохраняет mapping сторон")
	st.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	st.final_round = true
	st.players[0].momentum = 2
	var anime := PowerCalc.compute(st, 0, 1, 0, &"", &"")
	_check(anime.powers == [340, 300] and anime.momentum == [0, 0] and not anime.final_round, "новые правила отключают авторские бонусы")
	_check(st.duplicate_full().ruleset == st.ruleset, "ruleset сохраняется при копировании")
	var ctrl := MatchController.new(_test_deck(0), _test_deck(1), 123)
	_check(ctrl.state.ruleset == MatchRules.Ruleset.ANIME_INSPIRED, "новый режим по умолчанию")
	for u in [1, 2]:
		ctrl.state.creatures[u].alive = false
	ctrl._check_final_round()
	_check(not ctrl.is_final_round(), "новый режим не включает финальный множитель")

	var default_ctrl := MatchController.new(_mk_deck([ZH, LU, GR], [NEUTRAL, NEUTRAL, NEUTRAL], [PLUS, MINUS, SHIELD]), _mk_deck([VI, SU, MA], [NEUTRAL, NEUTRAL, NEUTRAL], [PLUS, MINUS, SHIELD]), 124)
	_setup_controller(default_ctrl)
	_throw(default_ctrl, 0, 0, 0)
	_throw(default_ctrl, 1, 3, 0)
	_check(default_ctrl.state.battle_context != null, "контекст существует во время боя")
	_pass_windows(default_ctrl)
	_check(default_ctrl.state.battle_context == null, "контекст очищается после боя")
	_check(default_ctrl.state.players[0].momentum == 0 and default_ctrl.state.players[1].momentum == 0, "новый режим не наращивает натиск")


func _test_turn_draw() -> void:
	var a := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 991)
	var b := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 991)
	_check(a.state.players[0].arena_hand.size() == 3 and a.state.players[0].ability_hand.size() == 3, "старт 3+3 карты")
	a._draw_turn_card(0)
	b._draw_turn_card(0)
	_check(a.state.players[0].arena_hand.size() + a.state.players[0].ability_hand.size() == 6, "первый ход без лишней карты")
	for i in range(8):
		a._draw_turn_card(0)
		b._draw_turn_card(0)
	_check(a.state.players[0].arena_hand.size() + a.state.players[0].ability_hand.size() == 14, "по одной карте каждый следующий ход")
	_check(a.state.players[0].arena_hand == b.state.players[0].arena_hand and a.state.players[0].ability_hand == b.state.players[0].ability_hand, "детерминированный добор")
	var seen: Dictionary = {}
	for id in a.state.players[0].arena_hand + a.state.players[0].ability_hand:
		_check(not seen.has(id), "добор без повторов")
		seen[id] = true
	var view := a.get_view(1)
	_check(view.players[0].ability_hand[0] == &"", "добранные карты скрыты от соперника")
	for i in range(200):
		a._draw_turn_card(0)
	_check(a._draw_pools[0][0].is_empty() and a._draw_pools[0][1].is_empty(), "исчерпание запаса не создаёт повторов")


## Две стихии используют одну сетку, но золотая палитра не должна протекать в другой экземпляр.
func _test_model_material_isolation() -> void:
	var light := CreatureModels.build(CardDB.creature(&"creature_kolossar_light"))
	var gale := CreatureModels.build(CardDB.creature(&"creature_kolossar_gale"))
	var lm := _model_first_material(light)
	var gm := _model_first_material(gale)
	_check(lm != null and gm != null, "материалы двух вариантов существа доступны")
	if lm != null and gm != null:
		_check(lm != gm, "варианты не разделяют изменяемый материал")
		_check(lm.get_shader_parameter("gold_palette") == true, "у светлого варианта золотая палитра")
		_check(gm.get_shader_parameter("gold_palette") == false, "палитра другого варианта не меняется")
	light.free()
	gale.free()
	CreatureModels.clear()


func _model_first_material(node: Node) -> ShaderMaterial:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_surface_count() > 0:
		return node.get_active_material(0) as ShaderMaterial
	for child in node.get_children():
		var found := _model_first_material(child)
		if found != null:
			return found
	return null
