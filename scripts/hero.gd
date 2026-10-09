extends Node2D
## El héroe controlado por la IA. Versión del hito 1: farmea la horda,
## kitea, junta experiencia, sube de nivel y se retira con poca vida.
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
var speed := B.HERO_SPEED
var radius := B.HERO_RADIUS

var target = null
var _move_dir := Vector2.ZERO
var _aim := Vector2.RIGHT
var _fire_t := 0.0
var _think_t := 0.0
var _flash := 0.0
var _level_fx := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 2
	_rng.randomize()


func _process(delta: float) -> void:
	if not world.running:
		return
	hp = minf(max_hp, hp + B.HERO_REGEN * delta)

	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = _rng.randf_range(B.HERO_REACTION_MIN, B.HERO_REACTION_MAX)
		_think()

	position += _move_dir * speed * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	for g in world.gems.duplicate():
		if position.distance_to(g.position) < B.HERO_PICKUP_RADIUS:
			_gain_xp(g.xp)
			world.remove_gem(g)

	_fire_t -= delta
	if _fire_t <= 0.0 and _target_valid() and position.distance_to(target.position) <= B.HERO_RANGE:
		_fire_t = cooldown
		_fire()

	_flash = maxf(_flash - delta, 0.0)
	_level_fx = maxf(_level_fx - delta, 0.0)
	queue_redraw()


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

	# 2. juntar experiencia cuando no hay mucho peligro
	if not low_hp:
		var gem = _nearest(world.gems, 350.0)
		if gem != null:
			steer += (gem.position - position).normalized() * (1.2 if danger < 2.0 else 0.5)

	# 3. mantener al objetivo a buena distancia de tiro
	if _target_valid() and not low_hp:
		var to_t: Vector2 = target.position - position
		var d := to_t.length()
		var ideal := 220.0 if (target == world.player and world.detected) else B.HERO_RANGE * 0.7
		if d > ideal + 60.0:
			steer += to_t / d * (1.5 if target == world.player else 0.8)
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
	var dir: Vector2 = (target.position - position).normalized()
	dir = dir.rotated(deg_to_rad(_rng.randf_range(-B.HERO_AIM_ERROR_DEG, B.HERO_AIM_ERROR_DEG)))
	_aim = dir
	var spread := deg_to_rad(12.0)
	for i in arrows:
		var offset := (i - (arrows - 1) * 0.5) * spread
		world.spawn_projectile(position + dir * radius, dir.rotated(offset), damage)


func _gain_xp(amount: float) -> void:
	xp += amount
	while xp >= B.xp_for_level(level):
		xp -= B.xp_for_level(level)
		_level_up()


func _level_up() -> void:
	level += 1
	max_hp += B.HERO_HP_PER_LEVEL
	hp += B.HERO_HP_PER_LEVEL
	damage *= B.HERO_DAMAGE_PER_LEVEL
	cooldown = maxf(cooldown * B.HERO_COOLDOWN_PER_LEVEL, B.HERO_MIN_COOLDOWN)
	arrows = 1 + level / B.HERO_LEVELS_PER_EXTRA_ARROW
	_level_fx = 0.6


func enrage() -> void:
	damage *= B.HERO_ENRAGE_DAMAGE_MULT
	speed *= B.HERO_ENRAGE_SPEED_MULT


func take_damage(amount: float, from_player: bool) -> void:
	hp -= amount
	if from_player:
		_flash = 0.1
		world.add_threat(amount * B.THREAT_PER_DAMAGE)
	if hp <= 0.0:
		hp = 0.0
		world.end_game(true, "Mataste al héroe en el minuto %d." % int(world.elapsed / 60.0))


func _draw() -> void:
	var body := Color.WHITE if _flash > 0.0 else Color(0.3, 0.55, 1.0)
	if world.enraged:
		body = body.lerp(Color(1, 0.3, 0.2), 0.5)
	draw_circle(Vector2.ZERO, B.HERO_PICKUP_RADIUS, Color(0.3, 0.55, 1.0, 0.04))
	draw_rect(Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0), Color(0.05, 0.05, 0.1))
	draw_rect(Rect2(Vector2(-radius + 2, -radius + 2), Vector2(radius - 2, radius - 2) * 2.0), body)
	draw_line(Vector2.ZERO, _aim * (radius + 10.0), Color(1, 0.95, 0.7), 3.0)
	if _level_fx > 0.0:
		draw_arc(Vector2.ZERO, radius + 20.0 * (1.0 - _level_fx), 0.0, TAU, 24, Color(1, 1, 0.5, _level_fx), 2.0)
