extends Node2D
## Mecánica propia de cada héroe (hijo del nodo del héroe), según su título:
## Arquero: rueda más seguido y donde termina deja una trampa (te inmoviliza y te lastima).
## Caballero: escudo al frente que gira hacia su blanco; de frente tus golpes casi no le hacen.
## Maga: si la mordés seguido se teletransporta y deja una nova.
## Sus rangos ("trampa", "escudo", "parpadeo") viven en hero_powers y los sube la tabla.

const B := preload("res://scripts/balance.gd")

var hero
var world
var kind := "" # "Arquero", "Caballero" o "Maga"
var facing := Vector2.RIGHT # Caballero: hacia dónde mira el escudo
var _traps: Array = [] # {pos, t}
var _block_fx := 0.0
var _hits: Array = [] # Maga: momentos de tus últimos golpes cuerpo a cuerpo
var _blink_cd := 0.0
var _blink_fx := {} # {from, t}


func _ready() -> void:
	z_as_relative = false
	z_index = 0


func _rank(id: String) -> int:
	return hero.powers.rank(id)


# --- Arquero: trampas ------------------------------------------------------------

func roll_cooldown() -> float:
	return B.ARCHER_ROLL_COOLDOWN if kind == "Arquero" else B.HERO_ROLL_COOLDOWN


func on_roll_end() -> void:
	if kind != "Arquero":
		return
	_traps.append({"pos": hero.position, "t": B.TRAP_TIME})
	while _traps.size() > B.TRAP_MAX + B.TRAP_MAX_PER_RANK * _rank("trampa"):
		_traps.pop_front()


func trap_radius() -> float:
	return B.TRAP_RADIUS + B.TRAP_RADIUS_PER_RANK * _rank("trampa")


## El cepo se cierra con lo primero que lo pisa: a vos te inmoviliza y te lastima,
## a un creep menor lo mata.
func _update_traps(delta: float) -> void:
	var p = world.player
	var r := trap_radius()
	for tr in _traps.duplicate():
		tr.t -= delta
		if tr.t <= 0.0:
			_traps.erase(tr)
			continue
		if tr.pos.distance_to(p.position) < r + p.radius:
			_traps.erase(tr)
			p.root(B.TRAP_ROOT + B.TRAP_ROOT_PER_RANK * _rank("trampa"))
			p.take_damage(p.max_hp * B.TRAP_DAMAGE)
			world.shake()
			continue
		for m in world.minions_near(tr.pos):
			if not m.elite and m.type_name != "bruto" and tr.pos.distance_to(m.position) < r + m.radius:
				_traps.erase(tr)
				m.take_damage(m.hp + 1.0)
				break


# --- Caballero: escudo ---------------------------------------------------------------

func shield_arc() -> float:
	return deg_to_rad(B.SHIELD_ARC + B.SHIELD_ARC_PER_RANK * _rank("escudo"))


## ¿Un golpe que viene desde "from" pega en el escudo?
func blocks(from: Vector2) -> bool:
	if kind != "Caballero":
		return false
	var to_from: Vector2 = from - hero.position
	if to_from.length() < 0.01:
		return false
	return absf(facing.angle_to(to_from)) <= shield_arc() * 0.5


func _update_shield(delta: float) -> void:
	var aim = null
	var p = world.player
	if hero.hunting_you() and not world.player_hidden():
		aim = p.position
	else:
		var close = hero._nearest(world.minions_near(hero.position), INF)
		if close != null:
			aim = close.position
	if aim == null or aim.distance_to(hero.position) < 0.01:
		return
	var want: Vector2 = (aim - hero.position).normalized()
	var turn := deg_to_rad(B.SHIELD_TURN + B.SHIELD_TURN_PER_RANK * _rank("escudo")) * delta
	var diff := facing.angle_to(want)
	facing = facing.rotated(clampf(diff, -turn, turn))


# --- Daño que recibe -----------------------------------------------------------------

