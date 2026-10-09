extends Node2D
## El héroe controlado por la IA. Versión del hito 1: farmea la horda,
## kitea, junta experiencia, sube de nivel, esquiva proyectiles y se retira
## con poca vida. No se regenera: solo se cura al subir de nivel.
## Al jugador lo trata como un creep más hasta que lo detecta.

const B := preload("res://scripts/balance.gd")

var world
var hp := B.HERO_HP
var max_hp := B.HERO_HP
var level := 1
var xp := 0.0
var damage := B.HERO_ARROW_DAMAGE
var cooldown := B.HERO_ARROW_COOLDOWN
var arrows := 1
var pierce := B.HERO_ARROW_PIERCE
var speed := B.HERO_SPEED
var radius := B.HERO_RADIUS

var target = null
var _move_dir := Vector2.ZERO
var _aim := Vector2.RIGHT
var _fire_t := 0.0
var _think_t := 0.0
var _flash := 0.0
var _hurt := 0.0
var _level_fx := 0.0
var _slash_cd := 0.0
var _slash_windup := 0.0
var _slash_dir := Vector2.RIGHT
var _slash_fx := 0.0
var _roll_t := 0.0
var _roll_cd := 0.0
var _roll_dir := Vector2.ZERO
var _aim_windup := 0.0
var _aim_locked := Vector2.RIGHT
var _rng := RandomNumberGenerator.new()
var damage_taken := {"jugador": 0.0, "horda": 0.0} # para los reportes de --sim


func _ready() -> void:
	z_index = 2
	_rng.randomize()


