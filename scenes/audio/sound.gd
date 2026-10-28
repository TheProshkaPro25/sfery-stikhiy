class_name SoundFx
extends Node
## Звук: эффекты, крики существ, музыка, шины громкости. Один экземпляр в корне дерева: SoundFx.i().
## Файлы: assets/audio/sfx/<имя>.ogg, assets/audio/creatures/<вид>_<стихия>_<appear|attack>.ogg,
## assets/audio/music/*.ogg. Записанные звуки собирает tools/audio/build_sfx.py (источники и лицензии — CREDITS.md);
## если .ogg нет, берётся .wav с тем же именем (старые синтезированные файлы tools/audio/gen_sfx.py).

const SFX_DIR := "res://assets/audio/sfx/"
const CREATURE_DIR := "res://assets/audio/creatures/"
## Музыка (Suno → tools/audio/prep_music.py: петля, −23 LUFS). Ходы матча — battle.ogg, пока его нет — team.ogg.
const MUSIC_MENU := "res://assets/audio/music/menu.ogg"
const MUSIC_TEAM := "res://assets/audio/music/team.ogg"
const MUSIC_BATTLE := "res://assets/audio/music/battle.ogg"
const MUSIC_CLASH := "res://assets/audio/music/battle_clash.ogg"
const MUSIC_XFADE := 2.5
const POOL := 14
const MUSIC_DB := -9.0
const SFX_DB := -2.0
## Все короткие эффекты (имена файлов без расширения) — для прогрева кэша и стенда tools/audio/play_all.gd.
const SFX_NAMES: Array[String] = [
	"ui_hover", "ui_click", "card_select", "card_place", "card_flip", "card_capture", "turn_start",
	"ball_throw", "ball_bounce_1", "ball_bounce_2", "ball_bounce_3", "ball_roll_loop", "ball_land", "capsule_open",
	"battle_start", "clash", "power_up", "power_down", "miss", "eliminated", "vanish",
	"battle_win", "battle_lose", "victory", "defeat", "gate_trap",
	"ability_play", "ability_cancel", "ability_fusion",
	"ability_fire", "ability_gale", "ability_light", "ability_stone", "ability_shadow", "ability_tide",
]
## Суффиксы стихий по Attr.A (как GameData.ATTR_KEYS): имя способности и файлов криков.
const ATTR_KEYS: Array[String] = ["fire", "gale", "light", "stone", "shadow", "tide"]

var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _roll: AudioStreamPlayer
var _mus: Array[AudioStreamPlayer] = []  # два плеера: текущий и следующий — для кроссфейда
var _mus_cur := 0
var _mus_path := ""
var _mus_resume: Dictionary = {}           # путь -> позиция: вернувшись к треку, играем дальше, а не сначала
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
	for _k in range(2):
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_mus.append(m)
	(Engine.get_main_loop() as SceneTree).node_added.connect(_on_node_added)


## Прогрев кэша коротких эффектов: первый звук броска/удара не ждёт загрузки с диска.
func _ready() -> void:
	for n in SFX_NAMES:
		_load(SFX_DIR + n)


## Выход из игры: останавливаем плееры и отпускаем звуки, иначе при закрытии остаются
## «resources still in use» / «ObjectDB instances leaked» (воспроизведения ещё держат потоки).
func _exit_tree() -> void:
	for p in _pool + [_roll] + _mus:
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


## path без расширения: сначала .ogg (записанные), затем .wav (синтезированные).
func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(path + ext):
			s = load(path + ext)
			break
	_cache[path] = s
	return s


## Есть ли файл эффекта (для стенда и проверок).
func has_sfx(sfx_name: String) -> bool:
	return _load(SFX_DIR + sfx_name) != null


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
	_play_stream(_load(SFX_DIR + sfx_name), db, pitch * (1.0 + randf_range(-jitter, jitter)))


## Отложенный эффект (не блокирует вызывающего).
func play_later(sfx_name: String, delay: float, db: float = 0.0) -> void:
	(Engine.get_main_loop() as SceneTree).create_timer(delay).timeout.connect(play.bind(sfx_name, db))


## Крик существа: kind = "appear" | "attack".
func cry(creature_id: StringName, kind: String = "appear", delay: float = 0.0, db: float = -1.0) -> void:
	var short := String(creature_id).trim_prefix("creature_")
	var s := _load(CREATURE_DIR + "%s_%s" % [short, kind])
	if delay <= 0.0:
		_play_stream(s, db, randf_range(0.97, 1.03))
	else:
		(Engine.get_main_loop() as SceneTree).create_timer(delay).timeout.connect(_play_stream.bind(s, db, 1.0))


