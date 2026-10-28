class_name HelpOverlay
extends Control
## Экран «Как играть»: правила простыми словами, типы карт и цикл стихий. Закрывается кнопкой или кликом по фону.

const SECTIONS := [
	["Цель", "Выбей всех трёх существ соперника. Существа бросаются шарами на карты ворот и сражаются на них."],
	["Ход", "1. Положи карту ворот (по желанию; обязательно, если на поле нет ворот) — ближе к сопернику, рядом с другими картами.\n2. Выбери существо и брось шар: потяни мышь назад от шара и отпусти (как рогатку). ПКМ — отмена."],
	["Куда попал шар", "• Мимо ворот — существо уходит в зону использованных.\n• Пустые ворота — существо встаёт на них.\n• Ворота с существом соперника — бой.\n• Ворота со своим существом — оно переходит на другие ворота; если некуда, карта засчитывается тебе."],
	["Бой", "Сначала способности (атакующий, потом защитник), пока ворота закрыты. Затем ворота открываются и сравнивается сила: базовая сила существа + сила G ворот для его стихии + преимущество стихии (+60) + способности. Ничья — победа того, кто встал первым. Проигравший выбывает, победитель уходит в зону использованных и ходит следующим."],
	["Зона использованных", "Когда бросать некого, существа из зоны использованных возвращаются в руку. Если все живые стоят на воротах, можно снять одно и бросить снова."],
	["Карты ворот", "Золотые — сила G по стихии (своей стихии +100). Серебряные — особый бонус силы. Бронзовые — меняют правила боя. В колоде по одной каждого класса."],
	["Способности", "Красные — стихийные (только своя стихия), синие — прибавка силы, зелёные — меняют ситуацию боя. Слияние кладётся поверх своей способности. Каждая карта — один раз за игру. Наведи мышь на любую карту, чтобы прочитать подробности."],
	["Стихии", "Пламя > Буря > Свет > Камень > Тень > Прилив > Пламя. Стихия, которая бьёт стихию соперника, получает +60 к силе."],
]

var _built := false


func _ready() -> void:
	_build()


## Открыть поверх всего (parent — слой интерфейса).
static func open_on(parent: Node) -> HelpOverlay:
	var h := HelpOverlay.new()
	parent.add_child(h)
	return h


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -470
	panel.offset_right = 470
	panel.offset_top = -320
	panel.offset_bottom = 320
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := VisualUtil.label("Как играть", 28)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "Понятно"
	close.custom_minimum_size = Vector2(130, 40)
	close.pressed.connect(queue_free)
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for sec in SECTIONS:
		var h := VisualUtil.label(sec[0], 19)
		h.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		list.add_child(h)
		var body := VisualUtil.label(sec[1], 15)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(880, 0)
		list.add_child(body)
