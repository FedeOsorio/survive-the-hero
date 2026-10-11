extends Node2D
## Jugo visual (world.fx): partículas al morir, números de daño que recibís,
## hit-stop, cámara lenta al morir un héroe, anillos al mutar y evolucionar, y la
## columna de luz del héroe al subir de nivel. Los demás scripts lo llaman con una
## línea; la muerte y el nivel de los héroes los detecta solo, mirando world.heroes.

const B := preload("res://scripts/balance.gd")

var world
var _parts: Array = [] # {pos, vel, t, life, color, size}
var _texts: Array = [] # {pos, text, t, color, size}
var _rings: Array = [] # {pos, t, life, radius, color, width}
var _columns: Array = [] # {pos, t, color}
var _stop_until := 0 # ms reales: hit-stop
var _slow_until := 0 # ms reales: cámara lenta
var _strike_pos := Vector2.ZERO
var _strike_at := -999.0 # world.elapsed del último golpe de un ataque de jefe
var _heroes := {} # id -> {level, pos, color}
var _killed := 0
var _hurt_sum := 0.0 # daño chico que recibís, sumado
var _hurt_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 5
	process_mode = Node.PROCESS_MODE_ALWAYS # el hit-stop se mide en tiempo real
	_rng.randomize()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	_update_time_scale()
	if get_tree().paused:
		return
	_watch_heroes()
	_hurt_t += delta
	if _hurt_t >= B.FX_GROUP_EVERY:
		_hurt_t = 0.0
		if _hurt_sum >= 1.0:
			_number(world.player.position, _hurt_sum, Color(1, 0.3, 0.25), 14)
		_hurt_sum = 0.0
	for p in _parts:
		p.t += delta
		p.pos += p.vel * delta
		p.vel *= 1.0 - minf(4.0 * delta, 1.0)
	_parts = _parts.filter(func(p): return p.t < p.life)
	for n in _texts:
		n.t += delta
	_texts = _texts.filter(func(n): return n.t < B.DMG_NUMBER_TIME * n.get("long", 1.0))
	for r in _rings:
		r.t += delta
	_rings = _rings.filter(func(r): return r.t < r.life)
	for c in _columns:
		c.t += delta
	_columns = _columns.filter(func(c): return c.t < B.FX_LEVEL_COLUMN)
	queue_redraw()


func _update_time_scale() -> void:
	if world.sim_mode:
		return
	var now := Time.get_ticks_msec()
	var scale := 1.0
	if now < _slow_until:
		scale = B.FX_SLOWMO_SCALE
	if now < _stop_until:
		scale = 0.0
	Engine.time_scale = scale


## Muertes y subidas de nivel de los héroes, sin tocar heroes.gd ni hero.gd.
func _watch_heroes() -> void:
	var alive := {}
	for h in world.heroes.list:
		var id: int = h.get_instance_id()
		alive[id] = true
		var seen = _heroes.get(id)
		if seen and h.level > seen.level:
			_level_up(h)
		_heroes[id] = {"level": h.level, "pos": h.position, "color": h.color}
	var killed: int = world.heroes.killed
	for id in _heroes.keys():
		if alive.has(id):
			continue
		if killed > _killed:
			_hero_died(_heroes[id].pos, _heroes[id].color)
		_heroes.erase(id)
	_killed = killed


func _hit_stop(seconds: float) -> void:
	_stop_until = maxi(_stop_until, Time.get_ticks_msec() + int(seconds * 1000.0))


# --- Llamadas desde otros scripts ----------------------------------------------

## Mordida o embestida que le pega al héroe.
func melee_hit() -> void:
	_hit_stop(B.FX_HITSTOP_MELEE)


## Un ataque de jefe golpea en "pos" (hero_attacks.gd, justo antes de aplicar el daño).
func boss_strike(pos: Vector2) -> void:
	_strike_pos = pos
	_strike_at = world.elapsed


## Daño que recibís: número rojo (los chicos se suman) y hit-stop si fue un ataque de jefe.
func player_hit(amount: float) -> void:
	var p = world.player
	if world.elapsed - _strike_at <= B.FX_BLAST_WINDOW:
		_hit_stop(B.FX_HITSTOP_BOSS)
	if amount >= p.max_hp * B.DMG_NUMBER_BIG:
		_number(p.position, amount, Color(1, 0.25, 0.2), 20)
	else:
		_hurt_sum += amount


func minion_died(m) -> void:
	var blast: bool = world.elapsed - _strike_at <= B.FX_BLAST_WINDOW
	var n := _rng.randi_range(B.FX_DEATH_PARTICLES.x, B.FX_DEATH_PARTICLES.y)
	for i in n:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var speed := _rng.randf_range(B.FX_DEATH_SPEED.x, B.FX_DEATH_SPEED.y)
		if blast:
			var away: Vector2 = m.position - _strike_pos
			if away.length() > 1.0:
				dir = away.normalized().rotated(_rng.randf_range(-0.5, 0.5))
			speed = _rng.randf_range(B.FX_BLAST_SPEED.x, B.FX_BLAST_SPEED.y)
		_particle(m.position, dir * speed, m.color, _rng.randf_range(2.0, 4.0), B.FX_PARTICLE_TIME * (1.5 if blast else 1.0))


