extends Node2D
## Infamia: la barra que sube cuando el héroe no puede con vos (matás civiles,
## sobrevivís detectado, lo hacés retirarse). Al llenarse, el cielo manda un
## Paladín que se une al héroe. También reparte el corazón celestial.

const B := preload("res://scripts/balance.gd")
const Paladin := preload("res://scripts/paladin.gd")
const Corpse := preload("res://scripts/corpse.gd")

var world
var bar := 0.0
var paladins: Array = []
var _spawned := 0
var _arrival_t := 0.0 # columna de luz: el Paladín está por llegar
var arrival_pos := Vector2.ZERO
var _hero_was_low := false


func arriving() -> bool:
	return _arrival_t > 0.0


func _process(delta: float) -> void:
	if not world.running:
		return
	queue_redraw()
	_heal_hero(delta)
	if _arrival_t > 0.0:
		_arrival_t -= delta
		if _arrival_t <= 0.0:
			_spawn_paladin()
		return
	if world.detected:
		add(B.INFAMY_PER_SECOND_DETECTED * delta)
	var hero = world.hero
	var low: bool = hero.hp / hero.max_hp < B.INFAMY_HERO_LOW_HP
	if low and not _hero_was_low:
		add(B.INFAMY_HERO_LOW)
	_hero_was_low = low
	if bar >= B.INFAMY_MAX and paladins.size() < B.PALADIN_MAX_ALIVE:
		bar = 0.0
		_arrival_t = B.PALADIN_ARRIVAL
		arrival_pos = (hero.position + Vector2.from_angle(world.rng.randf() * TAU) * B.PALADIN_SPAWN_DIST) \
				.clamp(Vector2(30, 30), B.ARENA_SIZE - Vector2(30, 30))
		world.hud.banner("El cielo envía refuerzos" if not paladins.is_empty() else "El cielo envía a un Paladín")


## Sube aunque haya Paladines vivos; solo se frena mientras uno está llegando.
func add(amount: float) -> void:
	if _arrival_t <= 0.0:
		bar = minf(bar + amount, B.INFAMY_MAX)


## Las auras no se suman: con uno o más Paladines cerca, el héroe se cura una sola vez.
func _heal_hero(delta: float) -> void:
	var hero = world.hero
	for p in paladins:
		if p.position.distance_to(hero.position) < B.PALADIN_HEAL_RADIUS:
			hero.hp = minf(hero.max_hp, hero.hp + hero.max_hp * B.PALADIN_HEAL * delta)
			return


func _spawn_paladin() -> void:
	var p = Paladin.new()
	p.world = world
	p.setup(world.player, _spawned)
	_spawned += 1
	p.position = arrival_pos
	paladins.append(p)
	world.add_entity(p)


func on_paladin_killed(p) -> void:
	paladins.erase(p)
	var c = Corpse.new()
	c.world = world
	c.position = p.position
	c.holy = true
	c.value = 0.0
	c.radius = 12.0
	world.corpses.append(c)
	world.add_entity(c)
	p.queue_free()


## El Paladín más cercano dentro de "max_dist" del punto.
func nearest_paladin(pos: Vector2, max_dist: float):
	var best = null
	var best_d := max_dist
	for p in paladins:
		var d := pos.distance_to(p.position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _draw() -> void:
	if _arrival_t <= 0.0:
		return
	var k := 1.0 - _arrival_t / B.PALADIN_ARRIVAL
	draw_rect(Rect2(arrival_pos + Vector2(-14, -600), Vector2(28, 600)), Color(1.0, 0.95, 0.6, 0.15 + 0.35 * k))
	draw_circle(arrival_pos, 26.0, Color(1.0, 0.95, 0.6, 0.2 + 0.4 * k))
	draw_arc(arrival_pos, 26.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 0.9), 2.0)
