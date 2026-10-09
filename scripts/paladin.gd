extends Node2D
## Paladín del cielo: llega cuando se llena la Infamia, se une al héroe y te caza.
## Martillazo con aviso (arco), carga en línea recta con aviso (línea dorada)
## y aura que cura al héroe si están cerca. Tu horda le pega; el héroe no.
## Al morir deja un corazón celestial. Cada 3.º soldado es un Capitán: más grande,
## más fuerte y su martillazo deja una onda alrededor.

const B := preload("res://scripts/balance.gd")

var world
var hp := 100.0
var max_hp := 100.0
var speed := 100.0
var hammer_damage := 10.0
var charge_damage := 10.0
var radius := B.PALADIN_RADIUS
var _hammer_cd := 0.0
var _hammer_t := 0.0 # aviso del martillazo
var _hammer_dir := Vector2.RIGHT
var _hammer_fx := 0.0
var _charge_cd := B.PALADIN_CHARGE_EVERY
var _charge_aim := 0.0 # aviso de la carga
var _charge_left := 0.0 # distancia que le queda a la carga
var _charge_dir := Vector2.RIGHT
var _charge_hit := false
var _flash := 0.0
var _healing := false
var captain := false


## Stats según el creep al aparecer; "index" es cuántos soldados vinieron antes.
func setup(creep, index: int) -> void:
	var tier := index / B.PALADIN_TIER_EVERY
	captain = is_captain(index)
	var hp_scale := (1.0 + B.PALADIN_TIER_HP * tier) * (B.CAPTAIN_HP_MULT if captain else 1.0)
	var dmg_scale := (1.0 + B.PALADIN_TIER_DAMAGE * tier) * (B.CAPTAIN_DAMAGE_MULT if captain else 1.0)
	if captain:
		radius = B.CAPTAIN_RADIUS
	max_hp = creep.max_hp * B.PALADIN_HP_MULT * hp_scale
	hp = max_hp
	speed = creep.speed * B.PALADIN_SPEED_MULT
	hammer_damage = creep.max_hp * B.PALADIN_HAMMER_DAMAGE * dmg_scale
	charge_damage = creep.max_hp * B.PALADIN_CHARGE_DAMAGE * dmg_scale


## El soldado número index + 1 es Capitán si es el 3.º, 6.º, 9.º...
static func is_captain(index: int) -> bool:
	return (index + 1) % B.PALADIN_TIER_EVERY == 0


func _ready() -> void:
	z_index = 2


func hammer_reach() -> float:
	return radius + B.PALADIN_HAMMER_RANGE


func _process(delta: float) -> void:
	if not world.running:
		return
	var p = world.player
	var to_p: Vector2 = p.position - position
	var d := to_p.length()
	_hammer_cd = maxf(_hammer_cd - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_hammer_fx = maxf(_hammer_fx - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)

	# aura: la cura la aplica infamy.gd una sola vez aunque haya varios cerca
	_healing = world.heroes.any_within(position, B.PALADIN_HEAL_RADIUS)

	if _charge_left > 0.0:
		var step := B.PALADIN_CHARGE_SPEED * delta
		position += _charge_dir * step
		_charge_left -= step
		if not _charge_hit and position.distance_to(p.position) < radius + p.radius:
			_charge_hit = true
			p.take_damage(charge_damage)
	elif _charge_aim > 0.0:
		_charge_aim -= delta
		if _charge_aim <= 0.0:
			_charge_left = B.PALADIN_CHARGE_DIST
			_charge_hit = false
	elif _hammer_t > 0.0:
		_hammer_t -= delta
		if _hammer_t <= 0.0:
			_hammer()
	else:
		if _charge_cd <= 0.0 and d < B.PALADIN_CHARGE_RANGE and d > hammer_reach() + p.radius:
			_charge_cd = B.PALADIN_CHARGE_EVERY
			_charge_aim = B.PALADIN_CHARGE_WINDUP
			_charge_dir = to_p / d
		elif _hammer_cd <= 0.0 and d < hammer_reach() + p.radius:
			_hammer_cd = B.PALADIN_HAMMER_COOLDOWN
			_hammer_t = B.PALADIN_HAMMER_WINDUP
			_hammer_dir = to_p / d if d > 0.01 else Vector2.RIGHT
		elif d > radius + p.radius and d > 0.01:
			position += to_p / d * speed * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))
	queue_redraw()


func _hammer() -> void:
	_hammer_fx = 0.15
	var p = world.player
	var to_p: Vector2 = p.position - position
	var half := deg_to_rad(B.PALADIN_HAMMER_ARC_DEG) * 0.5
	var hit: bool = to_p.length() < hammer_reach() + p.radius and absf(_hammer_dir.angle_to(to_p)) <= half
	if captain and to_p.length() < B.CAPTAIN_WAVE_RADIUS + p.radius:
		hit = true
	if hit:
		p.take_damage(hammer_damage)


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		world.infamy.on_paladin_killed(self)


func _draw() -> void:
	if _healing:
		draw_arc(Vector2.ZERO, B.PALADIN_HEAL_RADIUS, 0.0, TAU, 40, Color(0.5, 1.0, 0.6, 0.25), 1.5)
	var half := deg_to_rad(B.PALADIN_HAMMER_ARC_DEG) * 0.5
	var a := _hammer_dir.angle()
	if _hammer_t > 0.0:
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 13:
			pts.append(Vector2.from_angle(a - half + half * 2.0 * i / 12.0) * hammer_reach())
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.3, 0.25))
		if captain:
			draw_circle(Vector2.ZERO, B.CAPTAIN_WAVE_RADIUS, Color(1.0, 0.75, 0.1, 0.12))
			draw_arc(Vector2.ZERO, B.CAPTAIN_WAVE_RADIUS, 0.0, TAU, 40, Color(1.0, 0.75, 0.1, 0.7), 2.0)
	if _hammer_fx > 0.0:
		draw_arc(Vector2.ZERO, hammer_reach() * 0.85, a - half, a + half, 16, Color(1, 1, 0.85, 0.9), 6.0)
		if captain:
			draw_arc(Vector2.ZERO, B.CAPTAIN_WAVE_RADIUS * (1.0 - _hammer_fx * 2.0), 0.0, TAU, 40, Color(1.0, 0.85, 0.3, 0.9), 5.0)
	if _charge_aim > 0.0:
		draw_line(Vector2.ZERO, _charge_dir * B.PALADIN_CHARGE_DIST, Color(1.0, 0.85, 0.2, 0.7), 3.0)
	var gold := Color(1.0, 0.75, 0.15) if captain else Color(0.95, 0.88, 0.6)
	var body := Color.WHITE if _flash > 0.0 else gold
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0.3, 0.25, 0.05))
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2(0, -radius - 6), 8.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.3), 2.0) # aureola
	for s in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([Vector2(s * radius * 0.8, -2), Vector2(s * (radius + 14), -10), Vector2(s * (radius + 10), 6)]), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(-radius, -radius - 18, radius * 2.0 * hp / max_hp, 3), Color(1.0, 0.85, 0.3))
