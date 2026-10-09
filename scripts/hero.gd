extends Node2D
## Un héroe controlado por la IA (Arquero, Caballero o Maga: ver heroes.gd).
## Farmea la horda, kitea, junta experiencia, sube de nivel, esquiva proyectiles
## y se retira con poca vida. No se regenera: solo se cura al subir de nivel.
## Al jugador lo trata como un creep más hasta que lo detecta.
## En cada nivel gana un poder (ver hero_powers.gd).

const B := preload("res://scripts/balance.gd")
const HeroPowers := preload("res://scripts/hero_powers.gd")
const HeroStatus := preload("res://scripts/hero_status.gd")

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
var _horde_turn := false # cazando: el próximo disparo va a la horda
var _rng := RandomNumberGenerator.new()
var powers # hero_powers.gd: orbes, rayo, aura, nova, etc.
var status # hero_status.gd: sangrado, aturdimiento, lentitud
var damage_taken := {"jugador": 0.0, "horda": 0.0} # para los reportes de --sim
var title := "Arquero"
var article := "el"
var color := Color(0.3, 0.55, 1.0)
var speed_mult := 1.0 # del tipo de héroe y del enfurecido
var power_mult := 1.0 # daño de los poderes: solo lo sube el enfurecido
var was_low := false # para la Infamia: ya sumó por tenerlo con poca vida


func _ready() -> void:
	z_index = 2
	_rng.randomize()
	powers = HeroPowers.new()
	powers.hero = self
	powers.world = world
	add_child(powers)
	status = HeroStatus.new()
	status.hero = self
	status.world = world
	add_child(status)


## Tipo de héroe (una fila de B.HEROES) y nivel de llegada. Los niveles de llegada
## suben los números sin elegir poder: llega solo con sus poderes de inicio.
## Se llama después de agregarlo al árbol.
func setup(cfg: Dictionary, start_level: int) -> void:
	title = cfg.name
	article = cfg.article
	color = cfg.color
	speed_mult = cfg.speed
	for id in cfg.powers:
		powers.ranks[id] = 1
	for i in start_level - 1:
		_level_up(false)
	max_hp *= cfg.hp
	hp = max_hp
	damage *= cfg.damage
	_apply_ranks()
	_level_fx = 0.0


func _process(delta: float) -> void:
	if not world.running:
		return
	if status.stunned():
		_aim_windup = 0.0
		queue_redraw()
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
		position += _move_dir * speed * status.speed_mult() * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))

	# las gemas dentro del radio vuelan hacia él; las junta al tocarlas
	for g in world.gems.duplicate():
		var gd := position.distance_to(g.position)
		if gd < radius + 6.0:
			_gain_xp(g.xp)
			world.remove_gem(g)
		elif gd < pickup_radius():
			g.position = g.position.move_toward(position, B.HERO_GEM_PULL_SPEED * delta)
	for c in world.corpses.duplicate():
		if c.heart and position.distance_to(c.position) < B.HERO_HEART_PICKUP + level * B.HERO_HEART_PICKUP_PER_LEVEL + c.radius:
			_level_up()
			hp = minf(max_hp, hp + max_hp * B.ELITE_HEART_HERO_HEAL)
			world.remove_corpse(c)

	_fire_t -= delta
	if _aim_windup > 0.0:
		_aim_windup -= delta
		if _aim_windup <= 0.0:
			_fire_t = cooldown
			_fire_dir(_aim_locked, _close_horde())
	elif _fire_t <= 0.0 and _roll_t <= 0.0 and _target_valid() and position.distance_to(target.position) <= B.HERO_RANGE:
		var hunting_you: bool = target == world.player and world.detected
		var guard: Array = _close_horde() if hunting_you else []
		if _horde_turn and not guard.is_empty():
			# cazando con creeps cerca, alterna: un disparo a la horda y uno a vos
			_horde_turn = false
			_fire_t = cooldown
			_fire_dir((guard[0].position - position).normalized(), guard.slice(1) if guard.size() > 1 else guard)
		elif hunting_you:
			# contra el jugador apunta primero y avisa: se puede esquivar
			_horde_turn = true
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
	if target == world.player:
		return world.player.stealth_t <= 0.0
	return world.minions.has(target)


