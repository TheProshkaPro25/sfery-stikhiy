class_name MatchController
extends RefCounted
## Конечный автомат матча по правилам Бакугана (официальная инструкция Spin Master):
## в начале хода игрок может положить карту ворот (ближе к сопернику, рядом с уже лежащими; обязательно,
## если ворот на поле нет), затем бросает существо. Промах и оба участника боя уходят в зону использованных;
## использованные возвращаются, когда бросать больше некого. Бой: ворота открываются, затем обмен способностями
## (поочерёдно, начиная с игрока, чей ход, до паса; ≤ 3 карты на игрока), победитель забирает карту и ходит
## следующим, проигравший выбывает. Победа — выбить
## всех трёх существ соперника. Попадание на свои ворота: существо
## переставляется на другие ворота без своего существа, а если таких нет, карта засчитывается игроку.
## Синхронный, без await, детерминированный при фиксированном seed.
## Правило эмита: действие сначала полностью меняет состояние, затем события уходят из очереди (_flush).
## События, вызванные из обработчика сигнала, встают в ту же очередь и эмитятся в исходном порядке.
## Механики «Боя как в аниме» (DESIGN.md): способности в три момента (до броска и после приземления — прикрепляются
## к существу; в бою — обмен), «ворота + бросок», ловушки ворот, «Натиск» (серия побед), финальный раунд.

## AFTER_LANDING — окно способностей после приземления на пустые ворота (только при landing_window = true).
enum Phase { SETUP, AWAIT_THROW, AWAIT_LANDING, ABILITY_WINDOW, RESOLVING, GAME_OVER, AFTER_LANDING }

const MAX_TURNS: int = 60
const WIN_CAPTURES: int = 3
const NUM_SLOTS: int = 6
## Предел карт способностей одного игрока в одном бою (прикреплённые к бойцу заранее тоже считаются).
const MAX_BATTLE_ABILITIES: int = 3

signal phase_changed(phase: int, active_player: int)
signal setup_requested(player: int)
signal arena_card_placed(player: int, slot: int)
signal throw_requested(player: int)
signal creature_selected(player: int, uid: int, recalled: bool)
signal creature_returned(uid: int, reason: StringName)
signal creature_stood(uid: int, slot: int)
signal creature_relocated(uid: int, from_slot: int, to_slot: int)
signal creatures_refilled(player: int)
## Все живые существа игрока стоят на воротах — бросать некого, ход переходит сопернику.
signal turn_skipped(player: int)
## Бросать некому обоим: сильнейшее стоящее существо игрока идёт на ворота к сильнейшему стоящему сопернику.
signal standoff(attacker_uid: int, defender_uid: int)
signal gates_recycled
signal battle_started(slot: int, attacker_uid: int, defender_uid: int)
signal card_revealed(slot: int, card_id: StringName)
signal ability_window(player: int, options: Array)
signal ability_played(player: int, card_id: StringName)
signal ability_cancelled(player: int, card_id: StringName)
signal battle_resolved(result: BattleResult)
signal creature_eliminated(uid: int)
signal card_captured(player: int, slot: int, card_id: StringName)
signal turn_started(player: int, turn: int)
signal game_over(winner: int, reason: StringName)
## Способность сыграна вне боя (до броска или после приземления) и прикреплена к существу uid.
signal ability_attached(player: int, uid: int, card_id: StringName)
## Окно «после приземления»: существо uid встало на пустые ворота, игрок может прикрепить к нему способность или пас.
signal attach_window(player: int, uid: int, options: Array)
## «Ворота + бросок»: карта ворот выложена в слот slot в момент броска существа uid (цель броска — эта карта).
signal gate_thrown(player: int, slot: int, uid: int)
## Ловушка ворот открылась в начале боя (сразу после card_revealed). effect: seal / mirror / backflow.
signal gate_trap_triggered(slot: int, card_id: StringName, effect: StringName)
## «Натиск» игрока изменился (0..PowerCalc.MOMENTUM_MAX); бонус в бою = value × PowerCalc.MOMENTUM_STEP.
signal momentum_changed(player: int, value: int)
## Финальный раунд объявлен (один раз за матч): у player осталось одно живое существо (-1 — у обоих).
signal final_round_started(player: int)

