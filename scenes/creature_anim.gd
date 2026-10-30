class_name CreatureAnim
extends Node3D
## Один таймлайн управляет корпусом, скелетом и контактом. +Z — к сопернику.
## Отложенные действия принадлежат текущему состоянию и отменяются новым действием.

signal strike_contact
signal action_finished(action: StringName)

const BodySupport := preload("res://scenes/creature_support.gd")
var _support
var _cloth

const FLYERS := ["bird", "flying_eye", "dragon"]
const TEMPO := [1.04, 1.08, 1.0, 0.92, 0.96, 0.98]

var fx_pos := Vector3.ZERO
var fx_scale := 1.0
var fx_pitch := 0.0
var fx_roll := 0.0
var fx_yaw := 0.0
var idle_on := false
var _base := Vector3.ZERO
var _height := 1.5
var _extent := 1.5
var _flyer := false
var _phase := 0.0
var _blend := 0.0
var _hover_blend := 0.0
var _color := Color.WHITE
var _meshes: Array[MeshInstance3D] = []
var _player: AnimationPlayer
var _overlay: StandardMaterial3D
var _flash_age := 0.0
var _flash_duration := 0.0
var _flash_strength := 0.0
var _kind := "fighter"
var _species: StringName = &""
var _tempo := 1.0
var _clock := 0.0
var _action: StringName = &""
var _elapsed := 0.0
var _delay := 0.0
var _duration := 1.0
var _contact_time := 0.42
var _contact_sent := false
var _distance := 0.0
var _clip_started := false
var _clip_time := 0.0
var _clip_name: StringName = &""
var _start_pos := Vector3.ZERO
var _start_angles := Vector3.ZERO
var _pause_left := 0.0


func _ready() -> void:
	_phase = randf() * TAU


func set_model(model: Node3D, d: CreatureDef) -> void:
	add_child(model)
	_height = float(model.get_meta("height", 1.5))
	_extent = float(model.get_meta("extent", _height))
	_species = d.species if d != null else &""
	var archetype := CreatureModels.archetype_of(d) if d != null else "knight"
	_flyer = FLYERS.has(archetype)
	_kind = "flyer" if _flyer else ("heavy" if archetype in ["cyclops", "beetle"] else ("beast" if archetype in ["wolf", "serpent"] else "fighter"))
	_color = VisualUtil.attr_color(d.attribute) if d != null else Color.WHITE
	_tempo = TEMPO[d.attribute] if d != null and d.attribute >= 0 and d.attribute < TEMPO.size() else 1.0
	_meshes.clear()
	_player = null
	_collect(model)
	if _player != null:
		# Библиотеки экземпляра: сглаживание не меняет общий ресурс и соседних бойцов.
		for name in _player.get_animation_library_list():
			var library := _player.get_animation_library(name).duplicate(true) as AnimationLibrary
			_player.remove_animation_library(name)
			_player.add_animation_library(name, library)
			for clip in library.get_animation_list():
				var animation := library.get_animation(clip)
				for track in range(animation.get_track_count()):
					if animation.track_get_type(track) in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
						animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
				animation.loop_mode = Animation.LOOP_LINEAR if clip == &"idle" else Animation.LOOP_NONE
				if clip == &"idle":
					_prepare_idle_loop(animation)
				for track in range(animation.get_track_count()):
					animation.track_set_interpolation_loop_wrap(track, clip == &"idle")
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_player.speed_scale = 1.0
		_player.playback_default_blend_time = 0.2
	reset()
	# У шестирукого собственные опорные ключи и смена ноги в клипах.
	_support = null
	if _species != &"likorez":
		_support = BodySupport.new()
		_support.configure(self, model)
	if _species == &"ratnik":
		_cloth = CreatureCloth.attach(model)


func get_height() -> float:
	return _height


