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
const ZH: StringName = &"test_fire"
const VI: StringName = &"test_gale"
const LU: StringName = &"test_light"
const GR: StringName = &"test_stone"
const SU: StringName = &"test_shadow"
const MA: StringName = &"test_tide"
const TEST_POWER: Array = [340, 300, 330, 370, 350, 320]

var _failures: int = 0
var _checks: int = 0
var _go_winner: int = -2
var _go_reason: StringName = &""
var _cancel_events: int = 0


## Тестовые существа кладутся только в словарь определений: в creature_ids() и случайные колоды они не попадают.
func _add_test_creatures() -> void:
	var ids: Array[StringName] = [ZH, VI, LU, GR, SU, MA]
	for a in ids.size():
		CardDB._creatures[String(ids[a])] = CreatureDef.make(ids[a], String(ids[a]), a, TEST_POWER[a], Color.WHITE)


## Колоды сценариев матча из тестовых существ (как прежние пресеты): планы боёв в тестах опираются на эти БС.
func _test_deck(index: int) -> DeckDef:
	if index % 2 == 0:
		return CardDB.build_deck([ZH, LU, GR], [&"arena_field_fire", &"arena_lowland", &"arena_bastion"],
			[&"ability_surge", &"ability_shield", &"ability_homeland"])
	return CardDB.build_deck([VI, SU, MA], [&"arena_field_tide", &"arena_void", &"arena_twilight"],
		[&"ability_overflow", &"ability_silencer", &"ability_legacy"])


