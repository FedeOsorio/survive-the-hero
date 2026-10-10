extends Node2D
## El creep que controla el jugador (el Anti Hero).
## Se mueve y embiste; la mordida y el escupitajo salen solos. Absorbe
## cadáveres, sube de nivel eligiendo mutaciones y evoluciona de etapa.

const B := preload("res://scripts/balance.gd")
const Mutations := preload("res://scripts/mutations.gd")
const CreepBot := preload("res://scripts/creep_bot.gd")

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
var _wave_fx := 0.0
var stealth_cd := 0.0
var stealth_t := 0.0 # mientras dura, el héroe no te puede apuntar
var _dash_victims: Array = []
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
	bite = d.bite * (1.0 + rank("colmillos") * B.MUT_DAMAGE + rank("festin") * B.FEAST_DAMAGE)


func bite_range() -> float:
	return B.BITE_RANGE + (B.JAW_BITE_RANGE if rank("mandibula") > 0 else 0.0)


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
	var hero = world.hero
	if hero == null:
		return 1.0
	var gap: int = hero.level - (power_level() + 3 * stage)
	return clampf(1.0 + gap * B.HUNGER_PER_LEVEL, 1.0, B.HUNGER_MAX)


## Nivel equivalente para medir tu fuerza contra los héroes (subís muchos más niveles que ellos).
func power_level() -> int:
	return roundi(level * B.CREEP_LEVEL_EQUIV)


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
		input = CreepBot.move(self)
		want_evolve = can_evolve()
	elif not world.sim_mode:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		want_dash = Input.is_action_just_pressed("dash")
		want_evolve = Input.is_action_just_pressed("evolve")
		if Input.is_action_just_pressed("stealth") and stealth_cd <= 0.0:
			stealth_cd = B.STEALTH_COOLDOWN
			stealth_t = B.STEALTH_TIME
			world.lose_aggro()
	if input.length() > 0.1:
		_facing = input.normalized()

	if _dash_t > 0.0:
		_dash_t -= delta
		position += _dash_dir * B.DASH_SPEED * delta
		if not _dash_hit and world.hero != null and _in_reach(world.hero, 0.0):
			_dash_hit = true
			world.hero.take_damage(bite * B.DASH_HIT_MULT, true, true)
			world.shake()
		_dash_through()
		if _dash_t <= 0.0 and rank("coraza") > 0:
			_shell_wave()
	else:
		position += input * speed * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_spit_cd = maxf(_spit_cd - delta, 0.0)
	_bite_fx = maxf(_bite_fx - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_wave_fx = maxf(_wave_fx - delta, 0.0)
	stealth_cd = maxf(stealth_cd - delta, 0.0)
	stealth_t = maxf(stealth_t - delta, 0.0)
	modulate.a = 0.35 if stealth_t > 0.0 else 1.0
	_combo_t -= delta
	if _combo_t <= 0.0:
		combo = 1.0

	_auto_attack()
	if want_dash and _dash_cd <= 0.0:
		_dash_cd = B.DASH_COOLDOWN
		_dash_t = B.DASH_TIME
		_dash_dir = _facing
		_dash_hit = false
		_dash_victims.clear()
	if want_evolve and can_evolve():
		_evolve()

	_absorb(delta)
	queue_redraw()


func _in_reach(target, extra: float) -> bool:
	if target == null:
		return false
	return position.distance_to(target.position) <= radius + target.radius + extra


## La embestida le pega una vez a cada Paladín que atraviesa.
func _dash_through() -> void:
	for v in world.infamy.paladins:
		if not _dash_victims.has(v) and _in_reach(v, 0.0):
			_dash_victims.append(v)
			v.take_damage(bite * B.DASH_HIT_MULT)


## Lo más cercano de una lista dentro de "max_dist".
func _closest(list: Array, max_dist: float):
	var best = null
	var best_d := max_dist
	for n in list:
		var d: float = position.distance_to(n.position) - n.radius
		if d < best_d:
			best_d = d
			best = n
	return best


## Mordida y escupitajo automáticos. Prioridad: héroe, Paladín y civiles.
func _auto_attack() -> void:
	var hero = world.hero
	if _bite_cd <= 0.0:
		var victim = null
		var reach := radius + bite_range()
		if _in_reach(hero, bite_range()):
			victim = hero
		else:
			victim = _closest(world.infamy.paladins, reach)
			if victim == null:
				victim = _closest(world.civilians, reach)
		if victim != null:
			_bite_cd = B.BITE_COOLDOWN
			_bite_fx = 0.15
			_bite_dir = (victim.position - position).normalized()
			if victim == hero:
				hero.take_damage(bite, true, true)
				world.shake()
				if rank("mandibula") > 0:
					hero.status.bleed(bite * B.BLEED_MULT)
			else:
				victim.take_damage(bite)
			if rank("mandibula") > 0:
				hp = minf(max_hp, hp + bite * B.JAW_HEAL)
			elif rank("vampiro") > 0:
				hp = minf(max_hp, hp + bite * B.MUT_VAMPIRE * rank("vampiro"))

	if _spit_cd <= 0.0:
		var target = null
		if hero != null and position.distance_to(hero.position) <= B.SPIT_RANGE:
			target = hero
		else:
			target = _closest(world.infamy.paladins, B.SPIT_RANGE)
			if target == null:
				target = _closest(world.civilians, B.SPIT_RANGE)
		if target != null:
			_spit_cd = spit_cooldown()
			var dir: Vector2 = (target.position - position).normalized()
			var shots := 1 + rank("doble")
			for i in shots:
				var offset := (i - (shots - 1) * 0.5) * deg_to_rad(10.0)
				world.spawn_spit(position + dir * radius, dir.rotated(offset), bite * B.SPIT_DAMAGE_MULT, true)


## Coraza viva: onda al terminar la embestida. Daña, empuja y aturde al héroe.
func _shell_wave() -> void:
	_wave_fx = 0.25
	for hero in world.heroes.list.duplicate():
		var to_h: Vector2 = hero.position - position
		if to_h.length() < B.SHELL_WAVE_RADIUS + hero.radius and not hero.rolling():
			hero.take_damage(bite * B.SHELL_WAVE_DAMAGE, true, true)
			world.shake()
			hero.position = (hero.position + to_h.normalized() * B.SHELL_WAVE_PUSH).clamp(Vector2(20, 20), B.ARENA_SIZE - Vector2(20, 20))
			hero.status.stun(B.HERO_STUN_TIME)
	for h in world.infamy.paladins:
		if position.distance_to(h.position) < B.SHELL_WAVE_RADIUS + h.radius:
			h.take_damage(bite * B.SHELL_WAVE_DAMAGE)
	for m in world.minions_near(position):
		var to_m: Vector2 = m.position - position
		if to_m.length() < B.SHELL_WAVE_RADIUS and to_m.length() > 0.01:
			m.position += to_m.normalized() * B.SHELL_WAVE_MINION_PUSH


func _evolve() -> void:
	biomass -= evolve_cost()
	_apply_stage(stage + 1)
	world.hud.banner("Evolucionaste: %s" % stage_name())


# --- Comer --------------------------------------------------------------------

func _absorb(delta: float) -> void:
	var magnet := magnet_radius()
	for c in world.corpses.duplicate():
		var d := position.distance_to(c.position)
		if d < radius + c.radius:
			if c.holy:
				biomass += maxf(evolve_cost(), 0.0) * B.HOLY_HEART_BIOMASS
				world.hud.banner("¡Corazón celestial! Mutación extra" if c.holy_mutations == 1 else "¡Corazón del Capitán! Dos mutaciones")
				for i in c.holy_mutations:
					grant_mutation()
			if c.heart:
				_queued_levels += 1
				world.hud.banner("¡Corazón de élite! Mutación extra")
			_eat(c.value)
			world.remove_corpse(c)
		elif d < radius + magnet:
			c.position = c.position.move_toward(position, B.MAGNET_PULL_SPEED * delta)
	# las gemas son la XP del héroe: pisarlas se las roba y te alimenta (el imán no las atrae)
	for g in world.gems.duplicate():
		if position.distance_to(g.position) < radius + B.GEM_EAT_RANGE:
			_eat(g.xp * B.GEM_BIOMASS)
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


## Mutación gratis (cofre): se suma a la cola de elecciones.
func grant_mutation() -> void:
	_queued_levels += 1
	if pending_choices.is_empty():
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
	elif id == "festin":
		_recalc_stats()
		hp = minf(max_hp, hp + max_hp * B.FEAST_HEAL)
	else:
		_recalc_stats()
	get_tree().paused = world.escaping # si amaneció, el resto sigue quieto
	if _queued_levels > 0:
		_offer_mutation()


func take_damage(amount: float) -> void:
	if invulnerable or _dash_t > 0.0: # la embestida te hace invulnerable
		return
	hp -= amount
	_flash = 0.1
	if hp <= 0.0:
		hp = 0.0
		world.end_game("derrota", "Te mataron siendo %s nivel %d." % [stage_name(), level])


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
		var reach := radius + bite_range()
		draw_arc(Vector2.ZERO, reach, _bite_dir.angle() - 0.9, _bite_dir.angle() + 0.9, 12, Color(1, 1, 1, 0.8), 3.0)
	# cooldown de la embestida
	if _dash_cd > 0.0:
		draw_arc(Vector2.ZERO, radius + 9.0, -PI / 2, -PI / 2 + TAU * (1.0 - _dash_cd / B.DASH_COOLDOWN), 24, Color(1, 1, 1, 0.35), 2.0)
	if _wave_fx > 0.0:
		draw_arc(Vector2.ZERO, B.SHELL_WAVE_RADIUS * (1.0 - _wave_fx * 2.0), 0.0, TAU, 32, Color(0.9, 0.85, 0.6, 0.9), 5.0)
	# anillo indicador para encontrarse en la horda
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.5, 0.5), 1.5)
	# ojo del héroe: cerrado (no te ve), entrecerrado (te busca), abierto rojo (te caza)
	var sight: int = world.sight_level()
	var ep := Vector2(0, -radius - 16.0)
	var ec := Color(1, 0.3, 0.3) if sight == 2 else Color(0.85, 0.85, 0.85, 0.7)
	if sight == 0:
		draw_arc(ep, 6.0, 0.2, PI - 0.2, 10, ec, 2.0)
	else:
		var h := 4.0 if sight == 2 else 2.0
		var pts := PackedVector2Array()
		for i in 13:
			var a := TAU * i / 12.0
			pts.append(ep + Vector2(cos(a) * 7.0, sin(a) * h))
		draw_colored_polygon(pts.slice(0, 12), Color(0.1, 0.05, 0.05, 0.8))
		draw_polyline(pts, ec, 1.5)
		draw_circle(ep, minf(h, 2.5), ec)
