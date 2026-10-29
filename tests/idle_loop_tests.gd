extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool, msg:String):
 checks+=1
 if not ok:failures+=1;push_error(msg)
func _initialize():call_deferred('run')
func run():
 for id in [&'creature_dragnar_shadow',&'creature_klykar_fire',&'creature_grifalon_gale',&'creature_kolossar_light',&'creature_rogozhuk_stone',&'creature_levian_tide',&'creature_ratnik_fire',&'creature_gorgul_shadow']:
  var d:=CardDB.creature(id)
  var a:=CreatureAnim.new();root.add_child(a);a.set_process(false)
  a.set_model(CreatureModels.build(d),d);a.idle_on=true
  var clip:=a._player.get_animation(&'idle')
  for track in range(clip.get_track_count()):check(clip.track_get_interpolation_loop_wrap(track),'%s: periodic interpolation'%id)
  for track in range(clip.get_track_count()):
   if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:continue
   var epsilon := clip.length*.001
   var q0:Quaternion = clip.rotation_track_interpolate(track,0)
   var prev:Quaternion = clip.rotation_track_interpolate(track,clip.length-epsilon)
   var next:Quaternion = clip.rotation_track_interpolate(track,epsilon)
   var left:Quaternion = prev.inverse()*q0
   var right:Quaternion = q0.inverse()*next
   if left.w<0:left=-left
   if right.w<0:right=-right
   var lv:=Vector3(left.x,left.y,left.z)*2/epsilon
   var rv:=Vector3(right.x,right.y,right.z)*2/epsilon
   check(lv.distance_to(rv)<.02,'%s: no rotation velocity jump at loop seam, track %d: %.5f'%[id,track,lv.distance_to(rv)])
  var speed:float=a._player.speed_scale
  # AnimationPlayer uses the speed passed to play(), not speed_scale.
  speed=a._tempo*{&'kolossar':.62,&'rogozhuk':.68,&'levian':.7,&'dragnar':.72,&'ratnik':.72,&'klykar':.8}.get(d.species,.85)
  for frame in range(720):a._process(1.0/120)
  var expected:=fposmod(a._clock*speed+a._phase/TAU*clip.length,clip.length)
  check(absf(a._player.current_animation_position-expected)<.002,'%s: continuous idle phase'%id)
  a.hit(Color.WHITE,0)
  for frame in range(240):a._process(1.0/120)
  expected=fposmod(a._clock*speed+a._phase/TAU*clip.length,clip.length)
  check(a._player.current_animation==&'idle' and absf(a._player.current_animation_position-expected)<.002,'%s: resumes continuing phase after hit'%id)
  a.free();CreatureModels.clear();await process_frame
 print('Idle runtime: %d checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
