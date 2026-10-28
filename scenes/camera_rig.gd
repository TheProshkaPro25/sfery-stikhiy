class_name CameraRig
extends Camera3D
## Режиссёрская камера в духе аниме: набор ракурсов (таблица SHOTS), плавные переходы и мгновенные
## каты, лёгкое «плечо» (мягкий шум), тряска, облёты, наезды и слежение за шаром с запаздыванием.
## Камера никогда не опускается ниже MIN_Y (не проваливается под пол).
##
## Режимы: STATIC — цель неподвижна (обзор дрейфует сам); FOLLOW — за шаром; ORBIT — облёт точки
## по дуге (угол, высота и точка взгляда меняются по времени); DOLLY — наезд от текущей точки к цели.

enum Mode { STATIC, FOLLOW, ORBIT, DOLLY }

const MIN_Y := 0.9
const FAR := 3000.0
## Обход фигур существ: радиус цилиндра (доля роста) и высота подъёма над ним (доля роста).
const AVOID_RADIUS := 0.55
const AVOID_TOP := 1.8

## Таблица ракурсов (мировые единицы; доли «h» — от высоты существа). Правится здесь.
## pos/look — смещения от опорной точки, fov — угол обзора, smooth — мягкость перехода (больше = резче),
## hand — амплитуда «плеча» (м), drift_deg/drift_period — медленный дрейф обзора.
const SHOTS := {
	# общий план между ходами: поле в центре, горизонт и ориентиры сверху; медленно дрейфует по кругу
	&"overview": {"pos": Vector3(0.0, 27.0, 56.0), "look": Vector3(0.0, 0.0, -6.0), "fov": 52.0, "smooth": 1.6,
		"hand": 0.35, "drift_deg": 9.0, "drift_period": 28.0},
	# прицел игрока: за спиной шара, невысоко, видны все ворота
	&"aim": {"pos": Vector3(0.0, 12.5, 19.0), "look": Vector3(0.0, 0.0, -24.0), "fov": 56.0, "smooth": 3.0, "hand": 0.12},
	# бросок соперника: низко за его спиной (ракурс через плечо в сторону поля)
	&"throw_low": {"pos": Vector3(4.0, 4.2, 15.0), "look": Vector3(0.0, 1.5, -20.0), "fov": 58.0, "hand": 0.25},
	# погоня за шаром: позади по скорости, с запаздыванием и креном на поворотах
	&"follow": {"back": 15.0, "up": 6.0, "lead": 7.0, "fov": 62.0, "smooth": 3.2, "hand": 0.3, "tilt": 0.0045, "tilt_max": 0.16},
	# приземление: короткий наезд на карту
	&"land": {"dist": 21.0, "up": 8.0, "look_y": 1.5, "fov": 50.0, "smooth": 4.5, "hand": 0.2},
	# раскрытие: облёт снизу вверх вокруг существа
	&"reveal": {"radius": 1.75, "y0": 0.08, "y1": 0.95, "look0": 0.75, "look1": 0.45, "arc_deg": 80.0, "dur": 1.9, "fov": 56.0, "hand": 0.15},
	# бой: общий план двух существ лицом к лицу (сбоку, низко)
	&"battle_wide": {"pos": Vector3(25.0, 3.2, 0.0), "look_h": 0.42, "fov": 54.0, "smooth": 3.5, "hand": 0.25},
	# крупный план при рёве: 3/4 спереди, снизу (side — вбок, fwd — вперёд по взгляду существа)
	&"close": {"side": 0.95, "up": 0.22, "fwd": 0.78, "look_h": 0.6, "fov": 48.0, "hand": 0.18},
	# способность: кат на автора и рывок к нему
	&"ability": {"side": 0.95, "up": 0.12, "fwd": 0.8, "push": 0.45, "dur": 0.35, "look_h": 0.55, "fov": 50.0, "hand": 0.2},
	# удар: быстрый наезд в точку столкновения
	&"impact": {"push": 0.55, "dur": 0.22, "fov": 46.0},
	# победитель: медленный облёт
	&"winner": {"radius": 1.6, "y0": 0.3, "y1": 0.45, "look0": 0.55, "look1": 0.55, "arc_deg": 55.0, "dur": 2.6, "fov": 50.0, "hand": 0.2},
}

