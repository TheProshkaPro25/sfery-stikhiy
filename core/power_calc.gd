class_name PowerCalc
extends RefCounted
## Детерминированный расчёт силы боя. Порядок шагов (DESIGN.md, раздел 1):
## 1. БС («Обмен сутью» меняет базовые силы). 2. Щит («Цепная искра» защищает от него).
## 3. Перелив, затем «Водоворот». 4. Карта арены (если нет Глушителя), «Перехват поля».
## 5. Преимущество атрибута (Пустота обнуляет, Перевес удваивает), «Встречный ветер».
## 6. Плоские модификаторы способностей и слияний. 6б. «Поглощение». 6в. «Ослепление».
## 7. max(0, ...). Ничья — победа защитника.
## Сторона 0 = атакующий, 1 = защитник. Состояние не изменяется.
##
## Договорённости по краевым случаям:
## - Щит отменяет способность соперника (и её слияние) независимо от очерёдности розыгрыша; два Щита отменяют друг друга.
## - «Цепная искра» защищает обе карты своей стороны от Щита.
## - Слияние без действующей основной способности не действует.
## - Два «Перелива» считаются одновременно от исходных атрибутов; два «Водоворота» / «Обмена сутью» гасят друг друга.
## - Глушитель любой стороны (если он не отменён Щитом) отменяет карту арены.
## - «Резонанс» удваивает числа основной способности на шагах 4–6б.
## - Пустой/неизвестный id карты арены (замаскированная в виде ИИ) = нейтральная арена.

const ADVANTAGE_BONUS: int = 60


