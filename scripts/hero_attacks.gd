extends Node2D
## Ataques de jefe del héroe o del Último Bastión (hijo de su nodo; el dueño decide
## cuándo puede atacar con can_boss_attack()). Cada "attack_every" segundos
## elige un blanco (vos si te caza; si no, el montón de horda más denso), marca una zona
## roja fija en el piso que se llena durante el aviso y después golpea: los creeps menores
## mueren, brutos y élites pierden HERO_ATTACK_BIG_DAMAGE y a vos te saca "player_damage"
## de tu vida máxima. Si estabas dentro al empezar el aviso y saliste, te reconoce.
## Mientras carga, el héroe se queda quieto y no dispara. Tabla en B.HERO_ATTACKS.

const B := preload("res://scripts/balance.gd")

var hero
var world
var attacks: Array = [] # ids de B.HERO_ATTACKS, en orden
var every := 6.0
var unlock_all := false # furia: el ataque 3 aunque no tenga nivel
var _t := 0.0
var _turn := 0
var _serial := 0
var _zones: Array = [] # zonas avisando: {cfg, serial, pos, dir, delay, warn, t, inside, grow_t, hit}
var _fx: Array = [] # destellos de las zonas que acaban de golpear: {zone, t}
var _hit_player := {} # serial -> true: el ataque ya te pegó
var _dash := {} # Embestida en curso: {from, to, t}


func _ready() -> void:
	z_as_relative = false
	z_index = 0


func setup(cfg: Dictionary) -> void:
	attacks = cfg.attacks
	every = cfg.attack_every
	_t = every * 0.5


## Cargando un ataque o embistiendo: el héroe no se mueve ni dispara.
func busy() -> bool:
	if not _dash.is_empty():
		return true
	for z in _zones:
		if not z.get("free", false):
			return true
	return false


## Zona suelta que no lo deja quieto ni corta su ciclo (la nova del parpadeo de la Maga).
func spawn_zone(cfg: Dictionary, pos: Vector2) -> void:
	_serial += 1
	_add_zone(cfg, pos, Vector2.RIGHT)
	_zones[-1].free = true


func _process(delta: float) -> void:
	if not world.running:
		return
	_update_dash(delta)
	_update_zones(delta)
	for f in _fx.duplicate():
		f.t -= delta
		if f.t <= 0.0:
			_fx.erase(f)
	if busy():
		queue_redraw()
		return
	_t -= delta
	if _t <= 0.0 and _can_attack():
		_start_attack()
	queue_redraw()


func _can_attack() -> bool:
	return hero.can_boss_attack()


## Corta lo que estaba cargando (el Bastión al arrodillarse).
func cancel() -> void:
	_zones.clear()
	_dash = {}
	_t = every


func _available() -> Array:
	if unlock_all or hero.level >= B.HERO_ATTACK_THIRD_LEVEL:
		return attacks
	return attacks.slice(0, 2)


# --- Blanco ------------------------------------------------------------------

## Vos si te caza (y no estás camuflado); si no, el creep con más vecinos a
## HERO_ATTACK_CLUSTER_RADIUS, a menos de HERO_ATTACK_TARGET_RANGE. null si no hay.
func _pick_target():
	var p = world.player
	if hero.hunting_you() and (not world.player_hidden(hero) or hero.ignores_stealth()):
		return p.position
	var best = null
	var best_n := 0
	var r2 := B.HERO_ATTACK_CLUSTER_RADIUS * B.HERO_ATTACK_CLUSTER_RADIUS
	for m in world.minions:
		if hero.position.distance_to(m.position) > B.HERO_ATTACK_TARGET_RANGE:
			continue
		var n := 0
		for o in world.minions_near(m.position):
			if m.position.distance_squared_to(o.position) < r2:
				n += 1
		if n > best_n:
			best_n = n
			best = m.position
	return best


# --- Zonas -------------------------------------------------------------------