## Способность: звук по стихии карты (params.lock — стихия-замок) или слиянию, иначе общий.
func ability(card: CardDef, cancelled: bool = false, db: float = 0.0) -> void:
	play(ability_sfx(card, cancelled), db)


static func ability_sfx(card: CardDef, cancelled: bool = false) -> String:
	if cancelled:
		return "ability_cancel"
	if card != null:
		var lock: int = int(card.params.get("lock", -1))
		if lock >= 0 and lock < ATTR_KEYS.size():
			return "ability_" + ATTR_KEYS[lock]
		if card.params.get("fusion", false):
			return "ability_fusion"
	return "ability_play"


## Удар шара о борт/стол; strength - скорость удара (м/с).
func bounce(strength: float) -> void:
	if strength < 1.2 * Arena.WORLD:
		return
	var db := linear_to_db(clampf(strength / (9.0 * Arena.WORLD), 0.08, 1.0)) - 2.0
	play("ball_bounce_%d" % randi_range(1, 3), db, 0.08)


## Качение шара: громкость от скорости, 0 - тишина.
func set_roll(speed: float) -> void:
	if _roll.stream == null:
		var src := _load(SFX_DIR + "ball_roll_loop")
		if src == null:
			return
		var s: AudioStream = src.duplicate()
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
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

## Музыка ходов матча: battle.ogg, если трек есть, иначе музыка выбора команды.
func turn_music() -> String:
	return MUSIC_BATTLE if ResourceLoader.exists(MUSIC_BATTLE) or FileAccess.file_exists(MUSIC_BATTLE) else MUSIC_TEAM


## Плавный переход на трек: старый гаснет, новый нарастает (равная мощность), без обрыва.
## resume — продолжить трек с места, где он прервался (музыка хода после боя).
func play_music(path: String, fade: float = MUSIC_XFADE, resume: bool = true) -> void:
	var cur := _mus[_mus_cur]
	if path == _mus_path and cur.playing:
		_fade_to(cur, null, fade)  # тот же трек: только снять приглушение
		return
	var s := _load(path.get_basename())
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if _mus_path != "" and cur.playing:
		_mus_resume[_mus_path] = cur.get_playback_position()
	var nxt := _mus[1 - _mus_cur]
	nxt.stop()
	nxt.stream = s
	nxt.volume_db = -80.0
	var at := 0.0
	if resume and _mus_resume.has(path):
		at = fmod(float(_mus_resume[path]), maxf(s.get_length(), 1.0))
	if nxt.is_inside_tree():
		nxt.play(at)
	else:
		nxt.play.call_deferred(at)
	_mus_cur = 1 - _mus_cur
	_mus_path = path
	_fade_to(nxt, cur if cur.playing else null, fade)


func stop_music(fade: float = 1.2) -> void:
	var cur := _mus[_mus_cur]
	if _mus_path != "" and cur.playing:
		_mus_resume[_mus_path] = cur.get_playback_position()
	_mus_path = ""
	_fade_to(null, cur if cur.playing else null, fade)


## Приглушить музыку на время джингла/важного звука (вернуть — play_music того же трека).
func duck_music(db: float = -14.0, fade: float = 0.4) -> void:
	if _music_tw != null:
		_music_tw.kill()
	_music_tw = create_tween()
	_music_tw.tween_property(_mus[_mus_cur], "volume_db", db, fade)


## Кроссфейд равной мощности: incoming 0→1, outgoing 1→0 по амплитуде; outgoing после — стоп.
func _fade_to(incoming: AudioStreamPlayer, outgoing: AudioStreamPlayer, fade: float) -> void:
	if _music_tw != null:
		_music_tw.kill()
	var in0 := db_to_linear(incoming.volume_db) if incoming != null else 0.0
	var out0 := db_to_linear(outgoing.volume_db) if outgoing != null else 0.0
	_music_tw = create_tween()
	_music_tw.tween_method(func(t: float) -> void:
		if incoming != null:
			incoming.volume_db = linear_to_db(maxf(lerpf(in0, 1.0, sin(t * PI / 2.0)), 0.0001))
		if outgoing != null:
			outgoing.volume_db = linear_to_db(maxf(out0 * cos(t * PI / 2.0), 0.0001)),
		0.0, 1.0, maxf(fade, 0.05))
	if outgoing != null:
		_music_tw.tween_callback(outgoing.stop)


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