var mode := Mode.STATIC
var _goal_pos := Vector3.ZERO
var _goal_look := Vector3.ZERO
var _goal_fov := 52.0
var _smooth := 2.0
var _hand := 0.3
var _look := Vector3.ZERO
var _base := Vector3.ZERO  ## позиция без шума «плеча»
var _avoid := true  ## обходить фигуры (выключено на крупных планах — объект в кадре намеренно близко)
var _drift := 0.0          # амплитуда дрейфа обзора (рад), 0 — без дрейфа
var _drift_period := 28.0
var _drift_center := Vector3.ZERO
var _t := 0.0
var _roll := 0.0
# слежение
var _follow: Node3D = null
var _follow_dir := Vector3(0, 0, -1)
# облёт
var _orb := {}
var _orb_t := 0.0
# наезд
var _dolly_from := Vector3.ZERO
var _dolly_to := Vector3.ZERO
var _dolly_t := 0.0
var _dolly_dur := 0.3
# бой: центр и высота существ для возврата к общему плану
var _battle_center := Vector3.ZERO
var _battle_h := 10.0
# тряска
var _shake := 0.0
var _shake_t := 0.0


func _ready() -> void:
	far = FAR
	snap_overview()


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-_smooth * delta)
	match mode:
		Mode.FOLLOW:
			_update_follow(delta)
		Mode.ORBIT:
			_orb_t += delta
			_orbit_goal(clampf(_orb_t / float(_orb["dur"]), 0.0, 1.0))
			k = 1.0 - exp(-10.0 * delta)
		Mode.DOLLY:
			_dolly_t += delta
			var s := clampf(_dolly_t / _dolly_dur, 0.0, 1.0)
			s = 1.0 - pow(1.0 - s, 3.0)
			_goal_pos = _dolly_from.lerp(_dolly_to, s)
			k = 1.0
		Mode.STATIC:
			if _drift > 0.0:
				var a := sin(_t * TAU / _drift_period) * _drift
				var rel := SHOTS[&"overview"]["pos"] as Vector3
				_goal_pos = _drift_center + rel.rotated(Vector3.UP, a) + Vector3(0, sin(_t * 0.31) * 1.2, 0)
	_avoid_figures()
	_base = _base.lerp(_goal_pos, k)
	_base.y = maxf(_base.y, MIN_Y)
	_look = _look.lerp(_goal_look, k if mode == Mode.ORBIT else 1.0 - exp(-maxf(_smooth, 3.0) * 1.3 * delta))
	fov = lerpf(fov, _goal_fov, 1.0 - exp(-4.0 * delta))
	_apply_transform()
	if mode != Mode.FOLLOW:
		_roll = lerpf(_roll, 0.0, 1.0 - exp(-4.0 * delta))
	if _shake_t > 0.0:
		_shake_t -= delta
		var amp := _shake * Arena.WORLD * 0.12 * clampf(_shake_t * 3.0, 0.0, 1.0)
		h_offset = randf_range(-amp, amp)
		v_offset = randf_range(-amp, amp)
	else:
		h_offset = 0.0
		v_offset = 0.0


