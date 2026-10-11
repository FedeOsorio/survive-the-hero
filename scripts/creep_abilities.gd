extends Node2D
## Habilidades del creep (hijo del creep, dibuja en coordenadas del mundo):
## las de cada etapa, automáticas con recarga (Huesos del Esqueleto, Detonar cadáver
## del Cultista, Aliento del Demonio; se suman al evolucionar) y las mutaciones de arma
## Espinas (embestida), Pegote (charcos que frenan) y Llamado (C o RT: la horda
## corre hacia donde apuntás).

const B := preload("res://scripts/balance.gd")

var creep
var world
var _bones_cd := B.BONES_EVERY
var _blast_cd := B.CORPSE_BLAST_EVERY
var _breath_cd := B.BREATH_EVERY
var _breath_t := 0.0 # > 0: echando fuego
var _breath_tick := 0.0
var _breath_dir := Vector2.RIGHT
var _bones: Array = [] # {pos, vel, target, bounces, hit, t}
var _goo: Array = [] # {pos, t}
var _goo_cd := B.GOO_EVERY
var _thorn_victims: Array = []
var _was_dashing := false
var rally_cd := 0.0
var _rally_fx := 0.0
var _rally_at := Vector2.ZERO
var _aim_mouse := true # el último que usaste para apuntar: mouse o joystick


func _ready() -> void:
	top_level = true # dibuja en el mundo, no relativo al creep
	z_index = 3


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_mouse = true
	elif event is InputEventJoypadMotion or event is InputEventJoypadButton:
		_aim_mouse = false


func _process(delta: float) -> void:
	if not world.running:
		return
	_update_bones(delta)
	_update_goo(delta)
	var kit: bool = not creep.klass.replaces_kit() # Huesos, Detonar y Aliento son del Engendro
	if kit and creep.stage >= 1:
		_bones_cd -= delta
		if _bones_cd <= 0.0 and _throw_bones():
			_bones_cd = B.BONES_EVERY
	if kit and creep.stage >= 2:
		_blast_cd -= delta
		if _blast_cd <= 0.0 and _corpse_blast():
			_blast_cd = B.CORPSE_BLAST_EVERY
	if kit and creep.stage >= 3:
		_update_breath(delta)
	_thorns()
	rally_cd = maxf(rally_cd - delta, 0.0)
	_rally_fx = maxf(_rally_fx - delta, 0.0)
	# C o RT: Llamado y la habilidad de la clase (las grietas del Abisal) salen juntos
	if not world.sim_mode and Input.is_action_just_pressed("rally"):
		if creep.rank("llamado") > 0 and rally_cd <= 0.0:
			_rally()
		creep.klass.ability()
	queue_redraw()


# --- Blancos -------------------------------------------------------------------

## Héroes, Bastión y Paladines: lo que las habilidades lastiman.
func _targets() -> Array:
	return world.heroes.targets() + world.infamy.paladins


func _hurt(t, amount: float) -> void:
	if t in world.infamy.paladins:
		t.take_damage(amount)
	else:
		t.take_damage(amount, true)


func _nearest_target(from: Vector2, max_dist: float, skip = null):
	var best = null
	var best_d := max_dist
	for t in _targets():
		if t == skip:
			continue
		var d: float = from.distance_to(t.position) - t.radius
		if d < best_d:
			best_d = d
			best = t
	return best


# --- Esqueleto: huesos que rebotan ---------------------------------------------

func _throw_bones() -> bool:
	var target = _nearest_target(creep.position, B.BONES_RANGE)
	if target == null:
		return false
	var dir: Vector2 = (target.position - creep.position).normalized()
	for i in B.BONES_COUNT:
		var spread := (i - (B.BONES_COUNT - 1) * 0.5) * 0.6
		_bones.append({"pos": creep.position, "vel": dir.rotated(spread) * B.BONES_SPEED, "target": target,
			"bounces": B.BONES_BOUNCES, "t": 0.0})
	return true


func _update_bones(delta: float) -> void:
	for b in _bones.duplicate():
		b.t += delta
		var t = b.target
		if t == null or not is_instance_valid(t) or not t in _targets() or b.t > 3.0:
			_bones.erase(b)
			continue
		var to_t: Vector2 = t.position - b.pos
		b.vel = b.vel.lerp(to_t.normalized() * B.BONES_SPEED, minf(8.0 * delta, 1.0))
		b.pos += b.vel * delta
		if to_t.length() < t.radius + 6.0:
			_hurt(t, creep.bite * B.BONES_DAMAGE)
			b.bounces -= 1
			b.target = _nearest_target(b.pos, B.BONES_BOUNCE_RANGE, t) if b.bounces >= 0 else null


# --- Cultista: detonar cadáver --------------------------------------------------

func _corpse_blast() -> bool:
	var best = null
	var best_d := B.CORPSE_BLAST_REACH
	for c in world.corpses:
		if c.heart or c.holy:
			continue
		for h in world.heroes.targets():
			var d: float = c.position.distance_to(h.position)
			if d < best_d:
				best_d = d
				best = c
	if best == null:
		return false
	var pos: Vector2 = best.position
	world.remove_corpse(best)
	for t in _targets():
		if pos.distance_to(t.position) < B.CORPSE_BLAST_RADIUS + t.radius:
			_hurt(t, creep.bite * B.CORPSE_BLAST_DAMAGE)
	world.fx.explosion(pos, B.CORPSE_BLAST_RADIUS, Color(0.75, 0.3, 0.9))
	world.shake()
	return true


# --- Demonio: aliento en cono ---------------------------------------------------

