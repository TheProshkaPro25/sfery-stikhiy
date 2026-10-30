extends SceneTree
## Flight support adds motion without destroying the sampled clip or turning claws.
var checks:=0
var failures:=0
func _initialize():call_deferred('run')
func run():
 for d in CardDB.all_creatures():
  var a:=CreatureAnim.new();root.add_child(a);a.set_process(false)
  a.set_model(CreatureModels.build(d),d)
  if not a._flyer:a.free();CreatureModels.clear();continue
  var support=a._support
  a._support=null
  for action in ['idle','appear','roar','attack','hit','brace','ability']:
   support.reset();a.reset();a.idle_on=true
   var first_correction:Quaternion
   var previous_correction:Quaternion
   var max_change:=0.0
   match action:
    'appear':a.appear()
    'roar':a.roar()
    'attack':a.lunge(a.get_height()*.22)
    'hit':a.hit(Color.WHITE,a.get_height()*.075)
    'brace':a.brace()
    'ability':a.ability_pulse()
   for frame in range(90):
    support.restore();a._process(1.0/60)
    var authored:Array[Basis]=[]
    var authored_upper:Array[Basis]=[]
    var authored_lower:Array[Basis]=[]
    var authored_positions:Array[Vector3]=[]
    var authored_local:Array[Transform3D]=[]
    for limb in support.limbs:
     authored.append(support.skeleton.get_bone_global_pose(limb.c).basis.orthonormalized())
     authored_upper.append(support.skeleton.get_bone_global_pose(limb.a).basis.orthonormalized())
     authored_lower.append(support.skeleton.get_bone_global_pose(limb.b).basis.orthonormalized())
     authored_positions.append(support.skeleton.get_bone_global_pose(limb.c).origin)
     authored_local.append(support.skeleton.get_bone_pose(limb.a))
    support.apply(1.0/60)
    for i in range(support.limbs.size()):
     var limb:Dictionary=support.limbs[i]
     var actual:Basis=support.skeleton.get_bone_global_pose(limb.c).basis.orthonormalized()
     checks+=1
     if actual.x.dot(authored[i].x)<.9 or actual.z.dot(authored[i].z)<.9:
      failures+=1;push_error('%s %s frame %d: claws reversed by support'%[d.id,action,frame])
     # A hanging foot follows the shin. Locking it globally introduces an
     # unwanted ankle counter-rotation and collapses the shared skin region.
     var lower:Basis=support.skeleton.get_bone_global_pose(limb.b).basis.orthonormalized()
     var ankle_before:Quaternion=(authored_lower[i].inverse()*authored[i]).get_rotation_quaternion()
     var ankle_after:Quaternion=(lower.inverse()*actual).get_rotation_quaternion()
     checks+=1
     if ankle_before.angle_to(ankle_after)>.005:
      failures+=1;push_error('%s %s frame %d: flight support twisted the ankle'%[d.id,action,frame])
     var foot:Vector3=support.skeleton.get_bone_global_pose(limb.c).origin
     if foot.y > authored_positions[i].y + a.get_height()*.3:
      failures+=1;push_error('%s %s frame %d: foot lifted too far above authored body pose'%[d.id,action,frame])
     if i==0:
      var upper:Basis=support.skeleton.get_bone_global_pose(limb.a).basis.orthonormalized()
      var correction:Quaternion=(upper*authored_upper[i].inverse()).get_rotation_quaternion()
      if frame==0:first_correction=correction
      else:
       max_change=maxf(max_change,first_correction.angle_to(correction))
       if previous_correction.angle_to(correction)>.12:
        failures+=1;push_error('%s %s frame %d: abrupt support rotation'%[d.id,action,frame])
      previous_correction=correction
    support.restore()
    for i in range(support.limbs.size()):
     if not support.skeleton.get_bone_pose(support.limbs[i].a).is_equal_approx(authored_local[i]):
      failures+=1;push_error('%s %s: support did not restore sampled clip'%[d.id,action])
   # Gorgul's sculpt is already tucked: extra support sways the entire leg.
   # Requiring the bird's .2-radian correction buckles its leg skin even
   # though the authored attack is still animated. Keep a nonzero sway floor.
   var attack_min:=.10 if a._species==&'gorgul' else .2
   if not support.limbs.is_empty() and ((action=='idle' and max_change<.025) or (action=='attack' and max_change<attack_min)):
    failures+=1;push_error('%s %s: insufficient flight leg motion (%f)'%[d.id,action,max_change])
  support.reset();a.free();CreatureModels.clear();await process_frame
 print('Flight foot orientation: %d checks, %d failures'%[checks,failures])
 quit(1 if failures else 0)
