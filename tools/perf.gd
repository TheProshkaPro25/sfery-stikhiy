extends "res://tools/autoplay.gd"
## Замер производительности в окне (автоигра, перезапуск через «ещё раз» как у игрока):
##   godot -s res://tools/perf.gd --resolution 1920x1080 -- h3d=1080 [ключ=значение ...]
## (полноэкранное окно KWin ограничивает частотой экрана — поэтому окно и масштаб 3D, см. h3d)
## Ключи:
##   mode=fps     — vsync выключен, fps без ограничения (нагрузка GPU/CPU); mode=cpu — 60 кадров/с как на
##                  ноутбуке с 60 Гц, считаем загрузку основного потока (% одного ядра) по /proc/self/task/<pid>/stat
##                  mode=bench — без автоигры: 6 раскрытых существ на воротах, три ракурса по 8 с (общий план,
##                  бой, крупный план) — повторяемый замер для сравнения настроек графики
##   matches=3    — сколько матчей подряд (между ними — перезапуск сцены, проверка памяти на утечки)
##   secs=0       — ограничить время замера одного матча (0 — до конца матча)
##   speed=2      — Engine.time_scale (2 — как в shot.gd; ход матча в 2 раза быстрее)
##   quality=     — low/medium/high: принудительно уровень графики (иначе — из user://settings.cfg)
##   h3d=1080     — подобрать масштаб 3D под высоту кадра (окно 1920×1050 → 1080; h3d=2160 — «4K», не больше ×2)
##   scale3d=1    — масштаб 3D-рендера (2.0 при окне 1920×1080 = 3840×2160 — нагрузочный тест «4K»)
##   gs.<параметр>=<значение> — подменить параметр уровня (см. GraphicsSettings.PRESETS), например gs.ssao=0
##   out=<файл>   — дописать строку итогов в файл (tsv)
## Итоги печатаются строкой «PERF ...»; память — после каждого матча («MEM ...»).

const WARMUP := 3.0  # секунд с начала матча не считаем (компиляция шейдеров, загрузка моделей)

var opts := {"mode": "fps", "matches": "3", "secs": "0", "speed": "2", "quality": "", "scale3d": "1", "out": ""}
var _switching := false
var _t_match := 0.0          # секунд от начала матча (реальных)
var _last_us := 0
var _ft: PackedFloat32Array = PackedFloat32Array()  # длительности кадров, мс (после прогрева)
var _proc_ms := 0.0
var _phys_ms := 0.0
var _gpu_ms := 0.0
var _rcpu_ms := 0.0
var _draw := 0.0
var _prims := 0.0
var _n := 0
var _win_t := 0.0
var _win_frames := 0
var _win_fps: PackedFloat32Array = PackedFloat32Array()
var _cpu0 := Vector2i.ZERO   # (основной поток, весь процесс) в тиках
var _cpu_t0 := 0
var _mem_rows: Array = []
var _measuring := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0].begins_with("gs."):
			# подмена параметра уровня графики: gs.ssao=0, gs.msaa=0, gs.shadow_size=8192 …
			GraphicsSettings.overrides[kv[0].trim_prefix("gs.")] = str_to_var(kv[1])
		elif kv.size() == 2:
			opts[kv[0]] = kv[1]
	if opts["quality"] != "":
		GraphicsSettings.force_level(GraphicsSettings.level_from_name(opts["quality"]))
	GraphicsSettings.max_fps = 60 if opts["mode"] == "cpu" else 0  # без записи в settings.cfg
	super._initialize()
	Engine.time_scale = float(opts["speed"])
	Engine.physics_ticks_per_second = 60
	if opts["mode"] == "cpu":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if opts.get("h3d", "") != "":
		# окно на весь экран KWin держит на частоте экрана (144 Гц) даже без vsync — меряем в окне
		# (1920×1050 после рамки) и добираем высоту 3D-кадра масштабом рендера
		await process_frame
		root.scaling_3d_scale = minf(2.0, float(opts["h3d"]) / float(DisplayServer.window_get_size().y))
	else:
		root.scaling_3d_scale = float(opts["scale3d"])
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_last_us = Time.get_ticks_usec()


var _bench_t := -1.0
var _bench_shot := -1
var _bench_res: Array = []
const BENCH_SHOT := 8.0


