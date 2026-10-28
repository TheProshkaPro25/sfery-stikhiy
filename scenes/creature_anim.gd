class_name CreatureAnim
extends Node3D
## Процедурная анимация статичной модели существа. Узел стоит в основании модели
## (точка опоры = пол), поэтому масштаб и наклоны не отрывают существо от карты.
## Локальные оси: +Z — взгляд существа (на соперника в бою).
## Итоговая поза = простой (idle) + эффект (fx_*), который двигают твины.

const FLYERS := ["bird", "flying_eye", "dragon"]

var fx_pos := Vector3.ZERO      ## смещение, м (в осях существа)
var fx_scale := 1.0             ## импульс масштаба
var fx_pitch := 0.0             ## наклон вперёд(+)/назад(-), рад
var fx_roll := 0.0              ## крен, рад
var fx_yaw := 0.0               ## доворот (появление), рад
var idle_on := false            ## включает «живой простой» (плавно)

var _base := Vector3.ZERO
var _height := 1.5
var _extent := 1.5
var _flyer := false
var _phase := 0.0
var _blend := 0.0
var _color := Color.WHITE
var _tw: Tween
var _tw_yaw: Tween
var _tw_flash: Tween
var _overlay: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
## Скелетные клипы вида (tools/blender/rig_species.py): idle, roar, attack, hit. Без скелета — null.
var _player: AnimationPlayer


func _ready() -> void:
	_phase = randf() * TAU


## Подключить построенную модель (CreatureModels.build); основание модели — в начале координат.
func set_model(model: Node3D, d: CreatureDef) -> void:
	add_child(model)
	_height = float(model.get_meta("height", 1.5))
	_extent = float(model.get_meta("extent", _height))
	_flyer = d != null and FLYERS.has(CreatureModels.archetype_of(d))
	_color = VisualUtil.attr_color(d.attribute) if d != null else Color.WHITE
	_meshes.clear()
	_player = null
	_collect(model)
	if _player != null and _player.has_animation("idle"):
		_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		_player.play("idle")
		_player.seek(randf() * _player.get_animation("idle").length)  # не синхронно с соседями
	reset()


## Рост модели (м) без эффектов.
func get_height() -> float:
	return _height


## Наибольший размер модели по полу (длина или размах), м.
func get_extent() -> float:
	return _extent


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	elif n is AnimationPlayer and _player == null:
		_player = n
	for c in n.get_children():
		_collect(c)


func set_base(p: Vector3) -> void:
	_base = p
	position = p


## Сброс всех эффектов (шар закрыт / переставлен).
func reset() -> void:
	_kill(_tw)
	_kill(_tw_yaw)
	_kill(_tw_flash)
	fx_pos = Vector3.ZERO
	fx_scale = 1.0
	fx_pitch = 0.0
	fx_roll = 0.0
	fx_yaw = 0.0
	_blend = 0.0
	for m in _meshes:
		m.material_overlay = null
	_apply(0.0)


func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()


func _process(delta: float) -> void:
	_blend = move_toward(_blend, 1.0 if idle_on else 0.0, delta * 2.5)
	_apply(Time.get_ticks_msec() * 0.001)


func _apply(now: float) -> void:
	var t := now + _phase
	var b := _blend
	var breath := sin(t * 2.2)
	var sy := 1.0 + breath * 0.025 * b
	var sxz := 1.0 - breath * 0.012 * b  # компенсация объёма
	var lift := 0.0
	if _flyer:
		lift = (0.6 + 0.4 * sin(t * 1.6)) * _height * 0.05 * b
	var sway := sin(t * 0.9)
	var rx := sin(t * 0.7 + 1.3) * deg_to_rad(1.2) * b
	var rz := sway * deg_to_rad(1.5) * b
	position = _base + fx_pos + Vector3(0.0, lift, 0.0)
	scale = Vector3(sxz, sy, sxz) * fx_scale
	rotation = Vector3(rx + fx_pitch, fx_yaw, rz + fx_roll)


