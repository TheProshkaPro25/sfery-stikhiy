class_name CardDB
extends RefCounted
## Реестр определений. Строится кодом из GameData (см. комментарий там), без autoload и без .tres.
## Ключи словарей — всегда String (StringName и String как ключи не смешиваем).

static var _loaded: bool = false
static var _creatures: Dictionary = {}
static var _cards: Dictionary = {}
static var _creature_order: Array[StringName] = []
static var _arena_order: Array[StringName] = []
static var _ability_order: Array[StringName] = []


static func load_all() -> void:
	if _loaded:
		return
	_creatures.clear()
	_cards.clear()
	_creature_order.clear()
	_arena_order.clear()
	_ability_order.clear()
	for d in species_creatures():
		_creatures[String(d.id)] = d
		_creature_order.append(d.id)
	for row in GameData.CARDS:
		var c: CardDef = CardDef.make(StringName(row["id"]), String(row["name"]), int(row["kind"]), StringName(row["effect"]), (row["params"] as Dictionary).duplicate(), String(row["text"]))
		if c.kind == CardDef.Kind.ARENA and not c.params.has("g"):
			c.params["g"] = _gate_table(c)
		_cards[String(c.id)] = c
		if c.kind == CardDef.Kind.ARENA:
			_arena_order.append(c.id)
		else:
			_ability_order.append(c.id)
	_loaded = true


## Все существа: каждый вид из GameData.SPECIES в каждой из 6 стихий (порядок: вид, затем стихия).
static func species_creatures() -> Array[CreatureDef]:
	var out: Array[CreatureDef] = []
	for i in GameData.SPECIES.size():
		var sp: Dictionary = GameData.SPECIES[i]
		for a in GameData.ATTR_KEYS.size():
			var id := StringName("creature_%s_%s" % [sp["id"], GameData.ATTR_KEYS[a]])
			var power: int = int(sp["power"]) + int(GameData.ATTR_POWER_SHIFT[(a + i) % GameData.ATTR_POWER_SHIFT.size()])
			var color: Color = Color.from_string(String(GameData.ATTR_COLORS[a]), Color.WHITE).lightened(0.04 * (i % 4))
			var d := CreatureDef.make(id, "%s %s" % [sp["name"], GameData.ATTR_GENITIVE[a]], a, power, color)
			d.species = StringName(sp["id"])
			d.archetype = String(sp["archetype"])
			out.append(d)
	return out


## Сила G карты ворот для каждой из 6 стихий (как столбец значений на картах ворот):
## «Поле X» даёт amount стихии X и 30 остальным; особые карты работают эффектом, их G = 0.
static func _gate_table(c: CardDef) -> Array:
	var g: Array = [0, 0, 0, 0, 0, 0]
	if c.effect_id == &"attr_bonus":
		g = [30, 30, 30, 30, 30, 30]
		g[int(c.params.get("attr", 0))] = int(c.params.get("amount", 100))
	return g


## null, если id пуст или неизвестен.
static func creature(id: StringName) -> CreatureDef:
	load_all()
	if id == &"":
		return null
	return _creatures.get(String(id)) as CreatureDef


## null, если id пуст или неизвестен.
static func card(id: StringName) -> CardDef:
	load_all()
	if id == &"":
		return null
	return _cards.get(String(id)) as CardDef


static func creature_ids() -> Array[StringName]:
	load_all()
	return _creature_order.duplicate()


static func arena_ids() -> Array[StringName]:
	load_all()
	return _arena_order.duplicate()


static func ability_ids() -> Array[StringName]:
	load_all()
	return _ability_order.duplicate()


static func build_deck(creature_list: Array, arena_list: Array, ability_list: Array) -> DeckDef:
	var deck: DeckDef = DeckDef.new()
	for id in creature_list:
		deck.creatures.append(creature(StringName(id)))
	for id in arena_list:
		deck.arena.append(card(StringName(id)))
	for id in ability_list:
		deck.abilities.append(card(StringName(id)))
	return deck


