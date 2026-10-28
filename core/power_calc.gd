class_name PowerCalc
extends RefCounted
## Детерминированный расчёт силы боя. Способности — упорядоченный список розыгрышей plays = [[сторона, card_id], ...]
## (сторона 0 = атакующий, 1 = защитник), в который сначала входят прикреплённые к бойцам карты (по времени розыгрыша),
## затем карты, сыгранные в обмене боя. Состояние не изменяется (пробные перестановки возвращаются на место).
## Набор карт — DESIGN.md «Карты по мотивам аниме (2026-10-28)».
##
## Порядок шагов:
## 0. Отмены: «Глухие врата» гасят все карты соперника владельца ворот; «Волчья хватка» разрешается с конца списка
##    (как стопка): отменяет последнюю действующую основную карту соперника ДО себя, а если такой нет — первую
##    следующую (кроме отмены); карты с «нельзя отменить» (sure) и мгновенные не трогает. «Глубинная тишь» гасит все
##    следующие за ней карты соперника (кроме sure). Слияние без действующей основной карты не действует.
##    «Отпечаток в камне» повторяет последнюю действующую карту соперника (иначе — первую следующую).
## 1. БС. 3. Ворота: «Каменный взгляд» (любые, кроме ворот вида), «Очищающий луч» / «Затмение врат» (ворота соперника)
##    отменяют ворота; «Взор с высоты» не даёт воротам усилить соперника.
## 5. Преимущество стихии +60 (финальный раунд ×2). 6. Плоские карты и слияния. 6а. «Натиск». 7. Метки на этот бой.
## 8. «Кольца глубин» (сжечь бонусы соперника, доля params.share — себе). 9. «Пучина», «Хитиновый панцирь», «Великий сброс».
## 9а. Плоские карты, сыгранные после первого из «потолков» 8–9 (CardEffects.CEILING_EFFECTS), — поверх них.
## 10. «Гнёт». 11. Фиксированная сила из метки («Драконий напор»). 12. max(0, …). 13. «Зеркало».
## 14. Исход: по силе (ничья — защитнику) → «Трон сумрака» → «Предел» → «Обоюдный удар» → «Общая бездна» → «Отлив».
## Пустой/неизвестный id карты ворот (замаскированная в виде ИИ) = нейтральные ворота.

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