func _new_tween() -> Tween:
	_kill(_tw)
	_tw = create_tween()
	return _tw


## Скелетный клип поверх процедурных эффектов, потом снова idle. Если у модели нет скелета — ничего.
func _clip(clip: StringName, delay: float = 0.0) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree():
			return
	_player.play(clip, 0.08)
	if _player.has_animation("idle"):
		_player.queue("idle")


## Появление: полуоборот (масштаб растит сам шар через _figure).
func appear() -> void:
	_kill(_tw_yaw)
	fx_yaw = -PI
	_tw_yaw = create_tween()
	_tw_yaw.tween_property(self, "fx_yaw", 0.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Рёв: наклон назад с рывком вверх, импульс масштаба, резкий возврат.
func roar(delay: float = 0.0) -> void:
	_clip(&"roar", delay)
	var tw := _new_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	var up := Vector3(0.0, _height * 0.06, -_height * 0.05)
	tw.set_parallel(true)
	tw.tween_property(self, "fx_pitch", -0.28, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pos", up, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_scale", 1.1, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.08)
	tw.chain().set_parallel(true)
	tw.tween_property(self, "fx_pitch", 0.0, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "fx_pos", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "fx_scale", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Рывок вперёд (+Z) на dist метров и откат. Удар приходится на ~0.3 с.
func lunge(dist: float) -> void:
	_clip(&"attack")
	var tw := _new_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "fx_pos", Vector3(0, 0, -dist * 0.15), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pitch", -0.12, 0.18)
	tw.chain().set_parallel(true)
	tw.tween_property(self, "fx_pos", Vector3(0, 0, dist), 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "fx_pitch", 0.2, 0.12)
	tw.chain().set_parallel(true)
	tw.tween_property(self, "fx_pos", Vector3.ZERO, 0.3).set_delay(0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pitch", 0.0, 0.3).set_delay(0.06)


## Ответный рывок защитника: то же, но короче.
func counter(dist: float) -> void:
	lunge(dist * 0.4)


## Отдача проигравшего: откат назад (-Z), встряска, возврат; вспышка цветом стихии победителя.
func hit(flash: Color, dist: float) -> void:
	_clip(&"hit")
	var tw := _new_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "fx_pos", Vector3(0, 0, -dist), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pitch", -0.3, 0.1)
	tw.tween_property(self, "fx_scale", 0.94, 0.1)
	tw.chain().tween_method(_shake, 1.0, 0.0, 0.35)
	tw.tween_property(self, "fx_pos", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pitch", 0.0, 0.35)
	tw.tween_property(self, "fx_scale", 1.0, 0.35)
	flash_color(flash, 0.5, 0.45)


## Дрожь: крен меняется со знаком, амплитуда затухает.
func _shake(k: float) -> void:
	fx_roll = sin(k * 38.0) * 0.12 * k


## Короткий наклон/импульс при игре карты способности.
func ability_pulse() -> void:
	var tw := _new_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "fx_scale", 1.08, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pitch", -0.15, 0.15)
	tw.tween_property(self, "fx_pos", Vector3(0, _height * 0.04, 0), 0.15)
	tw.chain().set_parallel(true)
	tw.tween_property(self, "fx_scale", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fx_pitch", 0.0, 0.3)
	tw.tween_property(self, "fx_pos", Vector3.ZERO, 0.3)


## Вспышка: аддитивный overlay поверх материалов, затухает за dur.
func flash_color(c: Color, strength: float = 0.5, dur: float = 0.4) -> void:
	if _meshes.is_empty():
		return
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_kill(_tw_flash)
	_overlay.albedo_color = Color(c.r, c.g, c.b, strength)
	for m in _meshes:
		m.material_overlay = _overlay
	_tw_flash = create_tween()
	_tw_flash.tween_property(_overlay, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_OUT)
	_tw_flash.tween_callback(func() -> void:
		for m in _meshes:
			m.material_overlay = null)