func _initialize() -> void:
	CardDB.load_all()
	_add_test_creatures()
	_test_card_db()
	_test_attribute_table()
	_test_tie_goes_to_defender()
	_test_arena_cards()
	_test_abilities()
	_test_new_abilities()
	_test_fusion_window()
	_test_exchange()
	_test_attach_moments()
	_test_gate_throw()
	_test_gate_bonus()
	_test_gate_traps()
	_test_momentum()
	_test_final_round()
	_test_ai_levels()
	_test_shield_and_silencer_interplay()
	_test_hidden_info()
	_test_used_zone_refill()
	_test_gate_placement_rules()
	_test_win_by_three_captures()
	_test_own_gate()
	_test_no_recall_and_standoff()
	_test_all_in_loss()
	_test_turn_limit()
	_test_determinism()
	_test_simulation()
	print("")
	print("Проверок: %d, ошибок: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- утилиты

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: " + msg)


func _on_game_over(w: int, reason: StringName) -> void:
	_go_winner = w
	_go_reason = reason


func _on_cancelled(_p: int, _c: StringName) -> void:
	_cancel_events += 1


func _mk_state(atk_id: StringName, def_id: StringName, card_id: StringName) -> MatchState:
	var st: MatchState = MatchState.new()
	st.creatures[0] = CreatureState.new(0, atk_id, 0)
	st.players[0].creature_uids.append(0)
	st.creatures[1] = CreatureState.new(1, def_id, 1)
	st.players[1].creature_uids.append(1)
	st.slots[0].card_id = card_id
	st.slots[0].card_owner = 1
	st.slots[0].has_card = card_id != &""
	return st


func _calc(st: MatchState, a: StringName = &"", d: StringName = &"") -> BattleResult:
	return PowerCalc.compute(st, 0, 1, 0, a, d)


func _expect(label: String, atk_id: StringName, def_id: StringName, card_id: StringName, a: StringName, d: StringName, e0: int, e1: int) -> void:
	var st: MatchState = _mk_state(atk_id, def_id, card_id)
	var r: BattleResult = _calc(st, a, d)
	_check(r.powers[0] == e0 and r.powers[1] == e1, "%s: ожидалось %d:%d, получено %d:%d" % [label, e0, e1, r.powers[0], r.powers[1]])


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


# ---------------------------------------------------------------- тесты

func _test_card_db() -> void:
	# колода по правилам Бакугана
	var drng := RandomNumberGenerator.new()
	drng.seed = 99
	for _k in range(30):
		var dk: DeckDef = CardDB.random_deck(drng)
		var cs: Array = dk.creatures.map(func(d: CreatureDef) -> StringName: return d.id)
		var ar: Array = dk.arena.map(func(c: CardDef) -> StringName: return c.id)
		var ab: Array = dk.abilities.map(func(c: CardDef) -> StringName: return c.id)
		var e: String = CardDB.deck_error(cs, ar, ab)
		_check(e == "", "случайная колода по правилам: %s" % e)
	var fire: Array = [&"creature_dragnar_fire", &"creature_klykar_fire", &"creature_grifalon_fire"]
	var gates: Array = [&"arena_field_fire", &"arena_bastion", &"arena_void"]
	var abil: Array = [&"ability_firestorm", &"ability_surge", &"ability_shield"]
	_check(CardDB.deck_error(fire, gates, abil) == "", "колода Пламени годится")
	_check(CardDB.deck_error([&"creature_dragnar_fire", &"creature_grifalon_gale", &"creature_klykar_fire"], gates, abil) != "", "смешанные стихии запрещены")
	_check(CardDB.deck_error(fire, [&"arena_field_fire", &"arena_field_gale", &"arena_void"], abil) != "", "два золотых ворот запрещены")
	_check(CardDB.deck_error(fire, gates, [&"ability_headwind", &"ability_surge", &"ability_shield"]) != "", "чужая стихийная способность запрещена")
	_check(CardDB.deck_error(fire, gates, [&"ability_firestorm", &"ability_hamstring", &"ability_surge"]) != "", "нужна зелёная способность")
	_check(CardDB.creature_ids().size() == GameData.SPECIES.size() * 6, "каждый вид во всех 6 стихиях")
	var per_attr: Array[int] = [0, 0, 0, 0, 0, 0]
	for d in CardDB.all_creatures():
		per_attr[d.attribute] += 1
	_check(per_attr.min() >= 3, "по 3+ существа каждой стихии: %s" % str(per_attr))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok_deck: DeckDef = CardDB.deck_from_creatures([&"creature_dragnar_fire", &"creature_ratnik_light", &"creature_rogozhuk_stone"], rng)
	_check(ok_deck != null and ok_deck.creatures.size() == 3 and ok_deck.arena.size() == 3 and ok_deck.abilities.size() == 3, "колода из выбранных существ")
	_check(CardDB.deck_from_creatures([&"creature_kolossar_stone", &"creature_kolossar_gale", &"creature_kolossar_tide"], rng) == null, "лимит БС команды")
	_check(CardDB.deck_from_creatures([&"creature_dragnar_fire", &"creature_dragnar_fire", &"creature_klykar_fire"], rng) == null, "повтор существа запрещён")
	for i in range(50):
		var rd: DeckDef = CardDB.random_deck(rng)
		var ids: Array = rd.creatures.map(func(d): return d.id)
		_check(CardDB.team_power(ids) <= CardDB.team_power_limit(), "случайная колода в лимите БС")
	_check(CardDB.arena_ids().size() == 16, "16 карт ворот (12 + Престол + 3 ловушки)")
	_check(CardDB.ability_ids().size() == 20, "20 карт способностей")
	for i in range(2):
		var d: DeckDef = CardDB.preset_deck(i)
		_check(d.creatures.size() == 3 and d.arena.size() == 3 and d.abilities.size() == 3, "пресет %d: 3+3+3" % i)
		for c in d.creatures:
			_check(c != null, "пресет %d: существо найдено" % i)
		for c in d.arena:
			_check(c != null and c.kind == CardDef.Kind.ARENA, "пресет %d: арена" % i)
		for c in d.abilities:
			_check(c != null and c.kind == CardDef.Kind.ABILITY, "пресет %d: способности" % i)
	_check(CardDB.card(&"nope") == null, "неизвестная карта = null")


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
	var st2: MatchState = _mk_state(GR, ZH, &"")
	_check(_calc(st2).winner_uid == 0, "сильнейший атакующий побеждает")


func _test_arena_cards() -> void:
	# Жаровик (Пламя 340) атакует Вихрекрыла (Буря 300): Пламя бьёт Бурю -> база 400:300
	_expect("без карты", ZH, VI, &"", &"", &"", 400, 300)
	_expect("Поле Пламени", ZH, VI, &"arena_field_fire", &"", &"", 550, 300)
	_expect("Поле Бури", ZH, VI, &"arena_field_gale", &"", &"", 400, 450)
	_expect("Поле Света (мимо)", ZH, VI, &"arena_field_light", &"", &"", 400, 300)
	_expect("Поле Камня (мимо)", ZH, VI, &"arena_field_stone", &"", &"", 400, 300)
	_expect("Поле Тени (мимо)", ZH, VI, &"arena_field_shadow", &"", &"", 400, 300)
	_expect("Поле Прилива (мимо)", ZH, VI, &"arena_field_tide", &"", &"", 400, 300)
	_expect("Низина", ZH, VI, &"arena_lowland", &"", &"", 400, 450)
	_expect("Пустота", ZH, VI, &"arena_void", &"", &"", 340, 300)
	_expect("Перевес", ZH, VI, &"arena_overweight", &"", &"", 460, 300)
	_expect("Ловушка", ZH, VI, &"arena_trap", &"", &"", 300, 300)
	_expect("Бастион", ZH, VI, &"arena_bastion", &"", &"", 400, 400)
	_expect("Сумерки (мимо)", ZH, VI, &"arena_twilight", &"", &"", 400, 300)
	# Люминар (Свет 330) vs Сумрачник (Тень 350): преимущества нет
	_expect("Свет/Тень без карты", LU, SU, &"", &"", &"", 330, 350)
	_expect("Сумерки", LU, SU, &"arena_twilight", &"", &"", 400, 420)
	# Низина при равной БС ничего не даёт
	_expect("Низина равные БС", ZH, ZH, &"arena_lowland", &"", &"", 340, 340)


func _test_abilities() -> void:
	_expect("Рывок", ZH, VI, &"", &"ability_surge", &"", 480, 300)
	_expect("Рывок защитника", ZH, VI, &"", &"", &"ability_surge", 400, 380)
	_expect("Подсечка", ZH, VI, &"", &"ability_hamstring", &"", 400, 220)
	# Перелив защитника: Буря -> Прилив (бьёт Пламя); атакующий теряет своё преимущество
	_expect("Перелив защитника", ZH, VI, &"", &"", &"ability_overflow", 340, 360)
	_expect("Перелив атакующего (уже бьёт)", ZH, VI, &"", &"ability_overflow", &"", 400, 300)
	# Перелив происходит до карты арены: Прилив получает Поле Прилива
	_expect("Перелив + Поле Прилива", ZH, VI, &"arena_field_tide", &"", &"ability_overflow", 340, 510)
	_expect("Глушитель атакующего", ZH, VI, &"arena_field_fire", &"ability_silencer", &"", 400, 300)
	_expect("Глушитель защитника", ZH, VI, &"arena_field_fire", &"", &"ability_silencer", 400, 300)
	_expect("Щит против Рывка", ZH, VI, &"", &"ability_surge", &"ability_shield", 400, 300)
	_expect("Щит против Подсечки", ZH, VI, &"", &"ability_shield", &"ability_hamstring", 400, 300)
	_expect("Два Щита", ZH, VI, &"", &"ability_shield", &"ability_shield", 400, 300)
	_expect("Ва-банк", ZH, VI, &"", &"ability_allin", &"", 530, 300)
	_expect("Родная стихия без поля", ZH, VI, &"", &"ability_homeland", &"", 400, 300)
	_expect("Родная стихия + Поле Пламени", ZH, VI, &"arena_field_fire", &"ability_homeland", &"", 650, 300)
	_expect("Родная стихия + Глушитель", ZH, VI, &"arena_field_fire", &"ability_homeland", &"ability_silencer", 400, 300)
	# Наследие: +40 за каждое выбывшее своё существо
	var st: MatchState = _mk_state(ZH, VI, &"")
	var dead1: CreatureState = CreatureState.new(2, LU, 0)
	dead1.alive = false
	st.creatures[2] = dead1
	st.players[0].creature_uids.append(2)
	var dead2: CreatureState = CreatureState.new(3, GR, 0)
	dead2.alive = false
	st.creatures[3] = dead2
	st.players[0].creature_uids.append(3)
	var r: BattleResult = _calc(st, &"ability_legacy", &"")
	_check(r.powers[0] == 400 + 80 and r.powers[1] == 300, "Наследие x2: %d:%d" % [r.powers[0], r.powers[1]])
	var r0: BattleResult = _calc(_mk_state(ZH, VI, &""), &"ability_legacy", &"")
	_check(r0.powers[0] == 400, "Наследие без потерь = 0")
	# Нижняя граница: Подсечка не опускает силу ниже 0 (проверка через экстремальный случай)
	var st2: MatchState = _mk_state(ZH, VI, &"arena_trap")
	var r2: BattleResult = _calc(st2, &"", &"ability_hamstring")
	_check(r2.powers[0] >= 0, "нижняя граница 0")
	_check(not r.breakdown.is_empty(), "breakdown заполнен")


func _test_shield_and_silencer_interplay() -> void:
	# Щит атакующего отменяет Глушитель защитника -> арена действует
	_expect("Щит отменяет Глушитель", ZH, VI, &"arena_field_fire", &"ability_shield", &"ability_silencer", 550, 300)
	var st: MatchState = _mk_state(ZH, VI, &"arena_field_fire")
	var r: BattleResult = _calc(st, &"ability_shield", &"ability_silencer")
	_check(r.def_cancelled and not r.atk_cancelled, "Щит: флаги отмены")
	var r2: BattleResult = _calc(st, &"", &"ability_silencer")
	_check(r2.arena_cancelled, "Глушитель: арена отменена")


func _test_hidden_info() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 5)
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
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 11)
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
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 12)
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
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 41)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	_stand(ctrl, 0, 0)
	_stand(ctrl, 1, 2)
	_throw(ctrl, 0, 2, 4)
	_check(ctrl.state.creatures[2].slot == 4, "последнее существо P0 встало на ворота")
	_throw(ctrl, 1, 3, -1)  # P1 промахнулся
	_check(ctrl.event_log.any(func(e: String) -> bool: return e.begins_with("turn_skipped(0")), "P0 пропускает ход: бросать некого")
	_check(ctrl.get_active_player() == 1 and ctrl.get_phase() == MatchController.Phase.AWAIT_THROW, "ход перешёл к P1")
	_check(ctrl.state.creatures[0].slot == 0 and ctrl.state.creatures[1].slot == 2, "стоящие P0 не отозваны")
	var c2: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 42)
	_setup_controller(c2)
	for i in range(6):
		_set_card(c2, i, &"arena_void", i % 2)
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
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 31)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	_stand(ctrl, 0, 0)
	_stand(ctrl, 3, 4)
	var moved: Array = []
	ctrl.creature_relocated.connect(func(u: int, a: int, b: int) -> void: moved.append([u, a, b]))
	_throw(ctrl, 0, 2, 0)
	_check(moved.size() == 1 and moved[0] == [2, 0, 4], "переставлено на ворота с соперником: %s" % str(moved))
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "начался бой после перестановки")
	_pass_windows(ctrl)
	_check(ctrl.state.players[0].captured.size() == 1, "Гранитрог выиграл перенесённый бой")
	var c2: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 32)
	_setup_controller(c2)
	for i in range(6):
		var sl: SlotState = c2.state.slots[i]
		sl.has_card = false
		sl.card_id = &""
	_set_card(c2, 2, &"arena_void", 0)
	_stand(c2, 0, 2)
	_throw(c2, 0, 1, 2)
	_check(c2.event_log.any(func(e: String) -> bool: return e.begins_with("card_captured(0, 2")), "ворота со своими засчитаны")
	_check(c2.state.creatures[0].used and c2.state.creatures[1].used, "оба своих ушли в использованные")
	_check(not c2.state.slots[2].has_card, "карта убрана с поля")


