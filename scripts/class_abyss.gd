extends "res://scripts/creep_class.gd"
## Abisal: abre grietas con C (hasta 3, duran toda la partida). Cada grieta tiene
## tentáculos de Agarre que frenan y lastiman al que pasa cerca, y doble toque de
## embestida te lleva a la grieta que apuntás. Arma inicial: Azote (un tentáculo
## golpea el piso en línea hacia el héroe). Desde Esqueleto, Fauces: una grieta se
## vuelve boca un rato; desde Cultista, al cerrarse aplasta alrededor.

var _rifts: Array = [] # {pos, age}
var _rift_cd := 0.0
var _teleport_cd := 0.0
var _last_dash := -10.0
var _lash_cd := B.ABYSS_LASH_EVERY
var _lashes: Array = [] # {from, dir, t, hit_fx}
var _maw_cd := B.ABYSS_MAW_EVERY
var _maws: Array = [] # {rift, t}
var _fx: Array = [] # {pos, t} anillos al abrir, viajar o aplastar


func replaces_kit() -> bool:
	return true


func _deep() -> float:
	return 1.0 + B.ABYSS_DEEP_PER_RANK * creep.rank("hondo")


func ability() -> void:
	if _rift_cd > 0.0:
		return
	_rift_cd = B.ABYSS_RIFT_COOLDOWN
	_rifts.append({"pos": creep.position, "age": 0.0})
	if _rifts.size() > B.ABYSS_RIFT_MAX:
		var old = _rifts.pop_front()
		_maws = _maws.filter(func(m): return m.rift != old)
	_fx.append({"pos": creep.position, "t": 0.4})


func _process(delta: float) -> void:
	if not world.running:
		return
	_rift_cd = maxf(_rift_cd - delta, 0.0)
	_teleport_cd = maxf(_teleport_cd - delta, 0.0)
	for f in _fx:
		f.t -= delta
	_fx = _fx.filter(func(f): return f.t > 0.0)
	if not world.sim_mode and Input.is_action_just_pressed("dash"):
		_on_dash_pressed()
	_grab(delta)
	_update_lash(delta)
	if creep.stage >= 1:
		_update_maws(delta)
	queue_redraw()


# --- Viaje entre grietas ----------------------------------------------------------

func _on_dash_pressed() -> void:
	if world.elapsed - _last_dash > B.ABYSS_DOUBLE_TAP or _teleport_cd > 0.0 or _rifts.is_empty():
		_last_dash = world.elapsed
		return
	_last_dash = -10.0
	var goal = _teleport_goal()
	_fx.append({"pos": creep.position, "t": 0.4})
	creep.stop_dash()
	creep.position = goal.pos
	_teleport_cd = B.ABYSS_TELEPORT_COOLDOWN
	_fx.append({"pos": goal.pos, "t": 0.4})


## La grieta más cercana a donde apuntás; sin dirección, la más lejana.
func _teleport_goal():
	var aim = null
	if creep.abilities.aiming_with_mouse():
		aim = get_global_mouse_position()
	else:
		var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if stick.length() < 0.3:
			stick = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if stick.length() >= 0.3:
			aim = creep.position + stick.normalized() * 600.0
	var best = _rifts[0]
	for r in _rifts:
		if aim == null:
			if r.pos.distance_to(creep.position) > best.pos.distance_to(creep.position):
				best = r
		elif r.pos.distance_to(aim) < best.pos.distance_to(aim):
			best = r
	return best


# --- Agarre y Marea negra ---------------------------------------------------------

func _grab(delta: float) -> void:
	var reach := B.ABYSS_GRAB_RADIUS * _deep()
	var tide: bool = creep.rank("marea") > 0
	for r in _rifts:
		r.age += delta
	for t in targets():
		var grabbed := false
		for r in _rifts:
			if r.pos.distance_to(t.position) < reach + t.radius:
				grabbed = true
				break
		if grabbed:
			slow(t, B.ABYSS_GRAB_SLOW)
			hurt(t, creep.bite * B.ABYSS_GRAB_DPS * delta, true)
		elif tide and _on_tide(t):
			slow(t, B.ABYSS_TIDE_SLOW)


func _on_tide(t) -> bool:
	for i in _rifts.size():
		for j in range(i + 1, _rifts.size()):
			var p := Geometry2D.get_closest_point_to_segment(t.position, _rifts[i].pos, _rifts[j].pos)
			if p.distance_to(t.position) < B.ABYSS_TIDE_WIDTH + t.radius:
				return true
	return false


# --- Azote (arma inicial) ---------------------------------------------------------

func _update_lash(delta: float) -> void:
	for l in _lashes:
		l.t -= delta
		if l.t <= 0.0 and not l.hit:
			l.hit = true
			_lash_hit(l)
	_lashes = _lashes.filter(func(l): return l.t > -0.25)
	_lash_cd -= delta
	if _lash_cd > 0.0:
		return
	var t = nearest_target(creep.position, B.ABYSS_LASH_RANGE)
	if t == null:
		return
	_lash_cd = B.ABYSS_LASH_EVERY
	var from: Vector2 = creep.position
	for r in _rifts:
		if r.pos.distance_to(t.position) < from.distance_to(t.position):
			from = r.pos
	var dir: Vector2 = (t.position - from).normalized()
	if from.distance_to(t.position) > B.ABYSS_LASH_LENGTH * 0.85:
		from = t.position - dir * B.ABYSS_LASH_LENGTH * 0.5 # sale del piso cerca del blanco
	_lashes.append({"from": from, "dir": dir, "t": B.ABYSS_LASH_WARN, "hit": false})