func _process(delta: float) -> void:
	if not world.running:
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = _rng.randf_range(B.HERO_REACTION_MIN, B.HERO_REACTION_MAX)
		_think()

	_roll_cd = maxf(_roll_cd - delta, 0.0)
	if _roll_t > 0.0:
		_roll_t -= delta
		position += _roll_dir * B.HERO_ROLL_SPEED * delta
	else:
		_check_roll()
		position += _move_dir * speed * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	for g in world.gems.duplicate():
		if position.distance_to(g.position) < pickup_radius():
			_gain_xp(g.xp)
			world.remove_gem(g)

	_fire_t -= delta
	if _aim_windup > 0.0:
		_aim_windup -= delta
		if _aim_windup <= 0.0:
			_fire_t = cooldown
			_fire_dir(_aim_locked)
	elif _fire_t <= 0.0 and _roll_t <= 0.0 and _target_valid() and position.distance_to(target.position) <= B.HERO_RANGE:
		if target == world.player and world.detected:
			# contra el jugador apunta primero y avisa: se puede esquivar
			_aim_windup = B.HERO_AIM_WINDUP
			_aim_locked = (target.position - position).normalized()
			_aim = _aim_locked
		else:
			_fire_t = cooldown
			_fire()

	if B.HERO_SLASH_ENABLED and level >= B.HERO_SLASH_LEVEL:
		_update_slash(delta)

	_flash = maxf(_flash - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_level_fx = maxf(_level_fx - delta, 0.0)
	queue_redraw()


func rolling() -> bool:
	return _roll_t > 0.0


## Si un escupitajo del jugador viene directo hacia él y tiene la rodada lista, rueda.
func _check_roll() -> void:
	if _roll_cd > 0.0:
		return
	for s in world.spits:
		if not s.from_player or s.dodge_roll > B.HERO_DODGE_CHANCE:
			continue
		# sin detectarte no gasta la rodada en escupitajos que casi no le hacen nada
		if not world.detected and s.damage < max_hp * B.HERO_DODGE_MIN_DAMAGE:
			continue
		var rel: Vector2 = position - s.position
		var along: float = rel.dot(s.direction)
		if along <= 0.0 or along > B.HERO_DODGE_LOOKAHEAD:
			continue
		var lateral: Vector2 = rel - s.direction * along
		if lateral.length() < radius + 14.0:
			_roll_dir = lateral.normalized() if lateral.length() > 0.5 else s.direction.orthogonal()
			_roll_t = B.HERO_ROLL_TIME
			_roll_cd = B.HERO_ROLL_COOLDOWN
			_aim_windup = 0.0
			return


func pickup_radius() -> float:
	return B.HERO_PICKUP_RADIUS + level * B.HERO_PICKUP_PER_LEVEL


func slash_radius() -> float:
	return B.HERO_SLASH_RADIUS + level * B.HERO_SLASH_RADIUS_PER_LEVEL


## Tajo: cuando hay enemigos encima, avisa (windup) y después golpea en arco.
func _update_slash(delta: float) -> void:
	_slash_cd = maxf(_slash_cd - delta, 0.0)
	_slash_fx = maxf(_slash_fx - delta, 0.0)
	var r := slash_radius()
	if _slash_windup > 0.0:
		_slash_windup -= delta
		if _slash_windup <= 0.0:
			_do_slash(r)
		return
	if _slash_cd > 0.0:
		return
	var close = _nearest_enemy(r)
	if close != null:
		_slash_dir = (close.position - position).normalized()
		_slash_windup = B.HERO_SLASH_WINDUP
		_slash_cd = B.HERO_SLASH_COOLDOWN


func _do_slash(r: float) -> void:
	_slash_fx = 0.15
	var half := deg_to_rad(B.HERO_SLASH_ARC_DEG) * 0.5
	var dmg := damage * B.HERO_SLASH_DAMAGE_MULT
	var victims: Array = world.minions.duplicate()
	victims.append(world.player)
	for v in victims:
		var to_v: Vector2 = v.position - position
		if to_v.length() < r + v.radius and absf(_slash_dir.angle_to(to_v)) <= half:
			v.take_damage(dmg)


func _nearest_enemy(max_dist: float):
	var close = _nearest(world.minions, max_dist)
	var p = world.player
	var pd := position.distance_to(p.position)
	if pd < max_dist and (close == null or pd < position.distance_to(close.position)):
		return p
	return close


func _target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target == world.player or world.minions.has(target)


# --- Decisiones --------------------------------------------------------------

func _think() -> void:
	target = _pick_target()
	var low_hp := hp / max_hp < B.HERO_RETREAT_HP
	var mistake := _rng.randf() < B.HERO_MISTAKE_CHANCE

	# 1. alejarse de la horda (kitear). Con poca vida, mucho más fuerte.
	var steer := Vector2.ZERO
	var danger := 0.0
	var sense := 180.0
	for m in world.minions:
		var away: Vector2 = position - m.position
		var d := away.length()
		if d < sense and d > 0.01:
			var w: float = (sense - d) / sense * (m.radius / 10.0)
			steer += away / d * w
			danger += w
	if mistake:
		steer *= 0.2 # se distrae y se mete donde no debe
	elif low_hp:
		steer *= 2.5

	# 2. juntar experiencia: es su prioridad mientras no esté en peligro
	if not low_hp:
		var gem = _nearest(world.gems, 550.0)
		if gem != null:
			steer += (gem.position - position).normalized() * (2.2 if danger < 3.0 else 0.8)

	# 3. con el jugador detectado lo persigue a distancia de tiro; a la horda
	#    no la busca (ya viene sola), solo se aleja si está muy encima
	if _target_valid() and not low_hp:
		var to_t: Vector2 = target.position - position
		var d := to_t.length()
		var hunting: bool = target == world.player and world.detected
		var ideal := 220.0 if hunting else B.HERO_RANGE * 0.5
		if hunting and d > ideal + 60.0:
			steer += to_t / d * 1.8
		elif d < ideal - 60.0:
			steer -= to_t / d * 0.8

	# 4. no quedarse contra la pared
	var margin := 200.0
	var center := B.ARENA_SIZE * 0.5
	if position.x < margin or position.y < margin or position.x > B.ARENA_SIZE.x - margin or position.y > B.ARENA_SIZE.y - margin:
		steer += (center - position).normalized() * 1.5

	_move_dir = steer.normalized() if steer.length() > 0.15 else Vector2.ZERO


func _pick_target():
	var best = null
	var best_score := -INF
	var reach := B.HERO_RANGE * 1.3
	var candidates: Array = world.minions.duplicate()
	candidates.append(world.player)
	for c in candidates:
		var d := position.distance_to(c.position)
		if d > reach and not (c == world.player and world.detected):
			continue
		var score := -d
		if c.hp <= damage:
			score += 60.0 # prefiere lo que mata de un golpe
		if c == world.player and world.detected:
			score += B.HERO_DETECTED_TARGET_BONUS
		if score > best_score:
			best_score = score
			best = c
	return best


func _nearest(list: Array, max_dist: float):
	var best = null
	var best_d := max_dist
	for n in list:
		var d := position.distance_to(n.position)
		if d < best_d:
			best_d = d
			best = n
	return best


# --- Combate -----------------------------------------------------------------

func _fire() -> void:
	_fire_dir((target.position - position).normalized())


func _fire_dir(base: Vector2) -> void:
	var dir := base.rotated(deg_to_rad(_rng.randf_range(-B.HERO_AIM_ERROR_DEG, B.HERO_AIM_ERROR_DEG)))
	_aim = dir
	var spread := deg_to_rad(12.0)
	for i in arrows:
		var offset := (i - (arrows - 1) * 0.5) * spread
		world.spawn_projectile(position + dir * radius, dir.rotated(offset), damage, pierce)


func _gain_xp(amount: float) -> void:
	xp += amount
	while xp >= B.xp_for_level(level):
		xp -= B.xp_for_level(level)
		_level_up()


func _level_up() -> void:
	level += 1
	max_hp += B.HERO_HP_PER_LEVEL
	hp = minf(max_hp, hp + B.HERO_HP_PER_LEVEL + max_hp * B.HERO_LEVEL_HEAL)
	damage *= B.HERO_DAMAGE_PER_LEVEL
	cooldown = maxf(cooldown * B.HERO_COOLDOWN_PER_LEVEL, B.HERO_MIN_COOLDOWN)
	arrows = 1 + level / B.HERO_LEVELS_PER_EXTRA_ARROW
	_level_fx = 0.6


func enrage() -> void:
	damage *= B.HERO_ENRAGE_DAMAGE_MULT
	speed *= B.HERO_ENRAGE_SPEED_MULT


func take_damage(amount: float, from_player: bool) -> void:
	damage_taken["jugador" if from_player else "horda"] += amount
	if not from_player:
		# la horda lo desgasta pero el golpe final solo lo puede dar el jugador
		hp = maxf(hp - amount, 1.0)
		_hurt = 0.05
		return
	hp -= amount
	if from_player:
		_flash = 0.1
		world.add_threat(amount * B.THREAT_PER_DAMAGE)
	if hp <= 0.0:
		hp = 0.0
		world.end_game(true, "Mataste al héroe en el minuto %d." % int(world.elapsed / 60.0))


func _draw() -> void:
	var body := Color(0.3, 0.55, 1.0)
	if _flash > 0.0:
		body = Color.WHITE
	elif _hurt > 0.0:
		body = Color(1.0, 0.5, 0.5)
	if world.enraged:
		body = body.lerp(Color(1, 0.3, 0.2), 0.5)
	draw_circle(Vector2.ZERO, pickup_radius(), Color(0.3, 0.55, 1.0, 0.04))
	var half := deg_to_rad(B.HERO_SLASH_ARC_DEG) * 0.5
	var a := _slash_dir.angle()
	if _slash_windup > 0.0:
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 13:
			pts.append(Vector2.from_angle(a - half + half * 2.0 * i / 12.0) * slash_radius())
		draw_colored_polygon(pts, Color(1.0, 0.3, 0.2, 0.18))
	if _slash_fx > 0.0:
		draw_arc(Vector2.ZERO, slash_radius() * 0.85, a - half, a + half, 16, Color(1, 1, 0.85, 0.9), 6.0)
	if _aim_windup > 0.0:
		draw_line(Vector2.ZERO, _aim_locked * B.HERO_RANGE, Color(1, 0.25, 0.2, 0.55), 2.0)
	if _roll_t > 0.0:
		body = Color(body, 0.45)
	draw_rect(Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0), Color(0.05, 0.05, 0.1))
	draw_rect(Rect2(Vector2(-radius + 2, -radius + 2), Vector2(radius - 2, radius - 2) * 2.0), body)
	draw_line(Vector2.ZERO, _aim * (radius + 10.0), Color(1, 0.95, 0.7), 3.0)
	if _level_fx > 0.0:
		draw_arc(Vector2.ZERO, radius + 20.0 * (1.0 - _level_fx), 0.0, TAU, 24, Color(1, 1, 0.5, _level_fx), 2.0)