# --- Decisiones --------------------------------------------------------------

func _think() -> void:
	var hunting: bool = world.detected and world.player.stealth_t <= 0.0
	target = _pick_hunt_target() if hunting else _pick_target()
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

	# 2. juntar experiencia: es su prioridad mientras no esté en peligro.
	#    Cazándote, solo junta las gemas que le quedan en el camino.
	var busy: bool = hunting or (world.alarm_t > 0.0 and not world.detected) # cazando o yendo al grito
	if not low_hp:
		var gem = _nearest(world.gems, B.HUNT_GEM_RADIUS if busy else 550.0)
		if gem != null:
			var pull := B.HUNT_GEM_PULL if busy else (2.2 if danger < 3.0 else 0.8)
			steer += (gem.position - position).normalized() * pull

	# 2a. un corazón de élite vale más que cualquier gema
	if not low_hp:
		var best_heart = null
		var best_d := B.HERO_HEART_SEEK_RADIUS
		for c in world.corpses:
			if c.heart and position.distance_to(c.position) < best_d:
				best_d = position.distance_to(c.position)
				best_heart = c
		if best_heart != null:
			steer += (best_heart.position - position).normalized() * B.HERO_HEART_PULL

	# 2c. un cofre es lo que más le importa: lo hace subir de nivel
	if not low_hp and world.chest != null and position.distance_to(world.chest.position) < B.CHEST_HERO_SEEK_RADIUS:
		var to_chest: Vector2 = world.chest.position - position
		if to_chest.length() > B.CHEST_OPEN_RADIUS * 0.5:
			steer += to_chest.normalized() * B.CHEST_HERO_PULL
		else:
			steer = Vector2.ZERO # quieto encima para abrirlo

	# 2b. si un civil gritó, va hacia ahí a buscar al creep (a los civiles no los toca)
	if world.alarm_t > 0.0 and not low_hp and not world.detected:
		var to_alarm: Vector2 = world.alarm_pos - position
		if to_alarm.length() > 40.0:
			steer += to_alarm.normalized() * B.ALARM_PULL

	# 3. cacería: con el jugador detectado lo persigue a distancia de tiro.
	#    A la horda no la busca (ya viene sola), solo se aleja si está muy encima.
	if hunting and not low_hp:
		var to_p: Vector2 = world.player.position - position
		var d := to_p.length()
		if d > B.HUNT_IDEAL_DIST + 60.0:
			steer += to_p / d * (B.HUNT_PULL_CROWDED if danger > B.HUNT_CROWDED_DANGER else B.HUNT_PULL)
		elif d < B.HUNT_IDEAL_DIST - 60.0 and d > 0.01:
			steer -= to_p / d * 0.8
	elif _target_valid() and not low_hp:
		var to_t: Vector2 = target.position - position
		var d := to_t.length()
		if d < B.HERO_RANGE * 0.5 - 60.0 and d > 0.01:
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
	if world.player.stealth_t <= 0.0:
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


## Cazando: a vos si estás a tiro; si no, al creep más cerca de la línea hacia vos.
## Con HUNT_ESCAPE_COUNT creeps encima, primero zafa tirándole al más cercano.
## Con creeps a menos de HUNT_SHARE_RADIUS, el disparo alterna entre vos y la horda.
func _pick_hunt_target():
	var close: Array = []
	for m in _close_horde():
		if position.distance_to(m.position) < B.HUNT_ESCAPE_RADIUS:
			close.append(m)
	if close.size() >= B.HUNT_ESCAPE_COUNT:
		return _nearest(close, INF)
	var p = world.player
	var to_p: Vector2 = p.position - position
	if to_p.length() <= B.HERO_RANGE:
		return p
	var dir := to_p.normalized()
	var best = null
	var best_off := INF
	for m in world.minions:
		var rel: Vector2 = m.position - position
		var along := rel.dot(dir)
		if along <= 0.0 or rel.length() > B.HERO_RANGE:
			continue
		var off := absf(rel.cross(dir))
		if off < best_off:
			best_off = off
			best = m
	return best if best != null else p


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


