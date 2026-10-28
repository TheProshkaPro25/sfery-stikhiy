class_name BattleResult
extends RefCounted
## Итог (или предпросмотр) боя. Сторона 0 = атакующий, 1 = защитник.

var slot: int = -1
var attacker_uid: int = -1
var defender_uid: int = -1
var winner_uid: int = -1
var loser_uid: int = -1
var powers: Array[int] = [0, 0]
var breakdown: Array[Dictionary] = []  # {side:int, source:String, delta:int}
var atk_ability: StringName = &""
var def_ability: StringName = &""
var atk_cancelled: bool = false
var def_cancelled: bool = false
var arena_card_id: StringName = &""
var arena_cancelled: bool = false
var attr_atk: int = 0  # эффективные атрибуты после «Перелива»
var attr_def: int = 0
var lost_ability: StringName = &""  # заполняет контроллер («Ва-банк»)
var atk_fusion: StringName = &""  # карты «Слияния» сторон
var def_fusion: StringName = &""
var atk_rescue: bool = false  # действует «Спасение»
var def_rescue: bool = false
var rescued: bool = false  # проигравший спасён (заполняет контроллер)
var plays: Array = []  # все карты боя по порядку: [[сторона, card_id], ...] (прикреплённые — первыми)
var battle_plays: Array = []  # только карты обмена боя (без прикреплённых) — для предпросмотра ИИ
var passed: Array[bool] = [false, false]  # предпросмотр: стороны, уже вышедшие из обмена (заполняет контроллер)
var cancelled_plays: Array = []  # отменённые карты: [[сторона, card_id], ...]
var atk_all_in: bool = false  # действует «Ва-банк»
var def_all_in: bool = false
var trap_id: StringName = &""  # сработавшая ловушка ворот (не отменённая Глушителем), иначе пусто
var sealed: bool = false  # «Печать тишины»: все способности боя сгорели
var mirrored: bool = false  # «Зеркало»: итоговые силы поменялись местами
var final_round: bool = false  # бой идёт в финальном раунде (преимущество стихии ×2)
var momentum: Array[int] = [0, 0]  # бонус «Натиска» сторон


func add(side: int, source: String, delta: int) -> void:
	breakdown.append({"side": side, "source": source, "delta": delta})


func attacker_won() -> bool:
	return winner_uid == attacker_uid


func to_log_string() -> String:
	return "BR(slot=%d atk=%d def=%d win=%d p=%d:%d plays=%s trap=%s lost=%s)" % [
		slot, attacker_uid, defender_uid, winner_uid, powers[0], powers[1],
		str(plays), String(trap_id), String(lost_ability)]
