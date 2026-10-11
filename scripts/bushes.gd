extends Node2D
## Arbustos (world.bushes): matas donde el creep se esconde de la sospecha de los héroes.
## Cada mata aguanta BUSH_HIDE_TIME de uso seguido y se marchita BUSH_WITHER_TIME
## (también si la toca un ataque de jefe). Atacar desde adentro te revela un rato.
## Se dibujan por encima del creep y de la horda.

const B := preload("res://scripts/balance.gd")

var world
var _bushes: Array = [] # {pos, use_t, wither_t, blobs: [[offset, radius]]}
var _inside = null # la mata activa donde está el creep, o null
var _reveal_t := 0.0


func _ready() -> void:
	z_index = 4
	var center := B.ARENA_SIZE * 0.5
	var margin := B.BUSH_RADIUS + 40.0
	var tries := 0
	while _bushes.size() < B.BUSH_COUNT and tries < 2000:
		tries += 1
		var pos: Vector2 = Vector2(world.rng.randf_range(margin, B.ARENA_SIZE.x - margin), world.rng.randf_range(margin, B.ARENA_SIZE.y - margin))
		if pos.distance_to(center) < B.BUSH_CENTER_CLEAR or pos.distance_to(world.player.position) < B.BUSH_CENTER_CLEAR:
			continue
		var ok := true
		for b in _bushes:
			if pos.distance_to(b.pos) < B.BUSH_MIN_GAP:
				ok = false
				break
		if ok:
			_bushes.append({"pos": pos, "use_t": 0.0, "wither_t": 0.0, "blobs": _blobs()})


## 3 a 5 arbustos superpuestos que llenan la mata.
func _blobs() -> Array:
	var out: Array = []
	var n: int = world.rng.randi_range(3, 5)
	for i in n:
		var a: float = TAU * i / n + world.rng.randf_range(-0.4, 0.4)
		var r: float = world.rng.randf_range(0.45, 0.6) * B.BUSH_RADIUS
		out.append([Vector2.from_angle(a) * (B.BUSH_RADIUS - r) * 0.9, r])
	return out


func _process(delta: float) -> void:
	if not world.running:
		return
	_reveal_t = maxf(_reveal_t - delta, 0.0)
	var p = world.player
	_inside = null
	for b in _bushes:
		if b.wither_t > 0.0:
			b.wither_t -= delta
			b.use_t = 0.0
			continue
		if p.position.distance_to(b.pos) < B.BUSH_RADIUS:
			_inside = b
			b.use_t += delta
			if b.use_t >= B.BUSH_HIDE_TIME:
				_wither(b)
				_inside = null
		else:
			b.use_t = 0.0 # "uso seguido": salir lo reinicia
	queue_redraw()


func _wither(b: Dictionary) -> void:
	b.wither_t = B.BUSH_WITHER_TIME
	b.use_t = 0.0


## El creep está escondido en una mata (y no atacó hace poco).
func hiding() -> bool:
	return _inside != null and _reveal_t <= 0.0


## Atacaste (escupitajo, embestida, mordida al héroe): si estás adentro, te ven un rato.
func reveal() -> void:
	if _inside != null:
		_reveal_t = B.BUSH_REVEAL_ON_ATTACK


## ¿El arbusto te esconde de "h"? Si te está cazando, solo a más de BUSH_HUNT_ESCAPE_DIST.
func hides_from(h) -> bool:
	if not hiding():
		return false
	if h != null and h.hunting_you():
		return h.position.distance_to(world.player.position) > B.BUSH_HUNT_ESCAPE_DIST
	return true


## Un ataque de jefe (hero_attacks.gd) que toca una mata la quema.
func burn_zone(attacks, z: Dictionary) -> void:
	for b in _bushes:
		if b.wither_t <= 0.0 and attacks._inside(z, b.pos, B.BUSH_RADIUS):
			_wither(b)


func _draw() -> void:
	for b in _bushes:
		var withered: bool = b.wither_t > 0.0
		var dark := Color(0.4, 0.28, 0.12, 0.75) if withered else Color(0.1, 0.32, 0.14, 0.75)
		var light := Color(0.5, 0.36, 0.16, 0.75) if withered else Color(0.16, 0.45, 0.2, 0.75)
		for blob in b.blobs:
			draw_circle(b.pos + blob[0], blob[1], dark)
			draw_circle(b.pos + blob[0] + Vector2(-blob[1] * 0.25, -blob[1] * 0.25), blob[1] * 0.45, light)
		if b == _inside and b.use_t > 0.0:
			var w := B.BUSH_RADIUS * 1.4
			var k: float = 1.0 - b.use_t / B.BUSH_HIDE_TIME
			var at: Vector2 = b.pos + Vector2(-w * 0.5, -B.BUSH_RADIUS - 12.0)
			draw_rect(Rect2(at, Vector2(w, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(at, Vector2(w * k, 4)), Color(0.5, 0.95, 0.4))
	if hiding():
		_leaf(world.player.position + Vector2(0, -world.player.radius - 14.0))


## Ícono de hoja sobre el creep escondido.
func _leaf(at: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), Color(0.45, 0.95, 0.4))
	draw_line(at + Vector2(0, -5), at + Vector2(0, 7), Color(0.15, 0.4, 0.15), 1.0)