## Con "extra" (creeps cercanos), la primera flecha va a "base" y las demás a esos creeps.
func _fire_dir(base: Vector2, extra: Array = []) -> void:
	var dir := base.rotated(deg_to_rad(_rng.randf_range(-B.HERO_AIM_ERROR_DEG, B.HERO_AIM_ERROR_DEG)))
	_aim = dir
	var spread := deg_to_rad(12.0)
	for i in arrows:
		var d := dir.rotated((i - (arrows - 1) * 0.5) * spread)
		if not extra.is_empty():
			d = dir
			if i > 0:
				var m = extra[(i - 1) % extra.size()]
				if is_instance_valid(m):
					d = (m.position - position).normalized()
		world.spawn_projectile(position + dir * radius, d, damage, pierce)


## Creeps a menos de HUNT_SHARE_RADIUS, del más cercano al más lejano.
func _close_horde() -> Array:
	var out: Array = []
	for m in world.minions:
		if position.distance_to(m.position) < B.HUNT_SHARE_RADIUS:
			out.append(m)
	out.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
	return out


func _gain_xp(amount: float) -> void:
	xp += amount
	while xp >= B.xp_for_level(level):
		xp -= B.xp_for_level(level)
		_level_up()


## "pick_power" en false: sube los números del nivel sin elegir poder.
func _level_up(pick_power := true) -> void:
	level += 1
	max_hp += B.HERO_HP_PER_LEVEL
	hp = minf(max_hp, hp + B.HERO_HP_PER_LEVEL + max_hp * B.HERO_LEVEL_HEAL)
	damage *= B.HERO_DAMAGE_PER_LEVEL
	cooldown = maxf(cooldown * B.HERO_COOLDOWN_PER_LEVEL, B.HERO_MIN_COOLDOWN)
	if pick_power:
		powers.level_up()
	_apply_ranks()
	_level_fx = 0.6


func _apply_ranks() -> void:
	arrows = 1 + level / B.HERO_LEVELS_PER_EXTRA_ARROW + powers.rank("multiple")
	pierce = B.HERO_ARROW_PIERCE + powers.rank("perforante")
	speed = B.HERO_SPEED * speed_mult * (1.0 + B.POWER_SPEED * powers.rank("botas"))


func enrage() -> void:
	damage *= B.HERO_ENRAGE_DAMAGE_MULT
	power_mult *= B.HERO_ENRAGE_DAMAGE_MULT
	speed_mult *= B.HERO_ENRAGE_SPEED_MULT
	_apply_ranks()


func take_damage(amount: float, from_player: bool, melee := false, tick := false) -> void:
	if hp <= 0.0:
		return
	if from_player:
		status.log_damage(amount, melee)
		status.show_damage(amount, tick)
	damage_taken["jugador" if from_player else "horda"] += amount
	if not from_player:
		# la horda lo desgasta pero el golpe final solo lo puede dar el jugador
		hp = maxf(hp - amount, 1.0)
		_hurt = 0.05
		return
	hp -= amount
	if from_player:
		if not tick:
			_flash = B.HERO_HIT_FLASH
		world.add_threat(amount * B.THREAT_PER_DAMAGE)
	if hp <= 0.0:
		hp = 0.0
		world.heroes.on_hero_killed(self)


func _draw() -> void:
	var body := color
	if _flash > 0.0:
		body = Color.WHITE
	elif _hurt > 0.0:
		body = Color(1.0, 0.5, 0.5)
	if world.enraged:
		body = body.lerp(Color(1, 0.3, 0.2), 0.5)
	draw_circle(Vector2.ZERO, pickup_radius(), Color(color, 0.04))
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