func _test_win_by_three_captures() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 21)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
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


func _test_all_in_loss() -> void:
	# Мареолит (320) +130 Ва-банк -80 Ловушка = 370 против Гранитрога 370 -> ничья, побеждает защитник
	var deck0: DeckDef = _mk_deck([MA, ZH, LU], ["arena_void", "arena_void", "arena_void"], ["ability_allin", "ability_surge", "ability_shield"])
	var deck1: DeckDef = _mk_deck([GR, VI, SU], ["arena_void", "arena_void", "arena_void"], ["ability_surge", "ability_shield", "ability_legacy"])
	var ctrl: MatchController = MatchController.new(deck0, deck1, 41)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	_set_card(ctrl, 1, &"arena_trap", 1)
	_stand(ctrl, 3, 1)
	_cancel_events = 0
	ctrl.ability_cancelled.connect(_on_cancelled)
	_throw(ctrl, 0, 0, 1)
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 0, "окно атакующего")
	_check(ctrl.legal_abilities(0).size() == 3, "у атакующего 3 способности")
	_check(ctrl.legal_abilities(1).is_empty(), "у защитника пока нет окна")
	_check(ctrl.play_ability(0, &"ability_allin") == OK, "Ва-банк сыгран")
	_check(ctrl.play_ability(0, &"ability_surge") != OK, "второй раз за бой нельзя / не его окно")
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre != null and pre.atk_ability == &"ability_allin", "предпросмотр учитывает сыгранное")
	_check(ctrl.pass_ability(1) == OK, "защитник пасует")
	_pass_windows(ctrl)  # атакующий может доиграть — пасует
	_check(not ctrl.state.creatures[0].alive, "проигравший Мареолит выбыл")
	_check(ctrl.state.creatures[3].used and ctrl.state.creatures[3].slot == -1, "Гранитрог тоже в зоне использованных")
	_check(ctrl.state.players[0].ability_hand.size() == 1, "после Ва-банка и потери в руке 1 карта, а не %d" % ctrl.state.players[0].ability_hand.size())
	_check(ctrl.state.players[1].captured.size() == 1, "защитник захватил карту")
	_check(ctrl.get_active_player() == 1, "ходит победитель P1")
	# Ва-банк, отменённый Щитом, ничего не теряет
	var ctrl2: MatchController = MatchController.new(deck0, deck1, 42)
	_setup_controller(ctrl2)
	for i in range(6):
		_set_card(ctrl2, i, &"arena_void", i % 2)
	_set_card(ctrl2, 1, &"arena_trap", 1)
	_stand(ctrl2, 3, 1)
	ctrl2.ability_cancelled.connect(_on_cancelled)
	_cancel_events = 0
	_throw(ctrl2, 0, 0, 1)
	ctrl2.play_ability(0, &"ability_allin")
	ctrl2.play_ability(1, &"ability_shield")
	_check(ctrl2.get_ability_moment() == &"battle" and ctrl2.get_active_player() == 0, "после Щита защитника черёд атакующего")
	_pass_windows(ctrl2)
	_check(_cancel_events == 1, "ability_cancelled эмитнут один раз")
	_check(ctrl2.state.players[0].ability_hand.size() == 2, "отменённый Ва-банк не отнимает карту")


