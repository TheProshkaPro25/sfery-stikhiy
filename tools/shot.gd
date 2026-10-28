extends "res://tools/autoplay.gd"
## Автоигра в окне с сохранением кадров: godot -s res://tools/shot.gd -- <папка> [каждые N кадров=30] [скорость=2] [до кадра=2400]

var out_dir := "user://shots"
var shot_n := 0
var every := 30
var last := 2400

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	every = int(args[1]) if args.size() > 1 else every
	last = int(args[3]) if args.size() > 3 else last
	DirAccess.make_dir_recursive_absolute(out_dir)
	super._initialize()
	Engine.time_scale = float(args[2]) if args.size() > 2 else 2.0

func _process(d: float) -> bool:
	if frames % every == 0 and frames > 0:
		RenderingServer.force_draw(false)  # окно может быть скрыто (экран заблокирован) — кадр всё равно рисуем
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/s%05d.png" % [out_dir, frames])
		shot_n += 1
	if frames > last:
		quit(0)
		return false
	return super._process(d)
