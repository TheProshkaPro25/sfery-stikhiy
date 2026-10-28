class_name AIPlayer
extends RefCounted
## ИИ-игрок. Видит только MatchState из MatchController.get_view(player) (чужие закрытые карты пусты).
## Не мутирует состояние; все решения детерминированы по rng_seed.
##
## Уровни сложности (Difficulty):
## - EASY («Новичок»): большой разброс броска, шумная оценка целей, часто пасует, карты выбирает наугад.
## - NORMAL («Боец»): бой с перевесом, своя подходящая карта, самая дешёвая выигрышная способность, в обмене держит
##   запас перевеса 80 против ответа соперника; «ворота + бросок» под подходящее существо; ставит слабое существо
##   на своё «Зеркало» (приманка); после приземления прикрепляет защитную карту, если ворота под угрозой.
## - HARD («Мастер»): плюс блеф (ловушку кладёт первой и сажает на неё приманку), оценка риска ловушки на чужих
##   закрытых воротах (по уже раскрытым картам соперника), оценка ворот соперника под его существом (скорее всего
##   «Поле» его стихии), риск ответа в обмене (запас перевеса растёт с числом карт, которыми соперник ещё может
##   ответить), розыгрыш пары карт, если одной мало.
## Новые карты (2026-10-28) ИИ понимает через предпросмотр PowerCalc.compute_with (мгновенные «Сдвиг плит» и
## «Вихревая подмена» считаются на копии состояния) и оценку исхода _margin («Отлив», «Общая бездна», «Трон сумрака»,
## «Предел»); «Попутный шквал» — в choose_attach на всех уровнях.

enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_NAMES: Array[String] = ["Новичок", "Боец", "Мастер"]
## Разброс броска (для физики в main.gd) по уровню сложности.
const AIM_ERROR: Array[float] = [0.62, 0.42, 0.30]

const WIN_MARGIN: float = 40.0
## Порядок «дешевизны» способностей (по effect_id): от наименее ценных к самым рискованным.
## Карты-«спасатели» (doom, ebb) и мгновенные стоят дороже: их ценность не в силе, а в исходе.
const ABILITY_COST_ORDER: Array[String] = [
	"boost", "pact", "radiance", "scorch", "purge_gate", "eclipse", "nullify_gate", "aloft", "weaken_mark",
	"boost_fix", "fusion_boost", "drain", "copy", "shift_gate", "silence", "negate", "cap_own_base", "strip",
	"reset_base", "siphon", "swap_fighter", "revive", "recall", "doom", "ebb",
]
## Доля ловушек среди командных ворот (4 из 10): априорная вероятность, что бронзовая карта соперника — ловушка.
const TRAP_SHARE: float = 0.4
## Штраф оценки броска в бой на чужие закрытые ворота за вероятность ловушки (HARD).
const TRAP_RISK_PENALTY: float = 300.0

var player: int = 1
var difficulty: int = Difficulty.NORMAL
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _aim_error: float = 0.42
## Свои карты ворот на начало матча (чтобы отличать раскрытые карты соперника среди захваченных).
var _my_gates: Dictionary = {}
var _gates_known: bool = false


## aim_error < 0 — разброс по уровню сложности (AIM_ERROR).
func _init(p_player: int = 1, rng_seed: int = 0, aim_error: float = -1.0, p_difficulty: int = Difficulty.NORMAL) -> void:
	player = p_player
	_rng.seed = rng_seed
	difficulty = clampi(p_difficulty, Difficulty.EASY, Difficulty.HARD)
	_aim_error = aim_error if aim_error >= 0.0 else AIM_ERROR[difficulty]


func get_aim_error() -> float:
	return _aim_error


static func difficulty_name(d: int) -> String:
	return DIFFICULTY_NAMES[clampi(d, 0, DIFFICULTY_NAMES.size() - 1)]


