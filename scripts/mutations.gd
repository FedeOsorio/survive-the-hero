extends RefCounted
## Mutaciones del creep: cada vez que sube de nivel elige 1 de 3.
## "max" es cuántas veces se puede tomar la misma; "min_stage" desde qué etapa aparece.

const LIST := {
	"colmillos": {"name": "Colmillos", "desc": "+25% daño de mordida y escupitajo", "max": 5},
	"patas": {"name": "Patas ágiles", "desc": "+10% velocidad", "max": 4},
	"caparazon": {"name": "Caparazón", "desc": "+25% vida máxima y te cura", "max": 5},
	"glandula": {"name": "Glándula ácida", "desc": "Escupís 20% más seguido", "max": 4},
	"doble": {"name": "Escupitajo múltiple", "desc": "+1 escupitajo por disparo", "max": 2},
	"iman": {"name": "Imán de carne", "desc": "Los cadáveres cercanos vuelan hacia vos", "max": 3},
	"frenesi": {"name": "Frenesí", "desc": "Comer seguido arma un combo que multiplica la biomasa", "max": 2},
	"rey": {"name": "Rey de la horda", "desc": "Tu aura de liderazgo es más grande y más fuerte", "max": 3, "min_stage": 1},
	"vampiro": {"name": "Mordida vampírica", "desc": "La mordida te cura un 20% del daño", "max": 2},
}


static func roll(ranks: Dictionary, stage: int, rng: RandomNumberGenerator, count: int = 3) -> Array:
	var pool: Array = []
	for id in LIST:
		if ranks.get(id, 0) < LIST[id].max and stage >= LIST[id].get("min_stage", 0):
			pool.append(id)
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out
