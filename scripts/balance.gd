extends RefCounted
## Todos los números de balance en un solo lugar.
## Se ajustan acá mientras jugamos, sin tocar la lógica.

const MATCH_SECONDS := 15.0 * 60.0
const FORCED_DETECTION_SECONDS := 10.0 * 60.0
const ARENA_SIZE := Vector2(3000, 3000)

# --- Creep (jugador) ---------------------------------------------------------
# Cada etapa reemplaza los stats de la anterior. "cost" es la biomasa necesaria
# para pasar a la siguiente etapa (-1 = etapa final).
const CREEP_STAGES := [
	{"name": "Slime", "hp": 30.0, "speed": 170.0, "bite": 4.0, "radius": 10.0, "cost": 60.0, "color": Color(0.45, 0.85, 0.35)},
	{"name": "Esqueleto", "hp": 75.0, "speed": 180.0, "bite": 10.0, "radius": 13.0, "cost": 220.0, "color": Color(0.9, 0.88, 0.75)},
	{"name": "Cultista", "hp": 190.0, "speed": 190.0, "bite": 25.0, "radius": 17.0, "cost": 550.0, "color": Color(0.6, 0.35, 0.8)},
	{"name": "Demonio", "hp": 470.0, "speed": 200.0, "bite": 62.0, "radius": 23.0, "cost": -1.0, "color": Color(0.9, 0.2, 0.15)},
]
const BITE_COOLDOWN := 0.6
const BITE_RANGE := 26.0 # se suma a los radios del creep y del héroe
const DASH_SPEED := 650.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 2.5
const DASH_HIT_MULT := 1.5 # daño de la embestida = mordida * esto
const SPIT_DAMAGE_MULT := 0.4 # daño del escupitajo = mordida * esto
const SPIT_COOLDOWN := 1.2
const SPIT_SPEED := 420.0
const SPIT_RANGE := 380.0
const HEAL_PER_BIOMASS := 2.0
# Mutaciones: la biomasa también llena una barra de nivel; al subir elegís 1 de 3.
static func mutation_xp_for_level(level: int) -> float:
	return 15.0 + level * 15.0

const MUT_DAMAGE := 0.25
const MUT_SPEED := 0.10
const MUT_HP := 0.25
const MUT_SPIT_RATE := 0.20
const MUT_VAMPIRE := 0.20
const MAGNET_RADIUS_PER_RANK := 60.0
const MAGNET_PULL_SPEED := 350.0
const COMBO_WINDOW := 1.5 # segundos entre bocados para mantener el combo
const COMBO_WINDOW_PER_RANK := 0.75
const COMBO_STEP := 0.15 # cada bocado en combo suma esto al multiplicador
const COMBO_MAX := 2.5

# Liderazgo: los compañeros cerca tuyo se potencian.
const LEAD_RADIUS := 170.0
const LEAD_RADIUS_PER_RANK := 50.0
const LEAD_SPEED_MULT := 1.4
const LEAD_DAMAGE_MULT := 2.0
const LEAD_DAMAGE_PER_RANK := 0.5

# Civiles: comida que huye de vos, lejos del héroe.
const CIVILIANS_START := 14
const CIVILIANS_MAX := 24
const CIVILIAN_RESPAWN := 6.0
const CIVILIAN_HP := 8.0
const CIVILIAN_SPEED := 115.0
const CIVILIAN_FLEE_RADIUS := 220.0
const CIVILIAN_BIOMASS := 4.0
const GEM_BIOMASS := 0.5

# --- Amenaza y detección -----------------------------------------------------
const DETECTION_THRESHOLD := 100.0
const THREAT_PER_DAMAGE := 0.5
const THREAT_PER_STOLEN_GEM := 3.0
const STEAL_RADIUS := 300.0 # robar una gema cerca del héroe suma amenaza
const THREAT_PER_STAGE := 20.0

