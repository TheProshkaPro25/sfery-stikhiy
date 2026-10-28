extends SceneTree
## Витрина всех карт (ворота и способности): godot -s res://tools/card_gallery.gd -- <файл.png> [big] [low]
## Без «big» — все карты мелким форматом (как в колоде и на столе); с «big» — по карте каждого типа
## крупно с текстом (как в руке и при выборе ворот), с наведением/выбором/затемнением, и самые длинные имена.
## «low» — облик при уровне графики «Низкие» (без второго слоя дымки и рун).

## По карте каждого типа (первые 7 — крупно 150×210), затем самые длинные имена (124×174).
const BIG_NAMES := ["Поле Пламени", "Логово Драгнара", "Воронка", "Предел", "Вихревая подмена", "Буря мщения", "Сердце дракона",
	"Волчья хватка", "Последний рассвет", "Отпечаток в камне", "Обоюдный удар", "Пепельный дождь"]

func _initialize() -> void:
	var out := "user://cards.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var big: bool = args.has("big")
	if args.has("low"):
		GraphicsSettings.level = GraphicsSettings.Level.LOW
	Engine.max_fps = 60
	var sz := Vector2i(1600, 1000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(sz)
	root.size = sz
	CardDB.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.13)
	bg.size = Vector2(sz)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.position = Vector2(18, 18)
	grid.add_theme_constant_override("h_separation", 10 if not big else 22)
	grid.add_theme_constant_override("v_separation", 12 if not big else 26)
	root.add_child(grid)
	var all: Array = CardDB.arena_ids() + CardDB.ability_ids()
	if not big:
		grid.columns = 14
		for id in all:
			grid.add_child(CardView.new().for_card(CardDB.card(id), Vector2(102, 143)))
	else:
		grid.columns = 7
		var ids: Array = []
		for n in BIG_NAMES:
			for cid in all:
				if CardDB.card(cid).display_name == n:
					ids.append(cid)
		var k := 0
		for id in ids:
			var cv := CardView.new().for_card(CardDB.card(id), Vector2(150, 210) if k < 7 else Vector2(124, 174))
			grid.add_child(cv)
			if k == 1:
				cv.set_playable(true)
			elif k == 2:
				cv.button_pressed = true
				cv._mat.set_shader_parameter("selected", 1.0)
			elif k == 3:
				cv.set_dimmed(true)
			elif k == 4:
				cv._mat.set_shader_parameter("hover", 1.0)
			k += 1
		var cr := CardDB.species_creatures()
		for i in [0, 9, 20]:
			grid.add_child(CardView.new().for_creature(cr[i], -1, "", Vector2(124, 174)))
	for _i in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)  # окно может быть скрыто — кадр всё равно рисуем
	root.get_texture().get_image().save_png(out)
	quit()