func _start_attack() -> void:
	var target = _pick_target()
	if target == null:
		_t = B.HERO_ATTACK_RETRY
		return
	var list := _available()
	var id: String = list[_turn % list.size()]
	_turn += 1
	_t = every
	_serial += 1
	var cfg: Dictionary = B.HERO_ATTACKS[id]
	var from: Vector2 = hero.position
	var to_t: Vector2 = target - from
	var dir := to_t.normalized() if to_t.length() > 1.0 else Vector2.RIGHT
	match id:
		"terremoto":
			var reach := maxf(to_t.length(), cfg.radius * 3.0)
			for i in cfg.count:
				_add_zone(cfg, from + dir * reach * (i + 1) / cfg.count, dir, i * cfg.stagger)
		"meteoros":
			_add_zone(cfg, target, dir)
			for i in cfg.count - 1:
				_add_zone(cfg, target + Vector2.from_angle(randf() * TAU) * cfg.spread, dir)
		"cruz_rayos":
			_add_zone(cfg, target - dir * cfg.length * 0.5, dir)
			var side := dir.orthogonal()
			_add_zone(cfg, target - side * cfg.length * 0.5, side)
		_:
			var pos: Vector2 = target
			if cfg.center == "hero" or cfg.center == "line":
				pos = from
			_add_zone(cfg, pos, dir)


func _add_zone(cfg: Dictionary, pos: Vector2, dir: Vector2, delay := 0.0) -> void:
	var z := {"cfg": cfg, "serial": _serial, "pos": pos, "dir": dir, "delay": delay,
		"t": cfg.warn, "inside": false, "started": false, "grow_t": -1.0, "hit": {}}
	_zones.append(z)
	if delay <= 0.0:
		_begin(z)


## Empieza el aviso: guarda si estabas adentro (para saber si lo esquivaste).
func _begin(z: Dictionary) -> void:
	z.started = true
	var p = world.player
	z.inside = _inside(z, p.position, p.radius)


func _update_zones(delta: float) -> void:
	for z in _zones.duplicate():
		if not z.started:
			z.delay -= delta
			if z.delay <= 0.0:
				_begin(z)
			continue
		if z.grow_t >= 0.0:
			_grow_donut(z, delta)
			continue
		z.t -= delta
		if z.t > 0.0:
			continue
		if z.cfg.shape == "donut":
			z.grow_t = 0.0
			world.fx.boss_strike(z.pos)
			world.shake()
			continue
		_strike(z)
		_zones.erase(z)


func _strike(z: Dictionary) -> void:
	world.fx.boss_strike(z.pos)
	world.bushes.burn_zone(self, z) # los arbustos que toca se queman
	world.shake()
	_fx.append({"zone": z, "t": B.HERO_ATTACK_FLASH})
	for m in world.minions.duplicate():
		if _inside(z, m.position, m.radius):
			_hit_minion(m)
	var p = world.player
	var hit: bool = _inside(z, p.position, p.radius)
	if hit:
		_hit_you(z)
	elif z.inside:
		hero.suspect(B.SUSPICION_DODGE) # un creep común no esquiva
	if z.cfg.get("dash", false):
		var end: Vector2 = z.pos + z.dir * z.cfg.length
		_dash = {"from": hero.position, "to": end.clamp(Vector2(hero.radius, hero.radius), B.ARENA_SIZE - Vector2(hero.radius, hero.radius)), "t": 0.0}


## Anillo de fuego: el frente (de "width") crece hasta "radius" en "grow" segundos.
func _grow_donut(z: Dictionary, delta: float) -> void:
	z.grow_t += delta
	var k := minf(z.grow_t / z.cfg.grow, 1.0)
	var front: float = z.cfg.radius * k
	var half: float = z.cfg.width * 0.5
	for m in world.minions.duplicate():
		if z.hit.has(m):
			continue
		if absf(z.pos.distance_to(m.position) - front) < half + m.radius:
			z.hit[m] = true
			_hit_minion(m)
	var p = world.player
	if not z.hit.has(p) and absf(z.pos.distance_to(p.position) - front) < half + p.radius:
		z.hit[p] = true
		_hit_you(z)
	if k >= 1.0:
		if not z.hit.has(p) and z.inside:
			hero.suspect(B.SUSPICION_DODGE)
		_zones.erase(z)