## legal — MatchController.legal_setup_slots(). -> {card_id, slot[, throw_uid]}; {} = не класть (если можно пропустить).
## throw_uid — «ворота + бросок»: вызвать ctrl.throw_with_gate(p, card_id, slot, throw_uid) и бросать в slot.
## Кладёт карту, если ворот на поле мало (или с вероятностью), выбирая карту под стихии своих существ.
func choose_setup(view: MatchState, legal: Array = [], can_skip: bool = false) -> Dictionary:
	_remember_gates(view)
	var ps: PlayerState = view.players[player]
	var slots: Array = legal
	if slots.is_empty():
		for i in range(view.slots.size()):
			if not view.slots[i].has_card:
				slots.append(i)
	if ps.arena_hand.is_empty() or slots.is_empty():
		return {}
	var gates: int = 0
	for sl in view.slots:
		if sl.has_card:
			gates += 1
	if can_skip and gates >= 2 and _rng.randf() < 0.45:
		return {}
	var best: StringName = ps.arena_hand[0]
	var best_fit: int = -1
	for id in ps.arena_hand:
		var fit: int = 0
		var card: CardDef = CardDB.card(id)
		if difficulty == Difficulty.EASY:
			fit = _rng.randi_range(0, 9)
		else:
			for uid in ps_uids(view):
				if _fits(card, CardDB.creature(view.creatures[uid].def_id)):
					fit += 1
			# блеф: ловушка ложится первой, пока соперник не знает, где она
			if difficulty == Difficulty.HARD and CardEffects.is_gate_trap(card) and _rng.randf() < 0.7:
				fit = 5
			fit = fit * 10 + _rng.randi_range(0, 5)
		if fit > best_fit:
			best_fit = fit
			best = id
	var slot: int = int(slots[_rng.randi_range(0, slots.size() - 1)])
	var out: Dictionary = {"card_id": best, "slot": slot}
	# «Ворота + бросок»: сразу бросить под карту подходящее существо, если выгодной атаки нет
	if difficulty != Difficulty.EASY:
		var bcard: CardDef = CardDB.card(best)
		var pick: int = -1
		var attack: bool = false
		for uid in _ready(view):
			if pick < 0 and _fits(bcard, CardDB.creature(view.creatures[uid].def_id)):
				pick = uid
			for i in range(view.slots.size()):
				var occ: int = view.slots[i].occupant_uid
				if view.slots[i].has_card and occ >= 0 and view.creatures[occ].owner != player and _score(view, uid, i) >= 900.0:
					attack = true
		if pick >= 0 and not attack:
			out["throw_uid"] = pick
	return out


## Существа в руке (можно бросить).
func _ready(view: MatchState) -> Array[int]:
	var out: Array[int] = []
	for uid in view.players[player].creature_uids:
		var c: CreatureState = view.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			out.append(uid)
	return out


func ps_uids(view: MatchState) -> Array[int]:
	return view.players[player].creature_uids


## -> {uid: int, target_slot: int}
func choose_throw(view: MatchState) -> Dictionary:
	_remember_gates(view)
	var cands: Array[int] = _candidates(view)
	var best_uid: int = -1
	var best_slot: int = -1
	var best_score: float = -INF
	var noise: float = 250.0 if difficulty == Difficulty.EASY else 2.0
	for uid in cands:
		for slot in range(view.slots.size()):
			var score: float = _score(view, uid, slot)
			if score <= -500.0:
				continue
			score += _rng.randf() * noise
			if score > best_score:
				best_score = score
				best_uid = uid
				best_slot = slot
	if best_uid < 0:
		# нет осмысленной цели: любое существо, любой слот (будет возврат в резерв)
		if cands.is_empty():
			return {"uid": -1, "target_slot": -1}
		best_uid = cands[0]
		best_slot = _rng.randi_range(0, view.slots.size() - 1)
	return {"uid": best_uid, "target_slot": best_slot}