# --- Héroe -------------------------------------------------------------------
const HERO_HP := 400.0
const HERO_HP_PER_LEVEL := 20.0
const HERO_LEVEL_HEAL := 0.25 # al subir de nivel recupera este % de su vida máxima (no tiene regeneración)
const HERO_SPEED := 150.0
const HERO_RADIUS := 14.0
const HERO_ARROW_DAMAGE := 16.0
const HERO_ARROW_COOLDOWN := 0.45
const HERO_ARROW_SPEED := 520.0
const HERO_RANGE := 420.0
const HERO_PICKUP_RADIUS := 100.0
const HERO_PICKUP_PER_LEVEL := 2.0
const HERO_DAMAGE_PER_LEVEL := 1.07
const HERO_COOLDOWN_PER_LEVEL := 0.97
const HERO_MIN_COOLDOWN := 0.18
const HERO_LEVELS_PER_EXTRA_ARROW := 6
const HERO_ARROW_PIERCE := 1 # enemigos extra que atraviesa cada flecha
const HERO_LEVELS_PER_PIERCE := 6
# Tajo de espada: ataque cuerpo a cuerpo en arco, con aviso previo para poder esquivarlo.
# Apagado por ahora: los poderes extra del héroe se definen cuando el creep
# tenga habilidades para contrarrestarlos.
const HERO_SLASH_ENABLED := false
const HERO_SLASH_LEVEL := 3
const HERO_SLASH_COOLDOWN := 1.4
const HERO_SLASH_WINDUP := 0.25
const HERO_SLASH_RADIUS := 75.0
const HERO_SLASH_RADIUS_PER_LEVEL := 1.0
const HERO_SLASH_ARC_DEG := 130.0
const HERO_SLASH_DAMAGE_MULT := 1.5 # daño del tajo = daño de flecha * esto
# Esquivar proyectiles del jugador
const HERO_DODGE_CHANCE := 0.6
const HERO_DODGE_LOOKAHEAD := 260.0
const HERO_REACTION_MIN := 0.15
const HERO_REACTION_MAX := 0.3
const HERO_AIM_ERROR_DEG := 6.0
const HERO_RETREAT_HP := 0.3
const HERO_MISTAKE_CHANCE := 0.06
const HERO_DETECTED_TARGET_BONUS := 400.0
const HERO_ENRAGE_DAMAGE_MULT := 5.0
const HERO_ENRAGE_SPEED_MULT := 1.3


static func xp_for_level(level: int) -> float:
	return 10.0 + level * 20.0


# --- Horda -------------------------------------------------------------------
const MINION_TYPES := {
	"rata": {"hp": 6.0, "speed": 120.0, "dps": 4.0, "radius": 7.0, "xp": 1.0, "biomass": 0.4, "color": Color(0.6, 0.5, 0.4)},
	"zombi": {"hp": 16.0, "speed": 80.0, "dps": 7.0, "radius": 10.0, "xp": 2.0, "biomass": 0.8, "color": Color(0.4, 0.6, 0.45)},
	"arquero": {"hp": 10.0, "speed": 70.0, "dps": 0.0, "radius": 9.0, "xp": 2.0, "biomass": 0.8, "color": Color(0.55, 0.4, 0.75),
		"range": 260.0, "shot_cooldown": 2.2, "shot_damage": 4.0},
	"bruto": {"hp": 60.0, "speed": 60.0, "dps": 14.0, "radius": 16.0, "xp": 5.0, "biomass": 2.5, "color": Color(0.6, 0.3, 0.3)},
}
const MAX_MINIONS := 300
const CORPSE_LIFETIME := 20.0
const GEM_LIFETIME := 30.0
const SPAWN_MIN_DIST := 650.0
const SPAWN_MAX_DIST := 900.0


static func minion_hp_mult(minute: float) -> float:
	return 1.0 + minute * 0.25


static func spawns_per_second(minute: float) -> float:
	return 2.0 + minute * 1.2


static func pick_minion_type(minute: float, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if minute > 3.0 and r < minf(0.05 + minute * 0.02, 0.25):
		return "bruto"
	if minute > 1.0 and r < 0.4 and r >= 0.25:
		return "arquero"
	if r < 0.55:
		return "rata"
	return "zombi"
