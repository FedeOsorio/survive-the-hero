extends Node2D
## El creep que controla el jugador (el Anti Hero).
## Se mueve y embiste; la mordida y el escupitajo salen solos. Absorbe
## cadáveres, sube de nivel eligiendo mutaciones y evoluciona de etapa.

const B := preload("res://scripts/balance.gd")
const Mutations := preload("res://scripts/mutations.gd")

var world
var invulnerable := false
var stage := 0
var hp := 1.0
var max_hp := 1.0
var speed := 100.0
var bite := 1.0
var radius := 10.0
var color := Color.WHITE
var biomass := 0.0 # se gasta al evolucionar

# Mutaciones
var level := 1
var mut_xp := 0.0
var ranks := {}
var pending_choices: Array = [] # no vacío = esperando que el jugador elija
var _queued_levels := 0

var combo := 1.0
var _combo_t := 0.0

var _facing := Vector2.RIGHT
var _bite_cd := 0.0
var _bite_fx := 0.0
var _bite_dir := Vector2.RIGHT
var _dash_cd := 0.0
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dash_hit := false
var _spit_cd := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 2
	_rng.randomize()
	_apply_stage(0)


func stage_name() -> String:
	return B.CREEP_STAGES[stage].name


func evolve_cost() -> float:
	return B.CREEP_STAGES[stage].cost


func can_evolve() -> bool:
	var cost := evolve_cost()
	return cost > 0.0 and biomass >= cost


func rank(id: String) -> int:
	return ranks.get(id, 0)


# --- Stats derivados (etapa x mutaciones) ------------------------------------

func _apply_stage(s: int) -> void:
	stage = s
	color = B.CREEP_STAGES[s].color
	radius = B.CREEP_STAGES[s].radius
	_recalc_stats()
	hp = max_hp


func _recalc_stats() -> void:
	var d: Dictionary = B.CREEP_STAGES[stage]
	var ratio := hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = d.hp * (1.0 + rank("caparazon") * B.MUT_HP)
	hp = max_hp * ratio
	speed = d.speed * (1.0 + rank("patas") * B.MUT_SPEED)
	bite = d.bite * (1.0 + rank("colmillos") * B.MUT_DAMAGE)


func spit_cooldown() -> float:
	return B.SPIT_COOLDOWN * pow(1.0 - B.MUT_SPIT_RATE, rank("glandula"))


func magnet_radius() -> float:
	return rank("iman") * B.MAGNET_RADIUS_PER_RANK


func lead_radius() -> float:
	if rank("rey") == 0:
		return 0.0
	return B.LEAD_RADIUS + (rank("rey") - 1) * B.LEAD_RADIUS_PER_RANK


func lead_damage_mult() -> float:
	return B.LEAD_DAMAGE_MULT + (rank("rey") - 1) * B.LEAD_DAMAGE_PER_RANK


## Multiplicador de biomasa cuando vas atrás del héroe.
func hunger() -> float:
	var gap: int = world.hero.level - (level + 3 * stage)
	return clampf(1.0 + gap * B.HUNGER_PER_LEVEL, 1.0, B.HUNGER_MAX)


func mut_xp_needed() -> float:
	return B.mutation_xp_for_level(level)


# --- Loop ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not world.running:
		return
	var input := Vector2.ZERO
	var want_dash := false
	var want_evolve := false
	if world.bot_mode:
		input = _bot()
		want_evolve = can_evolve()
	elif not world.sim_mode:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		want_dash = Input.is_action_just_pressed("dash")
		want_evolve = Input.is_action_just_pressed("evolve")
	if input.length() > 0.1:
		_facing = input.normalized()

	if _dash_t > 0.0:
		_dash_t -= delta
		position += _dash_dir * B.DASH_SPEED * delta
		if not _dash_hit and _in_reach(world.hero, 0.0):
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
	_combo_t -= delta
	if _combo_t <= 0.0:
		combo = 1.0

	_auto_attack()
	if want_dash and _dash_cd <= 0.0:
		_dash_cd = B.DASH_COOLDOWN
		_dash_t = B.DASH_TIME
		_dash_dir = _facing
		_dash_hit = false
	if want_evolve and can_evolve():
		_evolve()

	_absorb(delta)
	queue_redraw()


func _in_reach(target, extra: float) -> bool:
	return position.distance_to(target.position) <= radius + target.radius + extra


## Mordida y escupitajo automáticos. Prioriza al héroe; si no, civiles.
func _auto_attack() -> void:
	var hero = world.hero
	if _bite_cd <= 0.0:
		var victim = null
		if _in_reach(hero, B.BITE_RANGE):
			victim = hero
		else:
			for c in world.civilians:
				if _in_reach(c, B.BITE_RANGE):
					victim = c
					break
		if victim != null:
			_bite_cd = B.BITE_COOLDOWN
			_bite_fx = 0.15
			_bite_dir = (victim.position - position).normalized()
			if victim == hero:
				hero.take_damage(bite, true)
			else:
				victim.take_damage(bite)
			if rank("vampiro") > 0:
				hp = minf(max_hp, hp + bite * B.MUT_VAMPIRE * rank("vampiro"))

	if _spit_cd <= 0.0:
		var target = null
		if position.distance_to(hero.position) <= B.SPIT_RANGE:
			target = hero
		else:
			var best_d := B.SPIT_RANGE
			for c in world.civilians:
				var d := position.distance_to(c.position)
				if d < best_d:
					best_d = d
					target = c
		if target != null:
			_spit_cd = spit_cooldown()
			var dir: Vector2 = (target.position - position).normalized()
			var shots := 1 + rank("doble")
			for i in shots:
				var offset := (i - (shots - 1) * 0.5) * deg_to_rad(10.0)
				world.spawn_spit(position + dir * radius, dir.rotated(offset), bite * B.SPIT_DAMAGE_MULT, true)


