extends Node2D
## Los tres héroes de la partida (B.HEROES): llegan a horario fijo (o antes, si
## matás al anterior: HERO_NEXT_AFTER_KILL) por un portal
## que se abre cerca tuyo, cada uno con su IA, nivel y poderes. "nearest" da el
## héroe vivo más cercano a un punto. Al minuto MATCH_MINUTES los que queden se
## enfurecen. Ganás cuando caen los tres.

const B := preload("res://scripts/balance.gd")
const Hero := preload("res://scripts/hero.gd")

var world
var list: Array = [] # héroes vivos
var killed := 0
var portal_pos := Vector2.ZERO
var _next := 0 # índice del próximo en llegar
var _portal_open := false
var _dawn := false
var _best_level := 1 # el nivel más alto que alcanzó un héroe en la partida
var _early_at := -1.0 # si matás a uno, el siguiente se adelanta a este segundo


func _ready() -> void:
	z_index = 0


## El primero (el Arquero) arranca ya en la arena.
func start(pos: Vector2) -> void:
	_spawn(pos)


func total() -> int:
	return B.HEROES.size()


## Segundo de la próxima llegada, o -1 si ya llegaron todos. Su horario fijo
## es el máximo; matar a un héroe la adelanta a HERO_NEXT_AFTER_KILL segundos.
func next_arrival() -> float:
	if _next >= total():
		return -1.0
	var fixed: float = B.HEROES[_next].minute * 60.0
	return minf(fixed, _early_at) if _early_at >= 0.0 else fixed


func next_name() -> String:
	return B.HEROES[_next].name if _next < total() else ""


## Nivel con el que llega el héroe "i": el Arquero en 1; los demás a la altura
## del más fuerte entre los héroes anteriores y vos, más su "level_bonus".
func arrival_level(i: int) -> int:
	var cfg: Dictionary = B.HEROES[i]
	if not cfg.has("level_bonus"):
		return cfg.level
	for h in list:
		_best_level = maxi(_best_level, h.level)
	return maxi(_best_level, world.player.level) + cfg.level_bonus


func nearest(pos: Vector2):
	var best = null
	var best_d := INF
	for h in list:
		var d := pos.distance_to(h.position)
		if d < best_d:
			best_d = d
			best = h
	return best


## Algún héroe vivo a menos de "dist" del punto.
func any_within(pos: Vector2, dist: float) -> bool:
	for h in list:
		if pos.distance_to(h.position) < dist:
			return true
	return false


func _process(_delta: float) -> void:
	if not world.running:
		return
	var t: float = world.elapsed
	for h in list:
		_best_level = maxi(_best_level, h.level)
	if _next < total():
		var at := next_arrival()
		if not _portal_open and t >= at - B.HERO_ARRIVAL_WARNING:
			_open_portal()
		if t >= at:
			_portal_open = false
			_spawn(portal_pos)
	if not _dawn and t >= B.MATCH_MINUTES * 60.0:
		_dawn = true
		if not list.is_empty():
			world.enraged = true
			world.hud.banner("Amanece: los héroes resisten")
			for h in list:
				h.enrage()
	queue_redraw()


func _open_portal() -> void:
	_portal_open = true
	var cfg: Dictionary = B.HEROES[_next]
	var player_pos: Vector2 = world.player.position
	var inner := Rect2(Vector2(80, 80), B.ARENA_SIZE - Vector2(160, 160))
	for i in 12:
		var dist: float = world.rng.randf_range(B.HERO_PORTAL_MIN, B.HERO_PORTAL_MAX)
		portal_pos = player_pos + Vector2.from_angle(world.rng.randf() * TAU) * dist
		if inner.has_point(portal_pos):
			break
	portal_pos = portal_pos.clamp(inner.position, inner.end)
	world.hud.banner("Llegó %s %s" % [cfg.article, cfg.name])


func _spawn(pos: Vector2) -> void:
	var h = Hero.new()
	h.world = world
	h.position = pos
	world.add_entity(h)
	h.setup(B.HEROES[_next], arrival_level(_next))
	if world.enraged:
		h.enrage()
	list.append(h)
	_next += 1
	_early_at = -1.0


func on_hero_killed(h) -> void:
	list.erase(h)
	killed += 1
	h.queue_free()
	if _next < total() and not _portal_open:
		var at: float = world.elapsed + B.HERO_NEXT_AFTER_KILL
		_early_at = minf(_early_at, at) if _early_at >= 0.0 else at
	if killed >= total():
		var t := int(world.elapsed)
		world.end_game(true, "Derrotaste a los tres héroes en %02d:%02d." % [t / 60, t % 60])
	else:
		world.hud.banner("¡Cayó %s %s!" % [h.article, h.title])


func _draw() -> void:
	if not _portal_open:
		return
	var k := clampf(1.0 - (next_arrival() - world.elapsed) / B.HERO_ARRIVAL_WARNING, 0.0, 1.0)
	var col: Color = B.HEROES[_next].color
	draw_circle(portal_pos, 34.0, Color(col, 0.12 + 0.25 * k))
	for i in 3:
		var a: float = world.elapsed * 3.0 + TAU * i / 3.0
		draw_arc(portal_pos, 20.0 + 12.0 * i, a, a + PI * 1.2, 16, Color(col, 0.5 + 0.4 * k), 2.5)
