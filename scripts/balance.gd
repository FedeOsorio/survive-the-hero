extends RefCounted
## Todos los números de balance en un solo lugar.
## Se ajustan acá mientras jugamos, sin tocar la lógica.

# Sin reloj fijo: la partida dura lo que vos decidas. El héroe escala con sus
# niveles y te detecta solo por amenaza.
const ARENA_SIZE := Vector2(3000, 3000)

# --- Creep (jugador) ---------------------------------------------------------
# Cada etapa reemplaza los stats de la anterior. "cost" es la biomasa necesaria
# para pasar a la siguiente etapa (-1 = etapa final).
const CREEP_STAGES := [
	{"name": "Slime", "hp": 30.0, "speed": 170.0, "bite": 6.0, "radius": 10.0, "cost": 60.0, "color": Color(0.45, 0.85, 0.35)},
	{"name": "Esqueleto", "hp": 75.0, "speed": 180.0, "bite": 15.0, "radius": 13.0, "cost": 280.0, "color": Color(0.9, 0.88, 0.75)},
	{"name": "Cultista", "hp": 190.0, "speed": 190.0, "bite": 38.0, "radius": 17.0, "cost": 800.0, "color": Color(0.6, 0.35, 0.8)},
	{"name": "Demonio", "hp": 470.0, "speed": 200.0, "bite": 90.0, "radius": 23.0, "cost": -1.0, "color": Color(0.9, 0.2, 0.15)},
]
const BITE_COOLDOWN := 0.6
const BITE_RANGE := 26.0 # se suma a los radios del creep y del héroe
const DASH_SPEED := 650.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 2.5
const DASH_HIT_MULT := 1.5 # daño de la embestida = mordida * esto
const SPIT_DAMAGE_MULT := 0.8 # daño del escupitajo = mordida * esto
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

# Liderazgo (solo con la mutación Rey de la horda): los compañeros cerca tuyo se potencian.
const LEAD_RADIUS := 140.0
const LEAD_RADIUS_PER_RANK := 40.0
const LEAD_SPEED_MULT := 1.4
const LEAD_DAMAGE_MULT := 1.5
const LEAD_DAMAGE_PER_RANK := 0.25

# Civiles: comida que huye de vos, lejos del héroe.
const CIVILIANS_START := 24
const CIVILIANS_MAX := 40
const CIVILIAN_RESPAWN := 3.0
const CIVILIAN_HP := 8.0
const CIVILIAN_SPEED := 85.0
const CIVILIAN_FLEE_RADIUS := 220.0
const CIVILIAN_BIOMASS := 4.0
# Comer civiles hace ruido: suma amenaza y el héroe va a investigar el lugar.
const THREAT_PER_CIVILIAN := 5.0
# El grito empieza apenas un civil sale corriendo de vos, no cuando muere.
const ALARM_TIME := 10.0 # segundos que el héroe busca en el lugar del grito
const ALARM_PULL := 3.0 # qué tanto le importa ir a investigar (las gemas pesan 2.2)
const CIVILIAN_SCREAM_COOLDOWN := 3.0 # cada civil grita como mucho cada tantos segundos
# El héroe también mata civiles para dejarte sin comida: los que mata él no dejan cadáver.
const HERO_CIVILIAN_TARGET_BONUS := 120.0 # durante la alarma, prefiere civiles a la horda

# Camuflaje (Q): te saca del radar del héroe. Una vez por minuto.
const STEALTH_COOLDOWN := 60.0
const STEALTH_TIME := 4.0 # segundos en que el héroe no te puede apuntar
const STEALTH_THREAT_LEFT := 0.4 # la amenaza queda en este % del umbral

# --- Amenaza y detección -----------------------------------------------------
const DETECTION_THRESHOLD := 150.0
const THREAT_PER_DAMAGE := 0.15
const THREAT_PER_STOLEN_GEM := 3.0
const STEAL_RADIUS := 300.0 # pisar una gema cerca del héroe suma amenaza
const THREAT_PER_STAGE := 20.0
const THREAT_PASSIVE_PER_STAGE := 0.15 # por segundo y por etapa: crecer te vuelve visible

# Hambre: si vas atrás del héroe, cada bocado rinde más.
# Tu poder = nivel + 3 x etapa; por cada nivel del héroe por encima, +12% de biomasa.
const HUNGER_PER_LEVEL := 0.12
const HUNGER_MAX := 3.0

# Élites: cada tanto aparece un creep dorado. Cuando el héroe lo mata deja un
# corazón; si lo comés, ganás una mutación al instante (y amenaza si estás cerca).
const ELITE_EVERY := 45.0
const ELITE_HP_MULT := 8.0
const ELITE_HEART_BIOMASS := 10.0
# Si el héroe agarra el corazón primero: sube un nivel y se cura este %.
const ELITE_HEART_HERO_HEAL := 0.3
const HERO_HEART_PULL := 2.8 # prioridad de ir a buscar un corazón (más que las gemas)
const HERO_HEART_SEEK_RADIUS := 700.0