## Le pegaste: el escudo del Caballero baja tus golpes de frente (no los ticks);
## a la Maga, tres golpes cuerpo a cuerpo seguidos la hacen parpadear.
func filter_damage(amount: float, melee: bool, tick: bool) -> float:
	if tick:
		return amount
	if blocks(world.player.position):
		_block_fx = 0.15
		return amount * B.SHIELD_BLOCK_MULT
	if kind == "Maga" and melee:
		_on_melee_hit()
	return amount


func _on_melee_hit() -> void:
	var now: float = world.elapsed
	_hits.append(now)
	while not _hits.is_empty() and now - _hits[0] > B.BLINK_WINDOW:
		_hits.pop_front()
	if _hits.size() >= B.BLINK_HITS and _blink_cd <= 0.0:
		_blink()


## Se teletransporta lejos de vos y deja una nova donde estaba.
func _blink() -> void:
	_hits.clear()
	_blink_cd = maxf(B.BLINK_COOLDOWN - B.BLINK_COOLDOWN_PER_RANK * _rank("parpadeo"), 1.0)
	var from: Vector2 = hero.position
	var away: Vector2 = from - world.player.position
	var dir := away.normalized() if away.length() > 1.0 else Vector2.from_angle(randf() * TAU)
	var r: float = hero.radius
	hero.position = (from + dir * B.BLINK_DIST).clamp(Vector2(r, r), B.ARENA_SIZE - Vector2(r, r))
	hero.attacks.spawn_zone({"name": "Nova", "shape": "circle", "radius": B.BLINK_NOVA_RADIUS + B.BLINK_NOVA_RADIUS_PER_RANK * _rank("parpadeo"),
		"warn": B.BLINK_NOVA_WARN, "player_damage": B.BLINK_NOVA_DAMAGE}, from)
	_blink_fx = {"from": from, "t": 0.3}


# --- Cada frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not world.running:
		return
	_block_fx = maxf(_block_fx - delta, 0.0)
	_blink_cd = maxf(_blink_cd - delta, 0.0)
	if not _blink_fx.is_empty():
		_blink_fx.t -= delta
		if _blink_fx.t <= 0.0:
			_blink_fx = {}
	match kind:
		"Arquero":
			_update_traps(delta)
		"Caballero":
			_update_shield(delta)
	queue_redraw()


func _draw() -> void:
	for tr in _traps:
		var c := to_local(tr.pos)
		var r := trap_radius()
		var a: float = minf(tr.t, 1.0)
		draw_circle(c, r, Color(0.35, 0.35, 0.4, 0.18 * a))
		draw_arc(c, r * 0.6, 0.0, TAU, 20, Color(0.75, 0.75, 0.8, 0.9 * a), 3.0)
		for i in 8:
			var ang := TAU * i / 8.0
			draw_line(c + Vector2.from_angle(ang) * r * 0.45, c + Vector2.from_angle(ang) * r * 0.8, Color(0.85, 0.85, 0.9, 0.9 * a), 2.0)
	if kind == "Caballero":
		var c := to_local(hero.position)
		var half := shield_arc() * 0.5
		var col := Color(1, 1, 0.8, 1.0) if _block_fx > 0.0 else Color(0.8, 0.85, 0.95, 0.85)
		draw_arc(c, hero.radius + 10.0, facing.angle() - half, facing.angle() + half, 20, col, 5.0)
		if _block_fx > 0.0:
			# chispa del "clang"
			var hit: Vector2 = c + facing * (hero.radius + 12.0)
			for i in 6:
				draw_line(hit, hit + Vector2.from_angle(TAU * i / 6.0 + facing.angle()) * 10.0, Color(1, 0.95, 0.5), 2.0)
	if not _blink_fx.is_empty():
		var k: float = _blink_fx.t / 0.3
		draw_circle(to_local(_blink_fx.from), 26.0 * (1.0 - k) + 6.0, Color(0.8, 0.5, 1.0, 0.7 * k))
		draw_circle(to_local(hero.position), 26.0 * k + 6.0, Color(0.8, 0.5, 1.0, 0.7 * k))