func _test_turn_limit() -> void:
	# A против B: суммы БС живых 1040 против 970 -> побеждает P0
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 51)
	_setup_controller(ctrl)
	_go_winner = -2
	_go_reason = &""
	ctrl.game_over.connect(_on_game_over)
	_idle_until_end(ctrl)
	_check(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "лимит ходов: матч окончен")
	_check(_go_reason == &"turn_limit" and _go_winner == 0, "тай-брейк по сумме БС: %d %s" % [_go_winner, String(_go_reason)])
	_check(ctrl.state.turn == MatchController.MAX_TURNS, "сыграно ровно MAX_TURNS ходов, а не %d" % ctrl.state.turn)
	# зеркальные колоды -> ничья
	var ctrl2: MatchController = MatchController.new(_test_deck(0), _test_deck(0), 52)
	_setup_controller(ctrl2)
	_go_winner = -2
	ctrl2.game_over.connect(_on_game_over)
	_idle_until_end(ctrl2)
	_check(_go_winner == -1 and _go_reason == &"turn_limit", "ничья при равенстве: %d" % _go_winner)
	# число захваченных карт важнее суммы БС
	var ctrl3: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 53)
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
func _run_match(seed_value: int) -> Dictionary:
	var out: Dictionary = {"ok": false, "error": "", "winner": -2, "reason": &"", "turns": 0, "log_hash": 0, "log_len": 0, "throws": 0, "hits": 0}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck0: DeckDef = CardDB.random_deck(rng)
	var deck1: DeckDef = CardDB.random_deck(rng)
	var ctrl: MatchController = MatchController.new(deck0, deck1, seed_value)
	ctrl.landing_window = true
	var ais: Array[AIPlayer] = [AIPlayer.new(0, seed_value + 1), AIPlayer.new(1, seed_value + 2)]
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


# ---------------------------------------------------------------- стихийные, слияния, особые

func _fx(label: String, atk_id: StringName, def_id: StringName, card_id: StringName, a: StringName, d: StringName, af: StringName, df: StringName, e0: int, e1: int) -> BattleResult:
	var st: MatchState = _mk_state(atk_id, def_id, card_id)
	var r: BattleResult = PowerCalc.compute(st, 0, 1, 0, a, d, af, df)
	_check(r.powers[0] == e0 and r.powers[1] == e1, "%s: ожидалось %d:%d, получено %d:%d" % [label, e0, e1, r.powers[0], r.powers[1]])
	return r


func _test_new_abilities() -> void:
	_expect("Огненный смерч", ZH, VI, &"", &"ability_firestorm", &"", 470, 230)
	_expect("Встречный ветер забирает преимущество", ZH, VI, &"", &"", &"ability_headwind", 340, 400)
	_expect("Ослепление гасит Рывок", ZH, LU, &"", &"ability_surge", &"ability_blind", 340, 330)
	_expect("Гранитная стена в защите", ZH, GR, &"", &"", &"ability_granite", 340, 530)
	_expect("Гранитная стена в атаке", GR, ZH, &"", &"ability_granite", &"", 460, 340)
	_expect("Поглощение половины бонусов", ZH, SU, &"", &"ability_surge", &"ability_absorb", 380, 390)
	_expect("Водоворот меняет стихии", ZH, MA, &"", &"", &"ability_whirlpool", 400, 350)
	_expect("Обмен сутью", ZH, VI, &"", &"", &"ability_essence", 360, 340)
	_expect("Перехват поля", ZH, VI, &"arena_field_fire", &"", &"ability_intercept", 400, 450)
	_expect("Щит против Огненного смерча", ZH, VI, &"", &"ability_firestorm", &"ability_shield", 400, 300)
	_fx("Резонанс удваивает Рывок", ZH, VI, &"", &"ability_surge", &"", &"ability_resonance", &"", 560, 300)
	_fx("Резонанс + Смерч", ZH, VI, &"", &"ability_firestorm", &"", &"ability_resonance", &"", 540, 160)
	_fx("Цепная искра против Щита", ZH, VI, &"", &"ability_surge", &"ability_shield", &"ability_chain", &"", 530, 300)
	_fx("Слияние без основной карты не действует", ZH, VI, &"", &"ability_surge", &"ability_shield", &"ability_resonance", &"", 400, 300)
	_fx("Отголосок", ZH, VI, &"", &"ability_surge", &"", &"ability_echo", &"", 510, 300)
	var r: BattleResult = _fx("Спасение", ZH, VI, &"", &"", &"ability_rescue", &"", &"", 400, 320)
	_check(r.def_rescue and not r.atk_rescue, "Спасение помечено у защитника")


