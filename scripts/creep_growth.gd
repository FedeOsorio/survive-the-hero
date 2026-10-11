extends "res://scripts/creep_base.gd"
## Crecer: comer cadáveres, civiles y gemas, subir de nivel eligiendo mutaciones
## y evolucionar de etapa. La extiende creep.gd.


## Pasarle por encima a un civil lo come al instante (sin esperar la mordida, en cualquier etapa).
func _trample_civilians() -> void:
	for c in world.civilians.duplicate():
		if position.distance_to(c.position) < radius + c.radius + B.CIVILIAN_TRAMPLE_MARGIN:
			c.take_damage(c.hp + 1.0)


func _evolve() -> void:
	biomass -= evolve_cost()
	_apply_stage(stage + 1)
	world.hud.banner("Evolucionaste: %s" % stage_name())
	world.suspect_all(B.SUSPICION_EVOLVE)
	_flash = B.EVOLVE_FLASH
	world.shake()
	world.fx.evolved(position, stage_name())


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
			klass.on_eat(c)
			_eat(c.value)
			world.remove_corpse(c)
			world.suspect_all(B.SUSPICION_EAT)
		elif d < radius + magnet:
			c.position = c.position.move_toward(position, B.MAGNET_PULL_SPEED * delta)
	# las gemas son la XP del héroe: pisarlas se las roba y te alimenta (el imán no las atrae)
	for g in (world.gems.duplicate() if klass.eats_gems() else []):
		if position.distance_to(g.position) < radius + B.GEM_EAT_RANGE:
			_eat(g.xp * B.GEM_BIOMASS)
			world.remove_gem(g)
			world.suspect_all(B.SUSPICION_GEM)


func _eat(value: float) -> void:
	if rank("frenesi") > 0:
		if _combo_t > 0.0:
			combo = minf(combo + B.COMBO_STEP, B.COMBO_MAX + 0.5 * (rank("frenesi") - 1))
		_combo_t = B.COMBO_WINDOW + B.COMBO_WINDOW_PER_RANK * (rank("frenesi") - 1)
	var gained := value * combo * hunger() * B.CREEP_BIOMASS_MULT
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
	pending_choices = Mutations.roll(ranks, stage, _rng, 3, klass.id)
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
	world.fx.mutated(position)
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
