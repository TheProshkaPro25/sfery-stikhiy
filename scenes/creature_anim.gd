class_name CreatureAnim
extends Node3D
## Один таймлайн управляет корпусом, скелетом и контактом. +Z — к сопернику.
## Отложенные действия принадлежат текущему состоянию и отменяются новым действием.

signal strike_contact
signal action_finished(action: StringName)

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
var _color := Color.WHITE
var _meshes: Array[MeshInstance3D] = []
var _player: AnimationPlayer
var _overlay: StandardMaterial3D
var _flash_age := 0.0
var _flash_duration := 0.0
var _flash_strength := 0.0
var _kind := "fighter"
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
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_player.speed_scale = 1.0
		_player.playback_default_blend_time = 0.2
	reset()


func get_height() -> float:
	return _height


func get_extent() -> float:
	return _extent


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


func reset() -> void:
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
	_flash_duration = 0.0
	for mesh in _meshes:
		mesh.material_overlay = null
	_idle_clip(0.0)
	_apply(_clock)


func _idle_clip(blend: float = 0.22) -> void:
	if _player != null and _player.has_animation(&"idle"):
		_player.clear_queue()
		_player.play(&"idle", blend, _tempo * 0.85)


static func _ease(value: float) -> float:
	var s := clampf(value, 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s)


func _process(delta: float) -> void:
	_update_flash(delta)
	if _pause_left > 0.0:
		_pause_left = maxf(0.0, _pause_left - delta)
		return
	_clock += delta
	_blend = move_toward(_blend, 1.0 if idle_on and _action == &"" else 0.0, delta * 3.5)
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


func _apply(now: float) -> void:
	var t := now + _phase
	var procedural := _blend if _player == null else 0.0
	var breath := sin(t * 1.7)
	var lift := (0.6 + 0.4 * sin(t * 1.3)) * _height * 0.025 * _blend if _flyer else 0.0
	position = _base + fx_pos + Vector3(0, lift, 0)
	scale = Vector3(1.0 - breath * 0.003 * procedural, 1.0 + breath * 0.006 * procedural, 1.0 - breath * 0.003 * procedural) * fx_scale
	rotation = Vector3(fx_pitch + sin(t * 0.7) * 0.006 * procedural, fx_yaw, fx_roll + sin(t * 0.8) * 0.006 * procedural)


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
		progress = (t / _contact_time) / 3.0 if t <= _contact_time else 1.0 / 3.0 + (t - _contact_time) / (_duration - _contact_time) * 2.0 / 3.0
	var target := clampf(progress, 0.0, 1.0) * animation.length
	_player.advance(maxf(0.0, target - _clip_time))
	_clip_time = target


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
	_contact_time = {"heavy": 0.5, "flyer": 0.42, "beast": 0.36, "fighter": 0.44}[_kind] / _tempo
	var duration: float = {"heavy": 1.28, "flyer": 1.08, "beast": 0.96, "fighter": 1.12}[_kind] / _tempo
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
		mesh.material_overlay = _overlay


func _update_flash(delta: float) -> void:
	if _flash_duration <= 0.0:
		return
	_flash_age += delta
	_overlay.albedo_color.a = _flash_strength * (1.0 - _ease(_flash_age / _flash_duration))
	if _flash_age >= _flash_duration:
		_flash_duration = 0.0
		for mesh in _meshes:
			mesh.material_overlay = null
