class_name AIPlayer
extends RefCounted
## ИИ-игрок. Видит только MatchState из MatchController.get_view(player) (чужие закрытые карты пусты).
## Не мутирует состояние; все решения детерминированы по rng_seed.

const WIN_MARGIN: float = 40.0
## Порядок «дешевизны» способностей (по effect_id): от наименее ценных к самым рискованным.
const ABILITY_COST_ORDER: Array[String] = [
	"home_element", "fusion_echo", "fusion_chain", "boost_self", "weaken_foe", "legacy", "steal_arena",
	"swap_attr", "steal_advantage", "rescue", "stone_wall", "nullify_arena", "overflow", "drain",
	"absorb", "fusion_double", "swap_base", "strip", "shield", "all_in",
]

var player: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _aim_error: float = 0.42


func _init(p_player: int = 1, rng_seed: int = 0, aim_error: float = 0.42) -> void:
	player = p_player
	_rng.seed = rng_seed
	_aim_error = aim_error


func get_aim_error() -> float:
	return _aim_error


## legal — MatchController.legal_setup_slots(). -> {card_id, slot}; {} = не класть (если можно пропустить).
## Кладёт карту, если ворот на поле мало (или с вероятностью), выбирая карту под стихии своих существ.
func choose_setup(view: MatchState, legal: Array = [], can_skip: bool = false) -> Dictionary:
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
		for uid in ps_uids(view):
			if _fits(card, CardDB.creature(view.creatures[uid].def_id).attribute):
				fit += 1
		fit = fit * 10 + _rng.randi_range(0, 5)
		if fit > best_fit:
			best_fit = fit
			best = id
	var slot: int = int(slots[_rng.randi_range(0, slots.size() - 1)])
	return {"card_id": best, "slot": slot}


func ps_uids(view: MatchState) -> Array[int]:
	return view.players[player].creature_uids


## -> {uid: int, target_slot: int}
func choose_throw(view: MatchState) -> Dictionary:
	var cands: Array[int] = _candidates(view)
	var best_uid: int = -1
	var best_slot: int = -1
	var best_score: float = -INF
	for uid in cands:
		for slot in range(view.slots.size()):
			var score: float = _score(view, uid, slot)
			if score <= -500.0:
				continue
			score += _rng.randf() * 2.0
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


## preview — MatchController.get_battle_preview(). &"" = пас.
## Берёт самую «дешёвую» карту из руки, после которой выигрывает; если уже выигрывает или не может — пас.
## legal: карты, разрешённые контроллером сейчас (ctrl.legal_abilities); пусто — вся рука.
func choose_ability(view: MatchState, preview: BattleResult, legal: Array = []) -> StringName:
	if preview == null:
		return &""
	var atk: CreatureState = view.creatures[preview.attacker_uid]
	var me_is_atk: bool = atk.owner == player
	var hand: Array[StringName] = view.players[player].ability_hand
	if hand.is_empty():
		return &""
	if _wins(preview, me_is_atk):
		return &""
	var sorted_hand: Array[StringName] = []
	for id in (legal if not legal.is_empty() else hand):
		if id != &"":
			sorted_hand.append(StringName(id))
	sorted_hand.sort_custom(_cheaper)
	for id in sorted_hand:
		var a: StringName = preview.atk_ability
		var d: StringName = preview.def_ability
		var af: StringName = preview.atk_fusion
		var df: StringName = preview.def_fusion
		var fusion: bool = CardEffects.is_fusion(CardDB.card(id))
		if me_is_atk:
			if fusion:
				af = id
			else:
				a = id
		elif fusion:
			df = id
		else:
			d = id
		var r: BattleResult = PowerCalc.compute(view, preview.attacker_uid, preview.defender_uid, preview.slot, a, d, af, df)
		if _wins(r, me_is_atk):
			return id
	return &""


# ---------------------------------------------------------------- внутреннее

func _wins(r: BattleResult, me_is_atk: bool) -> bool:
	# при ничьей побеждает защитник — это уже учтено в winner_uid
	if me_is_atk:
		return r.winner_uid == r.attacker_uid
	return r.winner_uid == r.defender_uid


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
		# чужая закрытая карта в виде пуста = нейтральная арена
		var r: BattleResult = PowerCalc.compute(view, uid, occ, slot, &"", &"")
		var margin: float = float(r.powers[0] - r.powers[1])
		if margin > WIN_MARGIN:
			return 1000.0 + margin
		return 300.0 + margin * 0.5
	if not s.has_card:
		return -1000.0
	if s.card_owner == player:
		if _fits(CardDB.card(s.card_id), cdef.attribute):
			return 800.0
		return 650.0
	return 600.0


func _fits(card: CardDef, attribute: int) -> bool:
	if card == null:
		return false
	if CardEffects.field_attr(card) == attribute:
		return true
	if card.effect_id == &"twilight":
		return attribute == Attr.A.LIGHT or attribute == Attr.A.SHADOW
	return false
