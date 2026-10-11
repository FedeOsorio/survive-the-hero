extends "res://scripts/hero_base.gd"
## Combate del héroe: rodada, tajo, disparos, daño recibido, furia, XP y subir de nivel.

## Si un escupitajo del jugador viene directo hacia él y tiene la rodada lista, rueda.
func _check_roll() -> void:
	if _roll_cd > 0.0:
		return
	for s in world.spits:
		if not s.from_player or s.dodge_roll > B.HERO_DODGE_CHANCE:
			continue
		# sin detectarte no gasta la rodada en escupitajos que casi no le hacen nada
		if not hunting_you() and s.damage < max_hp * B.HERO_DODGE_MIN_DAMAGE:
			continue
		var rel: Vector2 = position - s.position
		var along: float = rel.dot(s.direction)
		if along <= 0.0 or along > B.HERO_DODGE_LOOKAHEAD:
			continue
		var lateral: Vector2 = rel - s.direction * along
		if lateral.length() < radius + 14.0:
			_roll_dir = lateral.normalized() if lateral.length() > 0.5 else s.direction.orthogonal()
			_roll_t = B.HERO_ROLL_TIME
			_roll_cd = traits.roll_cooldown()
			_aim_windup = 0.0
			return


## Tajo: cuando hay enemigos encima, avisa (windup) y después golpea en arco.
func _update_slash(delta: float) -> void:
	_slash_cd = maxf(_slash_cd - delta, 0.0)
	_slash_fx = maxf(_slash_fx - delta, 0.0)
	var r := slash_radius()
	if _slash_windup > 0.0:
		_slash_windup -= delta
		if _slash_windup <= 0.0:
			_do_slash(r)
		return
	if _slash_cd > 0.0:
		return
	var close = _nearest_enemy(r)
	if close != null:
		_slash_dir = (close.position - position).normalized()
		_slash_windup = B.HERO_SLASH_WINDUP
		_slash_cd = B.HERO_SLASH_COOLDOWN


func _do_slash(r: float) -> void:
	_slash_fx = 0.15
	var half := deg_to_rad(B.HERO_SLASH_ARC_DEG) * 0.5
	var dmg := damage * B.HERO_SLASH_DAMAGE_MULT
	var victims: Array = world.minions.duplicate()
	victims.append(world.player)
	var dealt := 0.0
	for v in victims:
		var to_v: Vector2 = v.position - position
		if to_v.length() < r + v.radius and absf(_slash_dir.angle_to(to_v)) <= half:
			dealt += minf(dmg, v.hp)
			v.take_damage(dmg)
			if v != world.player and v.hp <= 0.0:
				rage.on_kill()
	rage.on_melee_damage(dealt)


func _fire() -> void:
	_fire_dir((target.position - position).normalized())


## Con "extra" (creeps cercanos), la primera flecha va a "base" y las demás a esos creeps.
func _fire_dir(base: Vector2, extra: Array = []) -> void:
	var dir := base.rotated(deg_to_rad(_rng.randf_range(-B.HERO_AIM_ERROR_DEG, B.HERO_AIM_ERROR_DEG)))
	if status.blinded(): # Nube de la Reina: tira para cualquier lado
		dir = Vector2.from_angle(_rng.randf() * TAU)
		extra = []
	_aim = dir
	var spread := deg_to_rad(12.0)
	for i in arrows:
		var d := dir.rotated((i - (arrows - 1) * 0.5) * spread)
		if not extra.is_empty():
			d = dir
			if i > 0:
				var m = extra[(i - 1) % extra.size()]
				if is_instance_valid(m):
					d = (m.position - position).normalized()
		world.spawn_projectile(position + dir * radius, d, damage, pierce, self)


## Creeps a menos de HUNT_SHARE_RADIUS, del más cercano al más lejano.
func _close_horde() -> Array:
	var out: Array = []
	for m in world.minions:
		if position.distance_to(m.position) < B.HUNT_SHARE_RADIUS:
			out.append(m)
	out.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
	return out


func take_damage(amount: float, from_player: bool, melee := false, tick := false) -> void:
	if hp <= 0.0 or shield_t > 0.0:
		return
	if from_player:
		amount = traits.filter_damage(amount, melee, tick)
		status.log_damage(amount, melee)
		status.show_damage(amount, tick)
	damage_taken["jugador" if from_player else "horda"] += amount
	amount = rage.absorb(amount) # escudo de maná de la Maga
	if not from_player:
		# la horda lo desgasta pero el golpe final solo lo puede dar el jugador
		hp = maxf(hp - amount, 1.0)
		_hurt = 0.05
		return
	hp -= amount
	if from_player and not tick:
		_flash = B.HERO_HIT_FLASH
	if hp <= 0.0:
		hp = 0.0
		world.heroes.on_hero_killed(self)


## Bajo HERO_FURY_HP: corre unos segundos alejándose y después ataca más seguido,
## con el ataque 3 aunque no tenga nivel. No hay más retirada. Enciende el reconocimiento.
func _enrage() -> void:
	fury = true
	aware = true
	suspicion = B.HERO_SUSPICION_START_ON_FURY
	_fury_run_t = B.HERO_FURY_RUN_TIME
	shield_t = maxf(shield_t, B.HERO_FURY_SHIELD_TIME)
	attacks.every *= B.HERO_FURY_ATTACK_MULT
	attacks.unlock_all = true
	world.hud.banner("¡%s se enfurece!" % full_name())


func _gain_xp(amount: float) -> void:
	xp += amount
	while xp >= B.xp_for_level(level):
		xp -= B.xp_for_level(level)
		_level_up()


## Sube un nivel: números y el poder de su fila en la tabla. "quiet": sin banner.
func _level_up(quiet := false) -> void:
	level += 1
	max_hp += B.HERO_HP_PER_LEVEL
	hp = minf(max_hp, hp + B.HERO_HP_PER_LEVEL + max_hp * B.HERO_LEVEL_HEAL)
	powers.apply_level(level, table, quiet)
	_apply_ranks()
	_level_fx = 0.6


func _apply_ranks() -> void:
	damage = B.HERO_ARROW_DAMAGE * damage_mult * (1.0 + B.HERO_DAMAGE_PER_LEVEL * (level - 1))
	var wait := maxf(B.HERO_ARROW_COOLDOWN * (1.0 - B.HERO_COOLDOWN_PER_LEVEL * (level - 1)), B.HERO_MIN_COOLDOWN)
	cooldown = wait / fire_rate
	arrows = 1 + level / B.HERO_LEVELS_PER_EXTRA_ARROW + powers.rank("multiple")
	pierce = B.HERO_ARROW_PIERCE + powers.rank("perforante")
	speed = B.HERO_SPEED * speed_mult * (1.0 + B.POWER_SPEED * powers.rank("botas"))
