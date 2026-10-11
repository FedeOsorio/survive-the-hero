extends "res://scripts/hero_combat.gd"
## IA del héroe: sospecha y estados de vista (farmear, cazarte, buscarte) y la decisión
## de cada momento (a qué tirar, hacia dónde moverse, qué gemas juntar).

## Solo con el reconocimiento encendido (aware, desde la furia).
## Sospecha que sube por tamaño y baja lejos; la mirada (cada SUSPICION_GAZE_EVERY) te puede
## reconocer antes de 100. Te caza RECOGNIZE_TIME; al vencer, a más de HUNT_LOSE_DIST o
## camuflado, te busca HUNT_SEARCH_TIME en tu última posición y vuelve a farmear.
func _update_sight(delta: float) -> void:
	if not aware:
		return
	var p = world.player
	if _sees(p):
		var last := B.CREEP_STAGES.size() - 1
		if p.stage == last:
			_add_suspicion(B.SUSPICION_DEMON_PER_SECOND * delta)
		elif p.stage == last - 1:
			_add_suspicion(B.SUSPICION_CULTIST_PER_SECOND * delta)
		_gaze_t -= delta
		if _gaze_t <= 0.0:
			_gaze_t = B.SUSPICION_GAZE_EVERY
			if sight != Sight.HUNT and _rng.randf() < suspicion / B.SUSPICION_MAX * B.SUSPICION_GAZE_CHANCE:
				recognize()
	else:
		suspicion = maxf(suspicion - B.SUSPICION_DECAY * delta, 0.0)
	if sight == Sight.HUNT:
		_hunt_t -= delta
		if world.player_hidden(self) or position.distance_to(p.position) > B.HUNT_LOSE_DIST or _hunt_t <= 0.0:
			sight = Sight.SEARCH
			_search_t = B.HUNT_SEARCH_TIME
			suspicion = B.SUSPICION_AFTER_HUNT
		else:
			_last_seen = p.position
	elif sight == Sight.SEARCH:
		_search_t -= delta
		if _search_t <= 0.0:
			sight = Sight.FARM
			world.hud.banner("Lo perdiste: %s dejó de buscarte" % _the_name())


func _sees(p) -> bool:
	return not world.player_hidden(self) and position.distance_to(p.position) < B.RECOGNIZE_RANGE


## Hiciste algo que un creep común no hace (comer, robar una gema, esquivar, matar un
## civil, evolucionar): suma "amount" ±SUSPICION_JITTER si te ve. Cazándote, reinicia los 12 s.
func suspect(amount: float) -> void:
	if not aware or not _sees(world.player):
		return
	if sight == Sight.HUNT:
		_hunt_t = B.RECOGNIZE_TIME
		return
	_add_suspicion(amount * _rng.randf_range(1.0 - B.SUSPICION_JITTER, 1.0 + B.SUSPICION_JITTER))


func _add_suspicion(amount: float) -> void:
	if sight == Sight.HUNT:
		_hunt_t = B.RECOGNIZE_TIME
		return
	suspicion = minf(suspicion + amount, B.SUSPICION_MAX)
	if suspicion >= B.SUSPICION_MAX:
		recognize()


## Te reconoció: te caza RECOGNIZE_TIME.
func recognize() -> void:
	if not aware:
		return
	var p = world.player
	if sight != Sight.HUNT:
		world.on_hero_saw_you(self)
	sight = Sight.HUNT
	suspicion = B.SUSPICION_MAX
	_hunt_t = B.RECOGNIZE_TIME
	_last_seen = p.position


func _think() -> void:
	var hunting: bool = hunting_you() and not world.player_hidden(self)
	target = _pick_hunt_target() if hunting else _pick_target()
	var low_hp := _fury_run_t > 0.0 # la carrera corta al enfurecerse
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
		var away_p: Vector2 = position - world.player.position
		if away_p.length() > 0.01:
			steer += away_p.normalized() * 3.0 # furia: primero toma distancia de vos

	# 2. juntar experiencia: va al montón de gemas que más vale. Cazándote o yendo
	#    a un grito mira más cerca y tira menos, pero igual se desvía por un montón.
	if not low_hp:
		var seek := B.HERO_GEM_SEEK_RADIUS
		var pull := B.HERO_GEM_PULL if danger < B.HERO_GEM_DANGER else B.HERO_GEM_PULL_DANGER
		if hunting:
			seek = B.HUNT_GEM_RADIUS
			pull = B.HUNT_GEM_PULL
		elif sight == Sight.SEARCH or (world.alarm_t > 0.0 and not hunting):
			seek = B.ALARM_GEM_RADIUS
			pull = B.ALARM_GEM_PULL
		if _pile_t <= 0.0 or not is_instance_valid(_pile) or position.distance_to(_pile.position) > seek:
			_pile_t = B.HERO_GEM_PILE_EVERY
			_pile = _best_gem_pile(seek)
		var gem = _pile if is_instance_valid(_pile) else null
		if gem != null:
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
	if world.alarm_t > 0.0 and not low_hp and not hunting:
		var to_alarm: Vector2 = world.alarm_pos - position
		if to_alarm.length() > 40.0:
			steer += to_alarm.normalized() * B.ALARM_PULL

	# 2c. te perdió de vista: va a tu última posición vista
	if sight == Sight.SEARCH and not low_hp:
		var to_seen: Vector2 = _last_seen - position
		if to_seen.length() > 40.0:
			steer += to_seen.normalized() * B.HUNT_SEARCH_PULL

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
	if not world.player_hidden(self):
		candidates.append(world.player)
	for c in candidates:
		var d := position.distance_to(c.position)
		if d > reach and not (c == world.player and hunting_you()):
			continue
		var score := -d
		if c.hp <= damage:
			score += 60.0 # prefiere lo que mata de un golpe
		if c == world.player and hunting_you():
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


## La gema a menos de "seek" con más XP alrededor (HERO_GEM_CLUSTER_RADIUS),
## dividida por (distancia + HERO_GEM_DIST_BIAS). Mira solo las HERO_GEM_PILE_LOOK más cercanas.
func _best_gem_pile(seek: float):
	var near: Array = []
	for g in world.gems:
		if position.distance_to(g.position) < seek:
			near.append(g)
	if near.size() > B.HERO_GEM_PILE_LOOK:
		near.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
		near.resize(B.HERO_GEM_PILE_LOOK)
	var best = null
	var best_score := 0.0
	for g in near:
		var xp_sum := 0.0
		for o in near:
			if g.position.distance_to(o.position) < B.HERO_GEM_CLUSTER_RADIUS:
				xp_sum += o.xp
		var score: float = xp_sum / (position.distance_to(g.position) + B.HERO_GEM_DIST_BIAS)
		if score > best_score:
			best_score = score
			best = g
	return best
