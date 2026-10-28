extends SceneTree
## Витрина всех карт (ворота и способности): godot -s res://tools/card_gallery.gd -- <файл.png>

func _initialize() -> void:
	var out := "user://cards.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	Engine.max_fps = 60
	root.size = Vector2i(1500, 1060)
	CardDB.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.13)
	bg.size = Vector2(1500, 1060)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 13
	grid.position = Vector2(14, 14)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		grid.add_child(CardView.new().for_card(CardDB.card(id), Vector2(104, 146)))
	var small := HBoxContainer.new()
	small.position = Vector2(14, 0)
	for _i in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
