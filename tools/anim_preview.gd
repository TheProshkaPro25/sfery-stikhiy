extends SceneTree
## Стенд скелетных анимаций существа: godot -s res://tools/anim_preview.gd -- <id существа> <папка>
## Ставит модель с CreatureAnim, по очереди играет idle → roar → attack → hit и сохраняет кадры каждые 6 тиков.

var _anim: CreatureAnim
var _out := "/tmp"
var _frame := 0
const PLAN := {30: "roar", 110: "attack", 180: "hit"}
const END := 260


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[0]) if args.size() > 0 else &"creature_dragnar_fire"
	_out = args[1] if args.size() > 1 else _out
	CardDB.load_all()
	var d: CreatureDef = CardDB.creature(id)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.16, 0.2)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	_anim = CreatureAnim.new()
	world.add_child(_anim)
	var model := CreatureModels.build(d)
	_anim.set_model(model, d)
	_anim.idle_on = true
	var h: float = float(model.get_meta("height", 1.5))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(h * 1.3, h * 0.6, h * 1.9), Vector3(0, h * 0.45, 0))


func _process(_delta: float) -> bool:
	_frame += 1
	if PLAN.has(_frame):
		match PLAN[_frame]:
			"roar": _anim.roar()
			"attack": _anim.lunge(0.0)
			"hit": _anim.hit(Color.ORANGE, 0.0)
	if _frame % 6 == 0:
		root.get_viewport().get_texture().get_image().save_png("%s/a%03d.png" % [_out, _frame])
	return _frame > END