## preview — MatchController.get_battle_preview(). &"" = пас (в бою пас окончателен).
## legal: карты, разрешённые контроллером сейчас (ctrl.legal_abilities); пусто — вся рука.
## Обмен способностями: проигрываю — самая дешёвая карта, после которой выигрываю (HARD ищет и пару карт);
## выигрываю — пас, если соперник уже не может ответить или запас перевеса достаточен, иначе карта «про запас».
func choose_ability(view: MatchState, preview: BattleResult, legal: Array = []) -> StringName:
	if preview == null:
		return &""
	var side: int = 0 if view.creatures[preview.attacker_uid].owner == player else 1
	var cards: Array[StringName] = []
	for id in (legal if not legal.is_empty() else view.players[player].ability_hand):
		if id != &"":
			cards.append(StringName(id))
	if cards.is_empty():
		return &""
	var foe_can: int = _foe_plays_left(view, preview, side)
	var margin: float = _margin(preview, side)
	if difficulty == Difficulty.EASY:
		if margin > 0.0 or _rng.randf() < 0.35:
			return &""
		_shuffle(cards)
		for id in cards:
			if _margin(_with_card(view, preview, id, side), side) > 0.0:
				return id
		return &""
	cards.sort_custom(_cheaper)
	# запас перевеса, при котором можно спокойно пасовать: соперник ещё может ответить картами
	var safe: float = 0.0
	if foe_can > 0:
		safe = 80.0 if difficulty == Difficulty.NORMAL else 60.0 + 40.0 * foe_can
	if margin > 0.0:
		if margin >= safe:
			return &""
		# выигрываю впритык, а соперник ещё ответит: усилиться, если это даёт запас
		for id in cards:
			if _margin(_with_card(view, preview, id, side), side) >= safe:
				return id
		return &""
	var best_id: StringName = &""
	var best_m: float = -INF
	for id in cards:
		var m: float = _margin(_with_card(view, preview, id, side), side)
		if m > 0.0:
			if difficulty == Difficulty.NORMAL or m >= safe:
				return id
			if m > best_m:
				best_m = m
				best_id = id
	if best_id != &"":
		return best_id
	# HARD: одной карты мало — начать с пары, которая выигрывает (если лимит позволяет)
	if difficulty == Difficulty.HARD and cards.size() >= 2 and _my_plays_left(view, preview, side) >= 2:
		for i in range(cards.size()):
			for j in range(cards.size()):
				if i == j:
					continue
				var ci: CardDef = CardDB.card(cards[i])
				var cj: CardDef = CardDB.card(cards[j])
				if CardEffects.is_instant(ci) or CardEffects.is_instant(cj) or CardEffects.is_lockout(ci):
					continue
				var bp: Array = preview.battle_plays.duplicate(true)
				bp.append([side, cards[i]])
				bp.append([side, cards[j]])
				var r: BattleResult = PowerCalc.compute_seq(view, preview.attacker_uid, preview.defender_uid, preview.slot, bp)
				if _margin(r, side) > 0.0:
					return cards[i]
	return &""


## Прикрепить способность вне боя: moment &"after_landing" (существо uid встало на пустые ворота) или &"pre_throw".
## NORMAL/HARD после приземления прикрепляют самую дешёвую карту, которая снимает угрозу атаки на эти ворота.
## До броска ИИ не играет: в бою та же карта сильнее (видно ворота и ответ соперника). &"" — пас.
## «Попутный шквал» (все уровни): перелететь к слабейшему стоящему сопернику, если бой там выгоден
## (Новичок — при любом перевесе и через раз, Боец — перевес > 40, Мастер — > 60).
func choose_attach(view: MatchState, uid: int, legal: Array, moment: StringName = &"after_landing") -> StringName:
	if moment != &"after_landing" or legal.is_empty():
		return &""
	var c: CreatureState = view.creatures[uid]
	if c.slot < 0:
		return &""
	for id in legal:
		var gc: CardDef = CardDB.card(StringName(id))
		if CardEffects.is_effect(gc, &"gust"):
			var target: int = PowerCalc.gust_target(view, player)
			if target >= 0:
				var r: BattleResult = PowerCalc.compute_seq(view, uid, target, view.creatures[target].slot, [[0, StringName(id)]])
				var need: float = [0.0, 40.0, 60.0][difficulty]
				if _margin(r, 0) > need and (difficulty != Difficulty.EASY or _rng.randf() < 0.5):
					return StringName(id)
	if difficulty == Difficulty.EASY:
		return &""
	if _exposure(view, uid, c.slot) <= 0.0:
		return &""
	var cards: Array[StringName] = []
	for id in legal:
		if not CardEffects.is_instant(CardDB.card(StringName(id))):
			cards.append(StringName(id))
	cards.sort_custom(_cheaper)
	for id in cards:
		if _exposure(view, uid, c.slot, id) <= 0.0:
			return id
	return &""


# ---------------------------------------------------------------- внутреннее

## Предпросмотр боя, если сторона side сыграет id следующей картой обмена.
func _with_card(view: MatchState, preview: BattleResult, id: StringName, side: int) -> BattleResult:
	return PowerCalc.compute_with(view, preview.attacker_uid, preview.defender_uid, preview.slot, preview.battle_plays, side, id)


## Перевес стороны side (ничья — в пользу защитника: атакующему нужен перевес > 0).
## «Отлив» (боя нет) — чуть лучше ничьей для обоих; оба выбывают: ворота «Предел»/«Обоюдный удар» — нейтрально,
## «Общая бездна» — спасение для того, кто проигрывал, и беда для того, кто выигрывал.
## «Трон сумрака» и «Предел» решают бой без сравнения сил.
func _margin(r: BattleResult, side: int) -> float:
	if r.interrupted:
		return 0.25
	var m: float = float(r.powers[0] - r.powers[1])
	var raw: float = m if side == 0 else -m + 0.5  # защитник выигрывает и при равенстве
	if r.both_lose:
		if r.gate_effect == &"clash" or r.gate_effect == &"limit":
			return -0.1
		return 0.25 if raw <= 0.0 else -60.0
	if r.winner_uid >= 0 and (r.auto_win or r.gate_effect == &"limit"):
		var won: bool = r.winner_uid == (r.attacker_uid if side == 0 else r.defender_uid)
		if won != (raw > 0.0):
			return 200.0 if won else -200.0
	return raw


