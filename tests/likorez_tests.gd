extends SceneTree
## Textured model, all six independent limb chains and the battle animation contract.
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 CardDB.load_all()
 var definition := CardDB.creature(CardDB.RARE_SHADOW_ID)
 check(definition != null, "Ликорез зарегистрирован")
 CreatureModels.preload_match([definition])
 var model := CreatureModels.build(definition)
 var actor := CreatureAnim.new()
 root.add_child(actor)
 actor.set_process(false)
 actor.set_model(model, definition)
 var sk: Skeleton3D
 var mesh: MeshInstance3D
 var nodes: Array[Node] = [model]
 while not nodes.is_empty():
  var node: Node = nodes.pop_back()
  for child in node.get_children(): nodes.append(child)
  if node is Skeleton3D: sk = node
  if node is MeshInstance3D and node.skin != null: mesh = node
 check(sk != null and mesh != null, "Настоящая текстурированная сетка со скелетом")
 if sk == null or mesh == null: quit(1); return
 var player := actor._player
 for clip in ["idle", "attack", "hit", "roar", "stance"]:
  check(player.has_animation(clip), "Клип: " + clip)
 var limbs: Array[int] = []
 for row in range(3):
  for side in ["L", "R"]:
   for part in ["arm", "forearm", "hand", "blade"]:
    var name := "%s%d.%s" % [part, row, side]
    var index := sk.find_bone(name)
    check(index >= 0, "Отдельный сустав: " + name)
    if part == "arm": limbs.append(index)
 for side in ["L", "R"]:
  limbs.append(sk.find_bone("thigh." + side))
  limbs.append(sk.find_bone("shin." + side))
 var material := mesh.get_surface_override_material(0) as ShaderMaterial
 check(material != null and material.get_shader_parameter("color_map") != null, "Цветовая текстура и общий аниме-шейдер")
 var arrays := mesh.mesh.surface_get_arrays(0)
 var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
 check(verts.size() > 30000, "Детальная сетка, больше 30 тысяч вершин")
 check(not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty(), "Сохранены UV")
 var influence: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
 var stride: int = weights.size() / verts.size()
 var used := {}
 for v in range(0, verts.size(), 7):
  var sum := 0.0
  for k in range(stride):
   var w := weights[v*stride+k]
   sum += w
   if w > 0.1:
    var slot := influence[v*stride+k]
    used[String(mesh.skin.get_bind_name(slot))] = true
  if absf(sum - 1.0) > 0.001:
   check(false, "Ненормализованные веса")
   break
 for row in range(3):
  for side in ["L", "R"]:
   check(used.has("blade%d.%s" % [row, side]), "Каждый клинок имеет собственную привязку")
 for clip in ["idle", "attack"]:
  player.play(clip, 0)
  player.advance(0)
  var start := []
  var motion := []
  for bone in limbs:
   start.append(sk.get_bone_pose_rotation(bone))
   motion.append(0.0)
  for sample in range(49):
   player.seek(sample/48.0 * player.get_animation(clip).length, true)
   for i in range(limbs.size()):
    motion[i] = maxf(motion[i], (start[i] as Quaternion).angle_to(sk.get_bone_pose_rotation(limbs[i])))
  for i in range(limbs.size()):
   check(motion[i] > 0.015, "%s двигает %s" % [clip, sk.get_bone_name(limbs[i])])
 var contacts: Array[Vector3] = []
 actor.strike_contact.connect(func() -> void: contacts.append(actor.fx_pos))
 for fps in [30, 60, 120]:
  actor.reset()
  var before := contacts.size()
  actor.lunge(actor.get_height() * 0.2)
  for frame in range(fps*3): actor._process(1.0/float(fps))
  check(contacts.size() == before+1, "Один контакт при %d FPS" % fps)
  check(actor._action == &"" and actor.fx_pos.is_equal_approx(Vector3.ZERO), "Возврат в idle при %d FPS" % fps)
 check(contacts.size() == 3 and contacts[0].distance_to(contacts[2]) < 0.001, "Контакт не зависит от FPS")
 actor.free()
 CreatureModels.clear()
 print("Ликорез: %d проверок, %d ошибок" % [checks, failures])
 quit(1 if failures else 0)