## Полный расчёт. battle_plays — карты обмена боя; прикреплённые к бойцам карты добавляются в начало автоматически.
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

	var uids: Array[int] = [atk_uid, def_uid]
	var cs: Array[CreatureState] = [state.creatures[atk_uid], state.creatures[def_uid]]
	var defs: Array[CreatureDef] = [CardDB.creature(cs[0].def_id), CardDB.creature(cs[1].def_id)]
	var owners: Array[int] = [cs[0].owner, cs[1].owner]

	# Ворота боя и сторона их владельца
	var arena_id: StringName = &""
	if slot >= 0 and slot < state.slots.size():
		arena_id = state.slots[slot].card_id
	r.arena_card_id = arena_id
	var arena: CardDef = CardDB.card(arena_id)
	var own_side: int = _gate_owner_side(state, slot, owners)
	r.gate_owner_side = own_side
	var muted: int = -1
	if CardEffects.is_effect(arena, &"mute") and own_side >= 0:
		muted = 1 - own_side
		r.silenced[muted] = true
		r.sealed = true
		r.trap_id = arena.id
		r.add(muted, "trap:" + String(arena.id), 0)

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
	var cancelled: Array[bool] = []
	for k in range(n):
		cancelled.append(cards[k] == null or sides[k] == muted)
	for k in range(n - 1, -1, -1):
		if cancelled[k] or not CardEffects.is_negate(cards[k]):
			continue
		var foe: int = 1 - sides[k]
		var target: int = -1
		for j in range(k - 1, -1, -1):
			if sides[j] == foe and not cancelled[j] and _negatable(cards[j]):
				target = j
				break
		if target < 0:
			for j in range(k + 1, n):
				if sides[j] == foe and not cancelled[j] and _negatable(cards[j]) and not CardEffects.is_negate(cards[j]):
					target = j
					break
		if target >= 0:
			cancelled[target] = true
	for k in range(n):
		if cancelled[k] or not CardEffects.is_effect(cards[k], &"silence"):
			continue
		var foe2: int = 1 - sides[k]
		r.silenced[foe2] = true
		for j in range(k + 1, n):
			if sides[j] == foe2 and not cancelled[j] and not CardEffects.is_sure(cards[j]):
				cancelled[j] = true
	# слияние без действующей основной карты не действует
	for k in range(n):
		if CardEffects.is_fusion(cards[k]) and not cancelled[k]:
			if main_of[k] < 0 or cancelled[main_of[k]]:
				cancelled[k] = true
	# действующие карты: mains[сторона] = [{c: карта эффекта, src: id карты-источника}], слияния отдельно
	var mains: Array = [[], []]
	var fusions: Array = [[], []]
	for k in range(n):
		var sd: int = sides[k]
		if cancelled[k]:
			r.cancelled_plays.append([sd, cards[k].id if cards[k] != null else StringName(plays[k][1])])
			r.add(sd, "cancelled:" + String(plays[k][1]), 0)
			continue
		if CardEffects.is_fusion(cards[k]):
			fusions[sd].append({"c": cards[k], "k": k})
		else:
			mains[sd].append({"c": cards[k], "src": cards[k].id, "k": k})
	# «Отпечаток в камне»: повтор действующей карты соперника
	for k in range(n):
		if cancelled[k] or not CardEffects.is_effect(cards[k], &"copy"):
			continue
		var foe3: int = 1 - sides[k]
		var t: int = -1
		for j in range(k - 1, -1, -1):
			if sides[j] == foe3 and not cancelled[j] and CardEffects.copyable(cards[j]):
				t = j
				break
		if t < 0:
			for j in range(k + 1, n):
				if sides[j] == foe3 and not cancelled[j] and CardEffects.copyable(cards[j]):
					t = j
					break
		if t >= 0:
			mains[sides[k]].append({"c": cards[t], "src": cards[k].id, "k": k})
			r.copies.append([sides[k], cards[k].id, cards[t].id])
	_fill_compat(r, plays, cards, cancelled)
	# «Потолки» (Великий сброс, Хитиновый панцирь, Кольца глубин, Пучина) действуют на силу, набранную до них:
	# плоские карты, сыгранные после первой такой карты (любой стороной), прибавляются уже после шагов 8–9.
	var ceil_k: int = n
	for i in range(2):
		for m in mains[i]:
			if CardEffects.CEILING_EFFECTS.has(String((m["c"] as CardDef).effect_id)):
				ceil_k = mini(ceil_k, int(m["k"]))
	var late: Array = []  # [сторона, источник, прибавка] карт после потолка

	# 1. Базовая сила
	var base: Array[int] = [defs[0].base_power, defs[1].base_power]
	var p: Array[int] = [base[0], base[1]]
	r.add(0, "base", p[0])
	r.add(1, "base", p[1])
	var attr: Array[int] = [defs[0].attribute, defs[1].attribute]
	r.attr_atk = attr[0]
	r.attr_def = attr[1]

	# 3. Ворота
	if arena != null:
		var kill: bool = false
		for i in range(2):
			for m in mains[i]:
				var e: StringName = (m["c"] as CardDef).effect_id
				if e == &"nullify_gate" and arena.effect_id != &"species_double":
					kill = true
				elif (e == &"purge_gate" or e == &"eclipse") and own_side == 1 - i:
					kill = true
		if kill:
			r.arena_cancelled = true
			arena = null
	if arena != null:
		r.gate_effect = arena.effect_id
		var ad: Array[int] = [0, 0]
		for i in range(2):
			ad[i] = _gate_delta(state, arena, i, own_side, attr[i], base[i], defs[i].species)
		for i in range(2):
			if _has(mains[i], &"aloft") and ad[1 - i] > 0:
				r.add(1 - i, "ability:" + String(_src(mains[i], &"aloft")), 0)
				ad[1 - i] = 0
		for i in range(2):
			if ad[i] != 0:
				p[i] += ad[i]
				r.add(i, "arena:" + String(arena.id), ad[i])

	# 5. Преимущество стихии
	var bonus: int = ADVANTAGE_BONUS * (FINAL_ADVANTAGE_MULT if state.final_round else 1)
	for i in range(2):
		if Attr.beats(attr[i], attr[1 - i]):
			p[i] += bonus
			r.add(i, "advantage", bonus)

	# 6. Плоские модификаторы способностей и слияний
	for i in range(2):
		var ctx: Dictionary = {"attack": i == 0, "own_gate": own_side == i, "my_base": base[i], "foe_base": base[1 - i],
			"foe_beats": Attr.beats(attr[1 - i], attr[i]),
			"dead_own": state.dead_count(owners[i]), "alive_own": state.alive_count(owners[i]),
			"alive_foe": state.alive_count(owners[1 - i])}
		for m in mains[i]:
			var v: Vector2i = CardEffects.ability_delta(m["c"], ctx)
			var src: String = "ability:" + String(m["src"])
			if int(m["k"]) > ceil_k:
				late.append([i, src, v.x])
				if v.y != 0:
					late.append([1 - i, src, v.y])
				continue
			if v.x != 0:
				p[i] += v.x
				r.add(i, src, v.x)
			if v.y != 0:
				p[1 - i] += v.y
				r.add(1 - i, src, v.y)
			if v == Vector2i.ZERO:
				r.add(i, src, 0)
		for f in fusions[i]:
			var fc: CardDef = f["c"]
			var fx: int = int(fc.params.get("amount", 0))
			if int(f["k"]) > ceil_k:
				late.append([i, "ability:" + String(fc.id), fx])
				continue
			p[i] += fx
			r.add(i, "ability:" + String(fc.id), fx)

	# 6а. «Натиск»: бонус за серию побед владельца бойца
	for i in range(2):
		var mo: int = clampi(state.players[owners[i]].momentum, 0, MOMENTUM_MAX) * MOMENTUM_STEP
		r.momentum[i] = mo
		if mo > 0:
			p[i] += mo
			r.add(i, "momentum", mo)

	# 7. Метки на этот бой (поставлены картами прошлых боёв)
	var fixed: Array[int] = [-1, -1]
	for i in range(2):
		for mk in cs[i].marks:
			if mk.has("fix"):
				fixed[i] = int(mk["fix"])
			elif int(mk.get("delta", 0)) != 0:
				p[i] += int(mk["delta"])
				r.add(i, "mark:" + String(mk.get("src", "")), int(mk["delta"]))

	# 8. «Кольца глубин»: все бонусы соперника сверх его БС переходят к тебе
	for i in range(2):
		if _has(mains[i], &"siphon"):
			var extra: int = maxi(0, p[1 - i] - base[1 - i])
			if extra > 0:
				var src2: String = "ability:" + String(_src(mains[i], &"siphon"))
				# params.share — какая доля (%) забранного переходит к тебе (у копии — как у оригинала)
				var share: int = 100
				for m in mains[i]:
					if (m["c"] as CardDef).effect_id == &"siphon":
						share = int((m["c"] as CardDef).params.get("share", 100))
						break
				var gain: int = extra * share / 100
				p[1 - i] -= extra
				p[i] += gain
				r.add(1 - i, src2, -extra)
				r.add(i, src2, gain)

	# 9. Потолки силы: «Пучина» (не выше своей БС), «Хитиновый панцирь» (не выше БС владельца), «Великий сброс»
	for i in range(2):
		if _has(mains[i], &"strip") and p[1 - i] > base[1 - i]:
			r.add(1 - i, "ability:" + String(_src(mains[i], &"strip")), base[1 - i] - p[1 - i])
			p[1 - i] = base[1 - i]
		if _has(mains[i], &"cap_own_base") and p[1 - i] > base[i]:
			r.add(1 - i, "ability:" + String(_src(mains[i], &"cap_own_base")), base[i] - p[1 - i])
			p[1 - i] = base[i]
	for i in range(2):
		if _has(mains[i], &"reset_base"):
			var rs: String = "ability:" + String(_src(mains[i], &"reset_base"))
			for j in range(2):
				if p[j] != base[j]:
					r.add(j, rs, base[j] - p[j])
					p[j] = base[j]
			break

	# 9а. Карты, сыгранные после потолка
	for lt in late:
		p[int(lt[0])] += int(lt[2])
		r.add(int(lt[0]), lt[1], int(lt[2]))

	# 10. «Гнёт»: −amount каждому с силой от порога
	if arena != null and arena.effect_id == &"weight":
		for i in range(2):
			if p[i] >= int(arena.params.get("threshold", 400)):
				var w: int = int(arena.params.get("amount", 100))
				p[i] -= w
				r.add(i, "arena:" + String(arena.id), -w)

	# 11. Фиксированная сила из метки
	for i in range(2):
		if fixed[i] >= 0:
			r.add(i, "mark_fix", fixed[i] - p[i])
			p[i] = fixed[i]

	# 12. Нижняя граница
	for i in range(2):
		if p[i] < 0:
			r.add(i, "floor", -p[i])
			p[i] = 0

	# 13. «Зеркало»: итоговые силы меняются местами
	if arena != null and arena.effect_id == &"mirror":
		r.trap_id = arena.id
		r.mirrored = true
		var d0: int = p[1] - p[0]
		if d0 != 0:
			r.add(0, "trap:" + String(arena.id), d0)
			r.add(1, "trap:" + String(arena.id), -d0)
		var tmp: int = p[0]
		p[0] = p[1]
		p[1] = tmp
	r.powers[0] = p[0]
	r.powers[1] = p[1]

	# 14. Исход
	var win_side: int = 0 if p[0] > p[1] else 1
	var gate_e: StringName = arena.effect_id if arena != null else &""
	if gate_e == &"dusk_throne":
		var dark: Array[bool] = [attr[0] == Attr.A.SHADOW, attr[1] == Attr.A.SHADOW]
		if dark[0] != dark[1]:
			win_side = 0 if dark[0] else 1
			r.auto_win = true
			r.add(win_side, "rule:dusk_throne", 0)
	if gate_e == &"limit":
		r.trap_id = arena.id
		var cap: int = int(arena.params.get("amount", 400))
		var over: Array[bool] = [p[0] > cap, p[1] > cap]
		if over[0] and over[1]:
			r.both_lose = true
		elif over[0] or over[1]:
			win_side = 1 if over[0] else 0
		r.add(0, "trap:" + String(arena.id), 0)
	if gate_e == &"clash":
		r.trap_id = arena.id
		r.both_lose = true
		r.add(0, "trap:" + String(arena.id), 0)
	if not r.both_lose and _has(mains[1 - win_side], &"doom"):
		r.both_lose = true
		r.add(1 - win_side, "ability:" + String(_src(mains[1 - win_side], &"doom")), 0)
	for i in range(2):
		if _has(mains[i], &"ebb"):
			var to: int = free_gate(state, slot)
			if to >= 0:
				r.interrupted = true
				r.relocate_uid = uids[1 - i]
				r.relocate_to = to
				r.both_lose = false
			break
	if r.interrupted or r.both_lose:
		r.winner_uid = -1
		r.loser_uid = -1
	else:
		r.winner_uid = uids[win_side]
		r.loser_uid = uids[1 - win_side]
		r.winner_stays = gate_e == &"hold"

	# Последствия для контроллера: метки на следующий бой, возрождение, возврат карт
	for i in range(2):
		r.revive[i] = _has(mains[i], &"revive")
		if _has(mains[i], &"recall"):
			r.recall[i] = _src(mains[i], &"recall")
		for m in mains[i]:
			var c: CardDef = m["c"]
			var amt: int = int(c.params.get("amount", 0))
			match String(c.effect_id):
				"scorch", "radiance":
					var spare: int = int(c.params.get("spare", -1))
					for u in _standing(state, owners[1 - i], uids):
						if CardDB.creature(state.creatures[u].def_id).attribute != spare:
							r.marks.append([u, {"src": m["src"], "delta": -amt}])
				"pact":
					for u in _standing(state, owners[i], uids):
						r.marks.append([u, {"src": m["src"], "delta": amt}])
				"weaken_mark":
					r.marks.append([uids[1 - i], {"src": m["src"], "delta": -int(c.params.get("mark", 0))}])
				"boost_fix":
					r.marks.append([uids[i], {"src": m["src"], "fix": int(c.params.get("fix", 0))}])
	return r