## Сколько карт ещё может сыграть соперник в этом бою (0, если он спасовал или ему запрещены способности).
func _foe_plays_left(view: MatchState, preview: BattleResult, side: int) -> int:
	var foe: int = 1 - side
	if preview.passed[foe] or preview.silenced[foe]:
		return 0
	var used: int = 0
	for pl in preview.plays:
		if int(pl[0]) == foe:
			used += 1
	var foe_player: int = view.creatures[preview.defender_uid if foe == 1 else preview.attacker_uid].owner
	return mini(view.players[foe_player].ability_hand.size(), MatchController.MAX_BATTLE_ABILITIES - used)


func _my_plays_left(view: MatchState, preview: BattleResult, side: int) -> int:
	var used: int = 0
	for pl in preview.plays:
		if int(pl[0]) == side:
			used += 1
	return mini(view.players[player].ability_hand.size(), MatchController.MAX_BATTLE_ABILITIES - used)


func _cost_rank(id: StringName) -> int:
	var c: CardDef = CardDB.card(id)
	if c == null:
		return 99
	var k: int = ABILITY_COST_ORDER.find(String(c.effect_id))
	if k < 0:
		return 98
	return k


func _cheaper(a: StringName, b: StringName) -> bool:
	return _cost_rank(a) < _cost_rank(b)


