class_name GameData
extends RefCounted
## Исходные таблицы данных (виды существ, карты, пресет-колоды).
##
## РЕШЕНИЕ: вместо .tres-файлов определения строятся кодом в CardDB.load_all() из этих констант.
## Причина: .tres написаны вручную без запуска Godot хрупки (uid, формат Dictionary/Color/typed arrays),
## а ошибка парсинга ресурса молча ломает весь матч. Таблицы-константы проверяются парсером GDScript.
## Атрибуты записаны числами = Attr.A (0 FIRE, 1 GALE, 2 LIGHT, 3 STONE, 4 SHADOW, 5 TIDE).
## kind: 0 = CardDef.Kind.ARENA, 1 = CardDef.Kind.ABILITY.

## Лимит суммы БС команды из 3 существ (выбор в меню и случайные колоды ИИ).
const TEAM_POWER_LIMIT: int = 1100

## Виды существ (как в Бакугане: каждый вид есть во всех 6 стихиях, отличаются цвет и детали).
## Существо = вид × стихия: id "creature_<вид>_<стихия>", имя "<вид> <стихия в род. падеже>",
## БС = power вида + ATTR_POWER_SHIFT[(стихия + номер вида) % 6] — у каждой стихии свой разброс, ни одна не сильнее в целом.
## archetype — запасная low-poly модель (assets/creatures/), если нет HD-модели assets/creatures_hd/<вид>_<стихия>.glb.
const SPECIES: Array = [
	{"id": "dragnar", "name": "Драгнар", "power": 360, "archetype": "dragon"},
	{"id": "klykar", "name": "Клыкарь", "power": 330, "archetype": "wolf"},
	{"id": "grifalon", "name": "Грифалон", "power": 320, "archetype": "bird"},
	{"id": "kolossar", "name": "Колоссар", "power": 380, "archetype": "cyclops"},
	{"id": "rogozhuk", "name": "Рогожук", "power": 340, "archetype": "beetle"},
	{"id": "levian", "name": "Левиан", "power": 350, "archetype": "serpent"},
	{"id": "ratnik", "name": "Ратник", "power": 350, "archetype": "knight"},
	{"id": "gorgul", "name": "Горгул", "power": 300, "archetype": "flying_eye"},
]
const ATTR_POWER_SHIFT: Array = [30, -10, 10, -30, 20, -20]
## По Attr.A: суффикс id, стихия в родительном падеже (для имени), цвет существа.
const ATTR_KEYS: Array = ["fire", "gale", "light", "stone", "shadow", "tide"]
const ATTR_GENITIVE: Array = ["Пламени", "Бури", "Света", "Камня", "Тени", "Прилива"]
const ATTR_COLORS: Array = ["#e8551f", "#4fb89a", "#f5d76e", "#8a7f72", "#6a48a8", "#2f7fd1"]