func _update_breath(delta: float) -> void:
	if _breath_t > 0.0:
		_breath_t -= delta
		var target = _nearest_target(creep.position, B.BREATH_LENGTH * 1.5)
		if target != null:
			_breath_dir = (target.position - creep.position).normalized()
		_breath_tick -= delta
		if _breath_tick <= 0.0:
			_breath_tick = B.BREATH_TICK
			var half := deg_to_rad(B.BREATH_ANGLE * 0.5)
			for t in _targets():
				var to_t: Vector2 = t.position - creep.position
				if to_t.length() < B.BREATH_LENGTH + t.radius and absf(_breath_dir.angle_to(to_t)) <= half:
					_hurt(t, creep.bite * B.BREATH_DAMAGE)
		return
	_breath_cd -= delta
	if _breath_cd > 0.0:
		return
	var target = _nearest_target(creep.position, B.BREATH_LENGTH)
	if target != null:
		_breath_cd = B.BREATH_EVERY
		_breath_t = B.BREATH_TIME
		_breath_tick = 0.0
		_breath_dir = (target.position - creep.position).normalized()


# --- Mutaciones de arma ---------------------------------------------------------

## Espinas: durante la embestida, cada cosa que tocás recibe daño una vez.
func _thorns() -> void:
	var dashing: bool = creep.dashing()
	if dashing and not _was_dashing:
		_thorn_victims.clear()
	_was_dashing = dashing
	var r: int = creep.rank("espinas")
	if not dashing or r == 0:
		return
	var dmg: float = creep.bite * (B.THORNS_DAMAGE + B.THORNS_PER_RANK * (r - 1))
	for v in _targets() + world.civilians:
		if not _thorn_victims.has(v) and creep.position.distance_to(v.position) <= creep.radius + v.radius:
			_thorn_victims.append(v)
			if v in world.civilians:
				v.take_damage(dmg)
			else:
				_hurt(v, dmg)


## Pegote: un charco cada GOO_EVERY que frena a los héroes que lo pisan.
func _update_goo(delta: float) -> void:
	var r: int = creep.rank("pegote")
	if r > 0:
		_goo_cd -= delta
		if _goo_cd <= 0.0:
			_goo_cd = B.GOO_EVERY
			_goo.append({"pos": creep.position, "t": B.GOO_TIME})
	var slow: float = B.GOO_SLOW[clampi(r - 1, 0, B.GOO_SLOW.size() - 1)]
	for g in _goo.duplicate():
		g.t -= delta
		if g.t <= 0.0:
			_goo.erase(g)
			continue
		for h in world.heroes.targets():
			if g.pos.distance_to(h.position) < B.GOO_RADIUS + h.radius:
				h.status.slow(slow)


## Llamado: la horda cercana corre hacia donde apuntás.
func _rally() -> void:
	var r: int = creep.rank("llamado")
	rally_cd = B.RALLY_COOLDOWN[clampi(r - 1, 0, B.RALLY_COOLDOWN.size() - 1)]
	_rally_at = _aim_point()
	_rally_fx = 0.6
	for m in world.minions:
		if m.position.distance_to(creep.position) < B.RALLY_RADIUS:
			m.rally_t = B.RALLY_TIME
			m.rally_pos = _rally_at


func aiming_with_mouse() -> bool:
	return _aim_mouse


func _aim_point() -> Vector2:
	if _aim_mouse:
		return get_global_mouse_position()
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var dir: Vector2 = stick.normalized() if stick.length() > 0.3 else creep.facing()
	return creep.position + dir * B.RALLY_AIM_DIST


# --- Dibujo ---------------------------------------------------------------------

func _draw() -> void:
	for g in _goo:
		var a := clampf(g.t / B.GOO_TIME, 0.2, 1.0)
		draw_circle(g.pos, B.GOO_RADIUS, Color(0.85, 0.75, 0.3, 0.22 * a))
		draw_arc(g.pos, B.GOO_RADIUS, 0.0, TAU, 28, Color(0.95, 0.85, 0.35, 0.5 * a), 1.5)
	for b in _bones:
		var side: Vector2 = b.vel.normalized().orthogonal() * 2.0
		var along: Vector2 = b.vel.normalized() * 6.0
		draw_line(b.pos - along, b.pos + along, Color(0.95, 0.93, 0.85), 3.0)
		draw_circle(b.pos + along + side, 2.0, Color(0.95, 0.93, 0.85))
		draw_circle(b.pos + along - side, 2.0, Color(0.95, 0.93, 0.85))
	if _breath_t > 0.0:
		var half := deg_to_rad(B.BREATH_ANGLE * 0.5)
		var pts := PackedVector2Array([creep.position])
		for i in 9:
			pts.append(creep.position + _breath_dir.rotated(-half + half * 2.0 * i / 8.0) * B.BREATH_LENGTH)
		var flicker := 0.25 + 0.1 * sin(world.elapsed * 40.0)
		draw_colored_polygon(pts, Color(1.0, 0.45, 0.1, flicker))
	if creep.rank("llamado") > 0 and rally_cd > 0.0:
		var k: float = rally_cd / B.RALLY_COOLDOWN[clampi(creep.rank("llamado") - 1, 0, 2)]
		draw_arc(creep.position, creep.radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - k), 24, Color(1.0, 0.9, 0.4, 0.5), 2.0)
	if _rally_fx > 0.0:
		var k := _rally_fx / 0.6
		draw_arc(_rally_at, 20.0 + 30.0 * (1.0 - k), 0.0, TAU, 24, Color(1.0, 0.9, 0.4, k), 3.0)
		draw_line(creep.position, _rally_at, Color(1.0, 0.9, 0.4, 0.4 * k), 2.0)