## Полное (нескрытое) состояние. Внешний код читает только через get_view().
var state: MatchState
## Текстовый лог всех эмитнутых событий (для проверки детерминизма).
var event_log: Array[String] = []
## Победитель после GAME_OVER (-1 ничья), до этого -2.
var winner: int = -2
var game_over_reason: StringName = &""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _queue: Array = []
var _flushing: bool = false
var _started: bool = false
var _turn_player: int = 0
var _pending_uid: int = -1
var _b_slot: int = -1
var _b_atk: int = -1
var _b_def: int = -1
var _b_plays: Array = []  # карты обмена этого боя: [[сторона, card_id], ...] (0 — атакующий)
var _b_count: Array[int] = [0, 0]  # карт сторон в бою (с прикреплёнными)
var _b_passed: Array[bool] = [false, false]  # пас окончателен
var _b_turn: int = 0  # сторона, чей черёд в обмене
var _landed_uid: int = -1  # существо в окне «после приземления»
var _gate_throw_slot: int = -1  # слот карты, выложенной «воротами + броском» в этот ход
## Окно «после приземления» (Phase.AFTER_LANDING). Выключено, пока интерфейс его не поддерживает (см. PLAN_ANIME «Отчёт Б»);
## тесты и tools/sim.gd включают его.
var landing_window: bool = false
var _stall: int = 0  # подряд ходов, где бросать было некого


func _init(deck0: DeckDef, deck1: DeckDef, rng_seed: int) -> void:
	_rng.seed = rng_seed
	state = MatchState.new()
	state.phase = Phase.SETUP
	var decks: Array[DeckDef] = [deck0, deck1]
	var next_uid: int = 0
	for p in range(2):
		var ps: PlayerState = state.players[p]
		var deck: DeckDef = decks[p]
		for cdef in deck.creatures:
			var cs: CreatureState = CreatureState.new(next_uid, cdef.id, p)
			state.creatures[next_uid] = cs
			ps.creature_uids.append(next_uid)
			next_uid += 1
		for card in deck.arena:
			ps.arena_hand.append(card.id)
		for card in deck.abilities:
			ps.ability_hand.append(card.id)


# ---------------------------------------------------------------- запросы

func get_view(player: int) -> MatchState:
	return state.duplicate_view(player)


func get_phase() -> int:
	return state.phase


func get_active_player() -> int:
	return state.active_player


func get_turn() -> int:
	return state.turn


## uid существа, выбранного в текущий бросок (-1, если нет).
func get_selected_uid() -> int:
	return _pending_uid


## Существа, которых можно бросить: не на поле и не в зоне использованных.
func legal_creatures(player: int) -> Array[int]:
	var out: Array[int] = []
	if state.phase != Phase.AWAIT_THROW or player != state.active_player:
		return out
	for uid in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			out.append(uid)
	return out


## Слоты, куда можно положить карту ворот: свободные, рядом с уже лежащими картами (если они есть),
## по возможности в ряду ближе к сопернику (для P0 — дальний ряд 0..2, для P1 — ближний 3..5).
func legal_setup_slots() -> Array[int]:
	if state.phase != Phase.SETUP:
		return [] as Array[int]
	return _gate_slots(state.active_player)


func _gate_slots(player: int) -> Array[int]:
	var free: Array[int] = []
	var near: Array[int] = []
	var any_card: bool = false
	for i in range(NUM_SLOTS):
		if state.slots[i].has_card:
			any_card = true
	for i in range(NUM_SLOTS):
		if state.slots[i].has_card:
			continue
		free.append(i)
		if any_card and _has_card_neighbor(i):
			near.append(i)
	var base: Array[int] = near if any_card and not near.is_empty() else free
	var row: int = 0 if player == 0 else 1
	var pref: Array[int] = []
	for i in base:
		if i / 3 == row:
			pref.append(i)
	return pref if not pref.is_empty() else base


