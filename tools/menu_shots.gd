extends SceneTree
## Главное меню в окне: снимки 8 моментов цикла суток и контактный лист, либо замер fps.
##   godot -s res://tools/menu_shots.gd --resolution 1920x1080 -- [ключ=значение ...]
## Ключи:
##   mode=shots   — 10 кадров (рассвет, восход, утро, день, золотой час, закат, сумерки, ночь, шары стихий
##                  загораются, полночь — шары в кольце) → лист
##                  tools/shots_anime/menu_<Ш>x<В>.png, отдельные кадры — в dir=<папка> (по умолчанию user://menu_shots)
##   mode=fps     — vsync выкл., без лимита: 40 с, фаза пробегает весь цикл; итог строкой «MENUPERF …»
##   mode=cpu     — то же при 60 кадрах/с: загрузка основного потока (% одного ядра) по /proc
##   quality=     — low/medium/high (без записи в settings.cfg), иначе из user://settings.cfg
##   secs=40      — длительность замера

const PHASES := [0.235, 0.27, 0.36, 0.52, 0.715, 0.752, 0.785, 0.92, 0.976, 0.015]
const NAMES := ["рассвет", "восход", "утро", "день", "золотой час", "закат", "сумерки", "ночь", "шары загораются", "полночь"]

var opts := {"mode": "shots", "quality": "", "secs": "40", "dir": "user://menu_shots"}
var menu: MainMenu


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	if opts["quality"] != "":
		GraphicsSettings.force_level(GraphicsSettings.level_from_name(opts["quality"]))
	# лимит 60 кадров/с (правило проверок, без записи в settings.cfg); снимается только в замере mode=fps
	GraphicsSettings.max_fps = 60
	if opts["mode"] == "fps":
		GraphicsSettings.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif opts["mode"] == "cpu":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	menu = load("res://scenes/menu/main_menu.tscn").instantiate() as MainMenu
	root.add_child(menu)
	_run.call_deferred()


func _run() -> void:
	for _i in range(90):   # появление интерфейса, компиляция шейдеров
		await process_frame
	if opts["mode"] == "shots":
		await _shots()
	else:
		await _measure()
	menu.queue_free()
	await process_frame
	quit(0)


func _shots() -> void:
	var dir: String = opts["dir"]
	DirAccess.make_dir_recursive_absolute(dir)
	var size := Vector2(DisplayServer.window_get_size())
	var tag := "%dx%d" % [int(size.x), int(size.y)]
	var imgs: Array[Image] = []
	menu.city.paused = true
	for i in range(PHASES.size()):
		menu.city.phase = PHASES[i]
		for _f in range(24):
			await process_frame
		RenderingServer.force_draw(false)   # при заблокированном экране окно не перерисовывается само
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/menu_%s_%d.png" % [dir, tag, i])
		imgs.append(img)
		print("кадр %d: %s (фаза %.3f, %s)" % [i, NAMES[i], PHASES[i], DayCycle.clock_text(PHASES[i])])
	# контактный лист по 4 в ряд, плитка 640 по ширине
	var tw := 640
	var th := int(round(640.0 * size.y / size.x))
	var rows := (imgs.size() + 3) / 4
	var sheet := Image.create(tw * 4 + 12, th * rows + 4 * (rows - 1), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in range(imgs.size()):
		var im := imgs[i]
		im.convert(Image.FORMAT_RGB8)
		im.resize(tw, th, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i((i % 4) * (tw + 4), (i / 4) * (th + 4)))
	var out := "res://tools/shots_anime/menu_%s.png" % tag
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("лист: ", ProjectSettings.globalize_path(out))


func _measure() -> void:
	var secs := float(opts["secs"])
	var t0 := Time.get_ticks_usec()
	var last := t0
	var ft := PackedFloat32Array()
	var gpu := 0.0
	var n := 0
	var cpu0 := _cpu_ticks()
	var vrid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vrid, true)
	menu.city.paused = true
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var el := (now - t0) / 1e6
		if el >= secs:
			break
		menu.city.phase = fposmod(DayCycle.START_PHASE + el / secs, 1.0)
		ft.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
		n += 1
	var wall := (Time.get_ticks_usec() - t0) / 1e6
	var cpu1 := _cpu_ticks()
	var sorted := ft.duplicate()
	sorted.sort()
	var worst: float = sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0
	var p99: float = sorted[int(sorted.size() * 0.99)] if sorted.size() > 0 else 0.0
	var size := Vector2(DisplayServer.window_get_size())
	print("MENUPERF mode=%s quality=%s res=%dx%d fps=%.0f gpu_ms=%.2f p99_ms=%.2f worst_ms=%.1f cpu_main=%.1f%% cpu_proc=%.1f%%" % [
		opts["mode"], GraphicsSettings.level_name(), int(size.x), int(size.y), n / wall, gpu / maxf(n, 1),
		p99, worst, 100.0 * (cpu1.x - cpu0.x) / 100.0 / wall, 100.0 * (cpu1.y - cpu0.y) / 100.0 / wall])


## utime+stime основного потока и всего процесса (тики USER_HZ = 100), как в tools/perf.gd.
func _cpu_ticks() -> Vector2i:
	var pid := OS.get_process_id()
	return Vector2i(_stat_ticks("/proc/%d/task/%d/stat" % [pid, pid]), _stat_ticks("/proc/%d/stat" % pid))


func _stat_ticks(path: String) -> int:
	var out := []
	OS.execute("cat", [path], out)
	var s: String = str(out[0]) if out.size() > 0 else ""
	if s == "":
		return 0
	var parts := s.substr(s.rfind(")") + 2).split(" ")
	return int(parts[11]) + int(parts[12])
