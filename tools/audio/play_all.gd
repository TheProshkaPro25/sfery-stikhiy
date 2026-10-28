extends SceneTree
## Стенд звуков: грузит все эффекты SoundFx.SFX_NAMES и крики всех существ (вид × стихия × appear/attack),
## проверяет, что файл есть, это записанный OGG, длительность в разумных пределах. В headless не слышно —
## это проверка сборки tools/audio/build_sfx.py, а не прослушивание.
## Запуск: godot --headless -s res://tools/audio/play_all.gd   (код выхода 1 при ошибках)

const LIMITS := {  # имя -> [мин, макс] секунд; остальным эффектам — DEFAULT_LIMIT
	"ui_hover": [0.03, 0.6], "ui_click": [0.03, 0.6], "ball_roll_loop": [0.8, 6.0],
	"victory": [1.0, 7.0], "defeat": [1.0, 7.0], "battle_start": [0.5, 5.0],
}
const DEFAULT_LIMIT := [0.08, 4.5]
const CRY_LIMIT := [0.4, 4.5]


func _initialize() -> void:
	var errors: Array[String] = []
	var total := 0.0
	var count := 0
	for n in SoundFx.SFX_NAMES:
		var lim: Array = LIMITS.get(n, DEFAULT_LIMIT)
		var len_s := _check(SoundFx.SFX_DIR + n + ".ogg", lim, errors)
		if len_s > 0.0:
			total += len_s
			count += 1
	if not _is_loop_ok(SoundFx.SFX_DIR + "ball_roll_loop.ogg"):
		errors.append("ball_roll_loop: не включается петля")
	for sp in GameData.SPECIES:
		for attr_key in GameData.ATTR_KEYS:
			for kind in ["appear", "attack"]:
				var len_s := _check(SoundFx.CREATURE_DIR + "%s_%s_%s.ogg" % [sp.id, attr_key, kind], CRY_LIMIT, errors)
				if len_s > 0.0:
					total += len_s
					count += 1
	# способности: каждая карта получает существующий звук
	for c in GameData.CARDS:
		if int(c.kind) != 1:
			continue
		var cd := CardDef.new()
		cd.params = c.params
		var sfx := SoundFx.ability_sfx(cd)
		if not ResourceLoader.exists(SoundFx.SFX_DIR + sfx + ".ogg"):
			errors.append("способность %s: нет звука %s" % [c.id, sfx])
	print("Звуков проверено: %d, суммарно %.1f с" % [count, total])
	for e in errors:
		printerr("  ОШИБКА: ", e)
	print("play_all: %s" % ("OK" if errors.is_empty() else "%d ошибок" % errors.size()))
	quit(0 if errors.is_empty() else 1)


func _check(path: String, lim: Array, errors: Array[String]) -> float:
	if not ResourceLoader.exists(path):
		errors.append("нет файла " + path)
		return 0.0
	var s: AudioStream = load(path)
	if s == null:
		errors.append("не загрузился " + path)
		return 0.0
	if not s is AudioStreamOggVorbis:
		errors.append("не OGG: " + path)
	var len_s := s.get_length()
	if len_s < float(lim[0]) or len_s > float(lim[1]):
		errors.append("%s: длительность %.2f с вне [%.2f, %.2f]" % [path.get_file(), len_s, lim[0], lim[1]])
	return len_s


func _is_loop_ok(path: String) -> bool:
	var s = load(path)
	if not s is AudioStreamOggVorbis:
		return false
	var d: AudioStreamOggVorbis = s.duplicate()
	d.loop = true
	return d.loop
