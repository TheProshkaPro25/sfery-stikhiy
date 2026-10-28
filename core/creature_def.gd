class_name CreatureDef
extends Resource
## Неизменяемое определение существа. В рантайме не мутируется.

@export var id: StringName = &""
@export var display_name: String = ""
@export var attribute: int = 0
@export var base_power: int = 0
@export var color: Color = Color.WHITE
## Вид (GameData.SPECIES): одно существо в 6 стихиях. archetype — запасная low-poly модель.
@export var species: StringName = &""
@export var archetype: String = "knight"


static func make(p_id: StringName, p_name: String, p_attr: int, p_power: int, p_color: Color) -> CreatureDef:
	var d: CreatureDef = CreatureDef.new()
	d.id = p_id
	d.display_name = p_name
	d.attribute = p_attr
	d.base_power = p_power
	d.color = p_color
	return d
