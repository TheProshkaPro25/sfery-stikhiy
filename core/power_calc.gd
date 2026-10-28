class_name PowerCalc
extends RefCounted
## Детерминированный расчёт силы боя. Способности — упорядоченный список розыгрышей plays = [[сторона, card_id], ...]
## (сторона 0 = атакующий, 1 = защитник), в который сначала входят прикреплённые к бойцам карты (по времени розыгрыша),
## затем карты, сыгранные в обмене боя. Состояние не изменяется.
##
## Порядок шагов:
## 0. Отмены: «Печать тишины» гасит всё; Щиты разрешаются с конца списка (как стопка): Щит отменяет последнюю
##    действующую основную карту соперника, сыгранную ДО него (вместе с её слиянием), а если такой нет — первую
##    следующую основную карту соперника, кроме Щита. «Цепная искра» делает карты своей стороны неотменяемыми.
## 1. БС («Обмен сутью»: нечётное число действующих карт меняет базовые силы).
## 3. Перелив, затем «Водоворот» (нечётное число меняет стихии). 4. Карта ворот (если нет Глушителя), «Перехват поля».
## 5. Преимущество атрибута (Пустота обнуляет, Перевес удваивает, «Обратный ток» разворачивает, финальный раунд ×2),
##    «Встречный ветер». 6. Плоские модификаторы способностей и слияний. 6а. «Натиск». 6б. «Поглощение».
## 6в. «Ослепление». 7. max(0, ...). 8. «Зеркало» меняет итоговые силы. Ничья — победа защитника.
##
## Договорённости:
## - Слияние относится к последней своей основной карте перед ним и действует, только если она действует.
## - «Резонанс» удваивает числа своей основной карты на шагах 4–6б.
## - Глушитель любой стороны (если он действует) отменяет карту ворот, в том числе ловушки «Зеркало» и «Обратный ток».
## - Пустой/неизвестный id карты ворот (замаскированная в виде ИИ) = нейтральные ворота.

const ADVANTAGE_BONUS: int = 60
## «Натиск»: бонус за каждую победу подряд и предел серии.
const MOMENTUM_STEP: int = 40
const MOMENTUM_MAX: int = 2
## Финальный раунд: множитель преимущества стихии.
const FINAL_ADVANTAGE_MULT: int = 2


## Совместимый вход: по одной основной карте и одному слиянию на сторону (порядок: атакующий, затем защитник).
static func compute(state: MatchState, atk_uid: int, def_uid: int, slot: int, atk_ability: StringName, def_ability: StringName,
		atk_fusion: StringName = &"", def_fusion: StringName = &"") -> BattleResult:
	var plays: Array = []
	for pr in [[0, atk_ability], [0, atk_fusion], [1, def_ability], [1, def_fusion]]:
		if pr[1] != &"":
			plays.append(pr)
	return compute_seq(state, atk_uid, def_uid, slot, plays)


## Прикреплённые к бойцам карты (сыгранные до броска / после приземления), по времени розыгрыша: [[сторона, id], ...].
static func attached_plays(state: MatchState, atk_uid: int, def_uid: int) -> Array:
	var tmp: Array = []
	var uids: Array[int] = [atk_uid, def_uid]
	for side in range(2):
		var c: CreatureState = state.creatures[uids[side]]
		for a in c.attached:
			tmp.append([int(a[0]), side, StringName(a[1])])
	tmp.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: Array = []
	for t in tmp:
		out.append([t[1], t[2]])
	return out


