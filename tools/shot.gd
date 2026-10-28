extends "res://tools/autoplay.gd"
## Автоигра в окне с сохранением кадров: godot -s res://tools/shot.gd -- <папка>

var out_dir := "user://shots"
var shot_n := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	super._initialize()
	Engine.time_scale = 2.0

func _process(d: float) -> bool:
	if frames % 30 == 0 and frames > 0:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/s%d.png" % [out_dir, frames])
		shot_n += 1
	if frames > 2400:
		quit(0)
		return false
	return super._process(d)