## Перемешивание по своему rng (детерминированно).
func _shuffle(arr: Array[StringName]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: StringName = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _candidates(view: MatchState) -> Array[int]:
	var ready: Array[int] = []
	for uid in view.players[player].creature_uids:
		var c: CreatureState = view.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			ready.append(uid)
	if ready.is_empty():
		for uid in view.players[player].creature_uids:
			var c2: CreatureState = view.creatures[uid]
			if c2.alive and c2.slot >= 0:
				ready.append(uid)
	return ready


## Запомнить свои карты ворот на начало матча (первый вызов, пока рука ворот полная).
func _remember_gates(view: MatchState) -> void:
	if _gates_known:
		return
	_gates_known = true
	for id in view.players[player].arena_hand:
		_my_gates[String(id)] = true
	for s in view.slots:
		if s.has_card and s.card_owner == player and s.card_id != &"":
			_my_gates[String(s.card_id)] = true


## Вероятность, что конкретные закрытые ворота соперника — ловушка. Бронзовая карта у соперника одна;
## если она уже раскрыта (видна среди захваченных), риска нет; иначе она равновероятно любая из неизвестных.
func _foe_trap_prob(view: MatchState) -> float:
	var foe: int = 1 - player
	for p in range(2):
		for id in view.players[p].captured:
			var c: CardDef = CardDB.card(id)
			if c != null and not _my_gates.has(String(id)) and CardDB.card_class(c) == &"bronze":
				return 0.0
	var unknown: int = view.players[foe].arena_hand.size()
	for s in view.slots:
		if s.has_card and s.card_owner == foe and s.card_id == &"":
			unknown += 1
	if unknown <= 0:
		return 0.0
	return TRAP_SHARE / float(unknown)


## Оценка цели: больше — лучше; <= -500 — слот бессмыслен.
## Приоритет: забрать карту со своих ворот; бой с перевесом > 40; своя закрытая карта по атрибуту; свободные ворота.
func _score(view: MatchState, uid: int, slot: int) -> float:
	var c: CreatureState = view.creatures[uid]
	var cdef: CreatureDef = CardDB.creature(c.def_id)
	var s: SlotState = view.slots[slot]
	if not s.has_card:
		return -1000.0
	var occ: int = s.occupant_uid
	if occ == uid:
		return 300.0  # снятое с этих ворот существо просто встанет обратно
	if occ >= 0 and view.creatures[occ].owner == player:
		# свои ворота: перестановка (бой там, где соперник; иначе на пустые ворота) или карта засчитывается
		var foe_slot: int = -1
		var empty_slot: int = -1
		for i in range(view.slots.size()):
			var si: SlotState = view.slots[i]
			if not si.has_card:
				continue
			if si.occupant_uid < 0:
				if empty_slot < 0:
					empty_slot = i
			elif view.creatures[si.occupant_uid].owner != player and foe_slot < 0:
				foe_slot = i
		if foe_slot >= 0:
			return _score(view, uid, foe_slot) - 50.0
		if empty_slot >= 0:
			return 400.0
		return 1500.0
	if occ >= 0:
		# чужая закрытая карта в виде пуста = нейтральная арена (своя карта, в том числе ловушка, учтена)
		var r: BattleResult = PowerCalc.compute(view, uid, occ, slot, &"", &"")
		if r.both_lose:
			return 450.0  # размен один на один
		var margin: float = _margin(r, 0)
		var risk: float = 0.0
		if difficulty == Difficulty.HARD and s.card_owner != player and s.card_id == &"":
			risk = _foe_trap_prob(view) * TRAP_RISK_PENALTY
			if view.creatures[occ].owner == s.card_owner:
				# соперник стоит на своих воротах: скорее всего, это «Поле» его стихии
				margin = 0.5 * margin + 0.5 * _margin_with_card(view, uid, occ, slot, _field_of(view.creatures[occ]))
		if margin > WIN_MARGIN:
			return 1000.0 + margin - risk
		return 300.0 + margin * 0.5 - risk
	var stand: float = 600.0
	if s.card_owner == player:
		var card: CardDef = CardDB.card(s.card_id)
		if difficulty != Difficulty.EASY and CardEffects.is_gate_trap(card):
			return _trap_bait_score(view, uid, card)
		stand = 800.0 if _fits(card, cdef) else 650.0
	if difficulty == Difficulty.HARD:
		stand -= _exposure(view, uid, slot)
	return stand


## Перевес атакующего, если бы на воротах лежала карта card_id (вид — своя копия, карта возвращается на место).
func _margin_with_card(view: MatchState, uid: int, occ: int, slot: int, card_id: StringName) -> float:
	var keep: StringName = view.slots[slot].card_id
	view.slots[slot].card_id = card_id
	var r: BattleResult = PowerCalc.compute(view, uid, occ, slot, &"", &"")
	view.slots[slot].card_id = keep
	return float(r.powers[0] - r.powers[1])


## «Поле» стихии существа.
func _field_of(c: CreatureState) -> StringName:
	return StringName("arena_field_" + String(GameData.ATTR_KEYS[CardDB.creature(c.def_id).attribute]))


## Угроза для существа, вставшего на ворота: насколько сильнейший готовый к броску боец соперника
## перебьёт его здесь (без способностей; чужая закрытая карта — нейтральная). 0 — угрозы нет.
## extra — карта, которую защитник прикрепил бы к себе (для choose_attach).
func _exposure(view: MatchState, uid: int, slot: int, extra: StringName = &"") -> float:
	var worst: float = 0.0
	var bp: Array = [[1, extra]] if extra != &"" else []
	for fu in view.players[1 - player].creature_uids:
		var f: CreatureState = view.creatures[fu]
		if not f.alive or f.slot >= 0 or f.used:
			continue
		var r: BattleResult = PowerCalc.compute_seq(view, fu, uid, slot, bp)
		var m: float = float(r.powers[0] - r.powers[1])
		if m > 0.0:
			worst = maxf(worst, 150.0 + m * 0.5)
	return worst


## Своя ловушка без существа: «Зеркало», «Обоюдный удар», «Предел» — приманка для слабейшего (размен в нашу пользу),
## «Глухие врата» — когда у соперника больше способностей в руке.
func _trap_bait_score(view: MatchState, uid: int, card: CardDef) -> float:
	match String(card.effect_id):
		"mirror", "clash", "limit":
			var rank: int = 0
			var bp: int = CardDB.creature(view.creatures[uid].def_id).base_power
			for u in ps_uids(view):
				var o: CreatureState = view.creatures[u]
				if o.alive and u != uid and CardDB.creature(o.def_id).base_power < bp:
					rank += 1
			return 860.0 - rank * 150.0
		"mute":
			var diff: int = view.players[1 - player].ability_hand.size() - view.players[player].ability_hand.size()
			return 700.0 + diff * 40.0
	return 640.0


## Ворота подходят существу: Поле его стихии, Алтарь силы, ворота его вида, Трон сумрака для Тени.
func _fits(card: CardDef, d: CreatureDef) -> bool:
	if card == null or d == null:
		return false
	if CardEffects.field_attr(card) == d.attribute:
		return true
	match String(card.effect_id):
		"owner_power", "web", "funnel":
			return true
		"species_double":
			return CardEffects.species_lock(card) == d.species
		"dusk_throne":
			return d.attribute == Attr.A.SHADOW
	return false
