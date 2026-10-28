class_name Attr
extends RefCounted
## Атрибуты и цикл преимуществ: Пламя > Буря > Свет > Камень > Тень > Прилив > Пламя.

enum A { FIRE, GALE, LIGHT, STONE, SHADOW, TIDE }

const COUNT: int = 6
const NAMES: Array[String] = ["Пламя", "Буря", "Свет", "Камень", "Тень", "Прилив"]


## true, если атрибут a бьёт атрибут b.
static func beats(a: int, b: int) -> bool:
	return (a + 1) % COUNT == b


## Атрибут, который бьёт атрибут a (нужен для «Перелива»).
static func beaten_by(a: int) -> int:
	return (a + COUNT - 1) % COUNT


static func display_name(a: int) -> String:
	if a < 0 or a >= COUNT:
		return "?"
	return NAMES[a]