## Отменяема ли карта «Волчьей хваткой»: основная, не мгновенная, без «нельзя отменить».
static func _negatable(c: CardDef) -> bool:
	return c != null and not CardEffects.is_fusion(c) and not CardEffects.is_sure(c) and not CardEffects.is_instant(c)


## Совместимые поля: первая основная карта стороны и её слияние, флаги отмены.
static func _fill_compat(r: BattleResult, plays: Array, cards: Array[CardDef], cancelled: Array[bool]) -> void:
	for k in range(plays.size()):
		var sd: int = int(plays[k][0])
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


## Бонус ворот стороне i (шаг 3). Пороговые «Гнёт» и исходы («Предел», «Зеркало»…) считаются позже.
static func _gate_delta(state: MatchState, arena: CardDef, i: int, own_side: int, attr: int, base: int, species: StringName) -> int:
	var amount: int = int(arena.params.get("amount", 0))
	var v: int = 0
	var g: Array = arena.params.get("g", [])
	if attr >= 0 and attr < g.size():
		v += int(g[attr])
	match String(arena.effect_id):
		"owner_power":
			if i == own_side and i == 1:
				v += amount
		"species_double":
			if species != &"" and species == StringName(arena.params.get("species", "")):
				v += base
		"funnel":
			if own_side >= 0:
				v += amount if i == own_side else -amount
		"web":
			if i == own_side:
				v += amount * gates_on_field(state)
	return v


