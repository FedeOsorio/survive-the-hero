extends Node2D
## El creep que controla el jugador (el Anti Hero).
## Absorbe cadáveres y gemas, evoluciona, muerde y embiste al héroe.

const B := preload("res://scripts/balance.gd")

var world
var invulnerable := false
var stage := 0
var hp := 1.0
var max_hp := 1.0
var speed := 100.0
var bite := 1.0
var radius := 10.0
var color := Color.WHITE
var biomass := 0.0

var _facing := Vector2.RIGHT
var _bite_cd := 0.0
var _bite_fx := 0.0
var _dash_cd := 0.0
var _spit_cd := 0.0
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dash_hit := false
var _flash := 0.0


func _ready() -> void:
	z_index = 2
	_apply_stage(0)


func stage_name() -> String:
	return B.CREEP_STAGES[stage].name


func evolve_cost() -> float:
	return B.CREEP_STAGES[stage].cost


func can_evolve() -> bool:
	var cost := evolve_cost()
	return cost > 0.0 and biomass >= cost


func _apply_stage(s: int) -> void:
	stage = s
	var d: Dictionary = B.CREEP_STAGES[s]
	max_hp = d.hp
	hp = max_hp
	speed = d.speed
	bite = d.bite
	radius = d.radius
	color = d.color


func _process(delta: float) -> void:
	if not world.running:
		return
	var input := Vector2.ZERO
	var want := {}
	if world.bot_mode:
		input = _bot(want)
	elif not world.sim_mode:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		want = {
			"bite": Input.is_action_just_pressed("bite"),
			"dash": Input.is_action_just_pressed("dash"),
			"spit": Input.is_action_just_pressed("spit"),
			"evolve": Input.is_action_just_pressed("evolve"),
		}
	if input.length() > 0.1:
		_facing = input.normalized()

	if _dash_t > 0.0:
		_dash_t -= delta
		position += _dash_dir * B.DASH_SPEED * delta
		if not _dash_hit and _touching_hero(0.0):
			_dash_hit = true
			world.hero.take_damage(bite * B.DASH_HIT_MULT, true)
	else:
		position += input * speed * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_spit_cd = maxf(_spit_cd - delta, 0.0)
	_bite_fx = maxf(_bite_fx - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)

	if want.get("bite", false) and _bite_cd <= 0.0:
		_do_bite()
	if want.get("spit", false) and _spit_cd <= 0.0:
		_do_spit()
	if want.get("dash", false) and _dash_cd <= 0.0:
		_dash_cd = B.DASH_COOLDOWN
		_dash_t = B.DASH_TIME
		_dash_dir = _facing
		_dash_hit = false
	if want.get("evolve", false) and can_evolve():
		_evolve()

	_absorb()
	queue_redraw()


func _touching_hero(extra: float) -> bool:
	var hero = world.hero
	return position.distance_to(hero.position) <= radius + hero.radius + extra


func _do_bite() -> void:
	_bite_cd = B.BITE_COOLDOWN
	_bite_fx = 0.15
	if _touching_hero(B.BITE_RANGE):
		world.hero.take_damage(bite, true)


func _do_spit() -> void:
	_spit_cd = B.SPIT_COOLDOWN
	# apunta solo al héroe si está a tiro (pensado también para mobile)
	var dir := _facing
	var to_hero: Vector2 = world.hero.position - position
	if to_hero.length() <= B.SPIT_RANGE:
		dir = to_hero.normalized()
	world.spawn_spit(position + dir * radius, dir, bite * B.SPIT_DAMAGE_MULT, true)


## Bot muy simple para el modo --bot: come, evoluciona y ataca cuando es fuerte.
func _bot(want: Dictionary) -> Vector2:
	var hero = world.hero
	var to_hero: Vector2 = hero.position - position
	var d := to_hero.length()
	want["evolve"] = can_evolve()
	if stage >= 3 and hp / max_hp > 0.4:
		want["spit"] = d < B.SPIT_RANGE
		want["bite"] = d < radius + hero.radius + B.BITE_RANGE
		want["dash"] = d < 160.0
		return to_hero / d
	var best = null
	var best_d := INF
	for c in world.corpses:
		var cd := position.distance_to(c.position)
		if c.position.distance_to(hero.position) > 350.0 and cd < best_d:
			best_d = cd
			best = c
	var dir := Vector2.ZERO
	if best != null:
		dir = (best.position - position).normalized()
	if d < 380.0:
		dir -= to_hero / d * 2.0
	return dir.normalized() if dir.length() > 0.1 else Vector2.ZERO


func _evolve() -> void:
	biomass -= evolve_cost()
	_apply_stage(stage + 1)
	world.add_threat(B.THREAT_PER_STAGE)
	world.hud.banner("Evolucionaste: %s" % stage_name())


func _absorb() -> void:
	for c in world.corpses.duplicate():
		if position.distance_to(c.position) < radius + c.radius:
			biomass += c.value
			hp = minf(max_hp, hp + c.value * B.HEAL_PER_BIOMASS)
			world.remove_corpse(c)
	for g in world.gems.duplicate():
		if position.distance_to(g.position) < radius + 6.0:
			biomass += B.GEM_BIOMASS
			if position.distance_to(world.hero.position) < B.STEAL_RADIUS:
				world.add_threat(B.THREAT_PER_STOLEN_GEM)
			world.remove_gem(g)


func take_damage(amount: float) -> void:
	if invulnerable:
		return
	hp -= amount
	_flash = 0.1
	if hp <= 0.0:
		hp = 0.0
		world.end_game(false, "El héroe te mató siendo %s." % stage_name())


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else color
	if _dash_t > 0.0:
		draw_circle(-_dash_dir * radius, radius * 0.8, Color(c, 0.3))
	# cuernos a partir de la etapa 2
	if stage >= 2:
		var side := _facing.orthogonal()
		for s in [-1.0, 1.0]:
			var base: Vector2 = side * s * radius * 0.6 - _facing * radius * 0.2
			var tip: Vector2 = base + (side * s * 0.4 - _facing * 0.6).normalized() * radius * (0.5 + 0.2 * stage)
			draw_colored_polygon(PackedVector2Array([base + side * s * -3.0, base + side * s * 3.0, tip]), c.darkened(0.5))
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0.05, 0.05, 0.05))
	draw_circle(Vector2.ZERO, radius, c)
	var eye_off := _facing * radius * 0.35
	var perp := _facing.orthogonal() * radius * 0.35
	draw_circle(eye_off + perp, 2.0, Color.BLACK)
	draw_circle(eye_off - perp, 2.0, Color.BLACK)
	if _bite_fx > 0.0:
		var reach := radius + B.BITE_RANGE
		draw_arc(Vector2.ZERO, reach, _facing.angle() - 0.9, _facing.angle() + 0.9, 12, Color(1, 1, 1, 0.8), 3.0)
	# anillo indicador para encontrarse en la horda
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.5, 0.5), 1.5)