## Повторяемый замер: все 6 существ матча раскрыты на воротах, камера по очереди в трёх ракурсах.
func _bench(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	if _switching or main == null or main.ctrl == null:
		return false
	if _bench_t < 0.0:
		_bench_t = 0.0
		var i := 0
		for p in range(2):
			for uid in main.ctrl.get_view(0).players[p].creature_uids:
				var b: CreatureBall = main._spawn_ball(uid)
				b.freeze_at(main.arena.slot_position(i) + Vector3(0, main.BALL_Y + 0.02, 0))
				b.face_toward(b.global_position + Vector3(0, 0, -1.0 if p == 0 else 1.0))
				b.open_animated()
				i += 1
		main.setup_panel.hide_panel()
		return false
	_bench_t += dt / 1000.0
	var shot := int(_bench_t / BENCH_SHOT)
	if shot != _bench_shot:
		if _bench_shot >= 0:
			_stop_measure()
			_bench_res.append([_n, _gpu_ms])  # накопленные (кадры, мс GPU) — по разности считается ракурс
		if shot >= 3:
			_report()
			quit(0)
			return false
		_bench_shot = shot
		var cam: CameraRig = main.cam
		var b4: CreatureBall = main.balls.values()[4]
		match shot:
			0:
				cam.snap_overview()
			1:
				cam.battle_view(main.arena.slot_position(4), b4.figure_height())
			2:
				cam.close_up(b4.global_position, Vector3(0, 0, -1), b4.figure_height(), b4.figure_size())
	var in_shot := _bench_t - shot * BENCH_SHOT
	if in_shot > 2.0 and not _measuring:
		_start_measure()
	if _measuring:
		_ft.append(dt)
		var vrid := root.get_viewport_rid()
		_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
		_rcpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
		_draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_n += 1
	return false


## Первый матч — как в autoplay; следующие — через main._on_restart() (reload_current_scene, как кнопка «ещё раз»).
func _new_match() -> void:
	_switching = true
	_stop_measure()
	if main == null:
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
	else:
		var old: Node = main
		main = null
		old._on_restart()
		await process_frame
		await process_frame
		main = current_scene
	bot = AIPlayer.new(0, 12345 + done)
	match_frames = 0
	await process_frame
	if opts["mode"] == "bench":
		# одни и те же команды и колоды — сравнимые замеры
		main.rng.seed = 777
		main.team_menu._rng.seed = 777
	main.team_menu.pick_random_and_start()
	await process_frame
	main.ctrl.creature_returned.connect(func(uid, reason): _ret(uid, reason))
	main.ctrl.creature_stood.connect(func(uid, slot): _land(uid, true))
	main.ctrl.battle_started.connect(func(s, a, d): battles += 1; _land(a, true))
	_t_match = 0.0
	_switching = false


func _process(d: float) -> bool:
	if opts["mode"] == "bench":
		return _bench(d)
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	if _switching or main == null or not is_instance_valid(main):
		return false
	_t_match += dt / 1000.0
	if not _measuring and _t_match >= WARMUP and not main._game_over:
		_start_measure()
	if _measuring:
		_ft.append(dt)
		var vrid := root.get_viewport_rid()
		_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
		_rcpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
		_draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_n += 1
		_win_t += dt
		_win_frames += 1
		if _win_t >= 1000.0:
			# TIME_PROCESS/TIME_PHYSICS_PROCESS — максимум за последнюю секунду (так их обновляет движок)
			_proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			_win_fps.append(_win_frames * 1000.0 / _win_t)
			_win_t = 0.0
			_win_frames = 0
	var secs := float(opts["secs"])
	if main._game_over or (secs > 0.0 and _t_match > secs + WARMUP):
		_stop_measure()
		_mem_rows.append(_mem_snapshot())
		print("MEM матч %d: %s" % [done + 1, str(_mem_rows[-1])])
		done += 1
		print("Матч %d: победитель %d, ход %d, захваты %s" % [done, main.ctrl.winner, main.ctrl.get_turn(), str(main.captures)])
		if done >= int(opts["matches"]):
			_report(); quit(0); return false
		_new_match()
		return false
	if opts.get("profile", "") == "1" and _measuring and _n % 600 == 300:
		_print_timestamps()
	if _t_match < 900.0:
		match_frames = 0  # проверка зависания autoplay считает кадры, а при сотнях fps это меньше минуты
	return super._process(d)


func _start_measure() -> void:
	_measuring = true
	_cpu0 = _cpu_ticks()
	_cpu_t0 = Time.get_ticks_usec()


var _cpu_acc := Vector2.ZERO  # накоплено (основной поток, процесс), % × секунд
var _cpu_secs := 0.0


func _stop_measure() -> void:
	if not _measuring:
		return
	_measuring = false
	var c := _cpu_ticks()
	var wall := (Time.get_ticks_usec() - _cpu_t0) / 1e6
	_cpu_acc += Vector2(c.x - _cpu0.x, c.y - _cpu0.y) / 100.0  # тики по 10 мс → секунды CPU
	_cpu_secs += wall


## utime+stime основного потока и всего процесса (тики USER_HZ = 100).
func _cpu_ticks() -> Vector2i:
	var pid := OS.get_process_id()
	return Vector2i(_stat_ticks("/proc/%d/task/%d/stat" % [pid, pid]), _stat_ticks("/proc/%d/stat" % pid))


## Файлы /proc имеют нулевой размер — FileAccess их не читает, берём через cat.
func _read_proc(path: String) -> String:
	var out := []
	OS.execute("cat", [path], out)
	return str(out[0]) if out.size() > 0 else ""


func _stat_ticks(path: String) -> int:
	var s := _read_proc(path)
	if s == "":
		return 0
	var parts := s.substr(s.rfind(")") + 2).split(" ")
	return int(parts[11]) + int(parts[12])  # поля 14 и 15 (utime, stime)


func _status_kb(key: String) -> int:
	for line in _read_proc("/proc/%d/status" % OS.get_process_id()).split("\n"):
		if line.begins_with(key + ":"):
			return int(line.split(":")[1].strip_edges().split(" ")[0])
	return 0


func _nvidia_mib() -> int:
	var out := []
	if OS.execute("nvidia-smi", ["--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits"], out) != 0:
		return -1
	for line in str(out[0] if out.size() > 0 else "").split("\n"):
		var p := line.split(",")
		if p.size() == 2 and int(p[0]) == OS.get_process_id():
			return int(p[1])
	return -1


func _mem_snapshot() -> Dictionary:
	return {
		"rss_mb": _status_kb("VmRSS") / 1024, "hwm_mb": _status_kb("VmHWM") / 1024,
		"anon_mb": _status_kb("RssAnon") / 1024, "file_mb": _status_kb("RssFile") / 1024, "shmem_mb": _status_kb("RssShmem") / 1024,
		"static_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"vmem_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"tex_mb": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		"nvsmi_mb": _nvidia_mib(),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}


func _report() -> void:
	super._report()
	var sorted := _ft.duplicate()
	sorted.sort()
	var n: int = maxi(1, sorted.size())
	var total := 0.0
	for x in _ft:
		total += x
	var avg_fps := 1000.0 * _ft.size() / maxf(total, 0.001)
	var p99: float = sorted[mini(n - 1, int(n * 0.99))] if sorted.size() > 0 else 0.0
	var worst: float = sorted[n - 1] if sorted.size() > 0 else 0.0
	var min_win := 0.0
	if _win_fps.size() > 0:
		var w := _win_fps.duplicate()
		w.sort()
		min_win = w[0]
	var r3d := Vector2(DisplayServer.window_get_size()) * root.scaling_3d_scale
	var cpu_main := 100.0 * _cpu_acc.x / maxf(_cpu_secs, 0.001)
	var cpu_proc := 100.0 * _cpu_acc.y / maxf(_cpu_secs, 0.001)
	var last: Dictionary = _mem_rows[-1] if not _mem_rows.is_empty() else {}
	var line := "PERF mode=%s q=%s%s 3d=%dx%d fps_avg=%.0f fps_min1s=%.0f p99_ms=%.2f worst_ms=%.1f gpu_ms=%.2f rcpu_ms=%.2f procmax_ms=%.2f physmax_ms=%.2f draws=%.0f prims=%.0fk cpu_main=%.0f%% cpu_proc=%.0f%% rss=%s hwm=%s vram=%s nvsmi=%s" % [
		opts["mode"], GraphicsSettings.level_name(GraphicsSettings.level), str(GraphicsSettings.overrides) if not GraphicsSettings.overrides.is_empty() else "", int(r3d.x), int(r3d.y), avg_fps, min_win, p99, worst,
		_gpu_ms / maxf(_n, 1), _rcpu_ms / maxf(_n, 1),
		_proc_ms / maxf(_win_fps.size(), 1), _phys_ms / maxf(_win_fps.size(), 1), _draw / maxf(_n, 1), _prims / maxf(_n, 1) / 1000.0,
		cpu_main, cpu_proc, last.get("rss_mb", "?"), last.get("hwm_mb", "?"), last.get("vmem_mb", "?"), last.get("nvsmi_mb", "?")]
	if not _bench_res.is_empty():
		line += " gpu_shots="
		var prev := [0, 0.0]
		for r in _bench_res:
			line += "%.2f/" % ((r[1] - prev[1]) / maxf(r[0] - prev[0], 1))
			prev = r
	print(line)
	var rss_line := "MEMROW rss по матчам: "
	for m in _mem_rows:
		rss_line += "%s/%s/%s " % [m["rss_mb"], m["vmem_mb"], m["resources"]]
	print(rss_line, "(RSS МБ / видео МБ / ресурсов)")
	if opts["out"] != "":
		var f := FileAccess.open(opts["out"], FileAccess.READ_WRITE if FileAccess.file_exists(opts["out"]) else FileAccess.WRITE)
		f.seek_end()
		f.store_line(line + " | " + rss_line)


## profile=1: разбивка кадра GPU по проходам рендера (метки RenderingDevice, мс).
func _print_timestamps() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var n := rd.get_captured_timestamps_count()
	var line := "GPU по проходам:"
	for i in range(1, n):
		var dt := (rd.get_captured_timestamp_gpu_time(i) - rd.get_captured_timestamp_gpu_time(i - 1)) / 1000.0
		if dt > 0.05:
			line += " %s=%.2f" % [rd.get_captured_timestamp_name(i), dt / 1000.0]
	print(line)
