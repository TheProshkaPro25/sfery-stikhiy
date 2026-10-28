extends SceneTree
## Снимки экрана сборки колоды (TeamMenu) без матча: три шага, наведение на существо, ошибка колоды.
##   godot -s res://tools/team_shots.gd --resolution 1280x720 -- <папка>
## Файлы: team_<Ш>x<В>_<кадр>.png

var dir := "user://team_shots"
var menu: TeamMenu
var tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		dir = args[0]
	DirAccess.make_dir_recursive_absolute(dir)
	GraphicsSettings.max_fps = 60
	Engine.max_fps = 60
	var sz := DisplayServer.window_get_size()
	tag = "%dx%d" % [sz.x, sz.y]
	menu = load("res://scenes/ui/team_menu.tscn").instantiate() as TeamMenu
	root.add_child(menu)
	_run.call_deferred()


func _shot(n: String, frames: int = 30) -> void:
	for _i in range(frames):
		await process_frame
	RenderingServer.force_draw(false)   # при заблокированном экране окно не перерисовывается само
	var path := "%s/team_%s_%s.png" % [dir, tag, n]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("снимок: ", ProjectSettings.globalize_path(path))


func _run() -> void:
	menu._rng.seed = 4242
	menu.pick_random()
	await _shot("1_team", 90)
	if menu.has_method("debug_preview"):
		menu.debug_preview(1)
		await _shot("1_hover", 50)
		menu.debug_preview(-1)
	menu._show_step(1)
	await _shot("2_gates")
	menu._show_step(2)
	await _shot("3_abilities")
	# неполная команда: видна подсказка, почему нельзя в бой
	menu._show_step(0)
	menu._on_creature(menu._team[0])
	await _shot("4_error")
	# стихия с самыми длинными именами
	menu._on_element(5)
	await _shot("5_tide", 60)
	menu.debug_preview(0)
	await _shot("6_tide_hover", 60)
	# одна колонка ворот крупно (фильтр по классу)
	menu._filter = &"bronze"
	menu._show_step(1)
	menu._filter = &"bronze"
	menu._show_step(1)
	await _shot("7_filter")
	menu.queue_free()
	await process_frame
	quit(0)