# --- Héroe -------------------------------------------------------------------
const HERO_HP := 200.0
const HERO_HP_PER_LEVEL := 30.0
const HERO_LEVEL_HEAL := 0.25 # al subir de nivel recupera este % de su vida máxima (no tiene regeneración)
const HERO_SPEED := 150.0
const HERO_RADIUS := 14.0
const HERO_ARROW_DAMAGE := 16.0
const HERO_ARROW_COOLDOWN := 0.45
const HERO_ARROW_SPEED := 520.0
const HERO_RANGE := 420.0
# El héroe sube de nivel SOLO juntando gemas: tiene que caminar hasta ellas.
const HERO_PICKUP_RADIUS := 35.0
const HERO_PICKUP_PER_LEVEL := 1.0
const GEM_SCATTER := 30.0 # las gemas saltan un poco al caer, lejos del cadáver
const HERO_DAMAGE_PER_LEVEL := 1.10
const HERO_COOLDOWN_PER_LEVEL := 0.95
const HERO_MIN_COOLDOWN := 0.18
const HERO_LEVELS_PER_EXTRA_ARROW := 4
# Las flechas no atraviesan: eso será una mejora que el héroe elija (hito 2).
const HERO_ARROW_PIERCE := 0
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
# Rodada: el héroe esquiva tus escupitajos rodando (invulnerable mientras rueda).
# Con la rodada en cooldown no puede esquivar: ese es el momento de castigarlo.
const HERO_DODGE_CHANCE := 0.55
const HERO_DODGE_MIN_DAMAGE := 0.04 # sin detectarte, solo rueda si el escupitajo le saca al menos este % de vida
const HERO_ROLL_SPEED := 520.0
const HERO_ROLL_TIME := 0.25
const HERO_ROLL_COOLDOWN := 3.0
# Aviso de disparo: con el jugador detectado, apunta (línea de mira) antes de tirarle.
const HERO_AIM_WINDUP := 0.35
const HERO_DODGE_LOOKAHEAD := 260.0
const HERO_REACTION_MIN := 0.15
const HERO_REACTION_MAX := 0.3
const HERO_AIM_ERROR_DEG := 6.0
const HERO_RETREAT_HP := 0.3
const HERO_MISTAKE_CHANCE := 0.06
const HERO_DETECTED_TARGET_BONUS := 150.0 # chico: si tiene creeps encima, se defiende primero
const HERO_ENRAGE_DAMAGE_MULT := 5.0
const HERO_ENRAGE_SPEED_MULT := 1.3

# Poderes del héroe: en cada nivel elige 1 de 3 (nuevo o mejora), hasta 5 distintos.
# Como en Vampire Survivors: rango 1 es débil y cada rango lo mejora bastante.
# Daño = base + por_rango x (rango - 1). No depende del daño de flecha.
const HERO_MAX_POWERS := 5
const HERO_POWER_CHOICES := 3
# Orbes de fuego: giran alrededor del héroe y queman lo que tocan.
const ORB_DAMAGE := 3.0
const ORB_DAMAGE_PER_RANK := 3.0
const ORB_RADIUS := 9.0
const ORB_ORBIT := 56.0
const ORB_ORBIT_PER_RANK := 6.0
const ORB_SPIN := 3.0 # radianes por segundo
const ORB_HIT_COOLDOWN := 0.5 # cada orbe le pega al mismo blanco como mucho cada tanto
# Rayo: cada tanto marca círculos en el piso y después cae el rayo (se puede esquivar).
const BOLT_DAMAGE := 6.0
const BOLT_DAMAGE_PER_RANK := 6.0
const BOLT_COOLDOWN := 3.5
const BOLT_COOLDOWN_PER_RANK := 0.3
const BOLT_RANGE := 450.0
const BOLT_RADIUS := 32.0
const BOLT_WARNING := 0.55
# Aura sagrada: daño constante alrededor del héroe.
const AURA_DPS := 2.0
const AURA_DPS_PER_RANK := 2.5
const AURA_RADIUS := 45.0
const AURA_RADIUS_PER_RANK := 12.0
# Nova: explosión alrededor del héroe que empuja a la horda, con aviso previo.
const NOVA_DAMAGE := 6.0
const NOVA_DAMAGE_PER_RANK := 7.0
const NOVA_COOLDOWN := 7.0
const NOVA_COOLDOWN_PER_RANK := 0.6
const NOVA_RADIUS := 95.0
const NOVA_RADIUS_PER_RANK := 15.0
const NOVA_WARNING := 0.4
const NOVA_PUSH := 70.0
# Pasivos
const POWER_SPEED := 0.08 # botas: +8% velocidad por rango


static func xp_for_level(level: int) -> float:
	return 5.0 + level * 8.0


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


# La horda mejora por escalones: uno cada HORDE_TIER_MINUTES.
const HORDE_TIER_MINUTES := 2.0


static func horde_tier(minute: float) -> float:
	return floorf(minute / HORDE_TIER_MINUTES)


static func minion_hp_mult(minute: float) -> float:
	return 1.0 + horde_tier(minute) * 0.3


# Como en Vampire Survivors, tus compañeros se vuelven más fuertes con cada escalón.
static func minion_dps_mult(minute: float) -> float:
	return 1.0 + horde_tier(minute) * 0.15


static func minion_speed_mult(minute: float) -> float:
	return minf(1.0 + horde_tier(minute) * 0.04, 1.4)


static func spawns_per_second(minute: float) -> float:
	return 2.0 + minute * 1.2


static func pick_minion_type(minute: float, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if minute > 2.0 and r < minf(0.05 + minute * 0.025, 0.3):
		return "bruto"
	if minute > 1.0 and r < 0.4 and r >= 0.25:
		return "arquero"
	if r < 0.55:
		return "rata"
	return "zombi"
