extends Node2D
## Mecánica propia de cada héroe (hijo del nodo del héroe), según su título:
## Arquero: rueda más seguido y donde termina deja una trampa (solo vos la activás).
## Caballero: escudo al frente que gira hacia su blanco; de frente tus golpes casi no le hacen.
##   Además, hachas que giran a su alrededor y golpean lo que tocan (más en furia).
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
var _axe_angle := 0.0 # Caballero: ángulo de la primera hacha
var _axe_hits := {} # blanco -> segundos hasta que una hacha le pueda volver a pegar


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


## El cepo se cierra solo con vos (la horda pasa por encima): te inmoviliza y te lastima.
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
	if hero.hunting_you() and not world.player_hidden(hero):
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


# --- Caballero: hachas giratorias ---------------------------------------------------

func axe_count() -> int:
	return B.KNIGHT_AXES_FURY if hero.fury else B.KNIGHT_AXES


func _axe_pos(i: int) -> Vector2:
	var r: float = B.KNIGHT_AXE_RADIUS_FURY if hero.fury else B.KNIGHT_AXE_RADIUS
	return hero.position + Vector2.from_angle(_axe_angle + TAU * i / axe_count()) * r


## Cada hacha le pega a lo que toca (horda y vos), a cada blanco como mucho cada
## KNIGHT_AXE_HIT_EVERY. En furia el daño cuenta para su robo de vida.
func _update_axes(delta: float) -> void:
	var spin: float = B.KNIGHT_AXE_SPIN_FURY if hero.fury else B.KNIGHT_AXE_SPIN
	_axe_angle = fposmod(_axe_angle + TAU / spin * delta, TAU)
	for k in _axe_hits.keys():
		_axe_hits[k] -= delta
		if _axe_hits[k] <= 0.0 or not is_instance_valid(k):
			_axe_hits.erase(k)
	var dmg: float = hero.damage * B.KNIGHT_AXE_DAMAGE_MULT
	var dealt := 0.0
	var p = world.player
	for i in axe_count():
		var at := _axe_pos(i)
		var victims: Array = world.minions_near(at)
		victims.append(p)
		for v in victims:
			if _axe_hits.has(v) or at.distance_to(v.position) > B.KNIGHT_AXE_SIZE + v.radius:
				continue
			_axe_hits[v] = B.KNIGHT_AXE_HIT_EVERY
			dealt += minf(dmg, v.hp)
			v.take_damage(dmg)
			if v != p and v.hp <= 0.0:
				hero.rage.on_kill()
	hero.rage.on_melee_damage(dealt)


func _draw_axes() -> void:
	var n := axe_count()
	var spin: float = B.KNIGHT_AXE_SPIN_FURY if hero.fury else B.KNIGHT_AXE_SPIN
	var c := to_local(hero.position)
	var r: float = B.KNIGHT_AXE_RADIUS_FURY if hero.fury else B.KNIGHT_AXE_RADIUS
	for i in n:
		var ang := _axe_angle + TAU * i / n
		# estela: el arco que acaba de recorrer
		draw_arc(c, r, ang - TAU / spin * 0.12, ang, 8, Color(0.8, 0.8, 0.85, 0.35), 6.0)
		var at := c + Vector2.from_angle(ang) * r
		var fwd := Vector2.from_angle(ang + PI * 0.5)
		var out := Vector2.from_angle(ang)
		draw_line(at - out * 9.0, at + out * 5.0, Color(0.45, 0.32, 0.2), 3.0)
		draw_colored_polygon(PackedVector2Array([at + out * 2.0 - fwd * 2.0, at + out * 9.0 + fwd * 7.0, at + out * 9.0 - fwd * 7.0]), Color(0.75, 0.77, 0.82))


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
			_update_axes(delta)
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
		_draw_axes()
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