## Слияние в обмене способностями и стихийный замок; «Спасение» возвращает проигравшего в резерв.
func _test_fusion_window() -> void:
	var deck0: DeckDef = _mk_deck([ZH, LU, GR], ["arena_void", "arena_void", "arena_void"], ["ability_surge", "ability_resonance", "ability_headwind"])
	var deck1: DeckDef = _mk_deck([VI, SU, MA], ["arena_void", "arena_void", "arena_void"], ["ability_rescue", "ability_shield", "ability_legacy"])
	var ctrl: MatchController = MatchController.new(deck0, deck1, 5)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	var lu: int = ctrl.state.players[0].creature_uids[1]
	var vi: int = ctrl.state.players[1].creature_uids[0]
	_stand(ctrl, vi, 0)
	_throw(ctrl, 0, lu, 0)
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 0, "бой: обмен начинает игрок, чей ход")
	var legal: Array[StringName] = ctrl.legal_abilities(0)
	_check(legal.has(&"ability_surge") and not legal.has(&"ability_resonance") and not legal.has(&"ability_headwind"),
		"слияние без основной карты и чужая стихия недоступны: %s" % str(legal))
	_check(ctrl.play_ability(0, &"ability_resonance") != OK, "слияние нельзя сыграть первым")
	_check(ctrl.play_ability(0, &"ability_surge") == OK, "основная карта сыграна")
	_check(ctrl.get_active_player() == 1, "черёд защитника")
	_check(ctrl.play_ability(1, &"ability_rescue") == OK, "Спасение сыграно")
	_check(ctrl.get_active_player() == 0 and ctrl.legal_abilities(0) == [&"ability_resonance"], "атакующему доступно слияние поверх Рывка")
	_check(ctrl.play_ability(0, &"ability_resonance") == OK, "слияние сыграно")
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre != null and pre.powers[0] == 330 + 160 and pre.powers[1] == 320, "предпросмотр со слиянием: %s" % (pre.to_log_string() if pre else "null"))
	_check(ctrl.pass_ability(1) == OK, "защитник пасует")
	_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "атакующему нечего доиграть — бой решён")
	_check(ctrl.state.creatures[vi].alive and ctrl.state.creatures[vi].used, "Спасение: Вихрекрыл не выбыл, а в зоне использованных")
	_check(ctrl.state.players[0].captured.size() == 1, "карта ворот у победителя")
	_check(ctrl.state.creatures[lu].used, "победитель в зоне использованных")


# ---------------------------------------------------------------- механики «Боя как в аниме»

## Бой P0 (uid atk) против стоящего P1 (uid dfn) на воротах card в слоте 1; остальные ворота — Пустота.
func _battle_ctrl(abil0: Array, abil1: Array, card: StringName, atk_idx: int, def_idx: int, rng_seed: int, landing: bool = false) -> MatchController:
	var deck0: DeckDef = _mk_deck([ZH, LU, GR], ["arena_void", "arena_void", "arena_void"], abil0)
	var deck1: DeckDef = _mk_deck([VI, SU, MA], ["arena_void", "arena_void", "arena_void"], abil1)
	var ctrl: MatchController = MatchController.new(deck0, deck1, rng_seed)
	ctrl.landing_window = landing
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	_set_card(ctrl, 1, card, 1)
	if atk_idx >= 0:
		_stand(ctrl, ctrl.state.players[1].creature_uids[def_idx], 1)
		_throw(ctrl, 0, ctrl.state.players[0].creature_uids[atk_idx], 1)
	return ctrl


## Обмен способностями: поочерёдно, пас окончателен, второй доигрывает, не больше 3 карт на игрока за бой.
func _test_exchange() -> void:
	var ab3: Array = ["ability_surge", "ability_hamstring", "ability_allin"]
	var ctrl: MatchController = _battle_ctrl(ab3, ["ability_surge", "ability_hamstring", "ability_legacy"], &"arena_void", 0, 0, 61)
	var log: Array = []
	ctrl.ability_window.connect(func(p: int, _o: Array) -> void: log.append(p))
	_check(ctrl.get_ability_moment() == &"battle" and ctrl.abilities_left(0) == 3, "в бою 3 карты на игрока")
	_check(ctrl.state.slots[1].revealed, "ворота открыты до обмена способностями")
	_check(ctrl.play_ability(1, &"ability_surge") != OK, "не черёд защитника")
	ctrl.play_ability(0, &"ability_surge")
	ctrl.play_ability(1, &"ability_surge")
	ctrl.pass_ability(0)
	_check(ctrl.get_active_player() == 1 and ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "после паса атакующего защитник доигрывает")
	ctrl.play_ability(1, &"ability_hamstring")
	_check(ctrl.get_active_player() == 1, "спасовавший больше не получает окон")
	_check(ctrl.play_ability(0, &"ability_hamstring") != OK, "пас окончателен")
	ctrl.play_ability(1, &"ability_legacy")
	_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "у защитника 3 карты — обмен окончен")
	_check(log == [1, 0, 1, 1], "порядок окон после первого: %s" % str(log))
	# лимит 3 карты: атакующий играет все три подряд, защитник пасует
	var c2: MatchController = _battle_ctrl(ab3, ["ability_legacy", "ability_shield", "ability_hamstring"], &"arena_void", 0, 0, 62)
	c2.play_ability(0, &"ability_surge")
	c2.pass_ability(1)
	c2.play_ability(0, &"ability_hamstring")
	_check(c2.abilities_left(0) == 1, "осталась одна карта из трёх")
	c2.play_ability(0, &"ability_allin")
	_check(c2.get_phase() != MatchController.Phase.ABILITY_WINDOW, "после третьей карты бой решён")
	# Щиты в цепочке: Щит отменяет последнюю основную карту соперника до него, иначе следующую
	_expect("Рывок, Щит, Щит: второй Щит отменяет первый", ZH, VI, &"", &"", &"", 400, 300)
	var st: MatchState = _mk_state(ZH, VI, &"")
	var r1: BattleResult = PowerCalc.compute_seq(st, 0, 1, 0, [[0, &"ability_surge"], [1, &"ability_shield"], [0, &"ability_shield"]])
	_check(r1.powers[0] == 480 and r1.def_cancelled and r1.cancelled_plays == [[1, &"ability_shield"]], "Щит на Щит возвращает Рывок: %s" % r1.to_log_string())
	var r2: BattleResult = PowerCalc.compute_seq(st, 0, 1, 0, [[0, &"ability_surge"], [1, &"ability_shield"], [0, &"ability_hamstring"]])
	_check(r2.powers[0] == 400 and r2.powers[1] == 220, "Рывок отменён, Подсечка после Щита действует: %d:%d" % [r2.powers[0], r2.powers[1]])
	var r3: BattleResult = PowerCalc.compute_seq(st, 0, 1, 0, [[0, &"ability_surge"], [0, &"ability_hamstring"], [1, &"ability_shield"]])
	_check(r3.powers[0] == 480 and r3.powers[1] == 300, "Щит отменяет только последнюю карту (Подсечку): %d:%d" % [r3.powers[0], r3.powers[1]])
	var r4: BattleResult = PowerCalc.compute_seq(st, 0, 1, 0, [[0, &"ability_surge"], [0, &"ability_surge"]])
	_check(r4.powers[0] == 560, "две основные карты складываются: %d" % r4.powers[0])


