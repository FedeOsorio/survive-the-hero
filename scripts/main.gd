extends Node2D
## Raíz de la partida: crea el mundo, spawnea la horda, lleva el reloj,
## la amenaza del creep y las condiciones de victoria y derrota.

const B := preload("res://scripts/balance.gd")
const Creep := preload("res://scripts/creep.gd")
const Hero := preload("res://scripts/hero.gd")
const Minion := preload("res://scripts/minion.gd")
const Corpse := preload("res://scripts/corpse.gd")
const Gem := preload("res://scripts/gem.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Spit := preload("res://scripts/spit.gd")
const Arena := preload("res://scripts/arena.gd")
const Hud := preload("res://scripts/hud.gd")

const GRID_CELL := 64.0

var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var running := true
var won := false
var end_reason := ""
var detected := false
var threat := 0.0
var enraged := false
var kills := 0
var sim_mode := false # --sim: el creep es invulnerable y se imprime un reporte por minuto
var bot_mode := false # --bot: el creep lo maneja un bot simple, para medir cuánto tarda en ganarse

var player
var hero
var minions: Array = []
var corpses: Array = []
var gems: Array = []

var hud
var _entities: Node2D
var _spawn_accum := 0.0
var _grid := {}
var _next_report := 60.0


func _ready() -> void:
	_setup_input()
	rng.randomize()
	bot_mode = "--bot" in OS.get_cmdline_user_args()
	sim_mode = bot_mode or "--sim" in OS.get_cmdline_user_args()

	add_child(Arena.new())
	_entities = Node2D.new()
	_entities.y_sort_enabled = false
	add_child(_entities)

	var center := B.ARENA_SIZE * 0.5
	player = Creep.new()
	player.world = self
	player.position = center + Vector2(-350, 0)
	player.invulnerable = sim_mode and not bot_mode
	_entities.add_child(player)

	hero = Hero.new()
	hero.world = self
	hero.position = center + Vector2(350, 0)
	_entities.add_child(hero)

	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.limit_left = -150
	cam.limit_top = -150
	cam.limit_right = int(B.ARENA_SIZE.x) + 150
	cam.limit_bottom = int(B.ARENA_SIZE.y) + 150
	player.add_child(cam)

	hud = Hud.new()
	hud.world = self
	add_child(hud)
	hud.banner("Sos un creep más. Sobreviví, comé y evolucioná.")


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if not running:
		return

	elapsed += delta
	var minute := elapsed / 60.0

	if not detected and elapsed >= B.FORCED_DETECTION_SECONDS:
		set_detected()
	if not enraged and elapsed >= B.MATCH_SECONDS:
		enraged = true
		hero.enrage()
		hud.banner("¡El héroe se enfureció! Matalo ya.")

	_spawn_accum += B.spawns_per_second(minute) * delta
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		if minions.size() < B.MAX_MINIONS:
			spawn_minion(B.pick_minion_type(minute, rng))

	_rebuild_grid()

	if sim_mode and elapsed >= _next_report:
		_next_report += 60.0
		print("[sim] min %d | heroe nv %d vida %d/%d | creep %s biomasa %d | amenaza %d | horda %d | muertes %d" % [
			int(elapsed / 60.0), hero.level, int(hero.hp), int(hero.max_hp),
			player.stage_name(), int(player.biomass), int(threat), minions.size(), kills])


# --- Spawning ----------------------------------------------------------------

func spawn_minion(type_name: String) -> void:
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(B.SPAWN_MIN_DIST, B.SPAWN_MAX_DIST)
	var pos: Vector2 = hero.position + Vector2.from_angle(angle) * dist
	pos = pos.clamp(Vector2(20, 20), B.ARENA_SIZE - Vector2(20, 20))
	var m = Minion.new()
	m.world = self
	m.setup(type_name, B.minion_hp_mult(elapsed / 60.0))
	m.position = pos
	minions.append(m)
	_entities.add_child(m)


func on_minion_killed(m) -> void:
	kills += 1
	minions.erase(m)
	var c = Corpse.new()
	c.world = self
	c.position = m.position
	c.value = m.biomass
	c.radius = m.radius
	c.color = m.color
	corpses.append(c)
	_entities.add_child(c)

	var g = Gem.new()
	g.world = self
	g.position = m.position + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	g.xp = m.xp
	gems.append(g)
	_entities.add_child(g)
	m.queue_free()


func remove_corpse(c) -> void:
	corpses.erase(c)
	c.queue_free()


func remove_gem(g) -> void:
	gems.erase(g)
	g.queue_free()


func spawn_projectile(from: Vector2, dir: Vector2, damage: float, pierce: int) -> void:
	var p = Projectile.new()
	p.world = self
	p.position = from
	p.direction = dir
	p.damage = damage
	p.pierce = pierce
	_entities.add_child(p)


func spawn_spit(from: Vector2, dir: Vector2, damage: float) -> void:
	var s = Spit.new()
	s.world = self
	s.position = from
	s.direction = dir
	s.damage = damage
	_entities.add_child(s)


# --- Amenaza y fin de partida ------------------------------------------------

func add_threat(amount: float) -> void:
	if detected:
		return
	threat += amount
	if threat >= B.DETECTION_THRESHOLD:
		set_detected()


func set_detected() -> void:
	if detected:
		return
	detected = true
	threat = B.DETECTION_THRESHOLD
	hud.banner("¡El héroe te vio! Ahora te caza.")


func end_game(player_won: bool, reason: String) -> void:
	if not running:
		return
	running = false
	won = player_won
	end_reason = reason
	if sim_mode:
		print("[sim] fin (%02d:%02d): %s" % [int(elapsed) / 60, int(elapsed) % 60, reason])


# --- Consulta espacial para la separación de la horda ------------------------

func _rebuild_grid() -> void:
	_grid.clear()
	for m in minions:
		var key := Vector2i(floori(m.position.x / GRID_CELL), floori(m.position.y / GRID_CELL))
		if _grid.has(key):
			_grid[key].append(m)
		else:
			_grid[key] = [m]


func minions_near(pos: Vector2) -> Array:
	var out: Array = []
	var cx := floori(pos.x / GRID_CELL)
	var cy := floori(pos.y / GRID_CELL)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := Vector2i(cx + dx, cy + dy)
			if _grid.has(key):
				out.append_array(_grid[key])
	return out


# --- Controles ---------------------------------------------------------------

func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT], [[JOY_AXIS_LEFT_X, -1.0]], [JOY_BUTTON_DPAD_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP], [[JOY_AXIS_LEFT_Y, -1.0]], [JOY_BUTTON_DPAD_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]], [JOY_BUTTON_DPAD_DOWN])
	_add_action("bite", [KEY_SPACE, KEY_J], [], [JOY_BUTTON_A])
	_add_action("dash", [KEY_SHIFT, KEY_K], [], [JOY_BUTTON_B])
	_add_action("evolve", [KEY_E, KEY_L], [], [JOY_BUTTON_Y])
	_add_action("spit", [KEY_Q, KEY_I], [], [JOY_BUTTON_X])
	_add_action("restart", [KEY_R], [], [JOY_BUTTON_START])


func _add_action(action: String, keys: Array, axes: Array, buttons: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for a in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[0]
		ev.axis_value = a[1]
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
