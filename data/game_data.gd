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

## Набор карт «Ворота и способности 2.0» (2026-10-28, DESIGN.md «Карты по мотивам аниме»).
## Ворота: gold — стихийные (Поле X, Алтарь силы), silver — видовые (×2 базовой силы виду), bronze — командные.
## Способности: red — стихийные (params.lock), blue — усиления-лесенка своей стихии (boost, params.lock),
## green — видовые (params.species: играет только существо этого вида любой стихии).
## Прочие params: sure — карту нельзя отменить; moment — "landing" (только после приземления) / "battle" (только в бою);
## instant — действует сразу при розыгрыше (не прикрепляется); lockout — после неё своя сторона больше не играет;
## fusion — слияние поверх своей способности; hidden_trap — ворота-ловушка (срабатывают при открытии).
const CARDS: Array = [
	# --- Ворота стихии (gold): бонус только своей стихии, у каждой стихии своё число ---
	{"id": &"arena_field_fire", "name": "Поле Пламени", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 0, "amount": 120}, "text": "+120 существу Пламени."},
	{"id": &"arena_field_gale", "name": "Поле Бури", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 1, "amount": 150}, "text": "+150 существу Бури."},
	{"id": &"arena_field_light", "name": "Поле Света", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 2, "amount": 90}, "text": "+90 существу Света."},
	{"id": &"arena_field_stone", "name": "Поле Камня", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 3, "amount": 150}, "text": "+150 существу Камня."},
	{"id": &"arena_field_shadow", "name": "Поле Тени", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 4, "amount": 80}, "text": "+80 существу Тени."},
	{"id": &"arena_field_tide", "name": "Поле Прилива", "kind": 0, "effect": &"attr_bonus", "params": {"attr": 5, "amount": 130}, "text": "+130 существу Прилива."},
	{"id": &"arena_altar", "name": "Алтарь силы", "kind": 0, "effect": &"owner_power", "params": {"amount": 300}, "text": "+300 существу владельца ворот любой стихии, если оно защищает эти ворота."},
	# --- Ворота вида (silver): базовая сила существа этого вида на них удваивается (у любой стороны) ---
	{"id": &"arena_den_dragnar", "name": "Логово Драгнара", "kind": 0, "effect": &"species_double", "params": {"species": "dragnar"}, "text": "Драгнар на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_klykar", "name": "Нора Клыкаря", "kind": 0, "effect": &"species_double", "params": {"species": "klykar"}, "text": "Клыкарь на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_grifalon", "name": "Гнездо Грифалона", "kind": 0, "effect": &"species_double", "params": {"species": "grifalon"}, "text": "Грифалон на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_kolossar", "name": "Кузня Колоссара", "kind": 0, "effect": &"species_double", "params": {"species": "kolossar"}, "text": "Колоссар на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_rogozhuk", "name": "Чертог Рогожука", "kind": 0, "effect": &"species_double", "params": {"species": "rogozhuk"}, "text": "Рогожук на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_levian", "name": "Омут Левиана", "kind": 0, "effect": &"species_double", "params": {"species": "levian"}, "text": "Левиан на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_ratnik", "name": "Ристалище Ратника", "kind": 0, "effect": &"species_double", "params": {"species": "ratnik"}, "text": "Ратник на этих воротах удваивает базовую силу."},
	{"id": &"arena_den_gorgul", "name": "Шпиль Горгула", "kind": 0, "effect": &"species_double", "params": {"species": "gorgul"}, "text": "Горгул на этих воротах удваивает базовую силу."},
	# --- Командные ворота (bronze): меняют правила боя; ловушки (hidden_trap) срабатывают при открытии ---
	{"id": &"arena_mirror", "name": "Зеркало", "kind": 0, "effect": &"mirror", "params": {"hidden_trap": true}, "text": "Ловушка: итоговые силы бойцов меняются местами."},
	{"id": &"arena_funnel", "name": "Воронка", "kind": 0, "effect": &"funnel", "params": {"amount": 100}, "text": "Существо владельца ворот забирает 100 силы у соперника: +100 / −100."},
	{"id": &"arena_limit", "name": "Предел", "kind": 0, "effect": &"limit", "params": {"hidden_trap": true, "amount": 400}, "text": "Ловушка: кто сильнее 400 — проигрывает. Если оба — выбывают оба."},
	{"id": &"arena_weight", "name": "Гнёт", "kind": 0, "effect": &"weight", "params": {"amount": 100, "threshold": 400}, "text": "−100 каждому бойцу с силой 400 и больше."},
	{"id": &"arena_web", "name": "Сеть врат", "kind": 0, "effect": &"web", "params": {"amount": 50}, "text": "+50 существу владельца за каждые ворота на поле."},
	{"id": &"arena_hold", "name": "Удержание", "kind": 0, "effect": &"hold", "params": {}, "text": "Победитель остаётся на воротах, карту никто не забирает."},
	{"id": &"arena_clash", "name": "Обоюдный удар", "kind": 0, "effect": &"clash", "params": {"hidden_trap": true}, "text": "Ловушка: оба бойца выбывают, ворота сгорают."},
	{"id": &"arena_mute", "name": "Глухие врата", "kind": 0, "effect": &"mute", "params": {"hidden_trap": true}, "text": "Ловушка: сопернику владельца способности в этом бою запрещены, его прикреплённые карты сгорают."},
	{"id": &"arena_dusk_throne", "name": "Трон сумрака", "kind": 0, "effect": &"dusk_throne", "params": {}, "text": "Существо Тени в этом бою побеждает. Если Тень у обоих — обычный бой."},
	{"id": &"arena_fallen_call", "name": "Зов павших", "kind": 0, "effect": &"fallen_call", "params": {}, "text": "При открытии все выбывшие существа обеих сторон возвращаются в игру."},
	# --- Стихийные способности (red): играет только существо своей стихии ---
	{"id": &"ability_fire_drain", "name": "Пожирающий жар", "kind": 1, "effect": &"drain", "params": {"lock": 0, "amount": 100}, "text": "Забирает 100 силы у соперника: +100 тебе, −100 ему."},
	{"id": &"ability_fire_ash", "name": "Пепельный дождь", "kind": 1, "effect": &"scorch", "params": {"lock": 0, "amount": 50, "spare": 0}, "text": "−50 сопернику. Его существа на воротах (кроме Пламени) получат −50 в своём следующем бою."},
	{"id": &"ability_gale_leap", "name": "Попутный шквал", "kind": 1, "effect": &"gust", "params": {"lock": 1, "amount": 100, "vs_adv": 150}, "text": "+100 (против стихии, которая бьёт твою, +250). После приземления: перелёт к слабейшему сопернику на воротах — бой."},
	{"id": &"ability_gale_swap", "name": "Вихревая подмена", "kind": 1, "effect": &"swap_fighter", "params": {"lock": 1, "moment": "battle", "instant": true, "amount": 200, "vs_adv": 150}, "text": "В бою: боец уходит в руку, на его место — сильнейшее твоё существо не на воротах, +200 (+350 против бьющей стихии)."},
	{"id": &"ability_light_revive", "name": "Возрождение", "kind": 1, "effect": &"revive", "params": {"lock": 2, "amount": 30}, "text": "+30. После боя одно твоё выбывшее существо возвращается в игру."},
	{"id": &"ability_light_purge", "name": "Очищающий луч", "kind": 1, "effect": &"purge_gate", "params": {"lock": 2, "amount": 50}, "text": "+50. Ворота соперника под боем не действуют."},
	{"id": &"ability_light_crown", "name": "Сияющий венец", "kind": 1, "effect": &"radiance", "params": {"lock": 2, "amount": 50}, "text": "+50 тебе, −50 сопернику. Его существа на воротах получат −50 в следующем бою."},
	{"id": &"ability_stone_copy", "name": "Отпечаток в камне", "kind": 1, "effect": &"copy", "params": {"lock": 3, "amount": 50}, "text": "+50 и повторяет последнюю действующую способность соперника — в твою пользу."},
	{"id": &"ability_stone_shift", "name": "Сдвиг плит", "kind": 1, "effect": &"shift_gate", "params": {"lock": 3, "moment": "battle", "instant": true, "amount": 80}, "text": "В бою: +80, ворота боя меняются местами с твоими свободными воротами (самыми выгодными)."},
	{"id": &"ability_shadow_doom", "name": "Общая бездна", "kind": 1, "effect": &"doom", "params": {"lock": 4}, "text": "Если твой боец проигрывает этот бой, выбывают оба бойца, ворота сгорают."},
	{"id": &"ability_shadow_eclipse", "name": "Затмение врат", "kind": 1, "effect": &"eclipse", "params": {"lock": 4, "amount": 50}, "text": "−50 сопернику. Ворота соперника под боем не действуют."},
	{"id": &"ability_shadow_pact", "name": "Тёмный пакт", "kind": 1, "effect": &"pact", "params": {"lock": 4, "amount": 50}, "text": "+50 тебе, −50 сопернику. Твои существа на воротах получат +50 в следующем бою."},
	{"id": &"ability_tide_hush", "name": "Глубинная тишь", "kind": 1, "effect": &"silence", "params": {"lock": 5, "amount": 50}, "text": "+50. Соперник больше не играет способности в этом бою."},
	{"id": &"ability_tide_ebb", "name": "Отлив", "kind": 1, "effect": &"ebb", "params": {"lock": 5}, "text": "Бой прекращается: существо соперника уносит на свободные ворота (если они есть)."},
	# --- Усиления (blue): лесенка +30…+200 своей стихии; чем больше число, тем строже условие ---
	{"id": &"ability_fire_spark", "name": "Искра", "kind": 1, "effect": &"boost", "params": {"lock": 0, "amount": 30, "sure": true}, "text": "+30. Нельзя отменить."},
	{"id": &"ability_fire_assault", "name": "Жаркий натиск", "kind": 1, "effect": &"boost", "params": {"lock": 0, "amount": 100, "cond": "attack"}, "text": "+100 в атаке."},
	{"id": &"ability_fire_last", "name": "Последний костёр", "kind": 1, "effect": &"boost", "params": {"lock": 0, "amount": 200, "cond": "last", "returns": true}, "text": "+200, если это твоё последнее существо. После боя возвращается в руку."},
	{"id": &"ability_gale_gust", "name": "Порыв", "kind": 1, "effect": &"boost", "params": {"lock": 1, "amount": 80, "vs_adv": 170}, "text": "+80. Если стихия соперника бьёт твою — ещё +170."},
	{"id": &"ability_gale_counter", "name": "Встречный вихрь", "kind": 1, "effect": &"boost", "params": {"lock": 1, "amount": 120, "cond": "underdog"}, "text": "+120, если базовая сила соперника выше твоей или его стихия бьёт твою."},
	{"id": &"ability_gale_vengeance", "name": "Буря мщения", "kind": 1, "effect": &"boost", "params": {"lock": 1, "amount": 250, "cond": "behind", "returns": true}, "text": "+250, если у тебя меньше существ, чем у соперника. После боя возвращается в руку."},
	{"id": &"ability_light_glint", "name": "Отблеск", "kind": 1, "effect": &"boost", "params": {"lock": 2, "amount": 50, "sure": true}, "text": "+50. Нельзя отменить."},
	{"id": &"ability_light_guard", "name": "Светлый страж", "kind": 1, "effect": &"boost", "params": {"lock": 2, "amount": 100, "cond": "defense"}, "text": "+100 в защите."},
	{"id": &"ability_light_dawn", "name": "Последний рассвет", "kind": 1, "effect": &"boost", "params": {"lock": 2, "amount": 150, "cond": "last", "returns": true}, "text": "+150, если это твоё последнее существо. После боя возвращается в руку."},
	{"id": &"ability_stone_firm", "name": "Твердь", "kind": 1, "effect": &"boost", "params": {"lock": 3, "amount": 80}, "text": "+80."},
	{"id": &"ability_stone_footing", "name": "Опора", "kind": 1, "effect": &"boost", "params": {"lock": 3, "amount": 120, "cond": "own_gate"}, "text": "+120 на своих воротах."},
	{"id": &"ability_stone_wrath", "name": "Гнев гор", "kind": 1, "effect": &"boost", "params": {"lock": 3, "amount": 180, "cond": "behind", "returns": true}, "text": "+180, если у тебя меньше существ, чем у соперника. После боя возвращается в руку."},
	{"id": &"ability_shadow_haze", "name": "Мгла", "kind": 1, "effect": &"boost", "params": {"lock": 4, "amount": 30, "sure": true}, "text": "+30. Нельзя отменить."},
	{"id": &"ability_shadow_strike", "name": "Удар из тени", "kind": 1, "effect": &"boost", "params": {"lock": 4, "amount": 100, "cond": "attack"}, "text": "+100 в атаке."},
	{"id": &"ability_shadow_revenge", "name": "Месть тьмы", "kind": 1, "effect": &"boost", "params": {"lock": 4, "amount": 180, "cond": "behind", "returns": true}, "text": "+180, если у тебя меньше существ, чем у соперника. После боя возвращается в руку."},
	{"id": &"ability_tide_spray", "name": "Брызги", "kind": 1, "effect": &"boost", "params": {"lock": 5, "amount": 50}, "text": "+50."},
	{"id": &"ability_tide_surf", "name": "Прибой", "kind": 1, "effect": &"boost", "params": {"lock": 5, "amount": 100, "cond": "defense"}, "text": "+100 в защите."},
	{"id": &"ability_tide_ninth", "name": "Девятый вал", "kind": 1, "effect": &"boost", "params": {"lock": 5, "amount": 180, "cond": "last", "returns": true}, "text": "+180, если это твоё последнее существо. После боя возвращается в руку."},
	# --- Видовые способности (green): играет только существо своего вида (любой стихии) ---
	{"id": &"ability_dragnar_rush", "name": "Драконий напор", "kind": 1, "effect": &"boost_fix", "params": {"species": "dragnar", "amount": 100, "fix": 440}, "text": "+100. В следующем бою сила этого существа будет ровно 440."},
	{"id": &"ability_dragnar_heart", "name": "Сердце дракона", "kind": 1, "effect": &"fusion_boost", "params": {"species": "dragnar", "amount": 200, "fusion": true}, "text": "Слияние: +200, только поверх твоей способности в этом бою."},
	{"id": &"ability_klykar_bite", "name": "Волчья хватка", "kind": 1, "effect": &"negate", "params": {"species": "klykar", "amount": 50}, "text": "−50 сопернику и отменяет его последнюю способность."},
	{"id": &"ability_klykar_hunt", "name": "Загонщик", "kind": 1, "effect": &"boost", "params": {"species": "klykar", "amount": 200, "cond": "weaker"}, "text": "+200, если базовая сила соперника выше твоей."},
	{"id": &"ability_grifalon_dive", "name": "Пикирование", "kind": 1, "effect": &"boost", "params": {"species": "grifalon", "amount": 200, "cond": "attack"}, "text": "+200 в атаке."},
	{"id": &"ability_grifalon_sky", "name": "Взор с высоты", "kind": 1, "effect": &"aloft", "params": {"species": "grifalon", "amount": 100}, "text": "+100. Ворота боя не дают сопернику бонуса."},
	{"id": &"ability_kolossar_wall", "name": "Несокрушимый", "kind": 1, "effect": &"boost", "params": {"species": "kolossar", "amount": 250, "cond": "defense", "sure": true}, "text": "+250 в защите. Нельзя отменить."},
	{"id": &"ability_kolossar_reset", "name": "Великий сброс", "kind": 1, "effect": &"reset_base", "params": {"species": "kolossar", "sure": true, "lockout": true}, "text": "Сила обоих сбрасывается до базовой; карты, сыгранные после, действуют, но ты больше не играешь. Нельзя отменить."},
	{"id": &"ability_rogozhuk_shell", "name": "Хитиновый панцирь", "kind": 1, "effect": &"cap_own_base", "params": {"species": "rogozhuk", "sure": true}, "text": "Сила соперника не выше твоей базовой. Нельзя отменить."},
	{"id": &"ability_rogozhuk_ram", "name": "Рогатый таран", "kind": 1, "effect": &"weaken_mark", "params": {"species": "rogozhuk", "amount": 100, "mark": 50}, "text": "−100 сопернику. Если он уцелеет, в следующем бою ещё −50."},
	{"id": &"ability_levian_coil", "name": "Кольца глубин", "kind": 1, "effect": &"siphon", "params": {"species": "levian", "lockout": true, "share": 25}, "text": "Сжигает бонусы соперника сверх его базовой силы, набранные до неё; четверть — тебе. Потом ты больше не играешь."},
	{"id": &"ability_levian_abyss", "name": "Пучина", "kind": 1, "effect": &"strip", "params": {"species": "levian"}, "text": "Сила соперника не выше его базовой: все его бонусы сгорают."},
	{"id": &"ability_ratnik_oath", "name": "Клятва стража", "kind": 1, "effect": &"boost", "params": {"species": "ratnik", "amount": 100, "sure": true}, "text": "+100. Нельзя отменить."},
	{"id": &"ability_ratnik_rearm", "name": "Второе дыхание", "kind": 1, "effect": &"recall", "params": {"species": "ratnik", "amount": 50}, "text": "+50. После боя твои сыгранные способности (кроме этой) возвращаются в руку."},
	{"id": &"ability_gorgul_gaze", "name": "Каменный взгляд", "kind": 1, "effect": &"nullify_gate", "params": {"species": "gorgul", "amount": 50}, "text": "+50. Ворота боя не действуют (кроме ворот вида)."},
	{"id": &"ability_gorgul_night", "name": "Крылья ночи", "kind": 1, "effect": &"scorch", "params": {"species": "gorgul", "amount": 100, "spare": -1}, "text": "−100 сопернику. Его существа на воротах получат −100 в следующем бою."},
]

const PRESET_DECKS: Array = [
	{
		"creatures": [&"creature_dragnar_fire", &"creature_klykar_fire", &"creature_grifalon_fire"],
		"arena": [&"arena_field_fire", &"arena_den_dragnar", &"arena_funnel"],
		"abilities": [&"ability_fire_drain", &"ability_fire_assault", &"ability_dragnar_heart"],
	},
	{
		"creatures": [&"creature_levian_tide", &"creature_ratnik_tide", &"creature_gorgul_tide"],
		"arena": [&"arena_field_tide", &"arena_den_levian", &"arena_mirror"],
		"abilities": [&"ability_tide_hush", &"ability_tide_surf", &"ability_ratnik_oath"],
	},
]
