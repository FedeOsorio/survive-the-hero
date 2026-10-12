extends "res://scripts/creep_class.gd"
## Reina del enjambre: no tiene vida normal, su vida son los insectos que la rodean.
## Cada golpe mata insectos (vida de etapa / máximo de insectos por insecto) y muere
## al quedarse sin ninguno en casa. Comer cadáveres y civiles cría.
## Poderes: A picar (fijo: parte del enjambre sale a picar; los que salen no la
## protegen), Nube (el enjambre envuelve al héroe y lo ciega), Aguijón, Zumbido,
## Colmena, Avispas de fuego, Alas de acero, Larvas, Reina madre y Enjambre cazador.
## C: Escudo de insectos (menos daño por golpe, pero muere un insecto más).
## Caparazón le suma insectos máximos.

var home := B.SWARM_START
var _sorties: Array = [] # {target, n, t}: salen cada SWARM_SEND_EVERY y pican STING_TIME (se pueden pisar)
var _send_cd := 1.0
var _cloud = null # {target, n, t}
var _cloud_cd := B.SWARM_CLOUD_EVERY
var _breed_t := 0.0
var _shield_cd := 0.0 # C: Escudo de insectos
var _shield_t := 0.0
var _larvae: Array = [] # {pos, t}


func max_insects() -> int:
	var base: int = B.SWARM_MAX[creep.stage] + B.SWARM_SHELL_INSECTS * creep.rank("caparazon")
	return roundi(base * (1.0 + B.SWARM_MOTHER_PER_RANK * creep.rank("madre")))


## C: Escudo de insectos. Alas de acero lo alarga.
func ability() -> void:
	if _shield_cd > 0.0 or home <= 0:
		return
	_shield_cd = B.SWARM_SHIELD_COOLDOWN
	_shield_t = B.SWARM_SHIELD_TIME + B.SWARM_STEEL_WINGS_PER_RANK * creep.rank("alas")


func away() -> int:
	var n: int = _cloud.n if _cloud != null else 0
	for s in _sorties:
		n += s.n
	return n


func _per_insect() -> float:
	return creep.max_hp / max_insects()


func _breed(n: int) -> void:
	home = mini(home + n, maxi(max_insects() - away(), home))


func on_eat(c) -> void:
	_breed(B.SWARM_PER_CIVILIAN if c.has_meta("civilian") else B.SWARM_PER_CORPSE)
	if creep.rank("larvas") > 0:
		_larvae.append({"pos": c.position, "t": B.SWARM_LARVA_TIME})


func take_hit(amount: float) -> bool:
	if home <= 0:
		home = 0
		creep.die()
		return true
	var extra := 0
	if _shield_t > 0.0:
		amount *= 1.0 - B.SWARM_SHIELD_REDUCTION
		extra = B.SWARM_SHIELD_EXTRA_KILL
	var killed := mini(maxi(ceili(amount / _per_insect()), 1) + extra, home)
	home -= killed
	if creep.rank("avispas") > 0:
		_fire_wasps(killed)
	if home <= 0:
		home = 0
		_sync()
		creep.die()
	return true


func hp_text() -> String:
	var out := away()
	var shield := "Escudo (C) listo" if _shield_cd <= 0.0 else "Escudo (C) %ds" % ceili(_shield_cd)
	return "Enjambre %d/%d" % [home, max_insects()] + (" (+%d afuera)" % out if out > 0 else "") + " · " + shield


func _sync() -> void:
	creep.hp = clampf(home * _per_insect(), 0.0, creep.max_hp)


func _process(delta: float) -> void:
	if not world.running:
		return
	_breed_t += delta
	var every: float = B.SWARM_BREED_EVERY * pow(B.SWARM_HIVE_MULT, creep.rank("colmena"))
	if _breed_t >= every:
		_breed_t = 0.0
		_breed(1)
	_update_sortie(delta)
	if creep.rank("nube") > 0 or _cloud != null:
		_update_cloud(delta)
	_update_extras(delta)
	_sync()
	queue_redraw()


# --- Arma inicial: salida a picar -------------------------------------------------

func _update_sortie(delta: float) -> void:
	for s in _sorties.duplicate():
		var t = s.target
		s.t -= delta
		if s.t <= 0.0 or not is_instance_valid(t) or not t in targets():
			home += s.n
			_sorties.erase(s)
		else:
			hurt(t, s.n * creep.bite * B.SWARM_STING_DPS * delta, true)
	_send_cd -= delta
	if _send_cd > 0.0:
		return
	var t = nearest_target(creep.position, B.SWARM_SEND_RANGE)
	if t == null:
		return
	var extra: int = B.SWARM_PICK_EXTRA_PER_RANK * maxi(creep.rank("picar") - 1, 0)
	var n := maxi(ceili(home * B.SWARM_SEND_SHARE), B.SWARM_SEND_MIN) + extra
	if home - n < 1:
		return # sin insectos de sobra no sale nadie
	_send_cd = maxf(B.SWARM_SEND_EVERY - B.SWARM_PICK_CD_PER_RANK * maxi(creep.rank("picar") - 1, 0), 1.0)
	home -= n
	_sorties.append({"target": t, "n": n, "t": B.SWARM_STING_TIME})
	if creep.rank("aguijon") > 0 and not is_paladin(t):
		t.status.bleed(n * creep.bite * B.SWARM_STINGER_BLEED * B.SWARM_STINGER_TIME * creep.pmult("aguijon"))
	if creep.rank("zumbido") > 0 and is_paladin(t):
		t.confuse(B.SWARM_BUZZ_CONFUSE * creep.pmult("zumbido"))