static func _rotation_log(q: Quaternion) -> Vector3:
	q = q.normalized()
	if q.w < 0.0: q = -q
	var vector := Vector3(q.x, q.y, q.z)
	var length := vector.length()
	return vector * (2.0 * atan2(length, q.w) / length) if length > 0.000001 else vector * 2.0


static func _rotation_exp(vector: Vector3) -> Quaternion:
	var angle := vector.length()
	return Quaternion(vector / angle, angle) if angle > 0.000001 else Quaternion(vector.x * 0.5, vector.y * 0.5, vector.z * 0.5, 1.0).normalized()


static func _prepare_idle_loop(animation: Animation) -> void:
	# Smooth cyclic curves in the small rotation vector around the first pose.
	# Play dense samples with SLERP: quaternion cubic wrap can change direction at
	# the boundary after import key reduction, even for closed source curves.
	var coarse_count := maxi(4, roundi(animation.length * 60.0))
	var samples := coarse_count * 2
	for track in range(animation.get_track_count()):
		var count := animation.track_get_key_count(track)
		if count < 2: continue
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
			animation.track_set_interpolation_loop_wrap(track, true)
			var reference := animation.rotation_track_interpolate(track, 0.0).normalized()
			var points: Array[Vector3] = []
			for index in range(coarse_count):
				var value := animation.rotation_track_interpolate(track, animation.length * float(index) / coarse_count)
				points.append(_rotation_log(reference.inverse() * value))
			points[0] = Vector3.ZERO
			var values: Array[Quaternion] = []
			for index in range(samples):
				var position := float(index) * coarse_count / samples
				var base := floori(position)
				var vector := points[base].cubic_interpolate(points[(base + 1) % coarse_count], points[posmod(base - 1, coarse_count)], points[(base + 2) % coarse_count], position - base)
				values.append((reference * _rotation_exp(vector)).normalized())
			values[0] = reference
			# The two adjacent geodesic increments give exactly the same seam velocity.
			var tangent := (_rotation_log(reference.inverse() * values[1]) - _rotation_log(reference.inverse() * values[-1])) * 0.5
			values[1] = (reference * _rotation_exp(tangent)).normalized()
			values[-1] = (reference * _rotation_exp(-tangent)).normalized()
			while animation.track_get_key_count(track) > 0:
				animation.track_remove_key(track, animation.track_get_key_count(track) - 1)
			for index in range(samples):
				animation.rotation_track_insert_key(track, animation.length * float(index) / samples, values[index])
			continue
		# Loop wrap supplies the first value at length; keep one copy only.
		if not is_equal_approx(animation.track_get_key_time(track, count - 1), animation.length): continue
		var first = animation.track_get_key_value(track, 0)
		var last = animation.track_get_key_value(track, count - 1)
		if first is Vector3 and last is Vector3 and first.is_equal_approx(last):
			animation.track_remove_key(track, count - 1)


func get_extent() -> float:
	return _extent


func get_hover_height() -> float:
	var ratio: float = {&"dragnar": 0.19, &"grifalon": 0.24, &"gorgul": 0.27}.get(_species, 0.20)
	return _height * ratio if _flyer else 0.0


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	elif n is AnimationPlayer and _player == null:
		_player = n
	for child in n.get_children():
		_collect(child)


func set_base(p: Vector3) -> void:
	_base = p
	_apply(_clock)
	if is_instance_valid(_cloth): _cloth.reset_simulation()


func reset() -> void:
	if _support != null: _support.reset()
	_action = &""
	_pause_left = 0.0
	_elapsed = 0.0
	_delay = 0.0
	fx_pos = Vector3.ZERO
	fx_scale = 1.0
	fx_pitch = 0.0
	fx_roll = 0.0
	fx_yaw = 0.0
	_blend = 0.0
	_hover_blend = 0.0
	_flash_duration = 0.0
	for mesh in _meshes:
		mesh.material_overlay = null
		if mesh.has_meta("cloth_material"):
			mesh.get_meta("cloth_material").set_shader_parameter("flash_tint", Color(0, 0, 0, 0))
	_idle_clip(0.0)
	_apply(_clock)
	if is_instance_valid(_cloth): _cloth.reset_simulation()


