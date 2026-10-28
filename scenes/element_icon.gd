extends RefCounted
## Значок стихии текстурой: тот же знак, что на картах и вспышках (scenes/shaders/sigils.gdshaderinc),
## растрируется на процессоре один раз на стихию и вид. Для подписей существ (Sprite3D рядом с Label3D)
## и 2D-интерфейса (плашки бойцов, подсказки). Подключается через preload (const ElementIcon := preload(...)).
##   badge — тёмный диск с кольцом и знаком в цвете стихии (читается поверх любого фона);
##   glyph — только знак, белый (тонируется modulate), для наложения на цветной шарик.

const SIZE := 96

static var _cache: Dictionary = {}


static func badge(el: int) -> Texture2D:
	return _get(el, true)


static func glyph(el: int) -> Texture2D:
	return _get(el, false)


static func _get(el: int, with_disc: bool) -> Texture2D:
	el = clampi(el, 0, 5)
	var key := el * 2 + (1 if with_disc else 0)
	if not _cache.has(key):
		_cache[key] = _render(el, with_disc)
	return _cache[key]


static func _render(el: int, with_disc: bool) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c: Color = VisualUtil.attr_color(el)
	var bright: Color = c.lightened(0.45)
	var disc_in: Color = c.darkened(0.78)
	var disc_out: Color = c.darkened(0.55)
	# знак крупнее в «глифе» (нет диска вокруг)
	var span: float = 0.36 if with_disc else 0.28
	for y in range(SIZE):
		for x in range(SIZE):
			var e := Vector2((x + 0.5) / SIZE - 0.5, (y + 0.5) / SIZE - 0.5) * span
			var m: float = sigil_mask(e, el)
			if not with_disc:
				img.set_pixel(x, y, Color(1, 1, 1, m))
				continue
			var r: float = e.length()
			var disc: float = _ss(0.172, 0.164, r)
			var rim: float = _ss(0.011, 0.004, absf(r - 0.156))
			var inner: float = _ss(0.004, 0.0015, absf(r - 0.138)) * 0.6
			var col: Color = disc_in.lerp(disc_out, clampf(r / 0.16, 0.0, 1.0))
			col = col.lerp(c.lightened(0.2), clampf(rim + inner, 0.0, 1.0))
			col = col.lerp(bright, m)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(disc * 0.95 + rim, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _ss(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


static func _fill(d: float) -> float:
	return smoothstep(0.006, -0.006, d)


static func _stroke(d: float, w: float) -> float:
	return smoothstep(w, w * 0.4, absf(d))


static func _sd_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var e0 := b - a
	var e1 := c - b
	var e2 := a - c
	var v0 := p - a
	var v1 := p - b
	var v2 := p - c
	var pq0 := v0 - e0 * clampf(v0.dot(e0) / e0.dot(e0), 0.0, 1.0)
	var pq1 := v1 - e1 * clampf(v1.dot(e1) / e1.dot(e1), 0.0, 1.0)
	var pq2 := v2 - e2 * clampf(v2.dot(e2) / e2.dot(e2), 0.0, 1.0)
	var s := signf(e0.x * e2.y - e0.y * e2.x)
	var d0 := Vector2(pq0.dot(pq0), s * (v0.x * e0.y - v0.y * e0.x))
	var d1 := Vector2(pq1.dot(pq1), s * (v1.x * e1.y - v1.y * e1.x))
	var d2 := Vector2(pq2.dot(pq2), s * (v2.x * e2.y - v2.y * e2.x))
	var d := Vector2(minf(minf(d0.x, d1.x), d2.x), minf(minf(d0.y, d1.y), d2.y))
	return -sqrt(d.x) * signf(d.y)


static func _sd_hex(p: Vector2, r: float) -> float:
	var k := Vector3(-0.866025404, 0.5, 0.577350269)
	p = p.abs()
	var kxy := Vector2(k.x, k.y)
	p -= 2.0 * minf(kxy.dot(p), 0.0) * kxy
	p -= Vector2(clampf(p.x, -k.z * r, k.z * r), r)
	return p.length() * signf(p.y)


## Маска знака стихии (порт sigil_mask из sigils.gdshaderinc), e — координаты эмблемы ~±0.13, y вниз.
static func sigil_mask(e: Vector2, id: int) -> float:
	var r := e.length()
	match id:
		0:  # пламя
			var body := (e - Vector2(0.0, 0.035)).length() - 0.062
			var tip := _sd_tri(e, Vector2(-0.058, 0.03), Vector2(0.058, 0.03), Vector2(0.012, -0.135))
			var inner := (e - Vector2(0.0, 0.05)).length() - 0.028
			return clampf(_fill(minf(body, tip)) - _fill(inner) * 0.7, 0.0, 1.0)
		1:  # буря: спираль
			var a := atan2(e.y, e.x) / TAU + 0.5
			var t := r / 0.038 - a
			var d := absf(fposmod(t, 1.0) - 0.5) * 0.038
			return smoothstep(0.01, 0.005, d) * smoothstep(0.125, 0.11, r) * smoothstep(0.008, 0.02, r)
		2:  # свет: звезда
			var ang := atan2(e.y, e.x)
			var rr := 0.045 + 0.085 * pow(absf(cos(ang * 4.0)), 10.0) + 0.03 * pow(absf(cos(ang * 4.0 + 0.785)), 10.0)
			return _fill(r - rr)
		3:  # камень: шестигранник
			return clampf(_fill(_sd_hex(e, 0.085)) - _stroke(_sd_hex(e, 0.045), 0.008) * 0.8, 0.0, 1.0)
		4:  # тень: полумесяц
			return _fill(maxf(e.length() - 0.1, -((e - Vector2(0.045, -0.035)).length() - 0.085)))
	var m := 0.0  # прилив: три волны
	for k in range(-1, 2):
		var y := e.y - float(k) * 0.042 - 0.016 * sin(e.x * 55.0 + float(k))
		m = maxf(m, smoothstep(0.012, 0.006, absf(y)))
	return m * smoothstep(0.115, 0.1, absf(e.x))