## index 0 — пресет игрока, 1 — запасной пресет.
static func preset_deck(index: int) -> DeckDef:
	load_all()
	var row: Dictionary = GameData.PRESET_DECKS[index % GameData.PRESET_DECKS.size()]
	return build_deck(row["creatures"], row["arena"], row["abilities"])


# ---------------------------------------------------------------- колода по правилам Бакугана
## Ворота: золотые (поля стихий), серебряные (сила G по ситуации), бронзовые (меняют правила боя).
## Способности: красные (зависят от стихии), синие (бонус G), зелёные (зависят от ситуации боя).
const GATE_CLASS := {
	"attr_bonus": &"gold",
	"underdog": &"silver", "trap": &"silver", "bastion": &"silver", "twilight": &"silver",
	"void": &"bronze", "overweight": &"bronze",
}
const ABILITY_CLASS := {
	"drain": &"red", "steal_advantage": &"red", "strip": &"red", "stone_wall": &"red", "absorb": &"red",
	"swap_attr": &"red", "home_element": &"red", "overflow": &"red",
	"boost_self": &"blue", "weaken_foe": &"blue", "legacy": &"blue", "all_in": &"blue", "fusion_echo": &"blue",
	"shield": &"green", "nullify_arena": &"green", "steal_arena": &"green", "swap_base": &"green",
	"rescue": &"green", "fusion_double": &"green", "fusion_chain": &"green",
}
const GATE_CLASSES: Array[StringName] = [&"gold", &"silver", &"bronze"]
const ABILITY_CLASSES: Array[StringName] = [&"red", &"blue", &"green"]


## Класс карты: gold/silver/bronze для ворот, red/blue/green для способностей.
static func card_class(c: CardDef) -> StringName:
	if c == null:
		return &""
	if c.kind == CardDef.Kind.ARENA:
		return GATE_CLASS.get(String(c.effect_id), &"silver")
	return ABILITY_CLASS.get(String(c.effect_id), &"green")


## Карты пула данного вида и класса (для стихии element: красные — только своей стихии или без привязки).
static func cards_of(kind: int, cls: StringName, element: int = -1) -> Array[StringName]:
	load_all()
	var out: Array[StringName] = []
	for id in (_arena_order if kind == CardDef.Kind.ARENA else _ability_order):
		var c: CardDef = card(id)
		if card_class(c) != cls:
			continue
		var lock: int = CardEffects.lock_attr(c)
		if element >= 0 and lock >= 0 and lock != element:
			continue
		out.append(id)
	return out


## Существа одной стихии.
static func creatures_of(element: int) -> Array[StringName]:
	load_all()
	var out: Array[StringName] = []
	for id in _creature_order:
		if creature(id).attribute == element:
			out.append(id)
	return out


## Проверка колоды игрока. "" — колода годится, иначе текст ошибки.
## 3 разных существа одной стихии в лимите силы; ворота по одной золотой/серебряной/бронзовой;
## способности по одной красной/синей/зелёной; красная — своей стихии.
static func deck_error(creatures: Array, arena: Array, abilities: Array) -> String:
	load_all()
	if creatures.size() != 3:
		return "Нужно 3 существа"
	var el: int = -1
	var seen: Dictionary = {}
	for id in creatures:
		var d: CreatureDef = creature(StringName(id))
		if d == null:
			return "Неизвестное существо"
		if seen.has(String(id)):
			return "Существа не должны повторяться"
		seen[String(id)] = true
		if el >= 0 and d.attribute != el:
			return "Все существа должны быть одной стихии"
		el = d.attribute
	if team_power(creatures) > GameData.TEAM_POWER_LIMIT:
		return "Сила команды больше %d" % GameData.TEAM_POWER_LIMIT
	for pair in [[arena, GATE_CLASSES, "ворот"], [abilities, ABILITY_CLASSES, "способностей"]]:
		var list: Array = pair[0]
		if list.size() != 3:
			return "Нужно 3 карты %s" % pair[2]
		var classes: Array = []
		for id in list:
			var c: CardDef = card(StringName(id))
			if c == null:
				return "Неизвестная карта"
			classes.append(card_class(c))
			var lock: int = CardEffects.lock_attr(c)
			if lock >= 0 and lock != el:
				return "Стихийная способность «%s» не подходит к стихии команды" % c.display_name
		for cls in pair[1]:
			if not classes.has(cls):
				return "Нужно по одной карте %s каждого класса" % pair[2]
	return ""