## Полный расчёт. plays — карты обмена боя; прикреплённые к бойцам карты добавляются в начало автоматически.
static func compute_seq(state: MatchState, atk_uid: int, def_uid: int, slot: int, battle_plays: Array) -> BattleResult:
	var r: BattleResult = BattleResult.new()
	r.slot = slot
	r.attacker_uid = atk_uid
	r.defender_uid = def_uid
	r.final_round = state.final_round
	var plays: Array = attached_plays(state, atk_uid, def_uid)
	plays.append_array(battle_plays)
	r.plays = plays.duplicate(true)
	r.battle_plays = battle_plays.duplicate(true)

	var ac: CreatureState = state.creatures[atk_uid]
	var dc: CreatureState = state.creatures[def_uid]
	var adef: CreatureDef = CardDB.creature(ac.def_id)
	var ddef: CreatureDef = CardDB.creature(dc.def_id)
	var owners: Array[int] = [ac.owner, dc.owner]

	# Карта ворот (нужна заранее: «Печать тишины» гасит способности до Щита)
	var arena_id: StringName = &""
	if slot >= 0 and slot < state.slots.size():
		arena_id = state.slots[slot].card_id
	r.arena_card_id = arena_id
	var arena: CardDef = CardDB.card(arena_id)
	var sealed: bool = CardEffects.is_effect(arena, &"seal")
	r.sealed = sealed
	if sealed:
		r.trap_id = arena.id

	# 0. Отмены
	var n: int = plays.size()
	var cards: Array[CardDef] = []
	var sides: Array[int] = []
	var main_of: Array[int] = []  # для слияния — индекс его основной карты (-1, если нет)
	var last_main: Array[int] = [-1, -1]
	for k in range(n):
		var c: CardDef = CardDB.card(StringName(plays[k][1]))
		var sd: int = int(plays[k][0])
		cards.append(c)
		sides.append(sd)
		if CardEffects.is_fusion(c):
			main_of.append(last_main[sd])
		else:
			main_of.append(-1)
			last_main[sd] = k
	var immune: Array[bool] = [false, false]
	for k in range(n):
		if CardEffects.is_effect(cards[k], &"fusion_chain") and main_of[k] >= 0:
			immune[sides[k]] = true
	var cancelled: Array[bool] = []
	for k in range(n):
		cancelled.append(sealed or cards[k] == null)
	if not sealed:
		for k in range(n - 1, -1, -1):
			if cancelled[k] or not CardEffects.is_shield(cards[k]):
				continue
			var foe: int = 1 - sides[k]
			if immune[foe]:
				continue
			var target: int = -1
			for j in range(k - 1, -1, -1):
				if sides[j] == foe and not cancelled[j] and not CardEffects.is_fusion(cards[j]):
					target = j
					break
			if target < 0:
				for j in range(k + 1, n):
					if sides[j] == foe and not cancelled[j] and not CardEffects.is_fusion(cards[j]) and not CardEffects.is_shield(cards[j]):
						target = j
						break
			if target >= 0:
				cancelled[target] = true
	# слияние без действующей основной карты не действует (и считается отменённым, если основная отменена)
	for k in range(n):
		if CardEffects.is_fusion(cards[k]) and not cancelled[k]:
			if main_of[k] < 0 or cancelled[main_of[k]]:
				cancelled[k] = true
	# действующие карты: основные с множителем «Резонанса», слияния
	var mains: Array = [[], []]  # [[CardDef, mult], ...]
	var fusions: Array = [[], []]  # [[CardDef, main CardDef], ...]
	var mult_at: Dictionary = {}
	for k in range(n):
		if not cancelled[k] and CardEffects.is_effect(cards[k], &"fusion_double"):
			mult_at[main_of[k]] = 2
	for k in range(n):
		var sd: int = sides[k]
		if cancelled[k]:
			r.cancelled_plays.append([sd, cards[k].id if cards[k] != null else StringName(plays[k][1])])
			r.add(sd, "cancelled:" + String(plays[k][1]), 0)
			continue
		if CardEffects.is_fusion(cards[k]):
			fusions[sd].append([cards[k], cards[main_of[k]]])
		else:
			mains[sd].append([cards[k], int(mult_at.get(k, 1))])
	# совместимые поля: первая основная карта стороны и её слияние, флаги отмены
	for k in range(n):
		var sd: int = sides[k]
		var id: StringName = StringName(plays[k][1])
		if CardEffects.is_fusion(cards[k]):
			if sd == 0 and r.atk_fusion == &"":
				r.atk_fusion = id
			elif sd == 1 and r.def_fusion == &"":
				r.def_fusion = id
		elif sd == 0 and r.atk_ability == &"":
			r.atk_ability = id
		elif sd == 1 and r.def_ability == &"":
			r.def_ability = id
		if cancelled[k] and not CardEffects.is_fusion(cards[k]):
			if sd == 0:
				r.atk_cancelled = true
			else:
				r.def_cancelled = true
	if sealed:
		r.add(0, "trap:" + String(arena.id), 0)
		r.add(1, "trap:" + String(arena.id), 0)

	# 1. Базовая сила
	var base: Array[int] = [adef.base_power, ddef.base_power]
	var p: Array[int] = [base[0], base[1]]
	r.add(0, "base", p[0])
	r.add(1, "base", p[1])
	var swaps: int = _count(mains, &"swap_base")
	if swaps % 2 == 1:
		var sc: CardDef = _first(mains, &"swap_base")
		var b0: int = base[0]
		base = [base[1], b0]
		for i in range(2):
			var d: int = base[i] - p[i]
			p[i] = base[i]
			r.add(i, "ability:" + String(sc.id), d)

	# 3. Перелив, затем Водоворот
	var orig: Array[int] = [adef.attribute, ddef.attribute]
	var attr: Array[int] = [orig[0], orig[1]]
	for i in range(2):
		var ov: CardDef = _first_side(mains[i], &"overflow")
		if ov != null:
			attr[i] = CardEffects.overflow_attr(orig[1 - i])
			r.add(i, "ability:" + String(ov.id), 0)
	if _count(mains, &"swap_attr") % 2 == 1:
		var a0: int = attr[0]
		attr = [attr[1], a0]
	r.attr_atk = attr[0]
	r.attr_def = attr[1]

	# 4. Карта ворот
	if arena != null and _count(mains, &"nullify_arena") > 0:
		r.arena_cancelled = true
		arena = null
	if arena != null:
		var ad: Array[int] = [0, 0]
		for i in range(2):
			ad[i] = CardEffects.arena_delta(arena, i == 0, attr[i], base[i], base[1 - i], _owner_attr(state, state.slots[slot].card_owner) if slot >= 0 else -1)
			if ad[i] != 0:
				p[i] += ad[i]
				r.add(i, "arena:" + String(arena.id), ad[i])
		for i in range(2):
			for m in mains[i]:
				if CardEffects.is_effect(m[0], &"steal_arena") and ad[1 - i] > 0:
					var take: int = ad[1 - i]
					ad[1 - i] = 0
					p[1 - i] -= take
					p[i] += take * int(m[1])
					r.add(1 - i, "ability:" + String(m[0].id), -take)
					r.add(i, "ability:" + String(m[0].id), take * int(m[1]))

	# 5. Преимущество атрибута
	var is_void: bool = CardEffects.arena_is_void(arena)
	var is_overweight: bool = CardEffects.arena_is_overweight(arena) and not is_void
	var backflow: bool = CardEffects.is_effect(arena, &"backflow")
	if backflow:
		r.trap_id = arena.id
	if not is_void:
		var bonus: int = ADVANTAGE_BONUS
		if is_overweight:
			bonus = ADVANTAGE_BONUS * 2
		if state.final_round:
			bonus *= FINAL_ADVANTAGE_MULT
		var adv: Array[int] = [0, 0]
		for i in range(2):
			# «Обратный ток»: преимущество у того, чью стихию бьют
			var beats: bool = Attr.beats(attr[1 - i], attr[i]) if backflow else Attr.beats(attr[i], attr[1 - i])
			if beats:
				adv[i] = bonus
		for i in range(2):
			for m in mains[i]:
				if CardEffects.is_effect(m[0], &"steal_advantage") and adv[1 - i] > 0:
					adv[i] += adv[1 - i] * int(m[1])
					adv[1 - i] = 0
					r.add(i, "ability:" + String(m[0].id), 0)
		for i in range(2):
			if adv[i] > 0:
				p[i] += adv[i]
				r.add(i, "advantage", adv[i])

	# 6. Плоские модификаторы способностей и слияний
	var field_attribute: int = CardEffects.field_attr(arena)
	var dead: Array[int] = [state.dead_count(owners[0]), state.dead_count(owners[1])]
	for i in range(2):
		for m in mains[i]:
			var v: Vector2i = CardEffects.ability_delta(m[0], attr[i], field_attribute, dead[i], i == 1) * int(m[1])
			if v.x != 0:
				p[i] += v.x
				r.add(i, "ability:" + String(m[0].id), v.x)
			if v.y != 0:
				p[1 - i] += v.y
				r.add(1 - i, "ability:" + String(m[0].id), v.y)
		for fpair in fusions[i]:
			var f: CardDef = fpair[0]
			var fx: int = 0
			match String(f.effect_id):
				"fusion_chain":
					fx = int(f.params.get("amount", 0))
				"fusion_echo":
					fx = int(f.params.get("amount", 0)) * _played_count(state.players[owners[i]], plays, i, f.id)
			if fx != 0:
				p[i] += fx
				r.add(i, "ability:" + String(f.id), fx)
			elif f.effect_id == &"fusion_double":
				r.add(i, "ability:" + String(f.id), 0)

	# 6а. «Натиск»: бонус за серию побед владельца бойца
	for i in range(2):
		var mo: int = clampi(state.players[owners[i]].momentum, 0, MOMENTUM_MAX) * MOMENTUM_STEP
		r.momentum[i] = mo
		if mo > 0:
			p[i] += mo
			r.add(i, "momentum", mo)

	# 6б. Поглощение: половина бонусов соперника сверх его БС (с Резонансом — все)
	for i in range(2):
		for m in mains[i]:
			if CardEffects.is_effect(m[0], &"absorb"):
				var extra: int = maxi(0, p[1 - i] - base[1 - i])
				var take: int = extra * int(m[1]) / 2
				if take > 0:
					p[1 - i] -= take
					p[i] += take
					r.add(1 - i, "ability:" + String(m[0].id), -take)
					r.add(i, "ability:" + String(m[0].id), take)

	# 6в. Ослепление: сила соперника не выше его базовой
	for i in range(2):
		var st: CardDef = _first_side(mains[i], &"strip")
		if st != null and p[1 - i] > base[1 - i]:
			var cut: int = p[1 - i] - base[1 - i]
			p[1 - i] = base[1 - i]
			r.add(1 - i, "ability:" + String(st.id), -cut)

	# 7. Нижняя граница
	for i in range(2):
		if p[i] < 0:
			r.add(i, "floor", -p[i])
			p[i] = 0

	# 8. «Зеркало»: итоговые силы меняются местами
	if CardEffects.is_effect(arena, &"mirror"):
		r.trap_id = arena.id
		r.mirrored = true
		var d0: int = p[1] - p[0]
		if d0 != 0:
			r.add(0, "trap:" + String(arena.id), d0)
			r.add(1, "trap:" + String(arena.id), -d0)
		var t: int = p[0]
		p[0] = p[1]
		p[1] = t

	r.atk_rescue = _first_side(mains[0], &"rescue") != null
	r.def_rescue = _first_side(mains[1], &"rescue") != null
	r.atk_all_in = _first_side(mains[0], &"all_in") != null
	r.def_all_in = _first_side(mains[1], &"all_in") != null
	r.powers[0] = p[0]
	r.powers[1] = p[1]
	if p[0] > p[1]:
		r.winner_uid = atk_uid
		r.loser_uid = def_uid
	else:
		r.winner_uid = def_uid
		r.loser_uid = atk_uid
	return r