func _evolve() -> void:
	biomass -= evolve_cost()
	_apply_stage(stage + 1)
	world.add_threat(B.THREAT_PER_STAGE)
	world.hud.banner("Evolucionaste: %s" % stage_name())


# --- Comer --------------------------------------------------------------------

func _absorb(delta: float) -> void:
	var magnet := magnet_radius()
	for c in world.corpses.duplicate():
		var d := position.distance_to(c.position)
		if d < radius + c.radius:
			if c.heart:
				_queued_levels += 1
				if position.distance_to(world.hero.position) < B.STEAL_RADIUS:
					world.add_threat(B.THREAT_PER_STOLEN_GEM * 5.0)
				world.hud.banner("¡Corazón de élite! Mutación extra")
			_eat(c.value)
			world.remove_corpse(c)
		elif d < radius + magnet:
			c.position = c.position.move_toward(position, B.MAGNET_PULL_SPEED * delta)
	for g in world.gems.duplicate():
		if position.distance_to(g.position) < radius + 6.0:
			_eat(B.GEM_BIOMASS)
			if position.distance_to(world.hero.position) < B.STEAL_RADIUS:
				world.add_threat(B.THREAT_PER_STOLEN_GEM)
			world.remove_gem(g)


func _eat(value: float) -> void:
	if rank("frenesi") > 0:
		if _combo_t > 0.0:
			combo = minf(combo + B.COMBO_STEP, B.COMBO_MAX + 0.5 * (rank("frenesi") - 1))
		_combo_t = B.COMBO_WINDOW + B.COMBO_WINDOW_PER_RANK * (rank("frenesi") - 1)
	var gained := value * combo * hunger()
	biomass += gained
	hp = minf(max_hp, hp + gained * B.HEAL_PER_BIOMASS)
	mut_xp += gained
	while mut_xp >= mut_xp_needed():
		mut_xp -= mut_xp_needed()
		level += 1
		_queued_levels += 1
	if pending_choices.is_empty() and _queued_levels > 0:
		_offer_mutation()


func _offer_mutation() -> void:
	_queued_levels -= 1
	pending_choices = Mutations.roll(ranks, stage, _rng)
	if pending_choices.is_empty():
		return
	if world.sim_mode:
		choose_mutation(_rng.randi_range(0, pending_choices.size() - 1))
	else:
		get_tree().paused = true


func choose_mutation(index: int) -> void:
	if index < 0 or index >= pending_choices.size():
		return
	var id: String = pending_choices[index]
	ranks[id] = rank(id) + 1
	pending_choices = []
	if id == "caparazon":
		_recalc_stats()
		hp = minf(max_hp, hp + max_hp * B.MUT_HP)
	else:
		_recalc_stats()
	get_tree().paused = false
	if _queued_levels > 0:
		_offer_mutation()


func take_damage(amount: float) -> void:
	if invulnerable or _dash_t > 0.0: # la embestida te hace invulnerable
		return
	hp -= amount
	_flash = 0.1
	if hp <= 0.0:
		hp = 0.0
		world.end_game(false, "El héroe te mató siendo %s nivel %d." % [stage_name(), level])


## Bot muy simple para el modo --bot: caza civiles y come; ataca al héroe de Demonio.
func _bot() -> Vector2:
	var hero = world.hero
	var to_hero: Vector2 = hero.position - position
	var d := to_hero.length()
	if stage >= 3 and hp / max_hp > 0.4:
		return to_hero / d
	var best = null
	var best_d := INF
	for c in world.corpses + world.civilians:
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


func _draw() -> void:
	var c := Color.WHITE if _flash > 0.0 else color
	if lead_radius() > 0.0:
		draw_arc(Vector2.ZERO, lead_radius(), 0.0, TAU, 48, Color(0.4, 1.0, 0.5, 0.08), 2.0)
	if magnet_radius() > 0.0:
		draw_arc(Vector2.ZERO, radius + magnet_radius(), 0.0, TAU, 32, Color(0.75, 0.45, 0.9, 0.12), 1.5)
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
		draw_arc(Vector2.ZERO, reach, _bite_dir.angle() - 0.9, _bite_dir.angle() + 0.9, 12, Color(1, 1, 1, 0.8), 3.0)
	# cooldown de la embestida
	if _dash_cd > 0.0:
		draw_arc(Vector2.ZERO, radius + 9.0, -PI / 2, -PI / 2 + TAU * (1.0 - _dash_cd / B.DASH_COOLDOWN), 24, Color(1, 1, 1, 0.35), 2.0)
	# anillo indicador para encontrarse en la horda
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.5, 0.5), 1.5)
