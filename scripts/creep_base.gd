extends Node2D
## Base del creep (el Anti Hero): todas las variables y las consultas chicas
## (etapa, rangos, stats, hambre). creep_growth.gd la extiende con comer y mutar,
## y creep.gd con moverse, atacar y dibujarse; esa es la que se instancia.

const B := preload("res://scripts/balance.gd")
const Mutations := preload("res://scripts/mutations.gd")
const CreepBot := preload("res://scripts/creep_bot.gd")
const CreepAbilities := preload("res://scripts/creep_abilities.gd")
const CreepClass := preload("res://scripts/creep_class.gd")

var world
var invulnerable := false
var stage := 0
var hp := 1.0
var max_hp := 1.0
var speed := 100.0
var bite := 1.0
var radius := 10.0
var color := Color.WHITE
var biomass := 0.0 # se gasta al evolucionar

# Mutaciones
var level := 1
var mut_xp := 0.0
var ranks := {}
var pending_choices: Array = [] # no vacío = esperando que el jugador elija
var _queued_levels := 0

var combo := 1.0
var _combo_t := 0.0

var _facing := Vector2.RIGHT
var _bite_cd := 0.0
var _bite_fx := 0.0
var _bite_dir := Vector2.RIGHT
var _dash_cd := 0.0
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dash_hit := false
var _flash := 0.0
var stealth_cd := 0.0
var stealth_t := 0.0 # mientras dura, el héroe no te puede apuntar
var root_t := 0.0 # trampa del Arquero: no te podés mover
var slow_t := 0.0 # Hielo de la Maga: caminás más lento
var _slow := 0.0
var _dash_victims: Array = []
var _rng := RandomNumberGenerator.new()
var abilities # creep_abilities.gd: habilidades por etapa y mutaciones de arma
var klass # creep_class.gd: la clase elegida en el menú (Engendro, Abisal, Reina)


func stage_name() -> String:
	return B.CREEP_STAGES[stage].name


func evolve_cost() -> float:
	return B.CREEP_STAGES[stage].cost


func can_evolve() -> bool:
	var cost := evolve_cost()
	return cost > 0.0 and biomass >= cost


## Hielo de la Maga: "amount" más lento estos segundos.
func slow(amount: float, time: float) -> void:
	_slow = amount
	slow_t = maxf(slow_t, time)


## Trampa del Arquero: inmovilizado (sin caminar ni embestir) estos segundos.
func root(time: float) -> void:
	root_t = maxf(root_t, time)


func rank(id: String) -> int:
	return ranks.get(id, 0)


func dashing() -> bool:
	return _dash_t > 0.0


func facing() -> Vector2:
	return _facing


# --- Stats derivados (etapa x mutaciones) ------------------------------------


func _apply_stage(s: int) -> void:
	stage = s
	color = B.CREEP_STAGES[s].color
	radius = B.CREEP_STAGES[s].radius
	_recalc_stats()
	hp = max_hp


func _recalc_stats() -> void:
	var d: Dictionary = B.CREEP_STAGES[stage]
	var ratio := hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = d.hp * klass.hp_mult() * (1.0 + rank("caparazon") * B.MUT_HP)
	hp = max_hp * ratio
	speed = d.speed * (1.0 + rank("patas") * B.MUT_SPEED)
	bite = d.bite * (1.0 + rank("colmillos") * B.MUT_DAMAGE + rank("festin") * B.FEAST_DAMAGE)


func bite_range() -> float:
	return B.BITE_RANGE + (B.JAW_BITE_RANGE if rank("mandibula") > 0 else 0.0)


## Poderes (S8): efecto x1,2 y recarga x0,92 por cada rango arriba del 1.
func pmult(id: String) -> float:
	return 1.0 + B.POWER_RANK_EFFECT * maxi(rank(id) - 1, 0)


func pcd(id: String) -> float:
	return pow(1.0 - B.POWER_RANK_COOLDOWN, maxi(rank(id) - 1, 0))


func magnet_radius() -> float:
	return rank("iman") * B.MAGNET_RADIUS_PER_RANK


func lead_radius() -> float:
	if rank("rey") == 0:
		return 0.0
	return B.LEAD_RADIUS + (rank("rey") - 1) * B.LEAD_RADIUS_PER_RANK


func lead_damage_mult() -> float:
	return B.LEAD_DAMAGE_MULT + (rank("rey") - 1) * B.LEAD_DAMAGE_PER_RANK


## Multiplicador de biomasa cuando vas atrás del héroe.
func hunger() -> float:
	var hero = world.hero
	if hero == null:
		return 1.0
	var gap: int = hero.level - (power_level() + 3 * stage)
	return clampf(1.0 + gap * B.HUNGER_PER_LEVEL, 1.0, B.HUNGER_MAX)


## Nivel equivalente para medir tu fuerza contra los héroes (subís muchos más niveles que ellos).
func power_level() -> int:
	return roundi(level * B.CREEP_LEVEL_EQUIV)


func mut_xp_needed() -> float:
	return B.mutation_xp_for_level(level)


# --- Loop ---------------------------------------------------------------------