## Способности вне боя: до броска и после приземления карта прикрепляется к существу и срабатывает в его бою.
func _test_attach_moments() -> void:
	var deck0: DeckDef = _mk_deck([ZH, LU, GR], ["arena_void", "arena_void", "arena_void"], ["ability_surge", "ability_hamstring", "ability_allin"])
	var deck1: DeckDef = _mk_deck([VI, SU, MA], ["arena_void", "arena_void", "arena_void"], ["ability_granite", "ability_shield", "ability_legacy"])
	var ctrl: MatchController = MatchController.new(deck0, deck1, 71)
	ctrl.landing_window = true
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	var att: Array = []
	ctrl.ability_attached.connect(func(p: int, u: int, c: StringName) -> void: att.append([p, u, c]))
	var zh: int = ctrl.state.players[0].creature_uids[0]
	_check(ctrl.select_creature(0, zh) == OK, "существо выбрано")
	_check(ctrl.get_ability_moment() == &"pre_throw" and ctrl.legal_abilities(0).size() == 3, "до броска можно сыграть способность")
	_check(ctrl.play_ability(0, &"ability_surge") == OK, "Рывок до броска")
	_check(att == [[0, zh, &"ability_surge"]] and ctrl.state.creatures[zh].attached.size() == 1, "Рывок прикреплён к существу")
	_check(ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING, "фаза броска не меняется")
	var wins: Array = []
	ctrl.attach_window.connect(func(p: int, u: int, _o: Array) -> void: wins.append([p, u]))
	ctrl.report_landing(zh, 0)
	_check(ctrl.get_phase() == MatchController.Phase.AFTER_LANDING and wins == [[0, zh]], "окно после приземления")
	_check(ctrl.get_landed_uid() == zh and ctrl.get_ability_moment() == &"after_landing", "запросы окна после приземления")
	_check(ctrl.pass_ability(0) == OK and ctrl.get_active_player() == 1, "пас — ход сопернику")
	# соперник атакует: Рывок срабатывает в бою, считается в лимит
	var su: int = ctrl.state.players[1].creature_uids[1]
	_throw(ctrl, 1, su, 0)
	_check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 1, "бой: начинает игрок, чей ход (атакующий P1)")
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.powers[1] == 340 + 80 and pre.plays.size() == 1, "прикреплённый Рывок действует в бою: %s" % pre.to_log_string())
	ctrl.pass_ability(1)
	_check(ctrl.abilities_left(0) == 2, "прикреплённая карта занимает место в лимите")
	ctrl.pass_ability(0)
	_check(ctrl.state.creatures[zh].attached.is_empty(), "после боя прикреплённые карты сняты")
	_check(ctrl.state.players[0].captured.size() == 1, "Жаровик (420) отбился от Сумрачника (350)")
	# без landing_window окна после приземления нет
	var c2: MatchController = MatchController.new(deck0, deck1, 72)
	_setup_controller(c2)
	_throw(c2, 0, 0, 0)
	_check(c2.get_active_player() == 1, "окно после приземления выключено по умолчанию")
	# стихийный замок для прикрепления: Гранитная стена только Камню
	var c3: MatchController = MatchController.new(deck1, deck0, 73)
	_setup_controller(c3)
	c3.select_creature(0, c3.state.players[0].creature_uids[0])
	_check(not c3.legal_abilities(0).has(&"ability_granite"), "чужая стихия не прикрепляется")


## «Ворота + бросок»: карта ворот ложится в момент броска, цель — эта карта.
func _test_gate_throw() -> void:
	var ctrl: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 81)
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
	var c2: MatchController = MatchController.new(_test_deck(0), _test_deck(1), 82)
	c2.start()
	c2.throw_with_gate(0, c2.state.players[0].arena_hand[0], 0, 1)
	c2.report_landing(1, -1)
	_check(c2.state.creatures[1].used and c2.state.slots[0].has_card, "промах: карта лежит, существо в зоне использованных")


## Бонус ворот только своей стихии; «Престол стихии».
func _test_gate_bonus() -> void:
	var g: Array = CardDB.card(&"arena_field_fire").params["g"]
	_check(g == [150, 0, 0, 0, 0, 0], "Поле Пламени даёт G только Пламени: %s" % str(g))
	for id in CardDB.arena_ids():
		var c: CardDef = CardDB.card(id)
		var amt: int = absi(int(c.params.get("amount", 0)))
		_check(amt == 0 or (amt >= 50 and amt <= 500), "бонус ворот %s в рамках 50–500" % id)
	_check(CardDB.card_class(CardDB.card(&"arena_throne")) == &"gold", "Престол — золотые ворота")
	# Престол владельца P1 (стихия команды — Буря у VI): защитник Буря +500, атакующий не получает
	var st: MatchState = _mk_state(ZH, VI, &"arena_throne")
	var r: BattleResult = _calc(st)
	_check(r.powers[0] == 400 and r.powers[1] == 800, "Престол: защитник своей стихии +500: %d:%d" % [r.powers[0], r.powers[1]])
	st.slots[0].card_owner = 0
	r = _calc(st)
	_check(r.powers[1] == 300, "Престол чужой стихии не помогает защитнику")