func _idle_clip(blend: float = 0.22) -> void:
	if _player != null and _player.has_animation(&"idle"):
		_player.clear_queue()
		var speed: float = _tempo * {&"kolossar": 0.62, &"rogozhuk": 0.68, &"levian": 0.7, &"dragnar": 0.72, &"ratnik": 0.72, &"klykar": 0.8}.get(_species, 0.85)
		_player.play(&"idle", blend, speed)
		# Return to the continuing idle phase, rather than replaying its first beat after each action.
		var length := _player.get_animation(&"idle").length
		_player.seek(fposmod(_clock * speed + _phase / TAU * length, length), false)


static func _ease(value: float) -> float:
	var s := clampf(value, 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s)


func _process(delta: float) -> void:
	# Закрытые сферы не требуют расчёта скрытого скелета и опоры.
	if not is_visible_in_tree(): return
	_update_flash(delta)
	if _pause_left > 0.0:
		_pause_left = maxf(0.0, _pause_left - delta)
		return
	if _support != null: _support.restore()
	_clock += delta
	_blend = move_toward(_blend, 1.0 if idle_on and _action == &"" else 0.0, delta * 3.5)
	_hover_blend = move_toward(_hover_blend, 1.0 if idle_on or _action != &"" else 0.0, delta * 3.5)
	if _action == &"":
		if _player != null:
			_player.advance(delta)
	else:
		_elapsed += delta
		var t := _elapsed - _delay
		if t >= 0.0:
			_sample_action(minf(t, _duration))
			_advance_clip(t)
			# Сначала поза контакта, затем сигнал — реакция цели видит правильную позу.
			_apply(_clock)
			if _action == &"attack" and not _contact_sent and t >= _contact_time:
				_contact_sent = true
				strike_contact.emit()
			if t >= _duration:
				_finish_action()
		elif _player != null:
			_player.advance(delta)
	_apply(_clock)
	if _support != null: _support.apply(delta)


func _apply(now: float) -> void:
	var t := now + _phase
	var procedural := _blend if _player == null else 0.0
	var breath := sin(t * 1.7)
	# Заметный постоянный просвет над воротами; волна только мягко меняет высоту.
	var lift := (get_hover_height() + 0.016 * _height * sin(t * 1.3)) * _hover_blend if _flyer else 0.0
	position = _base + fx_pos + Vector3(0, lift, 0)
	scale = Vector3(1.0 - breath * 0.003 * procedural, 1.0 + breath * 0.006 * procedural, 1.0 - breath * 0.003 * procedural) * fx_scale
	rotation = Vector3(fx_pitch + sin(t * 0.7) * 0.006 * procedural, fx_yaw, fx_roll + sin(t * 0.8) * 0.006 * procedural)
	if is_instance_valid(_cloth): CreatureCloth.update_floor(_cloth, self)


func _begin(action: StringName, duration: float, clip: StringName, delay: float = 0.0) -> void:
	_start_pos = fx_pos
	_start_angles = Vector3(fx_pitch, fx_yaw, fx_roll)
	_action = action
	_elapsed = 0.0
	_delay = maxf(delay, 0.0)
	_duration = duration
	_clip_name = clip
	_clip_started = false
	_clip_time = 0.0
	_contact_sent = false
	_pause_left = 0.0
	if _player != null:
		_player.clear_queue()


func _advance_clip(t: float) -> void:
	if _player == null:
		return
	if not _player.has_animation(_clip_name):
		_player.advance(get_process_delta_time())
		return
	if not _clip_started:
		_player.play(_clip_name, 0.16, 1.0)
		_clip_started = true
	var animation := _player.get_animation(_clip_name)
	var progress := clampf(t / _duration, 0.0, 1.0)
	if _action == &"attack":
		# Скелетный замах заканчивается на кадре 10 из 28. Продвижение клипа
		# привязано к контакту профиля, а не к отдельному таймеру/скорости стихии.
		progress = _attack_progress(t)
	var target := clampf(progress, 0.0, 1.0) * animation.length
	_player.advance(maxf(0.0, target - _clip_time))
	_clip_time = target


