extends RefCounted
## Mejoras del creep al subir de nivel, estilo HoloCure: cada vez elige 1 de 3 cartas.
## Las cartas mezclan poderes de la clase (CLASS_POWERS en balance.gd: poder nuevo o
## subir de rango uno tuyo) y stats (LIST). Hasta POWERS_MAX poderes distintos con
## POWER_MAX_RANK rangos cada uno; el primero de cada clase es fijo y arranca en rango 1.
## Mandíbula sangrienta (Colmillos al máximo + Mordida vampírica) es la única evolución:
## cuando está disponible viene garantizada. Festín es el relleno si no queda nada.
## Todo vive en player.ranks (id -> rango).

const B := preload("res://scripts/balance.gd")

const LIST := {
	"colmillos": {"name": "Colmillos", "desc": "+12,5% daño", "max": 10},
	"patas": {"name": "Patas ágiles", "desc": "+5% velocidad", "max": 8},
	"caparazon": {"name": "Caparazón", "desc": "+12,5% vida máxima y te cura", "max": 10},
	"iman": {"name": "Imán de carne", "desc": "Los cadáveres cercanos vuelan hacia vos (+30 de radio)", "max": 6},
	"frenesi": {"name": "Frenesí", "desc": "Comer seguido arma un combo que multiplica la biomasa", "max": 2},
	"rey": {"name": "Rey de la horda", "desc": "Los compañeros cerca tuyo van más rápido y pegan más (cada rango agranda el aura)", "max": 6, "min_stage": 1},
	"vampiro": {"name": "Mordida vampírica", "desc": "La mordida te cura un 10% del daño", "max": 4},
	# Relleno: solo aparece si no alcanzan las opciones (todo al máximo)
	"festin": {"name": "Festín", "desc": "Te cura 30% y +5% de daño", "max": 0, "filler": true},
	# Evolución
	"mandibula": {"name": "Mandíbula sangrienta", "desc": "La mordida cura 35%, llega más lejos y hace sangrar al héroe", "max": 1,
		"weapon": "colmillos", "passive": "vampiro"},
}


static func powers(klass: String) -> Array:
	return B.CLASS_POWERS.get(klass, B.CLASS_POWERS.engendro)


static func power(id: String, klass: String) -> Dictionary:
	for p in powers(klass):
		if p.id == id:
			return p
	return {}


static func is_power(id: String, klass: String) -> bool:
	return not power(id, klass).is_empty()


static func is_evolution(id: String) -> bool:
	return LIST.has(id) and LIST[id].has("weapon")


## Poderes que tenés, en el orden de la tabla.
static func owned_powers(ranks: Dictionary, klass: String) -> Array:
	var out: Array = []
	for p in powers(klass):
		if ranks.get(p.id, 0) > 0:
			out.append(p.id)
	return out


## "evolucion", "nuevo" (poder que no tenés), "rango" (poder tuyo), "stat" o "relleno".
static func kind(id: String, ranks: Dictionary, klass: String) -> String:
	if is_power(id, klass):
		return "rango" if ranks.get(id, 0) > 0 else "nuevo"
	if is_evolution(id):
		return "evolucion"
	return "relleno" if LIST[id].get("filler", false) else "stat"


static func title(id: String, klass: String) -> String:
	return power(id, klass).name if is_power(id, klass) else LIST[id].name


## Texto de la carta: el poder nuevo dice qué hace; subir de rango, qué gana.
static func desc(id: String, ranks: Dictionary, klass: String) -> String:
	if not is_power(id, klass):
		var text: String = LIST[id].desc
		for evo in LIST:
			if is_evolution(evo) and (LIST[evo].weapon == id or LIST[evo].passive == id):
				var other: String = LIST[evo].passive if LIST[evo].weapon == id else LIST[evo].weapon
				text += "\nEvoluciona con %s" % LIST[other].name
		return text
	var p := power(id, klass)
	if ranks.get(id, 0) == 0:
		return p.desc
	return "%s\nRango %d: +%d%% daño o efecto, -%d%% recarga" % [p.desc, ranks[id] + 1,
		roundi(B.POWER_RANK_EFFECT * 100.0), roundi(B.POWER_RANK_COOLDOWN * 100.0)]


static func available_evolutions(ranks: Dictionary) -> Array:
	var out: Array = []
	for id in LIST:
		if not is_evolution(id) or ranks.get(id, 0) > 0:
			continue
		var w: String = LIST[id].weapon
		if ranks.get(w, 0) >= LIST[w].max and ranks.get(LIST[id].passive, 0) >= 1:
			out.append(id)
	return out


static func roll(ranks: Dictionary, stage: int, rng: RandomNumberGenerator, count: int = 3, klass := "engendro") -> Array:
	var out: Array = []
	var evos := available_evolutions(ranks)
	if not evos.is_empty():
		out.append(evos[rng.randi_range(0, evos.size() - 1)])
	var pool: Array = [] # [id, peso]
	var room: bool = owned_powers(ranks, klass).size() < B.POWERS_MAX
	for p in powers(klass):
		var r: int = ranks.get(p.id, 0)
		if r == 0 and room:
			pool.append([p.id, B.PICK_WEIGHT_NEW])
		elif r > 0 and r < B.POWER_MAX_RANK:
			pool.append([p.id, B.PICK_WEIGHT_RANK])
	for id in LIST:
		if is_evolution(id) or LIST[id].get("filler", false):
			continue
		if ranks.get(id, 0) < LIST[id].max and stage >= LIST[id].get("min_stage", 0):
			pool.append([id, B.PICK_WEIGHT_STAT])
	while out.size() < count and not pool.is_empty():
		var total := 0
		for e in pool:
			total += e[1]
		var r := rng.randi_range(1, total)
		var i := 0
		while r > pool[i][1]:
			r -= pool[i][1]
			i += 1
		out.append(pool[i][0])
		pool.remove_at(i)
	if out.size() < count:
		out.append("festin")
	return out
