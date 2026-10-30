extends SceneTree
## Regression: flight support must not reverse authored foot/claw orientation.
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
    for limb in support.limbs:authored.append(support.skeleton.get_bone_global_pose(limb.c).basis.orthonormalized())
    support.apply(1.0/60)
    for i in range(support.limbs.size()):
     var actual:Basis=support.skeleton.get_bone_global_pose(support.limbs[i].c).basis.orthonormalized()
     checks+=1
     if actual.x.dot(authored[i].x)<.99999 or actual.z.dot(authored[i].z)<.99999:
      failures+=1;push_error('%s %s frame %d: claws reversed by support'%[d.id,action,frame])
  support.reset();a.free();CreatureModels.clear();await process_frame
 print('Flight foot orientation: %d checks, %d failures'%[checks,failures])
 quit(1 if failures else 0)