func civilian_eaten(pos: Vector2) -> void:
	for i in B.FX_CIVILIAN_PARTICLES:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_particle(pos, dir * _rng.randf_range(40.0, 110.0), Color(0.85, 0.08, 0.08), 2.5, B.FX_PARTICLE_TIME)


func explosion(pos: Vector2, radius: float, color: Color) -> void:
	_ring(pos, 0.35, radius, color, 8.0)
	for i in 14:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_particle(pos, dir * _rng.randf_range(100.0, 260.0), color.lightened(_rng.randf() * 0.4), _rng.randf_range(3.0, 5.0), B.FX_PARTICLE_TIME)


func mutated(pos: Vector2) -> void:
	_ring(pos, B.FX_MUTATE_RING.x, B.FX_MUTATE_RING.y, Color(0.4, 0.9, 1.0), 3.0)


func evolved(pos: Vector2, stage_name: String) -> void:
	_ring(pos, B.FX_EVOLVE_RING.x, B.FX_EVOLVE_RING.y, Color(0.7, 0.35, 1.0), 6.0)
	_texts.append({"pos": pos + Vector2(0, -30), "text": stage_name, "t": 0.0, "color": Color(0.85, 0.6, 1.0), "size": 28, "long": 2.0})


# --- Internos ------------------------------------------------------------------

func _level_up(h) -> void:
	_columns.append({"pos": h.position, "t": 0.0, "color": h.color})
	_texts.append({"pos": h.position + Vector2(0, -40), "text": "Nv %d" % h.level, "t": 0.0, "color": h.color.lightened(0.4), "size": 20, "long": 1.5})


func _hero_died(pos: Vector2, color: Color) -> void:
	_ring(pos, 0.6, B.FX_HERO_DEATH_RADIUS, color.lightened(0.5), 10.0)
	_ring(pos, 0.4, B.FX_HERO_DEATH_RADIUS * 0.5, Color.WHITE, 6.0)
	for i in B.FX_HERO_DEATH_PARTICLES:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_particle(pos, dir * _rng.randf_range(150.0, 450.0), color.lightened(_rng.randf() * 0.6), _rng.randf_range(3.0, 6.0), 0.8)
	if not world.sim_mode:
		_slow_until = Time.get_ticks_msec() + int(B.FX_SLOWMO_TIME * 1000.0)


func _number(pos: Vector2, amount: float, color: Color, size: int) -> void:
	if not Settings.get_option("damage_numbers"):
		return
	var jitter := Vector2(_rng.randf_range(-10.0, 10.0), -20.0)
	_texts.append({"pos": pos + jitter, "text": str(roundi(amount)), "t": 0.0, "color": color, "size": size})


func _particle(pos: Vector2, vel: Vector2, color: Color, size: float, life: float) -> void:
	_parts.append({"pos": pos, "vel": vel, "t": 0.0, "life": life, "color": color, "size": size})
	if _parts.size() > B.FX_MAX_PARTICLES:
		_parts.remove_at(0)


func _ring(pos: Vector2, life: float, radius: float, color: Color, width: float) -> void:
	_rings.append({"pos": pos, "t": 0.0, "life": life, "radius": radius, "color": color, "width": width})


func _draw() -> void:
	for p in _parts:
		var c: Color = p.color
		c.a = 1.0 - p.t / p.life
		draw_rect(Rect2(p.pos - Vector2.ONE * p.size * 0.5, Vector2.ONE * p.size), c)
	for r in _rings:
		var k: float = r.t / r.life
		var c: Color = r.color
		c.a = 1.0 - k
		draw_arc(r.pos, maxf(r.radius * sqrt(k), 1.0), 0.0, TAU, 48, c, r.width * (1.0 - k * 0.5))
	for col in _columns:
		var k: float = col.t / B.FX_LEVEL_COLUMN
		var c: Color = col.color.lightened(0.5)
		c.a = 0.6 * (1.0 - k)
		var w := 30.0 * (1.0 - k * 0.5)
		draw_rect(Rect2(col.pos + Vector2(-w * 0.5, -260.0), Vector2(w, 270.0)), c)
	var font := ThemeDB.fallback_font
	for n in _texts:
		var life: float = B.DMG_NUMBER_TIME * n.get("long", 1.0)
		var k: float = n.t / life
		var c: Color = n.color
		c.a = 1.0 - k * k
		var w := font.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, n.size).x
		var pos: Vector2 = n.pos + Vector2(-w * 0.5, -B.DMG_NUMBER_RISE * k)
		draw_string_outline(font, pos, n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, n.size, 3, Color(0, 0, 0, c.a * 0.8))
		draw_string(font, pos, n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, n.size, c)
