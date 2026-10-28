class_name CreatureState
extends RefCounted
## Экземпляр существа в матче. slot == -1: в руке (или в зоне использованных, если used).

var uid: int = -1
var def_id: StringName = &""
var owner: int = 0
var alive: bool = true
var slot: int = -1
## В зоне использованных: бросать нельзя, пока не вернутся все (см. MatchController._refill_if_needed).
var used: bool = false
## Слот, из которого существо отозвано в текущем ходу (туда приземлиться нельзя), иначе -1.
var recalled_from: int = -1
## Прикреплённые способности (сыграны до броска или после приземления): [[метка времени, card_id], ...].
## Срабатывают в следующем бою существа (первыми, по метке) и снимаются после него. Видны обоим игрокам.
var attached: Array = []


func _init(p_uid: int = -1, p_def_id: StringName = &"", p_owner: int = 0) -> void:
	uid = p_uid
	def_id = p_def_id
	owner = p_owner


func clone() -> CreatureState:
	var c: CreatureState = CreatureState.new(uid, def_id, owner)
	c.alive = alive
	c.slot = slot
	c.used = used
	c.recalled_from = recalled_from
	c.attached = attached.duplicate(true)
	return c
