extends Node2D
## Poderes del héroe (hijo del nodo del héroe). Cada nivel sube el poder de su
## fila en la tabla fija de su héroe (B.HEROES.table): termina con 5 distintos.
## Los de área le pegan a la horda y al jugador por igual; rayo y nova avisan antes.

const B := preload("res://scripts/balance.gd")

const LIST := {
	"orbes": {"name": "Orbes de fuego", "max": 5, "short": "Orbes"},
	"rayo": {"name": "Rayo", "max": 5, "short": "Rayo"},
	"aura": {"name": "Aura sagrada", "max": 5, "short": "Aura"},
	"nova": {"name": "Nova", "max": 5, "short": "Nova"},
	"perforante": {"name": "Flechas perforantes", "max": 3, "short": "Perforantes"},
	"multiple": {"name": "Lluvia de flechas", "max": 3, "short": "Lluvia"},
	"botas": {"name": "Botas aladas", "max": 3, "short": "Botas"},
}

var hero
var world
var ranks := {}
var _orb_angle := 0.0
var _orb_hits := {} # "orbe:blanco" -> segundos hasta poder volver a pegarle
var _bolt_t := 0.0
var _bolts: Array = [] # {pos, t} esperando caer
var _bolt_fx: Array = [] # {pos, t} rayos que acaban de caer
var _nova_t := 0.0
var _nova_warn := 0.0
var _nova_fx := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	z_index = 1


func rank(id: String) -> int:
	return ranks.get(id, 0)


## Sube el poder de la fila de "level" en la tabla del héroe (+1 rango, sin pasar
## del máximo). Devuelve el id, o "" si ese nivel no tiene fila. "quiet": sin banner.
func apply_level(level: int, table: Array, quiet := false) -> String:
	var i := level - 2
	if i < 0 or i >= table.size():
		return ""
	var id: String = table[i]
	if rank(id) >= LIST[id].max:
		return ""
	ranks[id] = rank(id) + 1
	if not quiet:
		if ranks[id] == 1:
			world.hud.banner("%s aprendió %s" % [hero.full_name(), LIST[id].name])
		else:
			world.hud.banner("%s %s sube a %d" % [LIST[id].name, hero.of_name(), ranks[id]])
	return id


## "Aura 4, Nova 3, Orbes 3": del rango más alto al más bajo, con nombres cortos.
func summary() -> String:
	var ids: Array = ranks.keys()
	ids.sort_custom(func(a, b): return ranks[a] > ranks[b])
	var parts: Array = []
	for id in ids:
		parts.append("%s %d" % [LIST[id].short, ranks[id]])
	return ", ".join(parts)


func _power_damage(id: String, base: float, per_rank: float) -> float:
	return base + per_rank * (rank(id) - 1)


func _process(delta: float) -> void:
	if not world.running:
		return
	if rank("orbes") > 0:
		_update_orbs(delta)
	if rank("aura") > 0:
		var r := aura_radius()
		_hit_area(hero.position, r, _power_damage("aura", B.AURA_DPS, B.AURA_DPS_PER_RANK) * delta)
	if rank("rayo") > 0:
		_update_bolts(delta)
	if rank("nova") > 0:
		_update_nova(delta)
	queue_redraw()


# --- Orbes -------------------------------------------------------------------

func orb_count() -> int:
	return rank("orbes")


func orb_orbit() -> float:
	return B.ORB_ORBIT + rank("orbes") * B.ORB_ORBIT_PER_RANK


func _orb_pos(i: int) -> Vector2:
	return Vector2.from_angle(_orb_angle + TAU * i / orb_count()) * orb_orbit()


func _update_orbs(delta: float) -> void:
	_orb_angle = wrapf(_orb_angle + B.ORB_SPIN * delta, 0.0, TAU)
	for k in _orb_hits.keys():
		_orb_hits[k] -= delta
		if _orb_hits[k] <= 0.0:
			_orb_hits.erase(k)
	var dmg := _power_damage("orbes", B.ORB_DAMAGE, B.ORB_DAMAGE_PER_RANK)
	for i in orb_count():
		var p: Vector2 = hero.position + _orb_pos(i)
		var victims: Array = world.minions_near(p)
		victims.append(world.player)
		for v in victims:
			if not is_instance_valid(v) or p.distance_to(v.position) > B.ORB_RADIUS + v.radius:
				continue
			var key := "%d:%d" % [i, v.get_instance_id()]
			if _orb_hits.has(key):
				continue
			_orb_hits[key] = B.ORB_HIT_COOLDOWN
			v.take_damage(dmg)


# --- Aura y área -------------------------------------------------------------

func aura_radius() -> float:
	return B.AURA_RADIUS + rank("aura") * B.AURA_RADIUS_PER_RANK


func _hit_area(center: Vector2, r: float, dmg: float, push := 0.0) -> void:
	for m in world.minions.duplicate():
		var to_m: Vector2 = m.position - center
		if to_m.length() < r + m.radius:
			if push > 0.0 and to_m.length() > 0.01:
				m.position += to_m.normalized() * push
			m.take_damage(dmg)
	var p = world.player
	if center.distance_to(p.position) < r + p.radius:
		p.take_damage(dmg)