## Камера не входит внутрь раскрытых существ: если цель (или, при слежении, луч к шару) попадает
## в цилиндр фигуры, цель поднимается над ней. Объект съёмки крупных планов стоит вне своего цилиндра.
func _avoid_figures() -> void:
	if not _avoid or mode == Mode.DOLLY or not is_inside_tree():
		return
	var lift := _goal_pos.y
	for n in get_tree().get_nodes_in_group(&"creature_balls"):
		var b := n as CreatureBall
		if b == null or not b.is_figure_shown():
			continue
		var h := b.figure_height()
		var c := b.global_position
		var r := b.figure_size() * AVOID_RADIUS + 1.0
		# сама камера на пути к цели вошла в фигуру — поднимаем её над существом
		if Vector2(_base.x - c.x, _base.z - c.z).length() < r and _base.y < h * 1.1:
			_base.y = lerpf(_base.y, h * AVOID_TOP, 0.2)
		var samples := [1.0]
		if mode == Mode.FOLLOW:
			samples = [1.0, 0.75, 0.5, 0.3]
		for f in samples:
			var p := _goal_look.lerp(_goal_pos, f)
			if Vector2(p.x - c.x, p.z - c.z).length() < r and p.y < h * 1.1:
				lift = maxf(lift, h * AVOID_TOP)
	_goal_pos.y = lift


## Итоговый кадр: чистая позиция + «плечо» (мягкий шум, разный по осям) + крен; не ниже MIN_Y.
func _apply_transform() -> void:
	var hand := Vector3(sin(_t * 0.83) + 0.4 * sin(_t * 2.1 + 1.0), sin(_t * 0.67 + 2.0) + 0.3 * sin(_t * 1.7), sin(_t * 0.59 + 4.0)) * _hand
	var cam_pos := _base + hand
	cam_pos.y = maxf(cam_pos.y, MIN_Y)
	var look := _look + hand * 0.5
	position = cam_pos
	if not is_inside_tree():
		return
	var dir := look - cam_pos
	if dir.length() > 0.01 and absf(dir.normalized().y) < 0.995:
		look_at(look, Vector3.UP)
	if absf(_roll) > 0.0005:
		rotate_object_local(Vector3(0, 0, 1), _roll)


## Тряска камеры (удар в бою).
func shake(amount: float, dur: float) -> void:
	_shake = amount
	_shake_t = dur


## Мгновенный кат: камера сразу встаёт в текущую цель.
func cut() -> void:
	_base = _goal_pos
	_base.y = maxf(_base.y, MIN_Y)
	_look = _goal_look
	fov = _goal_fov
	_roll = 0.0
	_apply_transform()


func _set_static(pos: Vector3, look: Vector3, s: Dictionary) -> void:
	mode = Mode.STATIC
	_follow = null
	_drift = 0.0
	_avoid = true
	_goal_pos = pos
	_goal_look = look
	_goal_fov = float(s.get("fov", _goal_fov))
	_smooth = float(s.get("smooth", 3.0))
	_hand = float(s.get("hand", 0.2))


# ------------------------------------------------------------ общий план

func snap_overview() -> void:
	overview()
	cut()


## Общий план между ходами: медленный дрейф по дуге вокруг центра поля.
func overview() -> void:
	var s: Dictionary = SHOTS[&"overview"]
	_set_static(s["pos"], s["look"], s)
	_drift_center = Vector3.ZERO
	_drift = deg_to_rad(float(s["drift_deg"]))
	_drift_period = float(s["drift_period"])


func is_overview() -> bool:
	return mode == Mode.STATIC and _drift > 0.0


# ------------------------------------------------------------ бросок

## Прицел: за спиной шара. side = +1 — игрок (бросает к −Z), −1 — соперник (зеркально).
func aim_view(ball_pos: Vector3, side: float, do_cut: bool = false) -> void:
	var s: Dictionary = SHOTS[&"aim"]
	var p: Vector3 = s["pos"]
	var l: Vector3 = s["look"]
	_set_static(ball_pos + Vector3(p.x * side, p.y, p.z * side), Vector3(0.0, l.y, ball_pos.z + l.z * side), s)
	if do_cut:
		cut()


