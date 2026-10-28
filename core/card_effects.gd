class_name CardEffects
extends RefCounted
## Чистые функции по effect_id. Каждая отвечает за один шаг расчёта силы (см. PowerCalc).
## Без состояния и без побочных эффектов.


# --- Шаг 2/3/4: управляющие способности ---

static func is_shield(card: CardDef) -> bool:
	return card != null and card.effect_id == &"shield"


static func is_overflow(card: CardDef) -> bool:
	return card != null and card.effect_id == &"overflow"


static func is_nullify_arena(card: CardDef) -> bool:
	return card != null and card.effect_id == &"nullify_arena"


static func is_all_in(card: CardDef) -> bool:
	return card != null and card.effect_id == &"all_in"


static func is_effect(card: CardDef, effect: StringName) -> bool:
	return card != null and card.effect_id == effect


## Слияние: играется только поверх своей способности в том же бою.
static func is_fusion(card: CardDef) -> bool:
	return card != null and bool(card.params.get("fusion", false))


## Стихийная способность: атрибут, которым должно обладать существо (-1 — без ограничения).
static func lock_attr(card: CardDef) -> int:
	if card == null:
		return -1
	return int(card.params.get("lock", -1))


# --- Шаг 3: «Перелив» ---

## Новый атрибут владельца «Перелива»: тот, который бьёт атрибут соперника.
static func overflow_attr(foe_attr: int) -> int:
	return Attr.beaten_by(foe_attr)


# --- Шаг 4: карта арены ---

## Поле, дающее бонус атрибуту: возвращает его атрибут, иначе -1.
static func field_attr(card: CardDef) -> int:
	if card == null:
		return -1
	if card.effect_id == &"attr_bonus":
		return int(card.params.get("attr", -1))
	return -1


## Плоский бонус/штраф карты ворот для одной стороны. owner_attr — стихия владельца ворот (для «Престола»).
static func arena_delta(card: CardDef, is_attacker: bool, attr: int, my_base: int, foe_base: int, owner_attr: int = -1) -> int:
	if card == null:
		return 0
	var amount: int = int(card.params.get("amount", 0))
	# G ворот по стихии бойца (бонус только своей стихии)
	var g: Array = card.params.get("g", [])
	var gv: int = int(g[attr]) if attr >= 0 and attr < g.size() else 0
	return gv + _arena_effect(card, is_attacker, attr, my_base, foe_base, amount, owner_attr)


static func _arena_effect(card: CardDef, is_attacker: bool, attr: int, my_base: int, foe_base: int, amount: int, owner_attr: int = -1) -> int:
	match String(card.effect_id):
		"throne":
			if not is_attacker and attr >= 0 and attr == owner_attr:
				return amount
			return 0
		"underdog":
			if my_base < foe_base:
				return amount
			return 0
		"trap":
			if is_attacker:
				return amount  # в params уже отрицательное значение
			return 0
		"bastion":
			if not is_attacker:
				return amount
			return 0
		"twilight":
			if attr == Attr.A.LIGHT or attr == Attr.A.SHADOW:
				return amount
			return 0
	return 0


# --- Шаг 5: флаги преимущества атрибутов ---

static func arena_is_void(card: CardDef) -> bool:
	return card != null and card.effect_id == &"void"


static func arena_is_overweight(card: CardDef) -> bool:
	return card != null and card.effect_id == &"overweight"


# --- Шаг 6: плоские модификаторы способностей ---

## Vector2i(x = себе, y = сопернику).
static func ability_delta(card: CardDef, my_attr: int, field_attribute: int, dead_own: int, is_defender: bool = false) -> Vector2i:
	if card == null:
		return Vector2i.ZERO
	var amount: int = int(card.params.get("amount", 0))
	match String(card.effect_id):
		"boost_self":
			return Vector2i(amount, 0)
		"weaken_foe":
			return Vector2i(0, -amount)
		"legacy":
			return Vector2i(amount * dead_own, 0)
		"home_element":
			if field_attribute >= 0 and my_attr == field_attribute:
				return Vector2i(amount, 0)
			return Vector2i.ZERO
		"all_in", "steal_advantage", "swap_attr", "rescue":
			return Vector2i(amount, 0)
		"drain":
			return Vector2i(amount, -amount)
		"stone_wall":
			if is_defender:
				return Vector2i(int(card.params.get("amount_def", amount)), 0)
			return Vector2i(amount, 0)
	return Vector2i.ZERO


# --- Ловушки ворот (срабатывают при открытии в бою) ---

## Ловушка ворот: «Печать тишины», «Зеркало», «Обратный ток» (params.hidden_trap).
static func is_gate_trap(card: CardDef) -> bool:
	return card != null and card.kind == CardDef.Kind.ARENA and bool(card.params.get("hidden_trap", false))


# --- Отмена ---

## Карта, которая отменяет другие (для ИИ: опасный ответ соперника).
static func is_counter_card(card: CardDef) -> bool:
	return card != null and card.kind == CardDef.Kind.ABILITY and card.effect_id == &"shield"
