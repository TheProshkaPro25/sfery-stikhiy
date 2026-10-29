extends SceneTree
## Полнотелая опора: конечные позиции, подошвы, сохранение длин костей, конечные значения.
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error(message)
func _initialize():call_deferred("run")
func run():
 CardDB.load_all()
 for definition in CardDB.all_creatures():
  var actor := CreatureAnim.new()
  root.add_child(actor);actor.set_process(false)
  actor.set_model(CreatureModels.build(definition),definition);actor.idle_on=true
  var support=actor._support
  check(support != null and support.skeleton != null,"скелет опоры: %s"%definition.id)
  for f in range(50):actor._process(1.0/60.0)
  if not actor._flyer and definition.species != &"levian":
   check(not support.last_ground_errors.is_empty(),"подошвы найдены: %s"%definition.id)
   for error in support.last_ground_errors:
    check(absf(error)<actor.get_height()*0.006,"подошва на полу: %s, отклонение %.4f"%[definition.id,error])
  var initial_rotations: Array[Quaternion] = []
  for limb in support.limbs: initial_rotations.append(support.skeleton.get_bone_pose_rotation(limb.a))
  var leg_motion := 0.0
  var landing_error := 0.0
  actor.lunge(actor.get_height()*.22)
  for f in range(100):
   actor._process(1.0/60.0)
   if actor._action == &"attack" and actor._attack_progress(actor._elapsed)>.75:
    for error in support.last_ground_errors: landing_error=maxf(landing_error,absf(error))
   for l in range(support.limbs.size()):
    leg_motion=maxf(leg_motion,initial_rotations[l].angle_to(support.skeleton.get_bone_pose_rotation(support.limbs[l].a)))
   if f%15==0:
    for limb in support.limbs:
     var a:Transform3D=support.skeleton.get_bone_global_pose(limb.a)
     var b:Transform3D=support.skeleton.get_bone_global_pose(limb.b)
     var c:Transform3D=support.skeleton.get_bone_global_pose(limb.c)
     check(a.origin.is_finite() and b.origin.is_finite() and c.origin.is_finite(),"конечная поза ног: %s"%definition.id)
     var rest_a:Transform3D=support.skeleton.get_bone_global_rest(limb.a)
     var rest_b:Transform3D=support.skeleton.get_bone_global_rest(limb.b)
     check(absf(a.origin.distance_to(b.origin)-rest_a.origin.distance_to(rest_b.origin))<0.001,"бедро не растянуто: %s"%definition.id)
  if not support.limbs.is_empty():check(leg_motion>.03,"ноги участвуют в атаке: %s"%definition.id)
  if not actor._flyer:check(landing_error<actor.get_height()*.006,"после выпада подошвы возвращаются на пол: %s"%definition.id)
  actor.reset();actor.free();CreatureModels.clear()
  await process_frame
 print("Полнотелая опора: 48 моделей, проверок %d, ошибок %d"%[checks,failures])
 quit(1 if failures else 0)
