extends Node2D
## Eventos del mundo: los cofres en disputa y los eventos de oleada
## (estampida, asedio y luna de sangre, en rotación).

const B := preload("res://scripts/balance.gd")
const Chest := preload("res://scripts/chest.gd")

const ROTATION := ["estampida", "asedio", "luna"]
const NAMES := {"estampida": "¡Estampida!", "asedio": "¡Asedio al héroe!", "luna": "¡Luna de sangre!"}

var world
var blood_moon_t := 0.0
var _chest_t := B.CHEST_FIRST
var _event_t := B.EVENT_FIRST
var _event_i := 0
var _warned := false
var _siege_t := 0.0
var _siege_pos := Vector2.ZERO


func _ready() -> void:
	z_index = 0


func damage_mult() -> float:
	return B.BLOOD_MOON_DAMAGE_MULT if blood_moon_t > 0.0 else 1.0


func _process(delta: float) -> void:
	if not world.running:
		return
	_update_chest(delta)
	blood_moon_t = maxf(blood_moon_t - delta, 0.0)
	_event_t -= delta
	var next: String = ROTATION[_event_i % ROTATION.size()]
	if not _warned and _event_t <= B.EVENT_WARNING:
		_warned = true
		world.hud.banner(NAMES[next])
	if _event_t <= 0.0:
		_event_t = B.EVENT_EVERY
		_warned = false
		_event_i += 1
		match next:
			"estampida":
				_stampede()
			"asedio":
				if world.hero != null:
					_siege_t = B.SIEGE_WARNING
					_siege_pos = world.hero.position
			"luna":
				blood_moon_t = B.BLOOD_MOON_TIME
	if _siege_t > 0.0 and world.hero != null:
		_siege_pos = world.hero.position
	if _siege_t > 0.0:
		_siege_t -= delta
		if _siege_t <= 0.0:
			_siege()
	queue_redraw()


# --- Cofres ------------------------------------------------------------------

func _update_chest(delta: float) -> void:
	_chest_t -= delta
	if _chest_t > 0.0:
		return
	_chest_t = B.CHEST_EVERY
	if world.chest != null:
		return
	var pos := Vector2.ZERO
	var base: Vector2 = world.hero.position if world.hero != null else world.player.position
	for i in 10:
		var dist: float = world.rng.randf_range(B.CHEST_MIN_DIST, B.CHEST_MAX_DIST)
		pos = base + Vector2.from_angle(world.rng.randf() * TAU) * dist
		if Rect2(Vector2(60, 60), B.ARENA_SIZE - Vector2(120, 120)).has_point(pos):
			break
	var c = Chest.new()
	c.world = world
	c.position = pos.clamp(Vector2(60, 60), B.ARENA_SIZE - Vector2(60, 60))
	world.chest = c
	world.add_entity(c)
	world.hud.banner("¡Apareció un cofre!")


func remove_chest() -> void:
	if world.chest != null:
		world.chest.queue_free()
		world.chest = null


# --- Oleadas -----------------------------------------------------------------

func _room() -> int:
	return maxi(B.MAX_MINIONS - world.minions.size(), 0)


## Una fila ancha de ratas sale de un costado y corre hacia el héroe.
func _stampede() -> void:
	var hero_pos: Vector2 = world.hero.position if world.hero != null else world.player.position
	var dir: Vector2 = Vector2.from_angle(world.rng.randf() * TAU)
	var origin := hero_pos + dir * B.STAMPEDE_DIST
	var side := dir.orthogonal()
	var n := mini(B.STAMPEDE_COUNT, _room())
	for i in n:
		var offset := (float(i) / maxf(n - 1, 1) - 0.5) * B.STAMPEDE_WIDTH
		var jitter: Vector2 = dir * world.rng.randf_range(-30.0, 30.0)
		var m = world.spawn_minion("rata", false, origin + side * offset + jitter)
		m.boost_t = B.STAMPEDE_BOOST_TIME


## Anillo de zombis alrededor del héroe que se cierra sobre él.
func _siege() -> void:
	var n := mini(B.SIEGE_COUNT, _room())
	for i in n:
		var pos := _siege_pos + Vector2.from_angle(TAU * i / B.SIEGE_COUNT) * B.SIEGE_RADIUS
		world.spawn_minion("zombi", false, pos)


func _draw() -> void:
	if _siege_t > 0.0:
		var k := 1.0 - _siege_t / B.SIEGE_WARNING
		draw_arc(_siege_pos, B.SIEGE_RADIUS, 0.0, TAU, 48, Color(0.4, 0.9, 0.45, 0.4 + 0.4 * k), 3.0)
		draw_circle(_siege_pos, B.SIEGE_RADIUS, Color(0.4, 0.9, 0.45, 0.05 + 0.08 * k))