func _hit_minion(m) -> void:
	if m.elite or m.type_name == "bruto":
		m.take_damage(m.max_hp * B.HERO_ATTACK_BIG_DAMAGE)
	else:
		m.take_damage(m.hp + 1.0)


func _hit_you(z: Dictionary) -> void:
	if _hit_player.has(z.serial):
		return
	_hit_player[z.serial] = true
	var p = world.player
	p.take_damage(p.max_hp * z.cfg.player_damage)


func _update_dash(delta: float) -> void:
	if _dash.is_empty():
		return
	_dash.t += delta
	var k := minf(_dash.t / B.HERO_ATTACK_DASH_TIME, 1.0)
	hero.position = _dash.from.lerp(_dash.to, k)
	if k >= 1.0:
		_dash = {}


func _inside(z: Dictionary, at: Vector2, r: float) -> bool:
	var cfg: Dictionary = z.cfg
	var rel: Vector2 = at - z.pos
	match cfg.shape:
		"circle":
			return rel.length() < cfg.radius + r
		"line":
			var along: float = rel.dot(z.dir)
			return along >= -r and along <= cfg.length + r and absf(rel.cross(z.dir)) < cfg.width * 0.5 + r
		"cone":
			return rel.length() < cfg.length + r and absf(z.dir.angle_to(rel)) <= deg_to_rad(cfg.angle) * 0.5
		"donut":
			return rel.length() < cfg.radius + r
	return false


# --- Dibujo ------------------------------------------------------------------

func _draw() -> void:
	for z in _zones:
		if not z.started:
			continue
		if z.grow_t >= 0.0:
			var front: float = z.cfg.radius * minf(z.grow_t / z.cfg.grow, 1.0)
			draw_arc(to_local(z.pos), front, 0.0, TAU, 64, Color(1.0, 0.55, 0.15, 0.9), z.cfg.width)
			continue
		var k: float = 1.0 - z.t / z.cfg.warn
		_draw_shape(z, 1.0, Color(1.0, 0.15, 0.1, 0.12), Color(1.0, 0.2, 0.15, 0.8))
		_draw_shape(z, k, Color(1.0, 0.15, 0.1, 0.3), Color(0, 0, 0, 0))
	for f in _fx:
		var a: float = f.t / B.HERO_ATTACK_FLASH
		_draw_shape(f.zone, 1.0, Color(1, 1, 1, 0.7 * a), Color(1, 1, 1, a))


## "k" escala la zona desde su centro u origen (el relleno que crece durante el aviso).
func _draw_shape(z: Dictionary, k: float, fill: Color, line: Color) -> void:
	var cfg: Dictionary = z.cfg
	var c := to_local(z.pos)
	match cfg.shape:
		"circle", "donut":
			draw_circle(c, cfg.radius * k, fill)
			if line.a > 0.0:
				draw_arc(c, cfg.radius, 0.0, TAU, 48, line, 2.5)
		"line":
			var side: Vector2 = z.dir.orthogonal() * cfg.width * 0.5
			var end: Vector2 = c + z.dir * cfg.length * k
			if k > 0.02:
				draw_colored_polygon(PackedVector2Array([c + side, end + side, end - side, c - side]), fill)
			if line.a > 0.0:
				var full: Vector2 = c + z.dir * cfg.length
				draw_polyline(PackedVector2Array([c + side, full + side, full - side, c - side, c + side]), line, 2.0)
		"cone":
			var half := deg_to_rad(cfg.angle) * 0.5
			var a0: float = z.dir.angle()
			var pts := PackedVector2Array([c])
			for i in 13:
				pts.append(c + Vector2.from_angle(a0 - half + half * 2.0 * i / 12.0) * cfg.length * maxf(k, 0.02))
			draw_colored_polygon(pts, fill)
			if line.a > 0.0:
				var outline := PackedVector2Array([c])
				for i in 13:
					outline.append(c + Vector2.from_angle(a0 - half + half * 2.0 * i / 12.0) * cfg.length)
				outline.append(c)
				draw_polyline(outline, line, 2.0)
