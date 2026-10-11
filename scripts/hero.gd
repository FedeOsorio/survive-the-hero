extends "res://scripts/hero_brain.gd"
## Un héroe controlado por la IA (Arquero, Caballero o Maga: ver heroes.gd).
## Farmea la horda, kitea, junta experiencia, sube de nivel, esquiva proyectiles
## y con poca vida se enfurece (furia). Casi no se cura.
## Al jugador lo trata como un creep más hasta enfurecerse; desde ahí sospecha (suspicion, "?").
## En cada nivel sube el poder de su tabla fija (ver hero_powers.gd y B.HEROES).
## Piezas: hero_base.gd (datos) < hero_combat.gd (combate y nivel) < hero_brain.gd (IA) < este (cada frame y dibujo).

func _ready() -> void:
	z_index = 2
	_rng.randomize()
	powers = HeroPowers.new()
	powers.hero = self
	powers.world = world
	add_child(powers)
	traits = HeroTraits.new()
	traits.hero = self
	traits.world = world
	add_child(traits)
	rage = HeroFury.new()
	rage.hero = self
	rage.world = world
	add_child(rage)
	attacks = HeroAttacks.new()
	attacks.hero = self
	attacks.world = world
	add_child(attacks)
	status = HeroStatus.new()
	status.hero = self
	status.world = world
	add_child(status)


## Tipo de héroe (una fila de B.HEROES) y nivel de llegada. Los niveles de llegada
## aplican su tabla de poderes en silencio. Se llama después de agregarlo al árbol.
func setup(cfg: Dictionary, start_level: int) -> void:
	title = cfg.name
	article = cfg.article
	color = cfg.color
	speed_mult = cfg.speed
	damage_mult = cfg.damage
	fire_rate = cfg.fire_rate
	table = cfg.table
	attacks.setup(cfg)
	traits.kind = cfg.name
	rage.kind = cfg.name
	for id in cfg.powers:
		powers.ranks[id] = 1
	for i in start_level - 1:
		_level_up(true)
	max_hp *= cfg.hp
	hp = max_hp
	_apply_ranks()
	_level_fx = 0.0


