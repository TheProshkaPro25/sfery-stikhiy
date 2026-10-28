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


func add(side: int, source: String, delta: int) -> void:
	breakdown.append({"side": side, "source": source, "delta": delta})


func attacker_won() -> bool:
	return winner_uid == attacker_uid


func to_log_string() -> String:
	return "BR(slot=%d atk=%d def=%d win=%d p=%d:%d a=%s d=%s lost=%s)" % [
		slot, attacker_uid, defender_uid, winner_uid, powers[0], powers[1],
		String(atk_ability), String(def_ability), String(lost_ability)]