const CARDS: Array = [
	# --- Карты арены (12) ---
	{"id": &"arena_field_fire", "name": "Поле Пламени", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 0, "amount": 100}, "text": "+100 существу атрибута Пламя."},
	{"id": &"arena_field_gale", "name": "Поле Бури", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 1, "amount": 100}, "text": "+100 существу атрибута Буря."},
	{"id": &"arena_field_light", "name": "Поле Света", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 2, "amount": 100}, "text": "+100 существу атрибута Свет."},
	{"id": &"arena_field_stone", "name": "Поле Камня", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 3, "amount": 100}, "text": "+100 существу атрибута Камень."},
	{"id": &"arena_field_shadow", "name": "Поле Тени", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 4, "amount": 100}, "text": "+100 существу атрибута Тень."},
	{"id": &"arena_field_tide", "name": "Поле Прилива", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 5, "amount": 100}, "text": "+100 существу атрибута Прилив."},
	{"id": &"arena_lowland", "name": "Низина", "kind": 0, "effect": &"underdog", "params": {"amount": 120}, "text": "Существо с меньшей базовой силой получает +120."},
	{"id": &"arena_void", "name": "Пустота", "kind": 0, "effect": &"void", "params": {}, "text": "Преимущество атрибутов не учитывается."},
	{"id": &"arena_overweight", "name": "Перевес", "kind": 0, "effect": &"overweight", "params": {}, "text": "Преимущество атрибута удваивается (+120)."},
	{"id": &"arena_trap", "name": "Ловушка", "kind": 0, "effect": &"trap", "params": {"amount": -80}, "text": "Атакующий получает -80."},
	{"id": &"arena_bastion", "name": "Бастион", "kind": 0, "effect": &"bastion", "params": {"amount": 80}, "text": "Защитник получает +80."},
	{"id": &"arena_twilight", "name": "Сумерки", "kind": 0, "effect": &"twilight", "params": {"amount": 70}, "text": "Свет и Тень получают +70."},
	# --- Карты способностей: базовые (8) ---
	{"id": &"ability_surge", "name": "Рывок", "kind": 1, "effect": &"boost_self", "params": {"amount": 80}, "text": "+80 себе."},
	{"id": &"ability_hamstring", "name": "Подсечка", "kind": 1, "effect": &"weaken_foe", "params": {"amount": 80}, "text": "-80 сопернику."},
	{"id": &"ability_overflow", "name": "Перелив", "kind": 1, "effect": &"overflow", "params": {}, "text": "На этот бой твой атрибут становится тем, который бьёт атрибут соперника."},
	{"id": &"ability_silencer", "name": "Глушитель", "kind": 1, "effect": &"nullify_arena", "params": {}, "text": "Отменяет карту арены."},
	{"id": &"ability_shield", "name": "Щит", "kind": 1, "effect": &"shield", "params": {}, "text": "Отменяет способность соперника."},
	{"id": &"ability_legacy", "name": "Наследие", "kind": 1, "effect": &"legacy", "params": {"amount": 40}, "text": "+40 за каждое своё выбывшее существо."},
	{"id": &"ability_homeland", "name": "Родная стихия", "kind": 1, "effect": &"home_element", "params": {"amount": 100}, "text": "+100, если твой атрибут совпадает с атрибутом «Поля»."},
	{"id": &"ability_allin", "name": "Ва-банк", "kind": 1, "effect": &"all_in", "params": {"amount": 130}, "text": "+130; при поражении теряешь случайную способность из руки."},
	# --- Стихийные способности (6): играет только существо своей стихии (params.lock = атрибут) ---
	{"id": &"ability_firestorm", "name": "Огненный смерч", "kind": 1, "effect": &"drain", "params": {"lock": 0, "amount": 70}, "text": "Перекачка силы: +70 себе и −70 сопернику."},
	{"id": &"ability_headwind", "name": "Встречный ветер", "kind": 1, "effect": &"steal_advantage", "params": {"lock": 1, "amount": 40}, "text": "+40. Если у соперника преимущество стихии, оно достаётся тебе."},
	{"id": &"ability_blind", "name": "Ослепление", "kind": 1, "effect": &"strip", "params": {"lock": 2}, "text": "Сила соперника не может быть выше его базовой: все его бонусы сгорают."},
	{"id": &"ability_granite", "name": "Гранитная стена", "kind": 1, "effect": &"stone_wall", "params": {"lock": 3, "amount": 90, "amount_def": 160}, "text": "+90, а в защите +160."},
	{"id": &"ability_absorb", "name": "Поглощение", "kind": 1, "effect": &"absorb", "params": {"lock": 4}, "text": "Забирает себе половину всех бонусов соперника сверх его базовой силы."},
	{"id": &"ability_whirlpool", "name": "Водоворот", "kind": 1, "effect": &"swap_attr", "params": {"lock": 5, "amount": 30}, "text": "+30. Стихии бойцов меняются местами до конца боя."},
	# --- Слияние (3): играется только поверх своей способности в этом же бою ---
	{"id": &"ability_resonance", "name": "Резонанс", "kind": 1, "effect": &"fusion_double", "params": {"fusion": true}, "text": "Слияние: числовой эффект твоей способности удваивается."},
	{"id": &"ability_chain", "name": "Цепная искра", "kind": 1, "effect": &"fusion_chain", "params": {"fusion": true, "amount": 50}, "text": "Слияние: +50, и твои способности в этом бою нельзя отменить."},
	{"id": &"ability_echo", "name": "Отголосок", "kind": 1, "effect": &"fusion_echo", "params": {"fusion": true, "amount": 30}, "text": "Слияние: +30 за каждую способность, сыгранную тобой за матч."},
	# --- Особые (3) ---
	{"id": &"ability_intercept", "name": "Перехват поля", "kind": 1, "effect": &"steal_arena", "params": {}, "text": "Бонус карты арены, который получил бы соперник, достаётся тебе."},
	{"id": &"ability_essence", "name": "Обмен сутью", "kind": 1, "effect": &"swap_base", "params": {}, "text": "Базовые силы бойцов меняются местами до конца боя."},
	{"id": &"ability_rescue", "name": "Спасение", "kind": 1, "effect": &"rescue", "params": {"amount": 20}, "text": "+20. Если проиграешь, существо не выбывает, а уходит в зону использованных."},
]

const PRESET_DECKS: Array = [
	{
		"creatures": [&"creature_dragnar_fire", &"creature_ratnik_light", &"creature_rogozhuk_stone"],
		"arena": [&"arena_field_fire", &"arena_lowland", &"arena_bastion"],
		"abilities": [&"ability_surge", &"ability_shield", &"ability_homeland"],
	},
	{
		"creatures": [&"creature_grifalon_gale", &"creature_ratnik_shadow", &"creature_levian_tide"],
		"arena": [&"arena_field_tide", &"arena_void", &"arena_twilight"],
		"abilities": [&"ability_overflow", &"ability_silencer", &"ability_legacy"],
	},
]
