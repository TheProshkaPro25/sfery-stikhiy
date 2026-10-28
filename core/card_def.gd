class_name CardDef
extends Resource
## Неизменяемое определение карты (арены или способности).

enum Kind { ARENA, ABILITY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: int = 0
@export var effect_id: StringName = &""
@export var params: Dictionary = {}
@export var text: String = ""


static func make(p_id: StringName, p_name: String, p_kind: int, p_effect: StringName, p_params: Dictionary, p_text: String) -> CardDef:
	var c: CardDef = CardDef.new()
	c.id = p_id
	c.display_name = p_name
	c.kind = p_kind
	c.effect_id = p_effect
	c.params = p_params
	c.text = p_text
	return c
