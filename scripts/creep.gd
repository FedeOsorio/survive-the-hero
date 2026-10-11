extends "res://scripts/creep_growth.gd"
## El creep que controla el jugador (el Anti Hero).
## Se mueve y embiste; la mordida y el escupitajo salen solos. Absorbe
## cadáveres, sube de nivel eligiendo mutaciones y evoluciona de etapa.
## Cadena: creep_base.gd (variables) → creep_growth.gd (comer y mutar) → creep.gd.


func _ready() -> void:
	z_index = 2
	_rng.randomize()
	klass = CreepClass.make(CreepClass.chosen())
	klass.creep = self
	klass.world = world
	_apply_stage(0)
	ranks[Mutations.powers(klass.id)[0].id] = 1 # el primer poder de la clase es fijo
	add_child(klass)
	abilities = CreepAbilities.new()
	abilities.creep = self
	abilities.world = world
	add_child(abilities)


func _process(delta: float) -> void:
	if not world.running:
		return
	var input := Vector2.ZERO
	var want_dash := false
	if world.bot_mode:
		input = CreepBot.move(self)
	elif not world.sim_mode:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		want_dash = Input.is_action_just_pressed("dash")
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
			if world.hero.blocks_from(position):
				# de frente contra el escudo del Caballero: lo empuja pero no lo daña
				world.hero.position += _dash_dir * B.SHIELD_DASH_PUSH
			else:
				world.hero.take_damage(bite * B.DASH_HIT_MULT, true, true)
			world.shake()
			world.fx.melee_hit()
		_dash_through()
	elif root_t <= 0.0:
		position += input * speed * (1.0 - _slow if slow_t > 0.0 else 1.0) * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_bite_fx = maxf(_bite_fx - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	stealth_cd = maxf(stealth_cd - delta, 0.0)
	stealth_t = maxf(stealth_t - delta, 0.0)
	root_t = maxf(root_t - delta, 0.0)
	slow_t = maxf(slow_t - delta, 0.0)
	modulate.a = 0.35 if stealth_t > 0.0 else (0.5 if world.bushes.hiding() else 1.0)
	_combo_t -= delta
	if _combo_t <= 0.0:
		combo = 1.0

	_trample_civilians()
	_auto_attack()
	if want_dash and _dash_cd <= 0.0 and root_t <= 0.0:
		_dash_cd = B.DASH_COOLDOWN
		_dash_t = B.DASH_TIME
		_dash_dir = _facing
		_dash_hit = false
		_dash_victims.clear()
		world.bushes.reveal()
	# la evolución de etapa es automática (si hay una elección de mutación abierta, al cerrarla)
	if can_evolve() and pending_choices.is_empty():
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


## Mordida y escupitajo automáticos. Prioridad: héroe, Paladín y civiles (con la mordida y, sin héroe a tiro, el escupitajo).
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
				world.fx.melee_hit()
				world.bushes.reveal()
				if rank("mandibula") > 0:
					hero.status.bleed(bite * B.BLEED_MULT)
			else:
				victim.take_damage(bite)
			if rank("mandibula") > 0:
				hp = minf(max_hp, hp + bite * B.JAW_HEAL)
			elif rank("vampiro") > 0:
				hp = minf(max_hp, hp + bite * B.MUT_VAMPIRE * rank("vampiro"))


func take_damage(amount: float) -> void:
	if invulnerable or _dash_t > 0.0: # la embestida te hace invulnerable
		return
	_flash = B.FX_FLASH
	world.fx.player_hit(amount)
	if klass.take_hit(amount): # la Reina no tiene vida normal
		return
	hp -= amount
	if hp <= 0.0:
		die()


func die() -> void:
	hp = 0.0
	world.end_game("derrota", "Te mataron siendo %s nivel %d." % [stage_name(), level])


## Corta la embestida (el viaje del Abisal).
func stop_dash() -> void:
	_dash_t = 0.0


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
