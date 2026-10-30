extends SceneTree
## Review poses must not depend on preceding idle/action exports.
## Optional: -- source-dir=tools/_tmp/repair035-light/candidate-v1
const ReviewState := preload("res://tools/model_review_state.gd")
const STEP := 1.0 / 60.0
const EPSILON := 0.00001
var failures := 0
var checks := 0
var largest_error := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func begin_action(actor: CreatureAnim, action: String) -> void:
	match action:
		"appear": actor.appear()
		"attack": actor.lunge(actor.get_height() * 0.22)

func sample(id: StringName, history: String, action: String, frames: int) -> Dictionary:
	var actor := CreatureAnim.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_model(CreatureModels.build(CardDB.creature(id)), CardDB.creature(id))
	actor.idle_on = true
	actor._phase = 0
	ReviewState.reset_actor(actor)
	if not history.is_empty():
		begin_action(actor, history)
		for frame in range(120 if history == "idle" else 40):
			actor._process(STEP)
	var prior_stance: float = actor._support.stance_extra
	ReviewState.reset_actor(actor)
	begin_action(actor, action)
	for frame in range(frames):
		actor._process(STEP)
	var skeleton: Skeleton3D = actor._support.skeleton
	var result := {"poses": [], "names": [], "transform": actor.global_transform,
		"stance": actor._support.stance_extra, "prior_stance": prior_stance}
	for bone in range(skeleton.get_bone_count()):
		result.poses.append(skeleton.get_bone_global_pose(bone))
		result.names.append(skeleton.get_bone_name(bone))
	actor.free()
	return result

func transform_error(a: Transform3D, b: Transform3D) -> float:
	if not a.is_finite() or not b.is_finite(): return INF
	var error := a.origin.distance_to(b.origin)
	for axis in range(3):
		error = maxf(error, (a.basis[axis] - b.basis[axis]).length())
	return error

func compare(fresh: Dictionary, reused: Dictionary, label: String) -> void:
	check(fresh.names == reused.names, label + ": same skeleton")
	if fresh.names != reused.names: return
	var error := transform_error(fresh.transform, reused.transform)
	var worst := "actor transform"
	for bone in range(fresh.poses.size()):
		var difference := transform_error(fresh.poses[bone], reused.poses[bone])
		if difference > error:
			error = difference
			worst = fresh.names[bone]
	largest_error = maxf(largest_error, error)
	check(error <= EPSILON, "%s: pose differs at %s by %.9f" % [label, worst, error])
	check(is_finite(reused.stance) and absf(fresh.stance - reused.stance) <= EPSILON,
		label + ": same calibrated stance")

func load_light_candidate(source_dir: String) -> bool:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := source_dir.path_join("rogozhuk_light.glb")
	var error := document.append_from_file(path, state)
	check(error == OK, "Load Light candidate: " + path)
	if error != OK: return false
	var original := document.generate_scene(state)
	check(original != null, "Generate Light candidate scene")
	if original == null: return false
	var packed := PackedScene.new()
	error = packed.pack(original)
	original.free()
	check(error == OK, "Pack Light candidate")
	if error != OK: return false
	CreatureModels._scenes["hd:rogozhuk_light"] = packed
	return true

func run() -> void:
	CardDB.load_all()
	var source_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("source-dir="): source_dir = arg.trim_prefix("source-dir=")
	for id in [&"creature_rogozhuk_stone", &"creature_rogozhuk_light",
			&"creature_levian_light", &"creature_kolossar_stone"]:
		if id == &"creature_rogozhuk_light" and not source_dir.is_empty():
			if not load_light_candidate(source_dir):
				quit(1)
				return
		for action in ["appear", "attack"]:
			for frame in [0, 8 if action == "appear" else 20]:
				var fresh := sample(id, "", action, frame)
				for history in ["idle", "attack"]:
					var reused := sample(id, history, action, frame)
					var label := "%s %s%d after %s" % [id, action, frame, history]
					compare(fresh, reused, label)
					if id == &"creature_kolossar_stone" and history == "idle":
						check(reused.prior_stance > EPSILON, label + ": history exercised stance calibration")
		CreatureModels.clear()
		print("REVIEW STATE ", id, " checked")
		await process_frame
	print("Review state: checks=%d failures=%d max_pose_error=%.9f" % [checks, failures, largest_error])
	quit(1 if failures else 0)