## Ловушки ворот: открываются в начале боя.
func _test_gate_traps() -> void:
	_check(CardEffects.is_gate_trap(CardDB.card(&"arena_seal")) and not CardEffects.is_gate_trap(CardDB.card(&"arena_trap")), "флаг ловушки")
	for id in [&"arena_seal", &"arena_mirror", &"arena_backflow"]:
		_check(CardDB.card_class(CardDB.card(id)) == &"bronze", "ловушка %s — бронзовая" % id)
	# Печать тишины: способности не играются, прикреплённые сгорают
	var ctrl: MatchController = _battle_ctrl(["ability_surge", "ability_shield", "ability_homeland"], ["ability_surge", "ability_shield", "ability_legacy"], &"arena_seal", -1, 0, 91)
	var traps: Array = []
	ctrl.gate_trap_triggered.connect(func(sl: int, c: StringName, e: StringName) -> void: traps.append([sl, c, e]))
	var cancels: Array = []
	ctrl.ability_cancelled.connect(func(p: int, c: StringName) -> void: cancels.append([p, c]))
	_stand(ctrl, 3, 1)
	ctrl.select_creature(0, 2)
	ctrl.play_ability(0, &"ability_surge")  # Рывок до броска
	ctrl.report_landing(2, 1)
	_check(traps == [[1, &"arena_seal", &"seal"]], "событие ловушки при открытии: %s" % str(traps))
	_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "Печать тишины: окон способностей нет")
	_check(cancels == [[0, &"ability_surge"]], "прикреплённый Рывок сгорел: %s" % str(cancels))
	_check(ctrl.state.players[0].captured.size() == 1, "Гранитрог 370 > Вихрекрыл 300 без способностей")
	# Зеркало: силы меняются; Глушитель отменяет ловушку
	_expect("Зеркало", ZH, VI, &"arena_mirror", &"", &"", 300, 400)
	_check(_calc(_mk_state(ZH, VI, &"arena_mirror")).mirrored, "флаг Зеркала")
	_expect("Зеркало + Глушитель", ZH, VI, &"arena_mirror", &"", &"ability_silencer", 400, 300)
	_expect("Зеркало + Рывок вредит", ZH, VI, &"arena_mirror", &"ability_surge", &"", 300, 480)
	# Обратный ток: преимущество у того, кого бьют
	_expect("Обратный ток", ZH, VI, &"arena_backflow", &"", &"", 340, 360)
	_expect("Обратный ток без связи стихий", LU, SU, &"arena_backflow", &"", &"", 330, 350)
	_check(_calc(_mk_state(ZH, VI, &"arena_backflow")).trap_id == &"arena_backflow", "trap_id Обратного тока")
	_check(_calc(_mk_state(ZH, VI, &"arena_backflow"), &"", &"ability_silencer").trap_id == &"", "Глушитель гасит Обратный ток")


## «Натиск»: серия побед даёт +40 за победу (до 2), поражение сбрасывает.
func _test_momentum() -> void:
	var ctrl: MatchController = _battle_ctrl(["ability_surge", "ability_shield", "ability_homeland"], ["ability_surge", "ability_shield", "ability_legacy"], &"arena_void", -1, 0, 101)
	var mom: Array = []
	ctrl.momentum_changed.connect(func(p: int, v: int) -> void: mom.append([p, v]))
	_stand(ctrl, 3, 1)
	_stand(ctrl, 4, 3)
	_stand(ctrl, 5, 5)
	_throw(ctrl, 0, 2, 3)  # Гранитрог 370 > Сумрачник 350
	_pass_windows(ctrl)
	_check(mom == [[0, 1]] and ctrl.get_momentum(0) == 1, "первая победа: натиск 1: %s" % str(mom))
	_throw(ctrl, 0, 0, 1)  # Жаровик 340 + натиск 40 против Вихрекрыла 300 (Пустота)
	var pre: BattleResult = ctrl.get_battle_preview()
	_check(pre.momentum[0] == 40 and pre.powers[0] == 380, "натиск в расчёте: %s" % pre.to_log_string())
	_pass_windows(ctrl)
	_check(ctrl.get_momentum(0) == 2, "вторая победа: натиск 2")
	var st: MatchState = _mk_state(ZH, VI, &"")
	st.players[0].momentum = 5
	_check(_calc(st).powers[0] == 400 + PowerCalc.MOMENTUM_STEP * PowerCalc.MOMENTUM_MAX, "натиск не выше предела")
	st.players[0].momentum = 0
	st.players[1].momentum = 2
	_check(_calc(st).powers[1] == 380, "натиск защитника")
	# поражение сбрасывает
	var c2: MatchController = _battle_ctrl(["ability_surge", "ability_shield", "ability_homeland"], ["ability_surge", "ability_shield", "ability_legacy"], &"arena_void", -1, 0, 102)
	c2.state.players[0].momentum = 2
	_stand(c2, 4, 1)
	var m2: Array = []
	c2.momentum_changed.connect(func(p: int, v: int) -> void: m2.append([p, v]))
	_throw(c2, 0, 1, 1)  # Люминар 330 + 80 = 410 > Сумрачник 350: победа, натиск остаётся 2
	_pass_windows(c2)
	_check(c2.get_momentum(0) == 2 and m2.is_empty(), "на пределе натиск не растёт")


