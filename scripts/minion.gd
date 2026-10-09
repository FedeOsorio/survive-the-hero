extends Node2D
## Un creep de la horda (compañero del jugador). Camina hacia el héroe y lo
## lastima por contacto. Al morir deja un cadáver y una gema de experiencia.

const B := preload("res://scripts/balance.gd")

var world
var type_name := ""
var hp := 1.0
var max_hp := 1.0
var speed := 80.0
var dps := 5.0
var radius := 10.0
var xp := 1.0
var biomass := 1.0
var color := Color.WHITE
var _flash := 0.0


func setup(t: String, hp_mult: float) -> void:
	var d: Dictionary = B.MINION_TYPES[t]
	type_name = t
	max_hp = d.hp * hp_mult
	hp = max_hp
	speed = d.speed * randf_range(0.9, 1.1)
	dps = d.dps
	radius = d.radius
	xp = d.xp
	biomass = d.biomass
	color = d.color
	z_index = 1


func _process(delta: float) -> void:
	if not world.running:
		return
	var hero = world.hero
	var to_hero: Vector2 = hero.position - position
	var dist := to_hero.length()
	var touch: float = radius + hero.radius
	var move := Vector2.ZERO
	if dist > touch:
		move = to_hero / dist
	# margen extra para que la separación de la horda no los deje justo afuera
	if dist <= touch + 6.0:
		hero.take_damage(dps * delta, false)

	# separación barata para que la horda no se apile en un solo punto
	var push := Vector2.ZERO
	for other in world.minions_near(position):
		if other == self:
			continue
		var away: Vector2 = position - other.position
		var d := away.length()
		var min_d: float = radius + other.radius
		if d < min_d and d > 0.01:
			push += away / d * (min_d - d) / min_d
	position += (move * speed + push * speed * 1.5) * delta

	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func take_damage(amount: float) -> void:
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		world.on_minion_killed(self)


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else color
	draw_circle(Vector2.ZERO, radius, c.darkened(0.4))
	draw_circle(Vector2.ZERO, radius - 2.0, c)
	var eye := radius * 0.35
	draw_circle(Vector2(-eye, -eye * 0.5), 1.5, Color.BLACK)
	draw_circle(Vector2(eye, -eye * 0.5), 1.5, Color.BLACK)
