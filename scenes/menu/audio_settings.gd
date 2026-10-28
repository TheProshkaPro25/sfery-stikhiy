class_name AudioSettings
extends RefCounted
## Громкость эффектов и музыки (0..1) поверх базовых уровней шин SoundFx (SFX_DB, MUSIC_DB).
## Хранится в user://settings.cfg, раздел [audio]; применяется при запуске главного меню и сразу при смене.

const SECTION := "audio"

static var sfx := -1.0
static var music := -1.0


static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.PATH)
	sfx = clampf(float(cfg.get_value(SECTION, "sfx", 1.0)), 0.0, 1.0)
	music = clampf(float(cfg.get_value(SECTION, "music", 1.0)), 0.0, 1.0)
	apply()


static func apply() -> void:
	_set_bus("SFX", SoundFx.SFX_DB, sfx)
	_set_bus("Music", SoundFx.MUSIC_DB, music)


static func set_volume(bus_name: String, v: float) -> void:
	if bus_name == "SFX":
		sfx = clampf(v, 0.0, 1.0)
	else:
		music = clampf(v, 0.0, 1.0)
	apply()
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.PATH)  # сохранить раздел [graphics]
	cfg.set_value(SECTION, "sfx", sfx)
	cfg.set_value(SECTION, "music", music)
	cfg.save(GraphicsSettings.PATH)


static func _set_bus(bus_name: String, base_db: float, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0 or v < 0.0:
		return
	AudioServer.set_bus_volume_db(i, base_db + linear_to_db(maxf(v, 0.0001)))
	# музыку SoundFx может глушить клавишей M — тогда её mute не трогаем
	if bus_name == "SFX" or not SoundFx.i().music_muted:
		AudioServer.set_bus_mute(i, v <= 0.001)