## Бонус ворот slot существу uid как защитнику (без соперника; для подсказок интерфейса).
static func gate_bonus_for(state: MatchState, uid: int, slot: int) -> int:
	var arena: CardDef = CardDB.card(state.slots[slot].card_id)
	var c: CreatureState = state.creatures.get(uid)
	if arena == null or c == null:
		return 0
	var d: CreatureDef = CardDB.creature(c.def_id)
	var own_side: int = 1 if state.slots[slot].card_owner == c.owner else 0
	return _gate_delta(state, arena, 1, own_side, d.attribute, d.base_power, d.species)


static func _gate_owner_side(state: MatchState, slot: int, owners: Array[int]) -> int:
	if slot < 0 or slot >= state.slots.size():
		return -1
	var o: int = state.slots[slot].card_owner
	if o < 0:
		return -1
	if owners[0] == o:
		return 0
	if owners[1] == o:
		return 1
	return -1


static func _has(list: Array, effect: StringName) -> bool:
	for m in list:
		if (m["c"] as CardDef).effect_id == effect:
			return true
	return false


static func _src(list: Array, effect: StringName) -> StringName:
	for m in list:
		if (m["c"] as CardDef).effect_id == effect:
			return m["src"]
	return &""


## Стоящие на воротах живые существа игрока, кроме бойцов этого боя.
static func _standing(state: MatchState, player: int, exclude: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for u in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[u]
		if c.alive and c.slot >= 0 and not exclude.has(u):
			out.append(u)
	return out


# ---------------------------------------------------------------- помощники мгновенных карт (контроллер и ИИ)

static func gates_on_field(state: MatchState) -> int:
	var k: int = 0
	for s in state.slots:
		if s.has_card:
			k += 1
	return k


## Свободные ворота (карта есть, существа нет), кроме слота exclude: первые по номеру; -1 — нет.
static func free_gate(state: MatchState, exclude: int) -> int:
	for i in range(state.slots.size()):
		var s: SlotState = state.slots[i]
		if i != exclude and s.has_card and s.occupant_uid < 0:
			return i
	return -1


## «Попутный шквал»: самое слабое (по БС) стоящее существо соперника player; -1 — нет.
static func gust_target(state: MatchState, player: int) -> int:
	var best: int = -1
	var best_pw: int = 1 << 30
	for u in state.players[1 - player].creature_uids:
		var c: CreatureState = state.creatures[u]
		if not c.alive or c.slot < 0:
			continue
		var pw: int = CardDB.creature(c.def_id).base_power
		if pw < best_pw:
			best_pw = pw
			best = u
	return best


## «Вихревая подмена»: сильнейшее существо игрока в руке или в зоне использованных (не на воротах), кроме exclude.
static func swap_candidate(state: MatchState, player: int, exclude: Array) -> int:
	var best: int = -1
	var best_pw: int = -1
	for u in state.players[player].creature_uids:
		var c: CreatureState = state.creatures[u]
		if not c.alive or c.slot >= 0 or exclude.has(u):
			continue
		var pw: int = CardDB.creature(c.def_id).base_power
		if pw > best_pw:
			best_pw = pw
			best = u
	return best


## «Сдвиг плит»: свои свободные ворота (известная карта, не ловушка), выгоднейшие для стороны side; -1 — нет.
static func best_gate_swap(state: MatchState, atk_uid: int, def_uid: int, slot: int, plays: Array, side: int) -> int:
	var player: int = state.creatures[atk_uid if side == 0 else def_uid].owner
	var best: int = -1
	var best_m: int = -(1 << 30)
	for j in range(state.slots.size()):
		var s: SlotState = state.slots[j]
		if j == slot or not s.has_card or s.occupant_uid >= 0 or s.card_owner != player:
			continue
		var c: CardDef = CardDB.card(s.card_id)
		if c == null or CardEffects.is_gate_trap(c):
			continue
		_swap_cards(state, slot, j)
		var r: BattleResult = compute_seq(state, atk_uid, def_uid, slot, plays)
		_swap_cards(state, slot, j)
		var m: int = r.powers[side] - r.powers[1 - side]
		if r.both_lose:
			m -= 1000
		if m > best_m:
			best_m = m
			best = j
	return best


## Обмен картами ворот двух слотов (карта, владелец, открытость); существа остаются на месте.
static func _swap_cards(state: MatchState, a: int, b: int) -> void:
	var sa: SlotState = state.slots[a]
	var sb: SlotState = state.slots[b]
	var t_id: StringName = sa.card_id
	var t_owner: int = sa.card_owner
	var t_rev: bool = sa.revealed
	sa.card_id = sb.card_id
	sa.card_owner = sb.card_owner
	sa.revealed = sb.revealed
	sb.card_id = t_id
	sb.card_owner = t_owner
	sb.revealed = t_rev


## Предпросмотр: сторона side играет card_id следующей картой обмена (учитывает мгновенные «Сдвиг плит» и
## «Вихревую подмену» на копии состояния). Для ИИ.
static func compute_with(state: MatchState, atk_uid: int, def_uid: int, slot: int, battle_plays: Array, side: int, card_id: StringName) -> BattleResult:
	var bp: Array = battle_plays.duplicate(true)
	bp.append([side, card_id])
	var c: CardDef = CardDB.card(card_id)
	if CardEffects.is_effect(c, &"shift_gate"):
		var j: int = best_gate_swap(state, atk_uid, def_uid, slot, battle_plays, side)
		if j >= 0:
			var v: MatchState = state.duplicate_full()
			_swap_cards(v, slot, j)
			v.slots[slot].revealed = true
			return compute_seq(v, atk_uid, def_uid, slot, bp)
	elif CardEffects.is_effect(c, &"swap_fighter"):
		var player: int = state.creatures[atk_uid if side == 0 else def_uid].owner
		var nu: int = swap_candidate(state, player, [atk_uid, def_uid])
		if nu >= 0:
			var v2: MatchState = state.duplicate_full()
			var old: int = atk_uid if side == 0 else def_uid
			if side == 1:
				v2.creatures[old].slot = -1
				v2.creatures[nu].slot = slot
				v2.slots[slot].occupant_uid = nu
			return compute_seq(v2, nu if side == 0 else atk_uid, nu if side == 1 else def_uid, slot, bp)
	return compute_seq(state, atk_uid, def_uid, slot, bp)
