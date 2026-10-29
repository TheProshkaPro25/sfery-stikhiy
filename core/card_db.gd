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
const RARE_SHADOW_ID: StringName = &"creature_likorez_shadow"
const RARE_ENCOUNTER_CHANCE: float = 0.10


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
	# Особая встреча: не входит в обычный пул и меню выбора игрока.
	var rare := CreatureDef.make(RARE_SHADOW_ID, "Ликорез Тени", Attr.A.SHADOW, 370, Color("674085"))
	rare.species = &"likorez"
	rare.archetype = "sixarm"
	_creatures[String(rare.id)] = rare
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
## «Поле X» даёт amount только стихии X (как в первом сезоне: бонус ворот получает лишь совпадающая стихия);
## особые карты работают эффектом, их G = 0.
static func _gate_table(c: CardDef) -> Array:
	var g: Array = [0, 0, 0, 0, 0, 0]
	if c.effect_id == &"attr_bonus":
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


# ---------------------------------------------------------------- колода
## Ворота: gold — ворота стихии (Поле X, Алтарь силы), silver — ворота вида (×2 БС виду), bronze — командные.
## Способности: red — стихийные, blue — усиления своей стихии (лесенка +30…+200), green — видовые.
const GATE_CLASSES: Array[StringName] = [&"gold", &"silver", &"bronze"]
const ABILITY_CLASSES: Array[StringName] = [&"red", &"blue", &"green"]


## Класс карты: gold/silver/bronze для ворот, red/blue/green для способностей.
static func card_class(c: CardDef) -> StringName:
	if c == null:
		return &""
	if c.kind == CardDef.Kind.ARENA:
		match String(c.effect_id):
			"attr_bonus", "owner_power":
				return &"gold"
			"species_double":
				return &"silver"
		return &"bronze"
	if CardEffects.species_lock(c) != &"":
		return &"green"
	if c.effect_id == &"boost":
		return &"blue"
	return &"red"


## Подходит ли карта команде: стихийный замок — стихии element, видовой — одному из видов species (пусто — любой).
static func card_fits(c: CardDef, element: int, species: Array = []) -> bool:
	var lock: int = CardEffects.lock_attr(c)
	if lock < 0:
		lock = CardEffects.field_attr(c)  # «Поле X» в колоду берётся только своей стихии
	if element >= 0 and lock >= 0 and lock != element:
		return false
	var sp: StringName = CardEffects.species_lock(c)
	if sp != &"" and not species.is_empty() and not species.has(sp):
		return false
	return true


## Карты пула данного вида и класса, подходящие стихии element и видам species (пусто — без фильтра по виду).
static func cards_of(kind: int, cls: StringName, element: int = -1, species: Array = []) -> Array[StringName]:
	load_all()
	var out: Array[StringName] = []
	for id in (_arena_order if kind == CardDef.Kind.ARENA else _ability_order):
		var c: CardDef = card(id)
		if card_class(c) == cls and card_fits(c, element, species):
			out.append(id)
	return out


## Виды существ команды (StringName), в порядке списка.
static func team_species(creature_list: Array) -> Array:
	var out: Array = []
	for id in creature_list:
		var d: CreatureDef = creature(StringName(id))
		if d != null and d.species != &"" and not out.has(d.species):
			out.append(d.species)
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
## способности по одной красной/синей/зелёной; стихийные карты и «Поле» — своей стихии, видовые — вида из команды.
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
	var species: Array = team_species(creatures)
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
			if lock < 0:
				lock = CardEffects.field_attr(c)
			if lock >= 0 and lock != el:
				return "«%s» — карта стихии %s, а команда — %s" % [c.display_name, Attr.display_name(lock), Attr.display_name(el)]
			var sp: StringName = CardEffects.species_lock(c)
			if sp != &"" and not species.has(sp):
				return "«%s»: в команде нет вида %s" % [c.display_name, species_name(sp)]
		for cls in pair[1]:
			if not classes.has(cls):
				return "Нужно по одной карте %s каждого класса" % pair[2]
	return ""


## Имя вида по id («Драгнар»).
static func species_name(sp: StringName) -> String:
	if sp == &"likorez":
		return "Ликорез"
	for row in GameData.SPECIES:
		if StringName(row["id"]) == sp:
			return String(row["name"])
	return String(sp)


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
	var species: Array = team_species(team)
	var arena: Array[StringName] = []
	for cls in GATE_CLASSES:
		arena.append_array(_pick(cards_of(CardDef.Kind.ARENA, cls, el, species), 1, rng))
	var abil: Array[StringName] = []
	for cls in ABILITY_CLASSES:
		abil.append_array(_pick(cards_of(CardDef.Kind.ABILITY, cls, el, species), 1, rng))
	return build_deck(team, arena, abil)


## Один независимый бросок на матч: 10% команд соперника содержат Ликореза.
## Вся команда Тени, ровно три разных существа и обычный лимит силы/карт.
static func opponent_deck(rng: RandomNumberGenerator) -> DeckDef:
	load_all()
	if rng.randf() >= RARE_ENCOUNTER_CHANCE:
		return random_deck(rng)
	var pool := creatures_of(Attr.A.SHADOW)
	var pairs: Array = []
	for i in range(pool.size()):
		for j in range(i + 1, pool.size()):
			var ids: Array[StringName] = [RARE_SHADOW_ID, pool[i], pool[j]]
			if team_power(ids) <= GameData.TEAM_POWER_LIMIT:
				pairs.append(ids)
	var team: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
	return deck_from_creatures(team, rng)


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


## Колода из выбранных игроком 3 существ; ворота и способности — случайные по правилам колоды.
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
	var el: int = creature(StringName(ids[0])).attribute
	var species: Array = team_species(ids)
	var arena: Array[StringName] = []
	for cls in GATE_CLASSES:
		arena.append_array(_pick(cards_of(CardDef.Kind.ARENA, cls, el, species), 1, rng))
	var abil: Array[StringName] = []
	for cls in ABILITY_CLASSES:
		abil.append_array(_pick(cards_of(CardDef.Kind.ABILITY, cls, el, species), 1, rng))
	return build_deck(ids, arena, abil)


static func _pick(ids: Array[StringName], n: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = ids.duplicate()
	var out: Array[StringName] = []
	var count: int = mini(n, pool.size())
	for i in range(count):
		var k: int = rng.randi_range(0, pool.size() - 1)
		out.append(pool[k])
		pool.remove_at(k)
	return out
