extends Node2D
## Cazador del infierno: llega cuando la barra de traición se llena y te caza
## solo a vos. Pega por contacto y tira bolas de fuego con aviso. El héroe y
## la horda lo ignoran. Al morir deja un corazón infernal.

const B := preload("res://scripts/balance.gd")

var world
var hp := 100.0
var max_hp := 100.0
var speed := 100.0
var contact_dps := 10.0
var fire_damage := 10.0
var radius := B.HUNTER_RADIUS
var _fire_t := B.HUNTER_FIRE_EVERY
var _aim_t := 0.0
var _aim := Vector2.RIGHT
var _balls: Array = [] # {pos, dir, travelled}
var _flash := 0.0


## Stats según el creep al aparecer; "index" es cuántos cazadores vinieron antes.
func setup(creep, index: int) -> void:
	var hp_scale := pow(B.HUNTER_NEXT_HP, index)
	var dmg_scale := pow(B.HUNTER_NEXT_DAMAGE, index)
	max_hp = creep.max_hp * B.HUNTER_HP_MULT * hp_scale
	hp = max_hp
	contact_dps = creep.max_hp * B.HUNTER_CONTACT * dmg_scale
	fire_damage = creep.max_hp * B.HUNTER_FIRE_DAMAGE * dmg_scale
	speed = creep.speed * B.HUNTER_SPEED_MULT


func _ready() -> void:
	z_index = 2


func _process(delta: float) -> void:
	if not world.running:
		return
	var p = world.player
	var to_p: Vector2 = p.position - position
	var d := to_p.length()
	if d > radius + p.radius and d > 0.01:
		position += to_p / d * speed * delta
	elif p.stealth_t <= 0.0:
		p.take_damage(contact_dps * delta)

	if _aim_t > 0.0:
		_aim_t -= delta
		if _aim_t <= 0.0:
			_balls.append({"pos": position, "dir": _aim, "travelled": 0.0})
	else:
		_fire_t -= delta
		if _fire_t <= 0.0 and d < B.HUNTER_FIRE_RANGE and d > 0.01:
			_fire_t = B.HUNTER_FIRE_EVERY
			_aim_t = B.HUNTER_FIRE_WARNING
			_aim = to_p / d
	for b in _balls.duplicate():
		var step := B.HUNTER_FIRE_SPEED * delta
		b.pos += b.dir * step
		b.travelled += step
		if b.travelled > B.HUNTER_FIRE_RANGE:
			_balls.erase(b)
		elif b.pos.distance_to(p.position) < p.radius + 7.0:
			p.take_damage(fire_damage)
			_balls.erase(b)
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		world.betrayal.on_hunter_killed(self)


func _draw() -> void:
	if _aim_t > 0.0:
		draw_line(Vector2.ZERO, _aim * B.HUNTER_FIRE_RANGE, Color(1, 0.2, 0.1, 0.55), 2.0)
	var body := Color.WHITE if _flash > 0.0 else Color(0.55, 0.05, 0.08)
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0.05, 0.0, 0.0))
	draw_circle(Vector2.ZERO, radius, body)
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(s * 6, -radius + 4), Vector2(s * 12, -radius + 2), Vector2(s * 10, -radius - 10)]), Color(0.2, 0.0, 0.0))
	draw_circle(Vector2(-5, -3), 2.5, Color(1, 0.8, 0.1))
	draw_circle(Vector2(5, -3), 2.5, Color(1, 0.8, 0.1))
	draw_rect(Rect2(-radius, -radius - 16, radius * 2.0 * hp / max_hp, 3), Color(1, 0.25, 0.2))
	for b in _balls:
		var lp: Vector2 = b.pos - position
		draw_circle(lp, 7.0, Color(1.0, 0.4, 0.05))
		draw_circle(lp, 3.5, Color(1.0, 0.9, 0.3))
