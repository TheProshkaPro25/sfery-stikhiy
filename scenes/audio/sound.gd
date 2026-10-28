class_name SoundFx
extends Node
## Звук: эффекты, крики существ, музыка, шины громкости. Один экземпляр в корне дерева: SoundFx.i().
## Файлы: assets/audio/sfx/<имя>.wav, assets/audio/creatures/<имя>_<appear|attack>.wav, assets/audio/music/*.ogg.

const SFX_DIR := "res://assets/audio/sfx/"
const CREATURE_DIR := "res://assets/audio/creatures/"
const MUSIC_BATTLE := "res://assets/audio/music/battle.ogg"
const POOL := 14
const MUSIC_DB := -9.0
const SFX_DB := -2.0

var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _roll: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_tw: Tween
var _last_play: Dictionary = {}   # имя -> время, чтобы одинаковые звуки не накладывались кашей
var music_muted := false

static var _inst: SoundFx


## Единственный экземпляр (создаётся при первом обращении и живёт в корне, переживая перезагрузку сцены).
static func i() -> SoundFx:
	if _inst == null or not is_instance_valid(_inst):
		_inst = SoundFx.new()
		_inst.name = "SoundFx"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music", MUSIC_DB)
	_ensure_bus("SFX", SFX_DB)
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_roll = AudioStreamPlayer.new()
	_roll.bus = "SFX"
	_roll.volume_db = -60.0
	add_child(_roll)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	(Engine.get_main_loop() as SceneTree).node_added.connect(_on_node_added)


## Выход из игры: останавливаем плееры и отпускаем звуки, иначе при закрытии остаются
## «resources still in use» / «ObjectDB instances leaked» (воспроизведения ещё держат потоки).
func _exit_tree() -> void:
	for p in _pool + [_roll, _music]:
		p.stop()
		p.stream = null
	_cache.clear()


func _ensure_bus(bus_name: String, db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, db)


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s


func _play_stream(s: AudioStream, db: float, pitch: float) -> void:
	if s == null:
		return
	if not is_inside_tree():
		# экземпляр только что создан и ещё не добавлен в корень (add_child отложен) — играем на следующем кадре
		_play_stream.call_deferred(s, db, pitch)
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## Короткий эффект. jitter - случайный разброс высоты (доля).
func play(sfx_name: String, db: float = 0.0, jitter: float = 0.04, pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sfx_name, -1000)) < 40:
		return
	_last_play[sfx_name] = now
	_play_stream(_load(SFX_DIR + sfx_name + ".wav"), db, pitch * (1.0 + randf_range(-jitter, jitter)))


## Отложенный эффект (не блокирует вызывающего).
func play_later(sfx_name: String, delay: float, db: float = 0.0) -> void:
	(Engine.get_main_loop() as SceneTree).create_timer(delay).timeout.connect(play.bind(sfx_name, db))


## Крик существа: kind = "appear" | "attack".
func cry(creature_id: StringName, kind: String = "appear", delay: float = 0.0, db: float = -1.0) -> void:
	var short := String(creature_id).trim_prefix("creature_")
	var s := _load(CREATURE_DIR + "%s_%s.wav" % [short, kind])
	if delay <= 0.0:
		_play_stream(s, db, randf_range(0.97, 1.03))
	else:
		(Engine.get_main_loop() as SceneTree).create_timer(delay).timeout.connect(_play_stream.bind(s, db, 1.0))


## Удар шара о борт/стол; strength - скорость удара (м/с).
func bounce(strength: float) -> void:
	if strength < 1.2 * Arena.WORLD:
		return
	var db := linear_to_db(clampf(strength / (9.0 * Arena.WORLD), 0.08, 1.0)) - 2.0
	play("ball_bounce_%d" % randi_range(1, 3), db, 0.08)


## Качение шара: громкость от скорости, 0 - тишина.
func set_roll(speed: float) -> void:
	if _roll.stream == null:
		var s := _load(SFX_DIR + "ball_roll_loop.wav") as AudioStreamWAV
		if s == null:
			return
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		_roll.stream = s
	var v := clampf(speed / (7.0 * Arena.WORLD), 0.0, 1.0)
	if v < 0.03:
		if _roll.playing:
			_roll.stop()
		return
	if not _roll.playing and is_inside_tree():
		_roll.play()
	_roll.volume_db = linear_to_db(v) - 8.0
	_roll.pitch_scale = 0.8 + 0.5 * v


# ---------------------------------------------------------------- музыка

func play_music(path: String = MUSIC_BATTLE, fade: float = 1.5) -> void:
	var s := _load(path)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.volume_db = -40.0
	if is_inside_tree():
		_music.play()
	else:
		_music.play.call_deferred()
	_fade_music(0.0 if not music_muted else -80.0, fade)


func stop_music(fade: float = 1.2) -> void:
	if not _music.playing:
		return
	_fade_music(-60.0, fade, true)


## Приглушить музыку на время джингла.
func duck_music(db: float = -14.0, fade: float = 0.4) -> void:
	_fade_music(db, fade)


func _fade_music(db: float, fade: float, stop_after: bool = false) -> void:
	if _music_tw != null:
		_music_tw.kill()
	_music_tw = create_tween()
	_music_tw.tween_property(_music, "volume_db", db, fade)
	if stop_after:
		_music_tw.tween_callback(_music.stop)


func toggle_music_mute() -> void:
	music_muted = not music_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_M:
				toggle_music_mute()


# ---------------------------------------------------------------- кнопки интерфейса

func _on_node_added(n: Node) -> void:
	if n is CardView:
		var cv := n as CardView
		if not cv.mouse_entered.is_connected(_ui_hover):
			cv.mouse_entered.connect(_ui_hover.bind(cv))
			cv.pressed.connect(func() -> void: play("card_select", -3.0))
	elif n is BaseButton:
		var b := n as BaseButton
		if not b.pressed.is_connected(_ui_click):
			b.pressed.connect(_ui_click)
			b.mouse_entered.connect(_ui_hover.bind(b))


func _ui_click() -> void:
	play("ui_click", -4.0)


func _ui_hover(b: BaseButton) -> void:
	if not b.disabled:
		play("ui_hover", -10.0, 0.06)
