extends Node2D
## Poderes del héroe (hijo del nodo del héroe). En cada nivel elige 1 de 3:
## un poder nuevo o subir uno que ya tiene, hasta 5 poderes distintos.
## Los de área le pegan a la horda y al jugador por igual; rayo y nova avisan antes.
## Con el jugador detectado, elige según cómo lo atacás (cuerpo a cuerpo o a distancia).

const B := preload("res://scripts/balance.gd")

const LIST := {
	"orbes": {"name": "Orbes de fuego", "max": 5},
	"rayo": {"name": "Rayo", "max": 5},
	"aura": {"name": "Aura sagrada", "max": 5},
	"nova": {"name": "Nova", "max": 5},
	"perforante": {"name": "Flechas perforantes", "max": 3},
	"multiple": {"name": "Lluvia de flechas", "max": 3},
	"botas": {"name": "Botas aladas", "max": 3},
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


## Elige un poder al subir de nivel. Devuelve el id, o "" si ya tiene todo al máximo.
## "start": sus poderes de inicio, que pesan más hasta rango HERO_START_POWER_MAX_RANK
## (los niveles con los que llega). "quiet": sin banner.
func level_up(start: Array = [], quiet := false) -> String:
	var pool: Array = []
	for id in LIST:
		var r := rank(id)
		if r >= LIST[id].max:
			continue
		if r == 0 and ranks.size() >= B.HERO_MAX_POWERS:
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	var options: Array = []
	while options.size() < B.HERO_POWER_CHOICES and not pool.is_empty():
		options.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
	var favored := _favored()
	var weights: Array = []
	var total := 0.0
	for id in options:
		var w: float = B.ADAPT_WEIGHT if favored.has(id) else 1.0
		if start.has(id) and rank(id) < B.HERO_START_POWER_MAX_RANK:
			w *= B.HERO_START_POWER_WEIGHT
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	var pick: String = options[-1]
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			pick = options[i]
			break
	ranks[pick] = rank(pick) + 1
	if quiet:
		return pick
	if favored.has(pick):
		world.hud.banner("El héroe se adapta: %s" % LIST[pick].name)
	elif ranks[pick] == 1:
		world.hud.banner("El héroe aprendió %s" % LIST[pick].name)
	return pick


## Con el jugador detectado, favorece lo que contrarresta cómo lo estás atacando.
func _favored() -> Array:
	if not world.detected:
		return []
	var share: float = hero.status.melee_share()
	if share < 0.0:
		return []
	if share > B.ADAPT_SHARE:
		return ["aura", "nova"]
	if 1.0 - share > B.ADAPT_SHARE:
		return ["rayo", "botas"]
	return []


func summary() -> String:
	var parts: Array = []
	for id in ranks:
		parts.append("%s %d" % [LIST[id].name, ranks[id]])
	return ", ".join(parts)


func _power_damage(id: String, base: float, per_rank: float) -> float:
	return (base + per_rank * (rank(id) - 1)) * hero.power_mult


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
			# al jugador detectado siempre le tira uno
			if world.detected:
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
