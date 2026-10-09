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
var shot_range := 0.0 # > 0: ataca a distancia
var shot_cooldown := 0.0
var shot_damage := 0.0
var _shot_t := 0.0
var _flash := 0.0
var elite := false
var led := false # cerca del jugador: más rápido y más fuerte
var raised := false # levantado por Señor de la carroña: dura poco y no deja nada
var raise_t := 0.0
var boost_t := 0.0 # estampida: corre más rápido un rato


func setup(t: String, minute: float, is_elite := false) -> void:
	var d: Dictionary = B.MINION_TYPES[t]
	type_name = t
	elite = is_elite
	max_hp = d.hp * B.minion_hp_mult(minute) * (B.ELITE_HP_MULT if elite else 1.0)
	hp = max_hp
	speed = d.speed * B.minion_speed_mult(minute) * randf_range(0.9, 1.1)
	dps = d.dps * B.minion_dps_mult(minute)
	radius = d.radius
	xp = d.xp
	biomass = d.biomass
	color = Color(1.0, 0.8, 0.2) if elite else d.color
	if elite:
		radius *= 1.4
	shot_range = d.get("range", 0.0)
	shot_cooldown = d.get("shot_cooldown", 0.0)
	shot_damage = d.get("shot_damage", 0.0) * B.minion_dps_mult(minute)
	_shot_t = randf() * shot_cooldown
	z_index = 1


func _process(delta: float) -> void:
	if not world.running:
		return
	var hero = world.heroes.nearest(position)
	var player = world.player
	led = position.distance_to(player.position) < player.lead_radius()
	if raised:
		raise_t -= delta
		if raise_t <= 0.0:
			world.on_minion_killed(self)
			return
	boost_t = maxf(boost_t - delta, 0.0)
	var spd := speed * (B.LEAD_SPEED_MULT if led else 1.0) * (B.STAMPEDE_SPEED_MULT if boost_t > 0.0 else 1.0)
	var dmg_mult: float = (player.lead_damage_mult() if led else 1.0) * world.events.damage_mult()
	var move := Vector2.ZERO
	if hero == null:
		# sin héroes vivos, la horda te sigue de cerca hasta que llegue el próximo
		var to_p: Vector2 = player.position - position
		if to_p.length() > B.HORDE_IDLE_DIST:
			move = to_p.normalized()
		_separate_and_move(move, spd, delta)
		return
	var to_hero: Vector2 = hero.position - position
	var dist := to_hero.length()
	var touch: float = radius + hero.radius
	if shot_range > 0.0:
		if dist > shot_range * 0.9:
			move = to_hero / dist
		_shot_t -= delta
		if _shot_t <= 0.0 and dist <= shot_range:
			_shot_t = shot_cooldown
			world.spawn_spit(position, to_hero / dist, shot_damage * dmg_mult, false)
	elif dist > touch:
		move = to_hero / dist
	# margen extra para que la separación de la horda no los deje justo afuera
	if dps > 0.0 and dist <= touch + 6.0:
		hero.take_damage(dps * dmg_mult * delta, false)
	# al Paladín también le pegan si lo tocan
	for pal in world.infamy.paladins:
		if dps > 0.0 and position.distance_to(pal.position) <= radius + pal.radius + 6.0:
			pal.take_damage(dps * dmg_mult * delta)

	_separate_and_move(move, spd, delta)


func _separate_and_move(move: Vector2, spd: float, delta: float) -> void:
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
	position += (move * spd + push * speed * 1.5) * delta

	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


## Lo levanta Señor de la carroña: mismo tipo y vida, verdoso, por unos segundos.
func make_raised() -> void:
	raised = true
	raise_t = B.RAISE_TIME
	hp = max_hp
	color = B.RAISED_COLOR


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		world.on_minion_killed(self)


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else color
	draw_circle(Vector2.ZERO, radius, Color(0.5, 1.0, 0.55) if led else c.darkened(0.4))
	draw_circle(Vector2.ZERO, radius - 2.0, c)
	var eye := radius * 0.35
	draw_circle(Vector2(-eye, -eye * 0.5), 1.5, Color.BLACK)
	draw_circle(Vector2(eye, -eye * 0.5), 1.5, Color.BLACK)