# --- Nube -------------------------------------------------------------------------

func _update_cloud(delta: float) -> void:
	if _cloud != null:
		_cloud.t -= delta
		if _cloud.t <= 0.0 or not is_instance_valid(_cloud.target):
			home += _cloud.n
			_cloud = null
		return
	_cloud_cd -= delta
	if _cloud_cd > 0.0 or home <= 0:
		return
	var hero = world.hero
	if hero == null or creep.position.distance_to(hero.position) > B.SWARM_CLOUD_RANGE:
		return
	_cloud_cd = B.SWARM_CLOUD_EVERY * creep.pcd("nube")
	var time: float = B.SWARM_CLOUD_TIME[creep.stage] * creep.pmult("nube")
	_cloud = {"target": hero, "n": home, "t": time}
	home = 0 # la apuesta: mientras dura, un golpe te mata
	hero.status.blind(time)


# --- Avispas, Escudo, Larvas y Enjambre cazador -----------------------------------

func _fire_wasps(killed: int) -> void:
	var r := B.SWARM_FIRE_WASP_RADIUS
	for t in targets():
		if creep.position.distance_to(t.position) < r + t.radius:
			hurt(t, creep.bite * B.SWARM_FIRE_WASP_DAMAGE * killed * creep.pmult("avispas"))
	world.fx.explosion(creep.position, r, Color(1.0, 0.5, 0.15))


func _update_extras(delta: float) -> void:
	_shield_t = maxf(_shield_t - delta, 0.0)
	_shield_cd = maxf(_shield_cd - delta, 0.0)
	for l in _larvae.duplicate():
		l.t -= delta
		if l.t <= 0.0:
			_larvae.erase(l)
			_breed(roundi(B.SWARM_LARVA_INSECTS * creep.pmult("larvas")))
	if creep.rank("cazador") > 0 and home > 0:
		for t in targets():
			if creep.position.distance_to(t.position) < B.SWARM_HUNTER_RADIUS + t.radius:
				hurt(t, creep.bite * B.SWARM_HUNTER_DPS * creep.pmult("cazador") * delta, true)


# --- Dibujo -----------------------------------------------------------------------

func _draw() -> void:
	var t: float = world.elapsed
	var col := Color(0.15, 0.12, 0.05)
	if _shield_t > 0.0: # el enjambre en casa hace un anillo cerrado
		draw_arc(creep.position, creep.radius + 20.0, 0.0, TAU, 40, Color(0.7, 0.85, 0.95, 0.35 + 0.15 * sin(t * 8.0)), 6.0)
		for i in mini(home, 40):
			draw_circle(creep.position + Vector2.from_angle(TAU * i / mini(home, 40) + t * 3.0) * (creep.radius + 20.0), 2.2, col)
	elif _shield_cd > 0.0:
		var k: float = _shield_cd / B.SWARM_SHIELD_COOLDOWN
		draw_arc(creep.position, creep.radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - k), 24, Color(0.7, 0.85, 0.95, 0.5), 2.0)
	if creep.rank("cazador") > 0:
		draw_arc(creep.position, B.SWARM_HUNTER_RADIUS, 0.0, TAU, 40, Color(0.6, 0.5, 0.2, 0.2), 1.5)
	for l in _larvae:
		draw_circle(l.pos + Vector2(0, sin(t * 5.0) * 1.5), 3.0, Color(0.95, 0.95, 0.8))
	for i in mini(home, 60):
		var a: float = TAU * i / maxf(mini(home, 60), 1.0) + t * (1.5 + (i % 3) * 0.4)
		var r: float = creep.radius + 8.0 + (i % 4) * 4.0 + 2.0 * sin(t * 7.0 + i)
		draw_circle(creep.position + Vector2.from_angle(a) * r, 1.8, col)
	for s in _sorties:
		if is_instance_valid(s.target):
			_swarm_at(s.target.position, s.target.radius + 6.0, mini(s.n, 40), Color(0.2, 0.16, 0.05))
	if _cloud != null and is_instance_valid(_cloud.target):
		var p: Vector2 = _cloud.target.position
		draw_circle(p, _cloud.target.radius + 30.0, Color(0.1, 0.08, 0.03, 0.45))
		_swarm_at(p, _cloud.target.radius + 18.0, mini(_cloud.n, 60), Color(0.12, 0.1, 0.03))


func _swarm_at(pos: Vector2, radius: float, n: int, color: Color) -> void:
	var t: float = world.elapsed
	for i in n:
		var a: float = TAU * i / maxf(n, 1.0) + t * 4.0 * (1.0 if i % 2 == 0 else -1.0)
		var r: float = radius * (0.4 + 0.6 * absf(sin(t * 3.0 + i * 1.7)))
		draw_circle(pos + Vector2.from_angle(a) * r, 1.8, color)