## Финальный раунд: у кого-то осталось одно существо — объявление и преимущество стихии ×2.
func _test_final_round() -> void:
	var ctrl: MatchController = _battle_ctrl(["ability_surge", "ability_shield", "ability_homeland"], ["ability_surge", "ability_shield", "ability_legacy"], &"arena_void", -1, 0, 111)
	var fin: Array = []
	ctrl.final_round_started.connect(func(p: int) -> void: fin.append(p))
	ctrl.state.creatures[3].alive = false  # у P1 осталось два
	_stand(ctrl, 4, 3)
	_throw(ctrl, 0, 2, 3)  # Гранитрог выбивает Сумрачника
	_pass_windows(ctrl)
	_check(fin == [1] and ctrl.is_final_round() and ctrl.get_view(1).final_round, "финальный раунд объявлен для P1: %s" % str(fin))
	var st: MatchState = _mk_state(ZH, VI, &"")
	st.final_round = true
	var r: BattleResult = _calc(st)
	_check(r.powers[0] == 340 + 120 and r.final_round, "финальный раунд: преимущество ×2: %d" % r.powers[0])
	st.slots[0].card_id = &"arena_overweight"
	st.slots[0].has_card = true
	_check(_calc(st).powers[0] == 340 + 240, "Перевес в финале ×4")
	_check(ctrl.get_active_player() == 0, "ходит победитель")
	_throw(ctrl, 0, 0, -1)
	_check(fin.size() == 1, "объявление один раз")


## Уровни сложности ИИ: детерминизм, приманка на «Зеркале», прикрепление защиты, пара карт у мастера.
func _test_ai_levels() -> void:
	_check(AIPlayer.new(1, 1).difficulty == AIPlayer.Difficulty.NORMAL and is_equal_approx(AIPlayer.new(1, 1).get_aim_error(), 0.42), "по умолчанию — Боец")
	_check(AIPlayer.new(1, 1, -1.0, AIPlayer.Difficulty.EASY).get_aim_error() > AIPlayer.new(1, 1, -1.0, AIPlayer.Difficulty.HARD).get_aim_error(), "мастер точнее новичка")
	_check(AIPlayer.difficulty_name(2) == "Мастер", "имя уровня")
	# приманка: на своё «Зеркало» Боец ставит слабейшее существо
	var deck1: DeckDef = _mk_deck([VI, SU, MA], ["arena_mirror", "arena_void", "arena_void"], ["ability_surge", "ability_shield", "ability_legacy"])
	var ctrl: MatchController = MatchController.new(_test_deck(0), deck1, 121)
	_setup_controller(ctrl)
	for i in range(6):
		_set_card(ctrl, i, &"arena_void", i % 2)
	for i in range(6):
		ctrl.state.slots[i].has_card = false
		ctrl.state.slots[i].card_id = &""
	_set_card(ctrl, 3, &"arena_mirror", 1)
	_p0_idle(ctrl)
	var ai := AIPlayer.new(1, 5, -1.0, AIPlayer.Difficulty.NORMAL)
	var th: Dictionary = ai.choose_throw(ctrl.get_view(1))
	_check(th["target_slot"] == 3 and th["uid"] == 3, "на Зеркало — слабейший Вихрекрыл (300): %s" % str(th))
	# мастер разыгрывает пару, если одной карты мало: Мареолит 320 против Гранитрога 370 на Пустоте
	var c2: MatchController = _battle_ctrl(["ability_surge", "ability_shield", "ability_homeland"], ["ability_surge", "ability_hamstring", "ability_legacy"], &"arena_void", -1, 0, 122)
	_set_card(c2, 3, &"arena_bastion", 0)
	_stand(c2, 2, 3)
	_p0_idle(c2)
	_throw(c2, 1, 5, 3)
	var hard := AIPlayer.new(1, 7, -1.0, AIPlayer.Difficulty.HARD)
	var normal := AIPlayer.new(1, 7, -1.0, AIPlayer.Difficulty.NORMAL)
	var pre: BattleResult = c2.get_battle_preview()
	_check(c2.get_active_player() == 1 and pre.powers[1] > pre.powers[0], "Мареолит атакует и проигрывает без карт")
	var hc: StringName = hard.choose_ability(c2.get_view(1), pre, c2.legal_abilities(1))
	var nc: StringName = normal.choose_ability(c2.get_view(1), pre, c2.legal_abilities(1))
	_check(hc != &"" and nc == &"", "мастер начинает пару карт, боец пасует: %s / %s" % [hc, nc])
	# прикрепление защиты после приземления
	var deck_g: DeckDef = _mk_deck([GR, ZH, LU], ["arena_void", "arena_void", "arena_void"], ["ability_granite", "ability_surge", "ability_legacy"])
	var c3: MatchController = MatchController.new(deck_g, _test_deck(1), 123)
	c3.landing_window = true
	_setup_controller(c3)
	for i in range(6):
		_set_card(c3, i, &"arena_void", i % 2)
	_throw(c3, 0, 1, 0)  # Жаровик (340) встаёт; Сумрачник (350) его перебьёт
	_check(c3.get_phase() == MatchController.Phase.AFTER_LANDING, "окно после приземления")
	var a0 := AIPlayer.new(0, 9, -1.0, AIPlayer.Difficulty.NORMAL)
	var pick: StringName = a0.choose_attach(c3.get_view(0), c3.get_landed_uid(), c3.legal_abilities(0))
	_check(pick == &"ability_surge", "Боец прикрепляет Рывок для защиты: %s" % pick)
	_check(AIPlayer.new(0, 9, -1.0, AIPlayer.Difficulty.EASY).choose_attach(c3.get_view(0), c3.get_landed_uid(), c3.legal_abilities(0)) == &"", "Новичок не прикрепляет")
	# детерминизм по seed с разными уровнями
	var d1: Dictionary = _run_match(4242)
	var d2: Dictionary = _run_match(4242)
	_check(d1["log_hash"] == d2["log_hash"], "детерминизм с новыми механиками")


## Ход P0 без последствий: промах.
func _p0_idle(ctrl: MatchController) -> void:
	var legal: Array[int] = ctrl.legal_creatures(0)
	_throw(ctrl, 0, legal[0], -1)
