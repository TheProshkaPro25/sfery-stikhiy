extends SceneTree
## Витрина всех карт способностей: godot -s res://tools/card_gallery.gd -- <файл.png>

func _initialize() -> void:
	var out := "user://cards.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	root.size = Vector2i(1280, 940)
	CardDB.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.13)
	bg.size = Vector2(1280, 940)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(14, 14)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	for id in CardDB.ability_ids():
		grid.add_child(CardView.new().for_card(CardDB.card(id), Vector2(148, 207)))
	for id in [&"arena_field_fire", &"arena_trap"]:
		grid.add_child(CardView.new().for_card(CardDB.card(id), Vector2(148, 207)))
	var small := HBoxContainer.new()
	small.position = Vector2(14, 0)
	for _i in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
