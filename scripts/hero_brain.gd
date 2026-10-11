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


## Un solo objetivo por vez, el primero que aplica (la carga de un ataque de jefe ya lo deja
## quieto en hero.gd): 1) carrera de la furia: lejos de vos y de la horda; 2) cazándote: a
## distancia de tiro; 3) rodeado o con poca vida: lejos de la horda; 4) _goal (grito cerca,
## cofre, corazón, gemas, grito lejos, tu última posición, farmear). Siempre se aparta un poco
## de la horda (salvo si se distrae) y de las paredes.
func _think() -> void:
	var hunting: bool = hunting_you() and not world.player_hidden(self)
	target = _pick_hunt_target() if hunting else _pick_target()
	var away := Vector2.ZERO # alejarse de la horda, más fuerte cuanto más cerca y más grande
	var danger := 0.0
	for m in world.minions:
		var off: Vector2 = position - m.position
		var d := off.length()
		if d < 180.0 and d > 0.01:
			var w: float = (180.0 - d) / 180.0 * (m.radius / 10.0)
			away += off / d * w
			danger += w
	var steer := Vector2.ZERO
	if _fury_run_t > 0.0:
		steer = away + _toward(world.player.position) * -3.0
	elif hunting:
		var d := position.distance_to(world.player.position)
		if absf(d - B.HUNT_IDEAL_DIST) > 60.0:
			steer = _toward(world.player.position) * signf(d - B.HUNT_IDEAL_DIST)
	elif danger >= B.HERO_SURROUNDED_DANGER or hp / max_hp < B.HERO_PRIORITY_HP:
		steer = away
	else:
		var goal = _goal()
		if goal == null: # encima del cofre: quieto para abrirlo
			_move_dir = Vector2.ZERO
			return
		steer = goal
	if _fury_run_t <= 0.0 and _rng.randf() >= B.HERO_MISTAKE_CHANCE: # a veces se distrae y se mete
		steer += away.limit_length(1.0) * B.HERO_HORDE_SEPARATION
	var margin := 200.0
	if position.x < margin or position.y < margin or position.x > B.ARENA_SIZE.x - margin or position.y > B.ARENA_SIZE.y - margin:
		steer += _toward(B.ARENA_SIZE * 0.5) * 1.5
	_move_dir = steer.normalized() if steer.length() > 0.15 else Vector2.ZERO


## Hacia dónde ir sin apuro (dirección; null = quedarse quieto encima del cofre).
func _goal():
	var alarm: bool = world.alarm_t > 0.0 and position.distance_to(world.alarm_pos) > 40.0
	if alarm and position.distance_to(world.alarm_pos) < B.ALARM_CLOSE_DIST:
		return _toward(world.alarm_pos)
	var chest = world.chest
	if chest != null and position.distance_to(chest.position) < B.CHEST_HERO_SEEK_RADIUS:
		return _toward(chest.position) if position.distance_to(chest.position) > B.CHEST_OPEN_RADIUS * 0.5 else null
	var heart = _nearest(world.corpses.filter(func(c): return c.heart), B.HERO_HEART_SEEK_RADIUS)
	if heart != null:
		return _toward(heart.position)
	if _pile_t <= 0.0 or not is_instance_valid(_pile) or position.distance_to(_pile.position) > B.HERO_GEM_SEEK_RADIUS:
		_pile_t = B.HERO_GEM_PILE_EVERY
		_pile = _best_gem_pile(B.HERO_GEM_SEEK_RADIUS)
	if is_instance_valid(_pile) and not status.blinded():
		return _toward(_pile.position)
	if alarm:
		return _toward(world.alarm_pos)
	if sight == Sight.SEARCH and position.distance_to(_last_seen) > 40.0:
		return _toward(_last_seen)
	if _target_valid() and position.distance_to(target.position) < B.HERO_RANGE * 0.5 - 60.0:
		return _toward(target.position) * -0.8 # farmear: no dejar que se le acerque tanto
	return Vector2.ZERO


func _toward(pos: Vector2) -> Vector2:
	return (pos - position).normalized()


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
	if status.blinded(): # Nube de la Reina: no ve gemas
		return null
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
