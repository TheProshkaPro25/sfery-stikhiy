extends Control
## Круглый значок стихии (знак как на картах, см. element_mark.gdshader). Мышь не ловит.

const SHADER: Shader = preload("res://scenes/ui/element_mark.gdshader")

var _mat: ShaderMaterial


static func make(element: int, px: float = 22.0, lit: bool = true) -> Control:
	var ic = load("res://scenes/ui/element_mark.gd").new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.set_element(element, lit)
	return ic


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat


func set_element(element: int, lit: bool = true) -> void:
	_mat.set_shader_parameter("element", clampi(element, 0, 5))
	_mat.set_shader_parameter("col", VisualUtil.attr_color(element).lightened(0.15))
	_mat.set_shader_parameter("lit", 1.0 if lit else 0.35)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
