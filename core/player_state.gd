class_name PlayerState
extends RefCounted
## Состояние игрока: uid существ, руки (ещё не сыгранные карты), сыгранные и захваченные карты.

var index: int = 0
var creature_uids: Array[int] = []
var arena_hand: Array[StringName] = []
var ability_hand: Array[StringName] = []
var abilities_used: Array[StringName] = []
var captured: Array[StringName] = []


func _init(p_index: int = 0) -> void:
	index = p_index


## hide_hands: руки заменяются пустыми id той же длины (число карт видно, содержимое нет).
func clone(hide_hands: bool) -> PlayerState:
	var p: PlayerState = PlayerState.new(index)
	p.creature_uids.assign(creature_uids)
	p.abilities_used.assign(abilities_used)
	p.captured.assign(captured)
	if hide_hands:
		for i in range(arena_hand.size()):
			p.arena_hand.append(&"")
		for i in range(ability_hand.size()):
			p.ability_hand.append(&"")
	else:
		p.arena_hand.assign(arena_hand)
		p.ability_hand.assign(ability_hand)
	return p