func _has_card_neighbor(i: int) -> bool:
	var col: int = i % 3
	var row: int = i / 3
	for n in [[col - 1, row], [col + 1, row], [col, 1 - row]]:
		if n[0] >= 0 and n[0] <= 2 and state.slots[n[1] * 3 + n[0]].has_card:
			return true
	return false


func _gates_on_field() -> int:
	var n: int = 0
	for i in range(NUM_SLOTS):
		if state.slots[i].has_card:
			n += 1
	return n


## Можно ли пропустить выкладку карты ворот (нельзя, если ворот на поле нет).
func can_skip_gate() -> bool:
	return state.phase == Phase.SETUP and _gates_on_field() > 0


## Карты способностей, доступные игроку прямо сейчас: в бою (свой черёд обмена), до броска (существо выбрано,
## фаза AWAIT_LANDING — карта прикрепится к нему) и после приземления (Phase.AFTER_LANDING).
func legal_abilities(player: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if player != state.active_player:
		return out
	var uid: int = -1
	var own: Array = []
	var limit_left: int = 0
	match state.phase:
		Phase.ABILITY_WINDOW:
			var side: int = _b_turn
			if _battle_player(side) != player or _b_passed[side]:
				return out
			if CardEffects.is_effect(CardDB.card(state.slots[_b_slot].card_id), &"seal"):
				return out  # «Печать тишины»: способности в этом бою не играются
			uid = _b_atk if side == 0 else _b_def
			for pl in PowerCalc.attached_plays(state, _b_atk, _b_def) + _b_plays:
				if int(pl[0]) == side:
					own.append(pl[1])
			limit_left = MAX_BATTLE_ABILITIES - _b_count[side]
		Phase.AWAIT_LANDING, Phase.AFTER_LANDING:
			uid = _pending_uid if state.phase == Phase.AWAIT_LANDING else _landed_uid
			if uid < 0:
				return out
			for a in state.creatures[uid].attached:
				own.append(a[1])
			limit_left = MAX_BATTLE_ABILITIES - own.size()
		_:
			return out
	if limit_left <= 0:
		return out
	for id in state.players[player].ability_hand:
		if _ability_legal(uid, id, own):
			out.append(id)
	return out


## Можно ли сыграть карту за существо uid: стихийный замок; слияние — только поверх своей основной карты без слияния.
## own — уже сыгранные этой стороной карты боя (или прикреплённые к существу) по порядку.
func _ability_legal(uid: int, id: StringName, own: Array) -> bool:
	var c: CardDef = CardDB.card(id)
	if c == null:
		return false
	if CardEffects.is_fusion(c):
		if own.is_empty() or CardEffects.is_fusion(CardDB.card(StringName(own[own.size() - 1]))):
			return false
	var lock: int = CardEffects.lock_attr(c)
	if lock >= 0 and CardDB.creature(state.creatures[uid].def_id).attribute != lock:
		return false
	return true


## Предпросмотр боя в окне способностей (уже сыгранные способности учтены, будущие — нет). Иначе null.
## Для ИИ: ai.choose_ability(get_view(p), get_battle_preview(), legal_abilities(p)).
func get_battle_preview() -> BattleResult:
	if state.phase != Phase.ABILITY_WINDOW:
		return null
	# до открытия ворот игрок знает только свою карту ворот
	var v: MatchState = state.duplicate_view(state.active_player)
	var r: BattleResult = PowerCalc.compute_seq(v, _b_atk, _b_def, _b_slot, _b_plays)
	r.passed = [_b_passed[0], _b_passed[1]]
	return r


## Момент розыгрыша способности: &"battle" (обмен в бою), &"pre_throw" (существо выбрано, бросок ещё не сделан),
## &"after_landing" (окно после приземления); иначе &"".
func get_ability_moment() -> StringName:
	match state.phase:
		Phase.ABILITY_WINDOW:
			return &"battle"
		Phase.AWAIT_LANDING:
			return &"pre_throw"
		Phase.AFTER_LANDING:
			return &"after_landing"
	return &""


## Сколько карт ещё может сыграть игрок в текущем бою (или прикрепить к существу вне боя).
func abilities_left(player: int) -> int:
	match state.phase:
		Phase.ABILITY_WINDOW:
			var side: int = 0 if _battle_player(0) == player else 1
			return MAX_BATTLE_ABILITIES - _b_count[side]
		Phase.AWAIT_LANDING, Phase.AFTER_LANDING:
			var uid: int = _pending_uid if state.phase == Phase.AWAIT_LANDING else _landed_uid
			return MAX_BATTLE_ABILITIES - state.creatures[uid].attached.size() if uid >= 0 else 0
	return 0


## Существо в окне «после приземления» (-1 вне окна).
func get_landed_uid() -> int:
	return _landed_uid if state.phase == Phase.AFTER_LANDING else -1


## Слот карты, выложенной «воротами + броском» в этот бросок (цель броска), иначе -1.
func get_throw_gate_slot() -> int:
	return _gate_throw_slot if state.phase == Phase.AWAIT_LANDING else -1


## «Натиск» игрока (побед подряд, 0..PowerCalc.MOMENTUM_MAX).
func get_momentum(player: int) -> int:
	return state.players[player].momentum


## Идёт ли финальный раунд.
func is_final_round() -> bool:
	return state.final_round
# ---------------------------------------------------------------- действия

func start() -> void:
	if _started:
		return
	_started = true
	_begin_turn(0)
	_flush()


func place_arena_card(player: int, card_id: StringName, slot: int) -> Error:
	if state.phase != Phase.SETUP or player != state.active_player:
		return ERR_UNAUTHORIZED
	if not _gate_slots(player).has(slot):
		return ERR_INVALID_PARAMETER
	var ps: PlayerState = state.players[player]
	if not ps.arena_hand.has(card_id):
		return ERR_DOES_NOT_EXIST
	ps.arena_hand.erase(card_id)
	var s: SlotState = state.slots[slot]
	s.card_id = card_id
	s.card_owner = player
	s.has_card = true
	s.revealed = false
	_ev(&"arena_card_placed", [player, slot])
	_begin_throw(player)
	_flush()
	return OK


## Не класть карту ворот в этот ход (если на поле уже есть ворота).
func skip_gate(player: int) -> Error:
	if state.phase != Phase.SETUP or player != state.active_player:
		return ERR_UNAUTHORIZED
	if not can_skip_gate():
		return ERR_UNAVAILABLE
	_begin_throw(player)
	_flush()
	return OK


## «Ворота + бросок»: в фазе выкладки положить карту ворот и сразу бросить на неё существо uid (один ход).
## Цель броска — слот slot; приземление обрабатывается как обычно (report_landing, промах возможен).
func throw_with_gate(player: int, card_id: StringName, slot: int, uid: int) -> Error:
	if state.phase != Phase.SETUP or player != state.active_player:
		return ERR_UNAUTHORIZED
	if not _gate_slots(player).has(slot):
		return ERR_INVALID_PARAMETER
	var ps: PlayerState = state.players[player]
	if not ps.arena_hand.has(card_id):
		return ERR_DOES_NOT_EXIST
	var c: CreatureState = state.creatures.get(uid)
	if c == null or c.owner != player or not c.alive or c.slot >= 0 or c.used:
		return ERR_INVALID_PARAMETER
	ps.arena_hand.erase(card_id)
	var s: SlotState = state.slots[slot]
	s.card_id = card_id
	s.card_owner = player
	s.has_card = true
	s.revealed = false
	_pending_uid = uid
	_gate_throw_slot = slot
	state.phase = Phase.AWAIT_LANDING
	_ev(&"arena_card_placed", [player, slot])
	_ev(&"gate_thrown", [player, slot, uid])
	_ev(&"creature_selected", [player, uid, false])
	_ev(&"phase_changed", [Phase.AWAIT_LANDING, player])
	_flush()
	return OK


func select_creature(player: int, uid: int) -> Error:
	if state.phase != Phase.AWAIT_THROW or player != state.active_player:
		return ERR_UNAUTHORIZED
	if not legal_creatures(player).has(uid):
		return ERR_INVALID_PARAMETER
	_pending_uid = uid
	_gate_throw_slot = -1
	state.phase = Phase.AWAIT_LANDING
	_ev(&"creature_selected", [player, uid, false])
	_ev(&"phase_changed", [Phase.AWAIT_LANDING, player])
	_flush()
	return OK


## Единственный вход из физики. slot -1 = промах/вылет.
func report_landing(uid: int, slot: int) -> void:
	if state.phase != Phase.AWAIT_LANDING or uid != _pending_uid:
		return
	var player: int = _turn_player
	var c: CreatureState = state.creatures[uid]
	_pending_uid = -1
	if slot < 0 or slot >= NUM_SLOTS or not state.slots[slot].has_card:
		_to_used(uid, &"miss")
		_begin_turn(1 - player)
		_flush()
		return
	var s: SlotState = state.slots[slot]
	if s.occupant_uid >= 0 and state.creatures[s.occupant_uid].owner == player:
		# свои ворота: переставить на ворота без своего существа (сначала туда, где соперник)
		var to: int = _relocation_target(player)
		if to < 0:
			_win_gate(player, slot, [uid, s.occupant_uid])
			return
		_ev(&"creature_relocated", [uid, slot, to])
		slot = to
		s = state.slots[slot]
	if s.occupant_uid >= 0:
		_start_battle(uid, s.occupant_uid, slot)
		return
	c.slot = slot
	s.occupant_uid = uid
	_ev(&"creature_stood", [uid, slot])
	if landing_window:
		_landed_uid = uid
		state.phase = Phase.AFTER_LANDING
		var options: Array = legal_abilities(player)
		if not options.is_empty():
			_ev(&"phase_changed", [Phase.AFTER_LANDING, player])
			_ev(&"attach_window", [player, uid, options])
			_flush()
			return
	_landed_uid = -1
	_begin_turn(1 - player)
	_flush()


func _relocation_target(player: int) -> int:
	var empty: int = -1
	for i in range(NUM_SLOTS):
		var s: SlotState = state.slots[i]
		if not s.has_card:
			continue
		if s.occupant_uid < 0:
			if empty < 0:
				empty = i
		elif state.creatures[s.occupant_uid].owner != player:
			return i
	return empty


## Ворота с двумя своими существами: карта засчитывается игроку, оба существа уходят в использованные.
func _win_gate(player: int, slot: int, uids: Array) -> void:
	var s: SlotState = state.slots[slot]
	var card: StringName = s.card_id
	for u in uids:
		_to_used(int(u), &"gate_won")
	s.occupant_uid = -1
	s.card_id = &""
	s.card_owner = -1
	s.has_card = false
	s.revealed = false
	state.players[player].captured.append(card)
	_ev(&"card_captured", [player, slot, card])
	if not _check_victory():
		_begin_turn(1 - player)
	_flush()


## Существо уходит в зону использованных (с поля или после промаха).
func _to_used(uid: int, reason: StringName) -> void:
	var c: CreatureState = state.creatures[uid]
	if c.slot >= 0 and state.slots[c.slot].occupant_uid == uid:
		state.slots[c.slot].occupant_uid = -1
	c.slot = -1
	c.used = true
	_ev(&"creature_returned", [uid, reason])


## Сыграть способность: в бою — в свой черёд обмена; до броска и после приземления — прикрепить к своему существу.
func play_ability(player: int, card_id: StringName) -> Error:
	var ph: int = state.phase
	if (ph != Phase.ABILITY_WINDOW and ph != Phase.AWAIT_LANDING and ph != Phase.AFTER_LANDING) or player != state.active_player:
		return ERR_UNAUTHORIZED
	var ps: PlayerState = state.players[player]
	if not ps.ability_hand.has(card_id):
		return ERR_DOES_NOT_EXIST
	if not legal_abilities(player).has(card_id):
		return ERR_UNAVAILABLE
	ps.ability_hand.erase(card_id)
	ps.abilities_used.append(card_id)
	if ph != Phase.ABILITY_WINDOW:
		var uid: int = _pending_uid if ph == Phase.AWAIT_LANDING else _landed_uid
		state.creatures[uid].attached.append([state.play_stamp, card_id])
		state.play_stamp += 1
		_ev(&"ability_attached", [player, uid, card_id])
		if ph == Phase.AFTER_LANDING:
			var options: Array = legal_abilities(player)
			if options.is_empty():
				_landed_uid = -1
				_begin_turn(1 - player)
			else:
				_ev(&"attach_window", [player, uid, options])
		_flush()
		return OK
	var side: int = _b_turn
	_b_plays.append([side, card_id])
	_b_count[side] += 1
	state.play_stamp += 1
	_ev(&"ability_played", [player, card_id])
	if not _b_passed[1 - side]:
		_b_turn = 1 - side
	_open_window()
	_flush()
	return OK


## Пас: в бою — окончательный (второй игрок может доиграть свои карты); после приземления — конец хода.
func pass_ability(player: int) -> Error:
	if player != state.active_player:
		return ERR_UNAUTHORIZED
	if state.phase == Phase.AFTER_LANDING:
		_landed_uid = -1
		_begin_turn(1 - player)
		_flush()
		return OK
	if state.phase != Phase.ABILITY_WINDOW:
		return ERR_UNAUTHORIZED
	_b_passed[_b_turn] = true
	_b_turn = 1 - _b_turn
	_open_window()
	_flush()
	return OK


# ---------------------------------------------------------------- внутренняя логика

func _begin_turn(player: int) -> void:
	if state.turn >= MAX_TURNS:
		_finish_by_limit(&"turn_limit")
		return
	# Ворота кончились: выигранные карты возвращаются в руки игроков, игра продолжается.
	if _gates_on_field() == 0 and state.players[0].arena_hand.is_empty() and state.players[1].arena_hand.is_empty():
		for p in range(2):
			for id in state.players[p].captured:
				state.players[p].arena_hand.append(id)
			state.players[p].captured.clear()
		_ev(&"gates_recycled", [])
		if state.players[0].arena_hand.is_empty() and state.players[1].arena_hand.is_empty():
			_finish_by_limit(&"no_gates")
			return
	_turn_player = player
	state.turn += 1
	state.active_player = player
	_pending_uid = -1
	_refill_if_needed(player)
	_ev(&"turn_started", [player, state.turn])
	if not _has_ready(player):
		# все существа стоят на воротах — бросать некого, ход переходит сопернику (отзыва с ворот нет)
		_stall += 1
		if _stall >= 2:
			# бросать некому обоим: сильнейшие стоящие сходятся в бою напрямую
			_stall = 0
			_standoff(player)
			return
		_ev(&"turn_skipped", [player])
		_begin_turn(1 - player)
		return
	_stall = 0
	var hand_ok: bool = not state.players[player].arena_hand.is_empty() and not _gate_slots(player).is_empty()
	if hand_ok:
		state.phase = Phase.SETUP
		_ev(&"phase_changed", [Phase.SETUP, player])
		_ev(&"setup_requested", [player])
		return
	if _gates_on_field() == 0:
		# класть нечего и ворот нет: ход переходит сопернику
		_begin_turn(1 - player)
		return
	_begin_throw(player)


## Тупик (у обоих все живые на воротах): существо player с наибольшей БС переходит на ворота к сильнейшему
## стоящему существу соперника, дальше обычный бой (окна способностей, открытие ворот, расчёт).
func _standoff(player: int) -> void:
	var atk: int = _strongest_standing(player)
	var dfn: int = _strongest_standing(1 - player)
	if atk < 0 or dfn < 0:
		_finish_by_limit(&"stalemate")
		return
	var c: CreatureState = state.creatures[atk]
	var from: int = c.slot
	var to: int = state.creatures[dfn].slot
	state.slots[from].occupant_uid = -1
	c.slot = -1
	_ev(&"standoff", [atk, dfn])
	_ev(&"creature_relocated", [atk, from, to])
	_start_battle(atk, dfn, to)


func _strongest_standing(player: int) -> int:
	var best: int = -1
	var best_power: int = -1
	for uid in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[uid]
		var pw: int = CardDB.creature(c.def_id).base_power
		if c.alive and c.slot >= 0 and pw > best_power:
			best = uid
			best_power = pw
	return best


func _begin_throw(player: int) -> void:
	state.phase = Phase.AWAIT_THROW
	state.active_player = player
	_ev(&"phase_changed", [Phase.AWAIT_THROW, player])
	_ev(&"throw_requested", [player])


## Есть кого бросить: живое существо в руке (не на воротах и не в зоне использованных).
func _has_ready(player: int) -> bool:
	for uid in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			return true
	return false


## Если бросать некого, все использованные существа возвращаются в руку.
func _refill_if_needed(player: int) -> void:
	for uid in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			return
	var any: bool = false
	for uid in state.players[player].creature_uids:
		var c2: CreatureState = state.creatures[uid]
		if c2.used and c2.alive:
			c2.used = false
			any = true
	if any:
		_ev(&"creatures_refilled", [player])


func _start_battle(atk_uid: int, def_uid: int, slot: int) -> void:
	_b_slot = slot
	_b_atk = atk_uid
	_b_def = def_uid
	_b_plays = []
	_b_count = [state.creatures[atk_uid].attached.size(), state.creatures[def_uid].attached.size()]
	_b_passed = [false, false]
	_b_turn = 0  # обмен начинает игрок, чей ход (он атакует)
	state.phase = Phase.ABILITY_WINDOW
	_ev(&"battle_started", [slot, atk_uid, def_uid])
	# ворота открываются в начале боя, ловушка срабатывает сразу
	var gs: SlotState = state.slots[slot]
	gs.revealed = true
	_ev(&"card_revealed", [slot, gs.card_id])
	var gc: CardDef = CardDB.card(gs.card_id)
	if CardEffects.is_gate_trap(gc):
		_ev(&"gate_trap_triggered", [slot, gc.id, gc.effect_id])
	_open_window()
	_flush()


## Игрок стороны боя (0 — атакующий, 1 — защитник).
func _battle_player(side: int) -> int:
	var uid: int = _b_def if side == 1 else _b_atk
	return state.creatures[uid].owner


## Обмен способностями: открывает окно стороне _b_turn; кто спасовал или не может сыграть — выбывает из обмена.
## Когда не может играть никто, бой решается.
func _open_window() -> void:
	for _guard in range(4):
		var side: int = _b_turn
		var player: int = _battle_player(side)
		state.active_player = player
		state.phase = Phase.ABILITY_WINDOW
		var options: Array = [] if _b_passed[side] else legal_abilities(player)
		if options.is_empty():
			_b_passed[side] = true
			if _b_passed[1 - side]:
				break
			_b_turn = 1 - side
			continue
		_ev(&"phase_changed", [Phase.ABILITY_WINDOW, player])
		_ev(&"ability_window", [player, options])
		return
	_resolve()


func _resolve() -> void:
	state.phase = Phase.RESOLVING
	var r: BattleResult = PowerCalc.compute_seq(state, _b_atk, _b_def, _b_slot, _b_plays)
	var wc: CreatureState = state.creatures[r.winner_uid]
	var lc: CreatureState = state.creatures[r.loser_uid]
	var s: SlotState = state.slots[_b_slot]
	var captured_id: StringName = s.card_id
	var slot: int = _b_slot

	# «Ва-банк»: проигравший теряет случайную способность из руки (если карта не отменена)
	var loser_is_atk: bool = r.loser_uid == r.attacker_uid
	if (r.atk_all_in if loser_is_atk else r.def_all_in):
		var hand: Array[StringName] = state.players[lc.owner].ability_hand
		if not hand.is_empty():
			var idx: int = _rng.randi_range(0, hand.size() - 1)
			r.lost_ability = hand[idx]
			hand.remove_at(idx)

	# «Спасение»: проигравший не выбывает, а уходит в зону использованных
	r.rescued = r.atk_rescue if loser_is_atk else r.def_rescue
	var atk_owner: int = state.creatures[_b_atk].owner
	var def_owner: int = state.creatures[_b_def].owner

	# прикреплённые карты отыграли
	state.creatures[_b_atk].attached.clear()
	state.creatures[_b_def].attached.clear()

	# отменённые карты и итог боя
	for cp in r.cancelled_plays:
		_ev(&"ability_cancelled", [atk_owner if int(cp[0]) == 0 else def_owner, cp[1]])
	_ev(&"battle_resolved", [r])

	# проигравший выбывает (или уходит в использованные со «Спасением»), победитель — в использованные
	if r.rescued:
		_to_used(lc.uid, &"rescued")
	else:
		if lc.slot >= 0 and state.slots[lc.slot].occupant_uid == lc.uid:
			state.slots[lc.slot].occupant_uid = -1
		lc.slot = -1
		lc.alive = false
		_ev(&"creature_eliminated", [lc.uid])
	_to_used(wc.uid, &"won")
	s.occupant_uid = -1
	s.card_id = &""
	s.card_owner = -1
	s.has_card = false
	s.revealed = false
	state.players[wc.owner].captured.append(captured_id)
	_ev(&"card_captured", [wc.owner, slot, captured_id])

	# «Натиск»: победитель наращивает серию, проигравший её теряет
	var wp: PlayerState = state.players[wc.owner]
	var lp: PlayerState = state.players[lc.owner]
	if wp.momentum < PowerCalc.MOMENTUM_MAX:
		wp.momentum += 1
		_ev(&"momentum_changed", [wc.owner, wp.momentum])
	if lp.momentum > 0:
		lp.momentum = 0
		_ev(&"momentum_changed", [lc.owner, 0])

	# следующим ходит победитель
	if not _check_victory():
		_check_final_round()
		_begin_turn(wc.owner)


## Финальный раунд: впервые у кого-то осталось одно живое существо.
func _check_final_round() -> void:
	if state.final_round:
		return
	var last: Array[int] = []
	for p in range(2):
		if state.alive_count(p) == 1:
			last.append(p)
	if last.is_empty():
		return
	state.final_round = true
	_ev(&"final_round_started", [last[0] if last.size() == 1 else -1])


## Победа — у соперника не осталось существ (все три выбиты).
func _check_victory() -> bool:
	for p in range(2):
		if state.alive_count(p) == 0:
			_end_game(1 - p, &"knockout")
			return true
	return false


## Конец без нокаута (лимит ходов/тупик): по числу живых существ, затем по силе живых, иначе ничья.
func _finish_by_limit(reason: StringName = &"turn_limit") -> void:
	var c0: int = state.alive_count(0)
	var c1: int = state.alive_count(1)
	if c0 != c1:
		_end_game(0 if c0 > c1 else 1, reason)
		return
	var s0: int = _alive_power(0)
	var s1: int = _alive_power(1)
	if s0 != s1:
		_end_game(0 if s0 > s1 else 1, reason)
		return
	_end_game(-1, reason)


func _alive_power(player: int) -> int:
	var total: int = 0
	for uid in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[uid]
		if c.alive:
			total += CardDB.creature(c.def_id).base_power
	return total


func _end_game(win: int, reason: StringName) -> void:
	if state.phase == Phase.GAME_OVER:
		return
	state.phase = Phase.GAME_OVER
	winner = win
	game_over_reason = reason
	_ev(&"phase_changed", [Phase.GAME_OVER, state.active_player])
	_ev(&"game_over", [win, reason])


# ---------------------------------------------------------------- очередь событий

func _ev(sig: StringName, args: Array) -> void:
	_queue.append([sig, args])


func _flush() -> void:
	if _flushing:
		return
	_flushing = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var sig: StringName = item[0]
		var args: Array = item[1]
		event_log.append(_fmt(sig, args))
		var call_args: Array = [sig]
		call_args.append_array(args)
		callv("emit_signal", call_args)
	_flushing = false


func _fmt(sig: StringName, args: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for a in args:
		if a is BattleResult:
			parts.append((a as BattleResult).to_log_string())
		else:
			parts.append(str(a))
	return "%s(%s)" % [String(sig), ", ".join(parts)]