func _attack_progress(t: float) -> float:
	if t <= _contact_time:
		return t / _contact_time / 3.0
	if t <= _contact_time + 0.07:
		return 1.0 / 3.0
	return 1.0 / 3.0 + (t - _contact_time - 0.07) / (_duration - _contact_time - 0.07) * 2.0 / 3.0


func _sample_action(t: float) -> void:
	var pos := Vector3.ZERO
	var pitch := 0.0
	var yaw := 0.0
	var roll := 0.0
	var skeleton_k := 0.45 if _player != null else 1.0
	match _action:
		&"attack":
			var windup := _contact_time * 0.66
			var hold := _contact_time + 0.07
			var back := Vector3(0, _height * 0.025 if _flyer else 0.0, -_distance * 0.18)
			var contact := Vector3(0, _height * 0.015 if _flyer else 0.0, _distance)
			var power: float
			if t < windup:
				power = _ease(t / windup)
				pos = back * power
				pitch = -0.14 * power * skeleton_k
				yaw = -0.12 * power if _kind == "fighter" else 0.0
			elif t < _contact_time:
				power = _ease((t - windup) / (_contact_time - windup))
				pos = back.lerp(contact, power)
				pitch = lerpf(-0.14, 0.19, power) * skeleton_k
				yaw = lerpf(-0.12, 0.08, power) if _kind == "fighter" else 0.0
			else:
				power = 1.0 - _ease((t - hold) / (_duration - hold))
				pos = contact * power
				pitch = 0.19 * power * skeleton_k
				yaw = 0.08 * power if _kind == "fighter" else 0.0
		&"hit":
			var recoil := _ease(t / 0.12) if t < 0.12 else 1.0 - _ease((t - 0.18) / (_duration - 0.18))
			pos.z = -_distance * recoil
			pitch = -0.16 * recoil * skeleton_k
			roll = sin(t * TAU * 2.0) * 0.035 * recoil
		&"brace":
			var weight := sin(clampf(t / _duration, 0.0, 1.0) * PI)
			pos.z = -_height * 0.025 * weight
			pitch = 0.07 * weight * skeleton_k
		&"appear":
			yaw = -0.3 * (1.0 - _ease(t / _duration))
			pitch = -0.045 * sin(t / _duration * PI)
		&"roar", &"ability":
			var rise := _ease(t / 0.28) if t < 0.28 else 1.0 - _ease((t - 0.42) / (_duration - 0.42))
			pitch = -0.12 * rise * skeleton_k
			pos.y = _height * 0.025 * rise if _flyer else 0.0
	if _action == &"attack":
		var p := clampf(_attack_progress(t), 0.0, 1.0)
		var envelope := sin(p * PI)
		var thrust := sin(minf(p * 1.5, 1.0) * PI)
		match _species:
			&"dragnar":
				pos.y += _height * 0.07 * envelope
				pitch += 0.045 * thrust
			&"grifalon":
				pos.y += _height * 0.11 * envelope
				pitch += 0.08 * thrust
			&"klykar":
				pos.y += _height * 0.045 * maxf(0.0, thrust)
				pitch += 0.04 * thrust
			&"ratnik":
				pos.x += _height * 0.035 * envelope
				yaw += 0.16 * sin(p * TAU) * envelope
			&"kolossar":
				yaw += 0.065 * sin(p * TAU) * envelope
			&"rogozhuk":
				pitch -= 0.10 * sin(p * PI) * skeleton_k
			&"levian":
				pos.z *= 0.45
				pos.x += _height * 0.025 * sin(p * TAU) * envelope
			&"gorgul":
				pos.x += _height * 0.06 * sin(p * TAU) * envelope
				pos.y += _height * 0.045 * envelope
				roll = -0.10 * sin(p * TAU) * envelope
	if _species == &"levian":
		pos = Vector3.ZERO
		pitch = 0.0
		roll = 0.0
	# При смене действия продолжаем из текущей позы, включая недовыполненную отдачу.
	var blend := _ease(t / 0.14)
	fx_pos = _start_pos.lerp(pos, blend)
	fx_pitch = lerpf(_start_angles.x, pitch, blend)
	fx_yaw = lerpf(_start_angles.y, yaw, blend)
	fx_roll = lerpf(_start_angles.z, roll, blend)
	fx_scale = 1.0


