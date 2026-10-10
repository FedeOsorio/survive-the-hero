extends RefCounted
## Mutaciones del creep: cada vez que sube de nivel elige 1 de 3.
## "max" es cuántas veces se puede tomar la misma; "min_stage" desde qué etapa aparece.
## Las evoluciones ("weapon" al máximo + "passive" con al menos 1 rango) se toman
## una sola vez y, cuando están disponibles, vienen garantizadas en la próxima elección.
## "filler" (Festín) no tiene máximo y solo aparece si no alcanzan las opciones.

const LIST := {
	"colmillos": {"name": "Colmillos", "desc": "+12,5% daño de mordida y escupitajo", "max": 10},
	"patas": {"name": "Patas ágiles", "desc": "+5% velocidad", "max": 8},
	"caparazon": {"name": "Caparazón", "desc": "+12,5% vida máxima y te cura", "max": 10},
	"glandula": {"name": "Glándula ácida", "desc": "Escupís 10% más seguido", "max": 8},
	"doble": {"name": "Escupitajo múltiple", "desc": "+1 escupitajo por disparo", "max": 2},
	"iman": {"name": "Imán de carne", "desc": "Los cadáveres cercanos vuelan hacia vos (+30 de radio)", "max": 6},
	"frenesi": {"name": "Frenesí", "desc": "Comer seguido arma un combo que multiplica la biomasa", "max": 2},
	"rey": {"name": "Rey de la horda", "desc": "Los compañeros cerca tuyo van más rápido y pegan más (cada rango agranda el aura)", "max": 6, "min_stage": 1},
	"vampiro": {"name": "Mordida vampírica", "desc": "La mordida te cura un 10% del daño", "max": 4},
	# Relleno: solo aparece si no alcanzan las opciones (todo al máximo)
	"festin": {"name": "Festín", "desc": "Te cura 30% y +5% de daño", "max": 0, "filler": true},
	# Evoluciones
	"lluvia": {"name": "Lluvia ácida", "desc": "Cada escupitajo deja un charco que quema y frena al héroe", "max": 1,
		"weapon": "doble", "passive": "glandula"},
	"mandibula": {"name": "Mandíbula sangrienta", "desc": "La mordida cura 35%, llega más lejos y hace sangrar al héroe", "max": 1,
		"weapon": "colmillos", "passive": "vampiro"},
	"carronia": {"name": "Señor de la carroña", "desc": "Los compañeros que mueren cerca tuyo se levantan 8 s como zombis", "max": 1,
		"weapon": "rey", "passive": "iman"},
	"coraza": {"name": "Coraza viva", "desc": "Al terminar la embestida sale una onda que daña, empuja y aturde al héroe", "max": 1,
		"weapon": "caparazon", "passive": "patas"},
}


static func is_evolution(id: String) -> bool:
	return LIST[id].has("weapon")


## Descripción con la pista de evolución ("Evoluciona con ...") si forma parte de una receta.
static func desc(id: String) -> String:
	var text: String = LIST[id].desc
	for evo in LIST:
		if not is_evolution(evo):
			continue
		if LIST[evo].weapon == id:
			text += "\nEvoluciona con %s" % LIST[LIST[evo].passive].name
		elif LIST[evo].passive == id:
			text += "\nEvoluciona con %s" % LIST[LIST[evo].weapon].name
	return text


static func available_evolutions(ranks: Dictionary) -> Array:
	var out: Array = []
	for id in LIST:
		if not is_evolution(id) or ranks.get(id, 0) > 0:
			continue
		var w: String = LIST[id].weapon
		if ranks.get(w, 0) >= LIST[w].max and ranks.get(LIST[id].passive, 0) >= 1:
			out.append(id)
	return out


static func roll(ranks: Dictionary, stage: int, rng: RandomNumberGenerator, count: int = 3) -> Array:
	var out: Array = []
	var evos := available_evolutions(ranks)
	if not evos.is_empty():
		out.append(evos[rng.randi_range(0, evos.size() - 1)])
	var pool: Array = []
	for id in LIST:
		if is_evolution(id) or LIST[id].get("filler", false):
			continue
		if ranks.get(id, 0) < LIST[id].max and stage >= LIST[id].get("min_stage", 0):
			pool.append(id)
	while out.size() < count and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	if out.size() < count:
		out.append("festin")
	return out