func _process(delta: float) -> void:
	if not world.running:
		return
	shield_t = maxf(shield_t - delta, 0.0)
	_fury_run_t = maxf(_fury_run_t - delta, 0.0)
	if not fury and hp / max_hp < B.HERO_FURY_HP:
		_enrage()
	_pile_t -= delta
	_update_sight(delta)
	if status.stunned():
		_aim_windup = 0.0
		queue_redraw()
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = _rng.randf_range(B.HERO_REACTION_MIN, B.HERO_REACTION_MAX)
		_think()

	_roll_cd = maxf(_roll_cd - delta, 0.0)
	if _roll_t > 0.0:
		_roll_t -= delta
		position += _roll_dir * B.HERO_ROLL_SPEED * delta
		if _roll_t <= 0.0:
			traits.on_roll_end()
	elif not attacks.busy(): # cargando un ataque de jefe se queda quieto
		_check_roll()
		position += _move_dir * speed * status.speed_mult() * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	# las gemas dentro del radio vuelan hacia él; las junta al tocarlas
	for g in world.gems.duplicate():
		var gd := position.distance_to(g.position)
		if gd < radius + 6.0:
			_gain_xp(g.xp)
			world.remove_gem(g)
		elif gd < pickup_radius():
			g.position = g.position.move_toward(position, B.HERO_GEM_PULL_SPEED * delta)
	for c in world.corpses.duplicate():
		if c.heart and position.distance_to(c.position) < B.HERO_HEART_PICKUP + level * B.HERO_HEART_PICKUP_PER_LEVEL + c.radius:
			_level_up()
			hp = minf(max_hp, hp + max_hp * B.ELITE_HEART_HERO_HEAL)
			world.remove_corpse(c)

	_fire_t -= delta / status.fire_slow() # Tinta del Abisal: dispara más lento
	if attacks.busy():
		_aim_windup = 0.0
	elif _aim_windup > 0.0:
		_aim_windup -= delta
		if _aim_windup <= 0.0:
			_fire_t = rage.fire_cooldown(cooldown)
			_fire_dir(_aim_locked, _close_horde())
	elif _fire_t <= 0.0 and _roll_t <= 0.0 and _target_valid() and position.distance_to(target.position) <= B.HERO_RANGE:
		var at_you: bool = target == world.player and hunting_you()
		var guard: Array = _close_horde() if at_you else []
		if _horde_turn and not guard.is_empty():
			# cazando con creeps cerca, alterna: un disparo a la horda y uno a vos
			_horde_turn = false
			_fire_t = rage.fire_cooldown(cooldown)
			_fire_dir((guard[0].position - position).normalized(), guard.slice(1) if guard.size() > 1 else guard)
		elif at_you:
			# contra el jugador apunta primero y avisa: se puede esquivar
			_horde_turn = true
			_aim_windup = B.HERO_AIM_WINDUP
			_aim_locked = (target.position - position).normalized()
			_aim = _aim_locked
		else:
			_fire_t = rage.fire_cooldown(cooldown)
			_fire()

	if B.HERO_SLASH_ENABLED and level >= B.HERO_SLASH_LEVEL and not attacks.busy():
		_update_slash(delta)

	_flash = maxf(_flash - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_level_fx = maxf(_level_fx - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var body := color
	if _flash > 0.0:
		body = Color.WHITE
	elif _hurt > 0.0:
		body = Color(1.0, 0.5, 0.5)
	draw_circle(Vector2.ZERO, pickup_radius(), Color(color, 0.04))
	var half := deg_to_rad(B.HERO_SLASH_ARC_DEG) * 0.5
	var a := _slash_dir.angle()
	if _slash_windup > 0.0:
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 13:
			pts.append(Vector2.from_angle(a - half + half * 2.0 * i / 12.0) * slash_radius())
		draw_colored_polygon(pts, Color(1.0, 0.3, 0.2, 0.18))
	if _slash_fx > 0.0:
		draw_arc(Vector2.ZERO, slash_radius() * 0.85, a - half, a + half, 16, Color(1, 1, 0.85, 0.9), 6.0)
	if _aim_windup > 0.0:
		draw_line(Vector2.ZERO, _aim_locked * B.HERO_RANGE, Color(1, 0.25, 0.2, 0.55), 2.0)
	if _roll_t > 0.0:
		body = Color(body, 0.45)
	if fury:
		body = body.lerp(Color(1.0, 0.15, 0.1), 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.012))
	if shield_t > 0.0:
		var glow := 0.35 + 0.25 * sin(shield_t * 12.0)
		draw_circle(Vector2.ZERO, radius + 9.0, Color(1.0, 0.85, 0.3, glow))
		body = body.lerp(Color(1.0, 0.85, 0.3), 0.5)
	draw_rect(Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0), Color(0.05, 0.05, 0.1))
	draw_rect(Rect2(Vector2(-radius + 2, -radius + 2), Vector2(radius - 2, radius - 2) * 2.0), body)
	draw_line(Vector2.ZERO, _aim * (radius + 10.0), Color(1, 0.95, 0.7), 3.0)
	if _level_fx > 0.0:
		draw_arc(Vector2.ZERO, radius + 20.0 * (1.0 - _level_fx), 0.0, TAU, 24, Color(1, 1, 0.5, _level_fx), 2.0)
	# "!" rojo si te caza; si no, "?" de gris (sin sospecha) a amarillo (a punto de reconocerte)
	var top := Vector2(0, -radius - 12.0)
	if hunting_you():
		draw_string(ThemeDB.fallback_font, top + Vector2(-6, 0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.25, 0.2))
	elif aware:
		var k := suspicion / B.SUSPICION_MAX
		draw_string(ThemeDB.fallback_font, top + Vector2(-7, 0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.6, 0.6, 0.7).lerp(Color(1.0, 0.85, 0.2), k))
