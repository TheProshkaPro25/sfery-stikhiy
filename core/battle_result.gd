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
var attr_atk: int = 0  # атрибуты бойцов в бою
var attr_def: int = 0
var atk_fusion: StringName = &""  # карты «Слияния» сторон
var def_fusion: StringName = &""
var plays: Array = []  # все карты боя по порядку: [[сторона, card_id], ...] (прикреплённые — первыми)
var battle_plays: Array = []  # только карты обмена боя (без прикреплённых) — для предпросмотра ИИ
var passed: Array[bool] = [false, false]  # предпросмотр: стороны, уже вышедшие из обмена (заполняет контроллер)
var cancelled_plays: Array = []  # отменённые карты: [[сторона, card_id], ...]
var trap_id: StringName = &""  # сработавшая ворота-ловушка (не отменённая), иначе пусто
var sealed: bool = false  # «Глухие врата»: способности одной стороны сгорели (см. silenced)
var mirrored: bool = false  # «Зеркало»: итоговые силы поменялись местами
var final_round: bool = false  # бой идёт в финальном раунде (преимущество стихии ×2)
var momentum: Array[int] = [0, 0]  # бонус «Натиска» сторон
var gate_effect: StringName = &""  # effect_id действующих ворот (после отмены — пусто)
var gate_owner_side: int = -1  # сторона владельца ворот (0/1), -1 — ничья
var silenced: Array[bool] = [false, false]  # сторона больше не может играть способности («Глухие врата», «Глубинная тишь»)
var interrupted: bool = false  # «Отлив»: боя не было, relocate_uid уносит на relocate_to
var relocate_uid: int = -1
var relocate_to: int = -1
var both_lose: bool = false  # выбывают оба бойца, ворота сгорают («Общая бездна», «Предел», «Обоюдный удар»)
var winner_stays: bool = false  # «Удержание»: победитель остаётся на воротах, карту не забирают
var auto_win: bool = false  # «Трон сумрака» решил бой
var revive: Array[bool] = [false, false]  # «Возрождение»: после боя вернуть выбывшее существо стороны
var recall: Array[StringName] = [&"", &""]  # «Второе дыхание»: id карты, вернуть сыгранные способности стороны
var marks: Array = []  # новые метки на следующий бой: [[uid, {"src", "delta"|"fix"}], ...] (контроллер вешает живым)
var copies: Array = []  # «Отпечаток в камне»: [[сторона, id копии, id повторённой карты], ...]


func add(side: int, source: String, delta: int) -> void:
	breakdown.append({"side": side, "source": source, "delta": delta})


func attacker_won() -> bool:
	return winner_uid == attacker_uid


func to_log_string() -> String:
	return "BR(slot=%d atk=%d def=%d win=%d p=%d:%d plays=%s trap=%s gate=%s int=%s both=%s stay=%s)" % [
		slot, attacker_uid, defender_uid, winner_uid, powers[0], powers[1],
		str(plays), String(trap_id), String(gate_effect), str(interrupted), str(both_lose), str(winner_stays)]