## Стихия владельца ворот (команда одной стихии): по первому его существу; -1 — неизвестно.
static func _owner_attr(state: MatchState, owner: int) -> int:
	if owner < 0 or owner > 1 or state.players[owner].creature_uids.is_empty():
		return -1
	var c: CreatureState = state.creatures.get(state.players[owner].creature_uids[0])
	if c == null:
		return -1
	var d: CreatureDef = CardDB.creature(c.def_id)
	return d.attribute if d != null else -1


static func _count(mains: Array, effect: StringName) -> int:
	var k: int = 0
	for i in range(2):
		for m in mains[i]:
			if CardEffects.is_effect(m[0], effect):
				k += 1
	return k


static func _first(mains: Array, effect: StringName) -> CardDef:
	for i in range(2):
		var c: CardDef = _first_side(mains[i], effect)
		if c != null:
			return c
	return null


static func _first_side(list: Array, effect: StringName) -> CardDef:
	for m in list:
		if CardEffects.is_effect(m[0], effect):
			return m[0]
	return null


## Число способностей игрока за матч (для «Отголоска»): сыгранные раньше плюс карты этого боя, ещё не учтённые
## (в предпросмотре ИИ карта может быть ещё в руке). Сам «Отголосок» не считается.
static func _played_count(ps: PlayerState, plays: Array, side: int, echo_id: StringName) -> int:
	var n: int = 0
	for id in ps.abilities_used:
		if id != echo_id:
			n += 1
	for pl in plays:
		var id2: StringName = StringName(pl[1])
		if int(pl[0]) == side and id2 != echo_id and not ps.abilities_used.has(id2):
			n += 1
	return n