func _lash_hit(l: Dictionary) -> void:
	var to: Vector2 = l.from + l.dir * B.ABYSS_LASH_LENGTH
	var half := B.ABYSS_LASH_WIDTH * 0.5 * _deep()
	for t in targets():
		var p := Geometry2D.get_closest_point_to_segment(t.position, l.from, to)
		if p.distance_to(t.position) > half + t.radius:
			continue
		hurt(t, creep.bite * B.ABYSS_LASH_DAMAGE)
		if creep.rank("ancla") > 0:
			stun(t, B.ABYSS_ANCHOR_STUN)
		elif t in world.heroes.list or is_paladin(t):
			t.position = (t.position + l.dir * B.ABYSS_LASH_PUSH).clamp(Vector2(20, 20), B.ARENA_SIZE - Vector2(20, 20))
	world.shake()


# --- Fauces y Aplastar ------------------------------------------------------------

func _update_maws(delta: float) -> void:
	var radius := B.ABYSS_RIFT_RADIUS * _deep()
	for m in _maws.duplicate():
		m.t -= delta
		var pos: Vector2 = m.rift.pos
		for c in world.civilians.duplicate():
			if pos.distance_to(c.position) < radius + c.radius:
				c.take_damage(c.hp + 1.0)
				if not world.corpses.is_empty():
					world.corpses.back().position = creep.position # te llega: lo comés al toque
		for t in targets():
			if pos.distance_to(t.position) < radius + t.radius:
				slow(t, B.ABYSS_MAW_SLOW)
				hurt(t, creep.bite * B.ABYSS_MAW_DPS * delta, true)
		if m.t <= 0.0:
			_maws.erase(m)
			if creep.stage >= 2:
				_slam(pos)
	_maw_cd -= delta
	if _maw_cd > 0.0 or _rifts.is_empty() or not _maws.is_empty():
		return
	var hero = world.hero
	if hero == null:
		return
	_maw_cd = B.ABYSS_MAW_EVERY
	if creep.stage >= 3:
		for r in _rifts:
			_maws.append({"rift": r, "t": B.ABYSS_MAW_TIME})
		return
	var best = _rifts[0]
	for r in _rifts:
		if r.pos.distance_to(hero.position) < best.pos.distance_to(hero.position):
			best = r
	_maws.append({"rift": best, "t": B.ABYSS_MAW_TIME})


func _slam(pos: Vector2) -> void:
	for t in targets():
		if pos.distance_to(t.position) < B.ABYSS_SLAM_RADIUS + t.radius:
			hurt(t, creep.bite * B.ABYSS_SLAM_DAMAGE)
			stun(t, B.ABYSS_SLAM_STUN)
	world.fx.explosion(pos, B.ABYSS_SLAM_RADIUS, Color(0.45, 0.2, 0.7))
	world.shake()


func _is_maw(r) -> bool:
	for m in _maws:
		if m.rift == r:
			return true
	return false


# --- Dibujo -----------------------------------------------------------------------

func _draw() -> void:
	var deep := _deep()
	var pulse: float = 0.5 + 0.5 * sin(world.elapsed * 3.0)
	if creep.rank("marea") > 0:
		for i in _rifts.size():
			for j in range(i + 1, _rifts.size()):
				draw_line(_rifts[i].pos, _rifts[j].pos, Color(0.3, 0.1, 0.45, 0.45), B.ABYSS_TIDE_WIDTH)
	for r in _rifts:
		var maw := _is_maw(r)
		var rr := B.ABYSS_RIFT_RADIUS * deep
		draw_arc(r.pos, B.ABYSS_GRAB_RADIUS * deep, 0.0, TAU, 40, Color(0.5, 0.25, 0.75, 0.25), 1.5)
		draw_circle(r.pos, rr, Color(0.08, 0.02, 0.12, 0.85))
		draw_arc(r.pos, rr, 0.0, TAU, 32, Color(0.85, 0.2, 0.3) if maw else Color(0.55, 0.25, 0.85, 0.6 + 0.3 * pulse), 3.0)
		# tentáculos de Agarre asomando
		for i in 5:
			var a: float = TAU * i / 5.0 + r.age * 0.6
			var base: Vector2 = r.pos + Vector2.from_angle(a) * rr * 0.8
			var tip: Vector2 = base + Vector2.from_angle(a + sin(world.elapsed * 4.0 + i) * 0.6) * (14.0 + 6.0 * pulse)
			draw_line(base, tip, Color(0.4, 0.15, 0.55), 4.0)
		if maw:
			for i in 10:
				var a: float = TAU * i / 10.0
				draw_line(r.pos + Vector2.from_angle(a) * rr, r.pos + Vector2.from_angle(a) * rr * 0.7, Color(0.95, 0.9, 0.85), 3.0)
	for l in _lashes:
		var to: Vector2 = l.from + l.dir * B.ABYSS_LASH_LENGTH
		var w := B.ABYSS_LASH_WIDTH * deep
		if l.t > 0.0:
			var k: float = 1.0 - l.t / B.ABYSS_LASH_WARN
			draw_line(l.from, to, Color(0.1, 0.0, 0.15, 0.25 + 0.3 * k), w)
		else:
			var a: float = 1.0 + l.t / 0.25
			draw_line(l.from, to, Color(0.55, 0.2, 0.8, a), w * 0.6)
			draw_line(l.from, to, Color(0.9, 0.7, 1.0, a), 3.0)
	for f in _fx:
		draw_arc(f.pos, 20.0 + 40.0 * (1.0 - f.t / 0.4), 0.0, TAU, 24, Color(0.6, 0.3, 0.9, f.t / 0.4), 3.0)
	if _rift_cd > 0.0:
		var k := _rift_cd / B.ABYSS_RIFT_COOLDOWN
		draw_arc(creep.position, creep.radius + 9.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - k), 24, Color(0.6, 0.3, 0.9, 0.6), 2.0)
