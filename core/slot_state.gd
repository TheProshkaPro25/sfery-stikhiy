class_name SlotState
extends RefCounted
## Слот поля. has_card отличает «карта есть, но замаскирована» от «карты нет».

var card_id: StringName = &""
var card_owner: int = -1
var revealed: bool = false
var occupant_uid: int = -1
var has_card: bool = false


func clone(mask_card: bool) -> SlotState:
	var s: SlotState = SlotState.new()
	s.card_owner = card_owner
	s.revealed = revealed
	s.occupant_uid = occupant_uid
	s.has_card = has_card
	if mask_card:
		s.card_id = &""
	else:
		s.card_id = card_id
	return s