func _finish_action() -> void:
	var finished := _action
	_action = &""
	fx_pos = Vector3.ZERO
	fx_pitch = 0.0
	fx_yaw = 0.0
	fx_roll = 0.0
	_idle_clip()
	action_finished.emit(finished)


func appear(pose: bool = true) -> void:
	_begin(&"appear", 1.1, &"stance" if pose else &"idle")


func roar(delay: float = 0.0) -> void:
	_begin(&"roar", 1.05, &"roar", delay)


func lunge(dist: float, contact_override: float = 0.0) -> void:
	var timing: Vector2 = {
		&"dragnar": Vector2(0.48, 1.22), &"klykar": Vector2(0.32, 0.94),
		&"grifalon": Vector2(0.39, 1.08), &"kolossar": Vector2(0.56, 1.42),
		&"rogozhuk": Vector2(0.5, 1.24), &"levian": Vector2(0.45, 1.26),
		&"ratnik": Vector2(0.43, 1.16), &"gorgul": Vector2(0.35, 1.0),
	}.get(_species, Vector2(0.44, 1.12))
	_contact_time = timing.x / _tempo
	var duration: float = timing.y / _tempo
	if contact_override > 0.0:
		_contact_time = contact_override
		duration = maxf(duration, _contact_time + 0.6)
	_distance = clampf(dist, 0.0, _height * 0.24)
	_begin(&"attack", duration, &"attack")


func counter(dist: float) -> void:
	lunge(dist * 0.45)


func brace() -> void:
	_begin(&"brace", 0.8, &"idle")


func hit(flash: Color, dist: float) -> void:
	_distance = clampf(dist, 0.0, _height * 0.1)
	_begin(&"hit", 0.8, &"hit")
	flash_color(flash, 0.22, 0.28)


## Короткая остановка только этого бойца: частицы, камера и интерфейс не замедляются.
func hold_impact(seconds: float = 0.055) -> void:
	_pause_left = maxf(_pause_left, seconds)


func ability_pulse() -> void:
	_begin(&"ability", 0.85, &"roar")
	flash_color(_color, 0.16, 0.45)


func flash_color(c: Color, strength: float = 0.22, dur: float = 0.28) -> void:
	if _meshes.is_empty():
		return
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_age = 0.0
	_flash_duration = maxf(dur, 0.01)
	_flash_strength = strength
	_overlay.albedo_color = Color(c.r, c.g, c.b, strength)
	for mesh in _meshes:
		if mesh.has_meta("cloth_material"):
			mesh.get_meta("cloth_material").set_shader_parameter("flash_tint", _overlay.albedo_color)
		else:
			mesh.material_overlay = _overlay


func _update_flash(delta: float) -> void:
	if _flash_duration <= 0.0:
		return
	_flash_age += delta
	_overlay.albedo_color.a = _flash_strength * (1.0 - _ease(_flash_age / _flash_duration))
	for mesh in _meshes:
		if mesh.has_meta("cloth_material"):
			mesh.get_meta("cloth_material").set_shader_parameter("flash_tint", _overlay.albedo_color)
	if _flash_age >= _flash_duration:
		_flash_duration = 0.0
		for mesh in _meshes:
			mesh.material_overlay = null