## Низкий ракурс через плечо бросающего (для броска соперника), всегда катом.
func throw_view(ball_pos: Vector3, side: float) -> void:
	var s: Dictionary = SHOTS[&"throw_low"]
	var p: Vector3 = s["pos"]
	var l: Vector3 = s["look"]
	_set_static(ball_pos + Vector3(p.x * side, p.y, p.z * side), ball_pos + Vector3(l.x, l.y, l.z * side), s)
	cut()


## Погоня за шаром: рывок вслед, позади по направлению скорости, с запаздыванием и креном.
func follow(n: Node3D) -> void:
	var s: Dictionary = SHOTS[&"follow"]
	mode = Mode.FOLLOW
	_follow = n
	_drift = 0.0
	_avoid = true
	_goal_fov = float(s["fov"])
	_smooth = float(s["smooth"])
	_hand = float(s["hand"])
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		_follow_dir = fwd.normalized()


func _update_follow(delta: float) -> void:
	if _follow == null or not is_instance_valid(_follow) or not _follow.is_inside_tree():
		return
	var s: Dictionary = SHOTS[&"follow"]
	var p := _follow.global_position
	var v := Vector3.ZERO
	if _follow is RigidBody3D:
		v = (_follow as RigidBody3D).linear_velocity
	var vf := Vector3(v.x, 0.0, v.z)
	var lateral := 0.0
	if vf.length() > 1.0:
		var nd := vf.normalized()
		lateral = _follow_dir.cross(nd).y
		_follow_dir = _follow_dir.slerp(nd, 1.0 - exp(-2.5 * delta)).normalized()
	var speed := vf.length()
	var lead := float(s["lead"]) * clampf(speed / 20.0, 0.2, 1.0)
	_goal_pos = p - _follow_dir * float(s["back"]) + Vector3(0, float(s["up"]), 0)
	_goal_look = p + _follow_dir * lead + Vector3(0, 0.8, 0)
	# крен в сторону поворота, сильнее на скорости
	var want_roll := clampf(-lateral * speed * float(s["tilt"]) * 10.0, -float(s["tilt_max"]), float(s["tilt_max"]))
	_roll = lerpf(_roll, want_roll, 1.0 - exp(-3.0 * delta))


## Приземление на карту: короткий наезд с текущей стороны.
func zoom_slot(p: Vector3) -> void:
	var s: Dictionary = SHOTS[&"land"]
	var d := _base - p
	d.y = 0.0
	d = d.normalized() if d.length() > 0.1 else Vector3(0, 0, 1)
	_set_static(p + d * float(s["dist"]) + Vector3(0, float(s["up"]), 0), p + Vector3(0, float(s["look_y"]), 0), s)


# ------------------------------------------------------------ облёты

## Облёт вокруг точки: из текущего азимута на arc_deg, высота и точка взгляда по долям высоты h.
## Возвращает длительность.
func _orbit(center: Vector3, h: float, s: Dictionary, start_az: float = NAN, size: float = 0.0) -> float:
	mode = Mode.ORBIT
	_follow = null
	_drift = 0.0
	_avoid = true
	var d := _base - center
	var az: float = atan2(d.x, d.z) if is_nan(start_az) else start_az
	_orb = s.duplicate()
	_orb["center"] = center
	_orb["h"] = h
	_orb["size"] = maxf(h, size)
	_orb["az"] = az
	_orb_t = 0.0
	_goal_fov = float(s["fov"])
	_smooth = 6.0
	_hand = float(s.get("hand", 0.15))
	_orbit_goal(0.0)
	return float(s["dur"])


