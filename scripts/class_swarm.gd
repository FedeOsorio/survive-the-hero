extends "res://scripts/creep_class.gd"
## Reina del enjambre: no tiene vida normal, su vida son los insectos que la rodean.
## Cada golpe mata insectos (vida de etapa / máximo de insectos por insecto) y muere
## al quedarse sin ninguno en casa. Comer cadáveres y civiles cría; no come gemas.
## Arma inicial: manda parte del enjambre a picar al héroe (los que salen no la
## protegen). Desde Esqueleto, Nube: todo el enjambre envuelve al héroe y lo ciega.

var home := B.SWARM_START
var _sorties: Array = [] # {target, n, t}: salen cada SWARM_SEND_EVERY y pican STING_TIME (se pueden pisar)
var _send_cd := 1.0
var _cloud = null # {target, n, t}
var _cloud_cd := B.SWARM_CLOUD_EVERY
var _breed_t := 0.0


func replaces_kit() -> bool:
	return true


func eats_gems() -> bool:
	return false


func max_insects() -> int:
	return B.SWARM_MAX[creep.stage]


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


func take_hit(amount: float) -> bool:
	if home <= 0:
		home = 0
		creep.die()
		return true
	home -= maxi(ceili(amount / _per_insect()), 1)
	if home <= 0:
		home = 0
		_sync()
		creep.die()
	return true


func hp_text() -> String:
	var out := away()
	return "Enjambre %d/%d" % [home, max_insects()] + (" (+%d afuera)" % out if out > 0 else "")


func _sync() -> void:
	creep.hp = clampf(home * _per_insect(), 0.0, creep.max_hp)


func _process(delta: float) -> void:
	if not world.running:
		return
	_breed_t += delta
	var every := maxf(B.SWARM_BREED_EVERY - B.SWARM_HIVE_PER_RANK * creep.rank("colmena"), 0.5)
	if _breed_t >= every:
		_breed_t = 0.0
		_breed(1)
	_update_sortie(delta)
	if creep.stage >= 1:
		_update_cloud(delta)
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
	var n := maxi(ceili(home * B.SWARM_SEND_SHARE), B.SWARM_SEND_MIN)
	if home - n < 1:
		return # sin insectos de sobra no sale nadie
	_send_cd = B.SWARM_SEND_EVERY
	home -= n
	_sorties.append({"target": t, "n": n, "t": B.SWARM_STING_TIME})
	if creep.rank("aguijon") > 0 and not is_paladin(t):
		t.status.bleed(n * creep.bite * B.SWARM_STINGER_BLEED * B.SWARM_STINGER_TIME)
	if creep.rank("zumbido") > 0 and is_paladin(t):
		t.confuse(B.SWARM_BUZZ_CONFUSE)


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
	_cloud_cd = B.SWARM_CLOUD_EVERY
	var time: float = B.SWARM_CLOUD_TIME[creep.stage]
	_cloud = {"target": hero, "n": home, "t": time}
	home = 0 # la apuesta: mientras dura, un golpe te mata
	hero.status.blind(time)


# --- Dibujo -----------------------------------------------------------------------

func _draw() -> void:
	var t: float = world.elapsed
	var col := Color(0.15, 0.12, 0.05)
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
