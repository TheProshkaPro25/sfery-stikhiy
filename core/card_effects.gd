class_name CardEffects
extends RefCounted
## Чистые функции по effect_id и params карты (см. PowerCalc). Без состояния и без побочных эффектов.
## Набор карт — DESIGN.md «Карты по мотивам аниме (2026-10-28)».

## Эффекты, которые «Отпечаток в камне» не повторяет (отмена, тишина, сама копия, перемещения).
const NO_COPY_EFFECTS: Array[String] = ["negate", "silence", "copy", "ebb", "swap_fighter", "shift_gate"]


static func is_effect(card: CardDef, effect: StringName) -> bool:
	return card != null and card.effect_id == effect


## Отмена способности соперника («Волчья хватка»).
static func is_negate(card: CardDef) -> bool:
	return card != null and card.effect_id == &"negate"


## Слияние: играется только поверх своей способности в том же бою.
static func is_fusion(card: CardDef) -> bool:
	return card != null and bool(card.params.get("fusion", false))


## Карту нельзя отменить (ни отменой, ни тишиной соперника).
static func is_sure(card: CardDef) -> bool:
	return card != null and bool(card.params.get("sure", false))


## Действует сразу при розыгрыше в бою («Вихревая подмена», «Сдвиг плит»): не прикрепляется и не отменяется.
static func is_instant(card: CardDef) -> bool:
	return card != null and bool(card.params.get("instant", false))


## Момент розыгрыша: &"landing" — только после приземления, &"battle" — только в бою, &"" — в любой.
static func moment(card: CardDef) -> StringName:
	if card == null:
		return &""
	return StringName(card.params.get("moment", ""))


## После этой карты своя сторона больше не играет способности в бою.
static func is_lockout(card: CardDef) -> bool:
	return card != null and bool(card.params.get("lockout", false))


## Карта возвращается в руку после боя, в котором её сыграли (params.returns).
static func returns_to_hand(card: CardDef) -> bool:
	return card != null and bool(card.params.get("returns", false))


## Стихийная или стихийное усиление: атрибут существа, которое может сыграть карту (-1 — без ограничения).
static func lock_attr(card: CardDef) -> int:
	if card == null:
		return -1
	return int(card.params.get("lock", -1))


## Видовая способность / ворота вида: id вида (&"" — без привязки).
static func species_lock(card: CardDef) -> StringName:
	if card == null:
		return &""
	return StringName(card.params.get("species", ""))


## Поле, дающее бонус атрибуту: возвращает его атрибут, иначе -1.
static func field_attr(card: CardDef) -> int:
	if card == null or card.effect_id != &"attr_bonus":
		return -1
	return int(card.params.get("attr", -1))


## Ворота-ловушка (params.hidden_trap): срабатывают при открытии, ИИ учитывает риск.
static func is_gate_trap(card: CardDef) -> bool:
	return card != null and card.kind == CardDef.Kind.ARENA and bool(card.params.get("hidden_trap", false))


## Карта, которая гасит чужие карты (для ИИ: опасный ответ соперника).
static func is_counter_card(card: CardDef) -> bool:
	return card != null and card.kind == CardDef.Kind.ABILITY and (card.effect_id == &"negate" or card.effect_id == &"silence")


## Можно ли повторить карту «Отпечатком в камне».
static func copyable(card: CardDef) -> bool:
	return card != null and not is_fusion(card) and not NO_COPY_EFFECTS.has(String(card.effect_id))


## Условие усиления boost (params.cond): ctx — {attack:bool, own_gate:bool, my_base, foe_base, dead_own, alive_own, alive_foe}.
static func boost_cond_ok(card: CardDef, ctx: Dictionary) -> bool:
	match String(card.params.get("cond", "")):
		"":
			return true
		"attack":
			return bool(ctx.get("attack", false))
		"defense":
			return not bool(ctx.get("attack", false))
		"own_gate":
			return bool(ctx.get("own_gate", false))
		"weaker":
			return int(ctx.get("foe_base", 0)) > int(ctx.get("my_base", 0))
		"fallen":
			return int(ctx.get("dead_own", 0)) > 0
		"last":
			return int(ctx.get("alive_own", 0)) <= 1
		"behind":
			return int(ctx.get("alive_own", 0)) < int(ctx.get("alive_foe", 0))
	return false


## Плоские модификаторы способности на шаге 6: Vector2i(x = себе, y = сопернику).
static func ability_delta(card: CardDef, ctx: Dictionary) -> Vector2i:
	if card == null:
		return Vector2i.ZERO
	var amount: int = int(card.params.get("amount", 0))
	match String(card.effect_id):
		"boost":
			return Vector2i(amount, 0) if boost_cond_ok(card, ctx) else Vector2i.ZERO
		"boost_fix", "revive", "purge_gate", "silence", "aloft", "recall", "nullify_gate", "copy", "gust", "swap_fighter", "shift_gate":
			return Vector2i(amount, 0)
		"drain", "radiance", "pact":
			return Vector2i(amount, -amount)
		"scorch", "eclipse", "negate", "weaken_mark", "weaken":
			return Vector2i(0, -amount)
	return Vector2i.ZERO