func _orbit_goal(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	var h: float = _orb["h"]
	var c: Vector3 = _orb["center"]
	var a: float = float(_orb["az"]) + deg_to_rad(float(_orb["arc_deg"])) * e
	var r: float = float(_orb["radius"]) * float(_orb["size"])
	var y: float = lerpf(float(_orb["y0"]), float(_orb["y1"]), e) * h
	_goal_pos = c + Vector3(sin(a) * r, y, cos(a) * r)
	_goal_look = c + Vector3(0, lerpf(float(_orb["look0"]), float(_orb["look1"]), e) * h, 0)


## Раскрытие существа: камера снизу вверх облетает его на 60–90°. Начинает катом. Возвращает длительность.
func reveal_orbit(p: Vector3, h: float, toward: Vector3, size: float = 0.0) -> float:
	# стартуем спереди-сбоку от существа (toward — куда оно смотрит)
	var az := atan2(toward.x, toward.z) - deg_to_rad(70.0)
	var dur := _orbit(p, h, SHOTS[&"reveal"], az, size)
	cut()
	return dur


## Победитель: медленный облёт. Возвращает длительность.
func winner_orbit(p: Vector3, h: float, size: float = 0.0) -> float:
	return _orbit(p, h, SHOTS[&"winner"], NAN, size)


# ------------------------------------------------------------ бой

## Общий план боя: сбоку и низко (+X), существа лицом к лицу вдоль Z. h — рост существ.
func battle_view(p: Vector3, h: float = 10.0, do_cut: bool = true) -> void:
	_battle_center = p
	_battle_h = h
	var s: Dictionary = SHOTS[&"battle_wide"]
	var off: Vector3 = s["pos"]
	# отъезд растёт с ростом существ, чтобы оба целиком помещались в кадр
	off = Vector3(off.x * maxf(1.0, h / 11.0), off.y, off.z)
	_set_static(p + off, p + Vector3(0, float(s["look_h"]) * h, 0), s)
	if do_cut:
		cut()


## Вернуться к общему плану текущего боя (плавно или катом).
func battle_wide(do_cut: bool = false) -> void:
	battle_view(_battle_center, _battle_h, do_cut)


## Кадр существа: отступы вбок/вперёд — от размера size (наибольшее из роста, длины и размаха), высоты — от роста h.
func _creature_frame(pos: Vector3, facing: Vector3, h: float, s: Dictionary, size: float) -> Array:
	var sz := maxf(h, size)
	var f := Vector3(facing.x, 0, facing.z)
	f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, 1)
	# сбоку — со стороны общего плана (+X), чтобы кат не перескакивал ось
	var side := f.cross(Vector3.UP)
	if side.x < 0.0:
		side = -side
	var cp := pos + side * float(s["side"]) * sz + f * float(s["fwd"]) * sz + Vector3(0, float(s["up"]) * h, 0)
	return [cp, pos + Vector3(0, float(s["look_h"]) * h, 0)]


## Крупный план существа (кат): 3/4 спереди и снизу.
func close_up(pos: Vector3, facing: Vector3, h: float, size: float = 0.0) -> void:
	var s: Dictionary = SHOTS[&"close"]
	var fr := _creature_frame(pos, facing, h, s, size)
	_set_static(fr[0], fr[1], s)
	_avoid = false
	cut()


## Способность: кат на автора и резкий рывок к нему.
func ability_jerk(pos: Vector3, facing: Vector3, h: float, size: float = 0.0) -> void:
	var s: Dictionary = SHOTS[&"ability"]
	var fr := _creature_frame(pos, facing, h, s, size)
	_set_static(fr[0], fr[1], s)
	_avoid = false
	cut()
	_dolly(fr[1].lerp(fr[0], float(s["push"])), float(s["dur"]))


## Удар: быстрый наезд к точке столкновения от текущей позиции.
func impact(point: Vector3) -> void:
	var s: Dictionary = SHOTS[&"impact"]
	_goal_look = point
	_goal_fov = float(s["fov"])
	_dolly(point.lerp(_base, float(s["push"])), float(s["dur"]))


func _dolly(to: Vector3, dur: float) -> void:
	mode = Mode.DOLLY
	_follow = null
	_drift = 0.0
	_dolly_from = _base
	_dolly_to = Vector3(to.x, maxf(to.y, MIN_Y), to.z)
	_dolly_t = 0.0
	_dolly_dur = maxf(dur, 0.01)
