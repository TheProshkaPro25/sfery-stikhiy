extends RefCounted
## A review pose starts from the same state as a fresh instance, independently
## of preceding screenshots or action exports. This is not a gameplay reset.
static func reset_actor(actor: CreatureAnim) -> void:
	actor._clock = 0
	actor.reset()
	if actor._support != null: actor._support.stance_extra = 0
	var stack: Array[Node] = [actor]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Skeleton3D: node.reset_bone_poses()
	if actor._player != null: actor._player.advance(0)
