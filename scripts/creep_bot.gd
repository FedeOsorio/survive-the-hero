extends RefCounted
## Bot muy simple para el modo --bot: caza civiles y come; ataca al héroe de Demonio.


static func move(creep) -> Vector2:
	var hero = creep.world.hero
	if hero == null:
		hero = creep # sin héroes vivos: solo come
	var to_hero: Vector2 = hero.position - creep.position
	var d := to_hero.length()
	if hero != creep and creep.stage >= 3 and creep.hp / creep.max_hp > 0.4:
		return to_hero / d
	var best = null
	var best_d := INF
	for c in creep.world.corpses + creep.world.civilians:
		var cd: float = creep.position.distance_to(c.position)
		if (hero == creep or c.position.distance_to(hero.position) > 350.0) and cd < best_d:
			best_d = cd
			best = c
	var dir := Vector2.ZERO
	if best != null:
		dir = (best.position - creep.position).normalized()
	if hero != creep and d < 380.0:
		dir -= to_hero / d * 2.0
	return dir.normalized() if dir.length() > 0.1 else Vector2.ZERO