# --- Rayo --------------------------------------------------------------------

func _update_bolts(delta: float) -> void:
	_bolt_t -= delta
	if _bolt_t <= 0.0:
		_bolt_t = maxf(B.BOLT_COOLDOWN - rank("rayo") * B.BOLT_COOLDOWN_PER_RANK, 0.8)
		var candidates: Array = []
		for m in world.minions:
			if hero.position.distance_to(m.position) < B.BOLT_RANGE:
				candidates.append(m)
		var p = world.player
		if p.stealth_t <= 0.0 and hero.position.distance_to(p.position) < B.BOLT_RANGE:
			# si te está cazando, siempre te tira uno
			if hero.hunting_you():
				_bolts.append({"pos": p.position, "t": B.BOLT_WARNING})
			else:
				candidates.append(p)
		for i in rank("rayo"):
			if candidates.is_empty():
				break
			var v = candidates.pop_at(_rng.randi_range(0, candidates.size() - 1))
			_bolts.append({"pos": v.position, "t": B.BOLT_WARNING})
	for b in _bolts.duplicate():
		b.t -= delta
		if b.t <= 0.0:
			_bolts.erase(b)
			_hit_area(b.pos, B.BOLT_RADIUS, _power_damage("rayo", B.BOLT_DAMAGE, B.BOLT_DAMAGE_PER_RANK))
			_bolt_fx.append({"pos": b.pos, "t": 0.15})
	for f in _bolt_fx.duplicate():
		f.t -= delta
		if f.t <= 0.0:
			_bolt_fx.erase(f)


# --- Nova --------------------------------------------------------------------

func nova_radius() -> float:
	return B.NOVA_RADIUS + rank("nova") * B.NOVA_RADIUS_PER_RANK


func _update_nova(delta: float) -> void:
	_nova_fx = maxf(_nova_fx - delta, 0.0)
	if _nova_warn > 0.0:
		_nova_warn -= delta
		if _nova_warn <= 0.0:
			_hit_area(hero.position, nova_radius(), _power_damage("nova", B.NOVA_DAMAGE, B.NOVA_DAMAGE_PER_RANK), B.NOVA_PUSH)
			_nova_fx = 0.2
		return
	_nova_t -= delta
	if _nova_t <= 0.0:
		_nova_t = maxf(B.NOVA_COOLDOWN - rank("nova") * B.NOVA_COOLDOWN_PER_RANK, 2.5)
		_nova_warn = B.NOVA_WARNING


# --- Dibujo ------------------------------------------------------------------

func _draw() -> void:
	if rank("aura") > 0:
		draw_circle(Vector2.ZERO, aura_radius(), Color(1.0, 0.9, 0.4, 0.08))
		draw_arc(Vector2.ZERO, aura_radius(), 0.0, TAU, 40, Color(1.0, 0.9, 0.4, 0.35), 1.5)
	if rank("orbes") > 0:
		for i in orb_count():
			var p := _orb_pos(i)
			draw_circle(p, B.ORB_RADIUS, Color(1.0, 0.45, 0.1))
			draw_circle(p, B.ORB_RADIUS * 0.5, Color(1.0, 0.9, 0.4))
	if _nova_warn > 0.0:
		var k := 1.0 - _nova_warn / B.NOVA_WARNING
		draw_circle(Vector2.ZERO, nova_radius(), Color(0.6, 0.8, 1.0, 0.06 + 0.12 * k))
		draw_arc(Vector2.ZERO, nova_radius(), 0.0, TAU, 40, Color(0.6, 0.8, 1.0, 0.6), 2.0)
	if _nova_fx > 0.0:
		draw_arc(Vector2.ZERO, nova_radius() * (1.0 - _nova_fx * 2.0), 0.0, TAU, 40, Color(0.85, 0.95, 1.0, 0.9), 6.0)
	for b in _bolts:
		var lp := to_local(b.pos)
		var k: float = 1.0 - b.t / B.BOLT_WARNING
		draw_circle(lp, B.BOLT_RADIUS, Color(1.0, 1.0, 0.5, 0.08 + 0.15 * k))
		draw_arc(lp, B.BOLT_RADIUS, 0.0, TAU, 24, Color(1.0, 1.0, 0.5, 0.7), 1.5)
	for f in _bolt_fx:
		var lp := to_local(f.pos)
		draw_line(lp + Vector2(6, -260), lp + Vector2(-8, -120), Color(1, 1, 0.8), 3.0)
		draw_line(lp + Vector2(-8, -120), lp + Vector2(5, -40), Color(1, 1, 0.8), 3.0)
		draw_line(lp + Vector2(5, -40), lp, Color(1, 1, 0.8), 3.0)
		draw_circle(lp, B.BOLT_RADIUS * 0.8, Color(1.0, 1.0, 0.7, 0.6))
