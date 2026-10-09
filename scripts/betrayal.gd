extends Node
## Traición: la barra que se llena cuando matás aliados y los cazadores del
## infierno que llegan cuando se llena. También reparte la biomasa de los aliados
## que te comés y el corazón infernal del cazador.

const B := preload("res://scripts/balance.gd")
const Hunter := preload("res://scripts/hunter.gd")
const Corpse := preload("res://scripts/corpse.gd")

var world
var bar := 0.0
var hunters: Array = []
var _spawned := 0


func _process(delta: float) -> void:
	if not world.running:
		return
	if not world.player.betrayal_mode:
		bar = maxf(bar - B.BETRAYAL_DECAY * delta, 0.0)
	if bar >= B.BETRAYAL_MAX and hunters.size() < B.HUNTER_MAX_ALIVE:
		bar = 0.0
		_spawn_hunter()


## Un aliado que mataste vos: no deja nada, te lo comés al instante y no hace ruido.
func on_ally_killed(m) -> void:
	if m.raised:
		return
	var gain: float = B.BETRAYAL_PER_ELITE if m.elite else B.BETRAYAL_PER_KILL.get(m.type_name, 3.0)
	bar = minf(bar + gain, B.BETRAYAL_MAX)
	var food: float = B.ELITE_HEART_BIOMASS if m.elite else m.biomass
	world.player.eat_now(food * B.BETRAYAL_BIOMASS_MULT)


func _spawn_hunter() -> void:
	var p = world.player
	var h = Hunter.new()
	h.world = world
	h.setup(p, _spawned)
	_spawned += 1
	var pos: Vector2 = p.position + Vector2.from_angle(world.rng.randf() * TAU) * B.HUNTER_SPAWN_DIST
	h.position = pos.clamp(Vector2(30, 30), B.ARENA_SIZE - Vector2(30, 30))
	hunters.append(h)
	world.add_entity(h)
	world.hud.banner("El infierno exige un pago")


func on_hunter_killed(h) -> void:
	hunters.erase(h)
	var c = Corpse.new()
	c.world = world
	c.position = h.position
	c.hell = true
	c.value = 0.0
	c.radius = 12.0
	world.corpses.append(c)
	world.add_entity(c)
	h.queue_free()


## Lo más cercano entre los cazadores, dentro de "max_dist" del punto.
func nearest_hunter(pos: Vector2, max_dist: float):
	var best = null
	var best_d := max_dist
	for h in hunters:
		var d := pos.distance_to(h.position)
		if d < best_d:
			best_d = d
			best = h
	return best
