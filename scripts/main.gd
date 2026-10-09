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
const Civilian := preload("res://scripts/civilian.gd")
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
var spits: Array = []
var civilians: Array = []
var _civilian_t := 0.0
var _elite_t := 0.0
var alarm_pos := Vector2.ZERO # último grito de un civil; el héroe va a investigar
var alarm_t := 0.0

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

	for i in B.CIVILIANS_START:
		spawn_civilian()

	hud = Hud.new()
	hud.world = self
	add_child(hud)
	hud.banner("Sos un creep más. Sobreviví, comé y evolucioná.")


func _process(delta: float) -> void:
	if not running:
		return

	elapsed += delta
	var minute := elapsed / 60.0

	add_threat(player.stage * B.THREAT_PASSIVE_PER_STAGE * delta)
	alarm_t = maxf(alarm_t - delta, 0.0)
	_elite_t += delta
	if _elite_t >= B.ELITE_EVERY:
		_elite_t = 0.0
		spawn_minion("bruto", true)
		hud.banner("Apareció un élite dorado: robale el corazón al héroe")

	_spawn_accum += B.spawns_per_second(minute) * delta
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		if minions.size() < B.MAX_MINIONS:
			spawn_minion(B.pick_minion_type(minute, rng))

	_civilian_t -= delta
	if _civilian_t <= 0.0 and civilians.size() < B.CIVILIANS_MAX:
		_civilian_t = B.CIVILIAN_RESPAWN
		spawn_civilian()

	_rebuild_grid()

	if sim_mode and elapsed >= _next_report:
		_next_report += 60.0
		print("[sim] min %d | heroe nv %d vida %d/%d | creep %s biomasa %d | amenaza %d | horda %d | muertes %d" % [
			int(elapsed / 60.0), hero.level, int(hero.hp), int(hero.max_hp),
			player.stage_name(), int(player.biomass), int(threat), minions.size(), kills])


# --- Spawning ----------------------------------------------------------------

func spawn_minion(type_name: String, elite := false) -> void:
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(B.SPAWN_MIN_DIST, B.SPAWN_MAX_DIST)
	var pos: Vector2 = hero.position + Vector2.from_angle(angle) * dist
	pos = pos.clamp(Vector2(20, 20), B.ARENA_SIZE - Vector2(20, 20))
	var m = Minion.new()
	m.world = self
	m.setup(type_name, elapsed / 60.0, elite)
	m.position = pos
	minions.append(m)
	_entities.add_child(m)


## Los civiles aparecen lejos del héroe, para que comer sea una alternativa a robarle.
func spawn_civilian() -> void:
	var pos := Vector2.ZERO
	for i in 10:
		pos = Vector2(rng.randf_range(60, B.ARENA_SIZE.x - 60), rng.randf_range(60, B.ARENA_SIZE.y - 60))
		if pos.distance_to(hero.position) > 700.0 and pos.distance_to(player.position) > 300.0:
			break
	var c = Civilian.new()
	c.world = self
	c.position = pos
	civilians.append(c)
	_entities.add_child(c)


## Un civil que huye grita: el héroe va hacia ahí a matar civiles.
func raise_alarm(pos: Vector2) -> void:
	alarm_pos = pos
	alarm_t = B.ALARM_TIME


func on_civilian_killed(c, by_hero := false) -> void:
	civilians.erase(c)
	if by_hero:
		c.queue_free() # el héroe no deja comida
		return
	add_threat(B.THREAT_PER_CIVILIAN)
	raise_alarm(c.position)
	var corpse = Corpse.new()
	corpse.world = self
	corpse.position = c.position
	corpse.value = B.CIVILIAN_BIOMASS
	corpse.radius = 9.0
	corpse.color = Color(0.95, 0.8, 0.6)
	corpses.append(corpse)
	_entities.add_child(corpse)
	c.queue_free()


func on_minion_killed(m) -> void:
	kills += 1
	minions.erase(m)
	var c = Corpse.new()
	c.world = self
	c.position = m.position
	c.value = B.ELITE_HEART_BIOMASS if m.elite else m.biomass
	c.heart = m.elite
	c.radius = m.radius
	c.color = m.color
	corpses.append(c)
	_entities.add_child(c)

	var g = Gem.new()
	g.world = self
	g.position = m.position + Vector2(rng.randf_range(-B.GEM_SCATTER, B.GEM_SCATTER), rng.randf_range(-B.GEM_SCATTER, B.GEM_SCATTER))
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


func spawn_spit(from: Vector2, dir: Vector2, damage: float, from_player: bool) -> void:
	var s = Spit.new()
	s.world = self
	s.position = from
	s.direction = dir
	s.damage = damage
	s.from_player = from_player
	spits.append(s)
	_entities.add_child(s)


func remove_spit(s) -> void:
	spits.erase(s)
	s.queue_free()


# --- Amenaza y fin de partida ------------------------------------------------

func add_threat(amount: float) -> void:
	if detected:
		return
	threat += amount
	if threat >= B.DETECTION_THRESHOLD:
		set_detected()


## Camuflaje del jugador: vuelve a no estar detectado y borra el rastro.
func lose_aggro() -> void:
	detected = false
	threat = B.DETECTION_THRESHOLD * B.STEALTH_THREAT_LEFT
	alarm_t = 0.0
	hud.banner("Camuflaje: el héroe te perdió de vista")


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
		print("[sim] fin (%02d:%02d): %s | daño al héroe %s | mutaciones %s | poderes %s" % [
			int(elapsed) / 60, int(elapsed) % 60, reason, hero.damage_taken, player.ranks, hero.powers.ranks])


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
	_add_action("dash", [KEY_SPACE, KEY_SHIFT], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("evolve", [KEY_E, KEY_L], [], [JOY_BUTTON_Y])
	_add_action("stealth", [KEY_Q], [], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("pick_1", [KEY_1, KEY_KP_1], [], [JOY_BUTTON_X])
	_add_action("pick_2", [KEY_2, KEY_KP_2], [], [JOY_BUTTON_A])
	_add_action("pick_3", [KEY_3, KEY_KP_3], [], [JOY_BUTTON_B])
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