## Случайная колода по тем же правилам; детерминирована по состоянию rng.
static func random_deck(rng: RandomNumberGenerator) -> DeckDef:
	load_all()
	var team: Array[StringName] = []
	var el: int = 0
	for _i in range(50):
		el = rng.randi_range(0, 5)
		team = _pick(creatures_of(el), 3, rng)
		if team_power(team) <= GameData.TEAM_POWER_LIMIT:
			break
	var arena: Array[StringName] = []
	for cls in GATE_CLASSES:
		arena.append_array(_pick(cards_of(CardDef.Kind.ARENA, cls, el), 1, rng))
	var abil: Array[StringName] = []
	for cls in ABILITY_CLASSES:
		abil.append_array(_pick(cards_of(CardDef.Kind.ABILITY, cls, el), 1, rng))
	return build_deck(team, arena, abil)


## Все существа в стабильном порядке (для меню выбора).
static func all_creatures() -> Array[CreatureDef]:
	load_all()
	var out: Array[CreatureDef] = []
	for id in _creature_order:
		out.append(_creatures[String(id)])
	return out


static func team_power_limit() -> int:
	return GameData.TEAM_POWER_LIMIT


static func team_power(ids: Array) -> int:
	var sum: int = 0
	for id in ids:
		var d: CreatureDef = creature(StringName(id))
		if d != null:
			sum += d.base_power
	return sum


## Колода из выбранных игроком 3 существ; карты арены и способностей — случайные из пула.
## null, если выбор некорректен (не 3 разных известных существа или превышен лимит БС).
static func deck_from_creatures(ids: Array, rng: RandomNumberGenerator) -> DeckDef:
	load_all()
	var seen: Dictionary = {}
	for id in ids:
		if creature(StringName(id)) == null:
			return null
		seen[String(id)] = true
	if ids.size() != 3 or seen.size() != 3 or team_power(ids) > GameData.TEAM_POWER_LIMIT:
		return null
	return build_deck(ids, _pick(_arena_order, 3, rng), _pick_abilities(ids, rng))


## 3 способности: стихийные только под атрибуты команды, не больше одного «Слияния».
static func _pick_abilities(team: Array, rng: RandomNumberGenerator) -> Array[StringName]:
	var attrs: Array[int] = []
	for id in team:
		attrs.append(creature(StringName(id)).attribute)
	var pool: Array[StringName] = []
	for id in _ability_order:
		var lock: int = CardEffects.lock_attr(card(id))
		if lock < 0 or attrs.has(lock):
			pool.append(id)
	var out: Array[StringName] = []
	var fusions: int = 0
	while out.size() < 3 and not pool.is_empty():
		var k: int = rng.randi_range(0, pool.size() - 1)
		var id: StringName = pool[k]
		pool.remove_at(k)
		if CardEffects.is_fusion(card(id)):
			if fusions >= 1:
				continue
			fusions += 1
		out.append(id)
	return out


static func _pick(ids: Array[StringName], n: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = ids.duplicate()
	var out: Array[StringName] = []
	var count: int = mini(n, pool.size())
	for i in range(count):
		var k: int = rng.randi_range(0, pool.size() - 1)
		out.append(pool[k])
		pool.remove_at(k)
	return out