static func compute(state: MatchState, atk_uid: int, def_uid: int, slot: int, atk_ability: StringName, def_ability: StringName,
		atk_fusion: StringName = &"", def_fusion: StringName = &"") -> BattleResult:
	var r: BattleResult = BattleResult.new()
	r.slot = slot
	r.attacker_uid = atk_uid
	r.defender_uid = def_uid
	r.atk_ability = atk_ability
	r.def_ability = def_ability
	r.atk_fusion = atk_fusion
	r.def_fusion = def_fusion

	var ac: CreatureState = state.creatures[atk_uid]
	var dc: CreatureState = state.creatures[def_uid]
	var adef: CreatureDef = CardDB.creature(ac.def_id)
	var ddef: CreatureDef = CardDB.creature(dc.def_id)
	var owners: Array[int] = [ac.owner, dc.owner]

	# Карты сторон и Щит (считаем заранее: от него зависит «Обмен сутью» на шаге 1)
	var abil: Array[CardDef] = [CardDB.card(atk_ability), CardDB.card(def_ability)]
	var fus: Array[CardDef] = [CardDB.card(atk_fusion), CardDB.card(def_fusion)]
	var chain: Array[bool] = [CardEffects.is_effect(fus[0], &"fusion_chain") and abil[0] != null,
		CardEffects.is_effect(fus[1], &"fusion_chain") and abil[1] != null]
	var eff: Array[CardDef] = [abil[0], abil[1]]
	if CardEffects.is_shield(abil[1]) and not chain[0]:
		eff[0] = null
	if CardEffects.is_shield(abil[0]) and not chain[1]:
		eff[1] = null
	var feff: Array[CardDef] = [fus[0] if eff[0] != null else null, fus[1] if eff[1] != null else null]
	r.atk_cancelled = abil[0] != null and eff[0] == null
	r.def_cancelled = abil[1] != null and eff[1] == null
	var mult: Array[int] = [1, 1]
	for i in range(2):
		if CardEffects.is_effect(feff[i], &"fusion_double"):
			mult[i] = 2

	# 1. Базовая сила
	var base: Array[int] = [adef.base_power, ddef.base_power]
	var p: Array[int] = [base[0], base[1]]
	r.add(0, "base", p[0])
	r.add(1, "base", p[1])
	var swap_b: bool = CardEffects.is_effect(eff[0], &"swap_base") != CardEffects.is_effect(eff[1], &"swap_base")
	if swap_b:
		var who: int = 0 if CardEffects.is_effect(eff[0], &"swap_base") else 1
		var b0: int = base[0]
		base = [base[1], b0]
		for i in range(2):
			var d: int = base[i] - p[i]
			p[i] = base[i]
			r.add(i, "ability:" + String(eff[who].id), d)

	# 2. Щит (запись в разбор)
	if r.atk_cancelled:
		r.add(0, "cancelled:" + String(atk_ability), 0)
	if r.def_cancelled:
		r.add(1, "cancelled:" + String(def_ability), 0)

	# 3. Перелив, затем Водоворот
	var orig: Array[int] = [adef.attribute, ddef.attribute]
	var attr: Array[int] = [orig[0], orig[1]]
	for i in range(2):
		if CardEffects.is_overflow(eff[i]):
			attr[i] = CardEffects.overflow_attr(orig[1 - i])
			r.add(i, "ability:" + String(eff[i].id), 0)
	if CardEffects.is_effect(eff[0], &"swap_attr") != CardEffects.is_effect(eff[1], &"swap_attr"):
		var a0: int = attr[0]
		attr = [attr[1], a0]
	r.attr_atk = attr[0]
	r.attr_def = attr[1]

	# 4. Карта арены
	var arena_id: StringName = &""
	if slot >= 0 and slot < state.slots.size():
		arena_id = state.slots[slot].card_id
	r.arena_card_id = arena_id
	var arena: CardDef = CardDB.card(arena_id)
	if arena != null and (CardEffects.is_nullify_arena(eff[0]) or CardEffects.is_nullify_arena(eff[1])):
		r.arena_cancelled = true
		arena = null
	if arena != null:
		var ad: Array[int] = [0, 0]
		for i in range(2):
			ad[i] = CardEffects.arena_delta(arena, i == 0, attr[i], base[i], base[1 - i])
			if ad[i] != 0:
				p[i] += ad[i]
				r.add(i, "arena:" + String(arena.id), ad[i])
		for i in range(2):
			if CardEffects.is_effect(eff[i], &"steal_arena") and ad[1 - i] > 0:
				var take: int = ad[1 - i]
				p[1 - i] -= take
				p[i] += take * mult[i]
				r.add(1 - i, "ability:" + String(eff[i].id), -take)
				r.add(i, "ability:" + String(eff[i].id), take * mult[i])

	# 5. Преимущество атрибута
	var is_void: bool = CardEffects.arena_is_void(arena)
	var is_overweight: bool = CardEffects.arena_is_overweight(arena) and not is_void
	if not is_void:
		var bonus: int = ADVANTAGE_BONUS
		if is_overweight:
			bonus = ADVANTAGE_BONUS * 2
		var adv: Array[int] = [0, 0]
		for i in range(2):
			if Attr.beats(attr[i], attr[1 - i]):
				adv[i] = bonus
		for i in range(2):
			if CardEffects.is_effect(eff[i], &"steal_advantage") and adv[1 - i] > 0:
				adv[i] += adv[1 - i] * mult[i]
				adv[1 - i] = 0
				r.add(i, "ability:" + String(eff[i].id), 0)
		for i in range(2):
			if adv[i] > 0:
				p[i] += adv[i]
				r.add(i, "advantage", adv[i])

	# 6. Плоские модификаторы способностей и слияний
	var field_attribute: int = CardEffects.field_attr(arena)
	var dead: Array[int] = [state.dead_count(owners[0]), state.dead_count(owners[1])]
	for i in range(2):
		if eff[i] == null:
			continue
		var v: Vector2i = CardEffects.ability_delta(eff[i], attr[i], field_attribute, dead[i], i == 1) * mult[i]
		if v.x != 0:
			p[i] += v.x
			r.add(i, "ability:" + String(eff[i].id), v.x)
		if v.y != 0:
			p[1 - i] += v.y
			r.add(1 - i, "ability:" + String(eff[i].id), v.y)
		var f: CardDef = feff[i]
		if f == null:
			continue
		var fx: int = 0
		match String(f.effect_id):
			"fusion_chain":
				fx = int(f.params.get("amount", 0))
			"fusion_echo":
				fx = int(f.params.get("amount", 0)) * _played_count(state.players[owners[i]], eff[i].id, f.id)
		if fx != 0:
			p[i] += fx
			r.add(i, "ability:" + String(f.id), fx)
		elif f.effect_id == &"fusion_double":
			r.add(i, "ability:" + String(f.id), 0)

	# 6б. Поглощение: половина бонусов соперника сверх его БС (с Резонансом — все)
	for i in range(2):
		if CardEffects.is_effect(eff[i], &"absorb"):
			var extra: int = maxi(0, p[1 - i] - base[1 - i])
			var take: int = extra * mult[i] / 2
			if take > 0:
				p[1 - i] -= take
				p[i] += take
				r.add(1 - i, "ability:" + String(eff[i].id), -take)
				r.add(i, "ability:" + String(eff[i].id), take)

	# 6в. Ослепление: сила соперника не выше его базовой
	for i in range(2):
		if CardEffects.is_effect(eff[i], &"strip") and p[1 - i] > base[1 - i]:
			var cut: int = p[1 - i] - base[1 - i]
			p[1 - i] = base[1 - i]
			r.add(1 - i, "ability:" + String(eff[i].id), -cut)

	# 7. Нижняя граница
	for i in range(2):
		if p[i] < 0:
			r.add(i, "floor", -p[i])
			p[i] = 0

	r.atk_rescue = CardEffects.is_effect(eff[0], &"rescue")
	r.def_rescue = CardEffects.is_effect(eff[1], &"rescue")
	r.powers[0] = p[0]
	r.powers[1] = p[1]
	if p[0] > p[1]:
		r.winner_uid = atk_uid
		r.loser_uid = def_uid
	else:
		r.winner_uid = def_uid
		r.loser_uid = atk_uid
	return r


## Число способностей, сыгранных игроком за матч, включая основную карту этого боя (для «Отголоска»).
static func _played_count(ps: PlayerState, main_id: StringName, echo_id: StringName) -> int:
	var n: int = 0
	var has_main: bool = false
	for id in ps.abilities_used:
		if id == echo_id:
			continue
		n += 1
		if id == main_id:
			has_main = true
	if not has_main:
		n += 1  # предпросмотр ИИ: основная карта ещё в руке
	return n
