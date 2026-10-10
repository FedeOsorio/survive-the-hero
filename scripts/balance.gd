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
	return 10.0 + level * 5.0

# Rinden la mitad por rango y se toman el doble de veces que antes (máximos en mutations.gd).
const MUT_DAMAGE := 0.125
const MUT_SPEED := 0.05
const MUT_HP := 0.125
const MUT_SPIT_RATE := 0.10
const MUT_VAMPIRE := 0.10
const FEAST_HEAL := 0.3 # Festín (relleno cuando todo está al máximo): cura y daño, sin máximo
const FEAST_DAMAGE := 0.05
# Nivel equivalente del creep (redondear(nivel × esto)) para medir su fuerza contra los
# héroes: nivel de llegada y hambre. La tabla y el HUD siguen mostrando el nivel real.
const CREEP_LEVEL_EQUIV := 0.6
const MAGNET_RADIUS_PER_RANK := 30.0
const MAGNET_PULL_SPEED := 350.0
const COMBO_WINDOW := 1.5 # segundos entre bocados para mantener el combo
const COMBO_WINDOW_PER_RANK := 0.75
const COMBO_STEP := 0.15 # cada bocado en combo suma esto al multiplicador
const COMBO_MAX := 2.5

# Liderazgo (solo con la mutación Rey de la horda): los compañeros cerca tuyo se potencian.
const LEAD_RADIUS := 140.0
const LEAD_RADIUS_PER_RANK := 20.0
const LEAD_SPEED_MULT := 1.4
const LEAD_DAMAGE_MULT := 1.5
const LEAD_DAMAGE_PER_RANK := 0.125

# Civiles: comida que huye de vos, lejos del héroe.
const CIVILIANS_START := 20
const CIVILIANS_MAX := 30
const CIVILIAN_RESPAWN := 3.0 # cada tanto aparece un caserío
# Aparecen en grupos, en un anillo alrededor del creep y lejos del héroe.
const CIVILIAN_GROUP_MIN := 2
const CIVILIAN_GROUP_MAX := 4
const CIVILIAN_GROUP_SPREAD := 40.0
const CIVILIAN_RING_MIN := 350.0 # del creep
const CIVILIAN_RING_MAX := 800.0
const CIVILIAN_MIN_HERO_DIST := 300.0
# Esquivan a la horda (solo visual: la horda no los daña).
const CIVILIAN_DODGE_RADIUS := 40.0
const CIVILIAN_DODGE_SPEED := 0.6
const CIVILIAN_HP := 8.0
const CIVILIAN_SPEED := 85.0
const CIVILIAN_FLEE_RADIUS := 220.0
const CIVILIAN_BIOMASS := 12.0
# Comer civiles hace ruido: el héroe va a investigar el lugar.
# El grito empieza apenas un civil sale corriendo de vos, no cuando muere.
# Cada grito nuevo actualiza el lugar. La alarma dura hasta que llega (a ALARM_ARRIVE_DIST)
# y ALARM_SEARCH_TIME más buscando, con un máximo de ALARM_MAX_TIME desde el último grito.
const ALARM_PULL := 4.0 # más que cofres (3,0), corazones (2,8) y gemas (2,2)
const ALARM_ARRIVE_DIST := 80.0
const ALARM_SEARCH_TIME := 3.0
const ALARM_MAX_TIME := 12.0
const CIVILIAN_SCREAM_COOLDOWN := 3.0 # cada civil grita como mucho cada tantos segundos

# Camuflaje (Q): corta la cacería al instante (el héroe pasa a buscarte). Una vez por minuto.
const STEALTH_COOLDOWN := 60.0
const STEALTH_TIME := 4.0 # segundos en que el héroe no te puede apuntar

# --- Te ve, te caza ----------------------------------------------------------
# Cada héroe te caza si estás a menos de HERO_RANGE y sin camuflaje. A más de
# HUNT_LOSE_DIST (o camuflado) va HUNT_SEARCH_TIME a tu última posición y vuelve a farmear.
const HUNT_LOSE_DIST := 520.0
const HUNT_SEARCH_TIME := 5.0
const HUNT_SEARCH_PULL := 3.0
const HUNT_SEEN_BANNER_EVERY := 10.0 # "¡El Arquero te vio!" como mucho cada tantos segundos
const GEM_BIOMASS := 0.5 # pisar una gema te alimenta: biomasa por punto de XP (el imán no las atrae)
const GEM_EAT_RANGE := 12.0 # se suma a tu radio

# Hambre: si vas atrás del héroe, cada bocado rinde más.
# Tu poder = nivel + 3 x etapa; por cada nivel del héroe por encima, +12% de biomasa.
const HUNGER_PER_LEVEL := 0.12
const HUNGER_MAX := 3.0

# Élites: cada tanto aparece un creep dorado. Cuando el héroe lo mata deja un
# corazón; si lo comés, ganás una mutación al instante.
const ELITE_EVERY := 45.0
const ELITE_HP_MULT := 8.0
const ELITE_HEART_BIOMASS := 10.0
# Si el héroe agarra el corazón primero: sube un nivel y se cura este %.
const ELITE_HEART_HERO_HEAL := 0.3
const HERO_HEART_PULL := 2.8 # prioridad de ir a buscar un corazón (más que las gemas)
const HERO_HEART_SEEK_RADIUS := 700.0

# --- Héroe -------------------------------------------------------------------
const HERO_HP := 320.0
const HERO_HP_PER_LEVEL := 40.0
const HERO_LEVEL_HEAL := 0.3 # al subir de nivel recupera este % de su vida máxima (no tiene regeneración)
const HERO_SPEED := 150.0
const HERO_RADIUS := 14.0
const HERO_ARROW_DAMAGE := 20.0
const HERO_ARROW_COOLDOWN := 0.45
const HERO_ARROW_SPEED := 520.0
const HERO_RANGE := 420.0
# El héroe sube de nivel SOLO juntando gemas: tiene que caminar hasta ellas.
const HERO_PICKUP_RADIUS := 40.0 # las gemas dentro de este radio vuelan hacia él
const HERO_PICKUP_PER_LEVEL := 1.0
const HERO_GEM_PULL_SPEED := 350.0
const HERO_HEART_PICKUP := 35.0 # los corazones de élite los tiene que pisar (más el radio del corazón)
const HERO_HEART_PICKUP_PER_LEVEL := 1.0
const GEM_SCATTER := 30.0 # las gemas saltan un poco al caer, lejos del cadáver
const HERO_DAMAGE_PER_LEVEL := 1.10
const HERO_COOLDOWN_PER_LEVEL := 0.95
const HERO_MIN_COOLDOWN := 0.18
const HERO_LEVELS_PER_EXTRA_ARROW := 4
# Cada flecha atraviesa a este número de enemigos extra (Flechas perforantes suma más).
const HERO_ARROW_PIERCE := 1
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
# Cacería: con el jugador detectado, el héroe va por vos.
const HUNT_PULL := 3.0
const HUNT_PULL_CROWDED := 1.5 # con mucha horda encima
const HUNT_CROWDED_DANGER := 3.0
const HUNT_IDEAL_DIST := 220.0
const HUNT_GEM_RADIUS := 200.0 # mientras caza, solo junta los montones cercanos
const HUNT_GEM_PULL := 1.2
# Gemas: va al montón que más vale (XP a HERO_GEM_CLUSTER_RADIUS / (distancia + HERO_GEM_DIST_BIAS)).
const HERO_GEM_CLUSTER_RADIUS := 100.0
const HERO_GEM_DIST_BIAS := 150.0
const HERO_GEM_SEEK_RADIUS := 600.0 # libre
const HERO_GEM_PULL := 2.6 # libre, sin peligro
const HERO_GEM_PULL_DANGER := 1.6 # libre, con horda encima
const HERO_GEM_DANGER := 3.0 # libre: con este peligro o más usa HERO_GEM_PULL_DANGER
const ALARM_GEM_RADIUS := 300.0 # yendo a un grito
const ALARM_GEM_PULL := 1.8
const HUNT_ESCAPE_RADIUS := 80.0 # con tantos creeps así de cerca, primero zafa
const HUNT_ESCAPE_COUNT := 2
const HUNT_SHARE_RADIUS := 150.0 # con creeps así de cerca, alterna un disparo a vos y uno a la horda

# Tres héroes en 15 minutos: llegan a horario fijo, haya muerto o no el anterior.
# Ganás matando a los tres. "hp", "speed" y "damage" multiplican la vida, la velocidad
# y el daño de las flechas; "powers" son los poderes con los que llega (rango 1).
# "level_bonus": llega en máx(nivel más alto de los héroes anteriores, tu nivel) + esto.
# "table": +1 rango del poder de cada nivel (índice 0 = nivel 2, hasta el 20; después solo stats).
# Al llegar se aplican en silencio todas las filas hasta su nivel de llegada.
const MATCH_MINUTES := 15.0 # amanece: los héroes vivos escapan y termina la partida
const HERO_ESCAPE_TIME := 2.0 # suben en una columna de luz; todo lo demás queda quieto
const HORDE_IDLE_DIST := 120.0 # sin héroes vivos, la horda te sigue a esta distancia
const HERO_ARRIVAL_WARNING := 5.0 # banner y portal antes de que llegue
const HERO_NEXT_AFTER_KILL := 60.0 # si matás a uno, el siguiente llega a más tardar en estos segundos
const HERO_ARRIVAL_WAVE_RADIUS := 300.0 # onda sagrada al llegar: mata a los menores, empuja a brutos y élites
const HERO_ARRIVAL_SHIELD := 3.0 # segundos invulnerable al llegar (brilla dorado)
const HERO_GEM_PILE_EVERY := 0.3 # cada cuánto recalcula el mejor montón de gemas
const HERO_GEM_PILE_LOOK := 40 # cuántas gemas cercanas mira para elegir montón
const HERO_PORTAL_MIN := 600.0 # distancia del portal a vos
const HERO_PORTAL_MAX := 900.0
const HEROES := [
	{"name": "Arquero", "article": "el", "minute": 0.0, "level": 1, "hp": 1.0, "speed": 1.0, "damage": 1.0,
		"powers": [], "color": Color(0.3, 0.55, 1.0),
		"table": ["perforante", "multiple", "botas", "rayo", "perforante", "multiple", "orbes", "rayo", "botas",
			"perforante", "multiple", "rayo", "orbes", "botas", "rayo", "orbes", "rayo", "orbes", "orbes"]},
	{"name": "Caballero", "article": "el", "minute": 5.0, "level_bonus": 2, "hp": 1.5, "speed": 0.9, "damage": 0.8,
		"powers": ["aura", "nova"], "color": Color(0.78, 0.8, 0.88),
		"table": ["aura", "orbes", "nova", "aura", "botas", "orbes", "rayo", "nova", "aura",
			"orbes", "botas", "nova", "rayo", "aura", "orbes", "nova", "botas", "rayo", "orbes"]},
	{"name": "Maga", "article": "la", "minute": 10.0, "level_bonus": 4, "hp": 0.8, "speed": 1.05, "damage": 1.15,
		"powers": ["rayo", "orbes"], "color": Color(0.72, 0.4, 0.95),
		"table": ["rayo", "orbes", "multiple", "rayo", "nova", "orbes", "aura", "rayo", "multiple",
			"nova", "orbes", "rayo", "aura", "nova", "multiple", "orbes", "nova", "aura", "nova"]},
]

# Poderes del héroe: cada nivel sube el de su fila en la tabla de su héroe (HEROES.table).
# Como en Vampire Survivors: rango 1 es débil y cada rango lo mejora bastante.
# Daño = base + por_rango x (rango - 1). No depende del daño de flecha.
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
	return 8.0 + level * 10.0 + 0.6 * level * level


# --- Horda -------------------------------------------------------------------
const MINION_TYPES := {
	"rata": {"hp": 6.0, "speed": 120.0, "dps": 4.0, "radius": 7.0, "xp": 1.0, "biomass": 0.8, "color": Color(0.6, 0.5, 0.4)},
	"zombi": {"hp": 16.0, "speed": 80.0, "dps": 7.0, "radius": 10.0, "xp": 2.0, "biomass": 1.5, "color": Color(0.4, 0.6, 0.45)},
	"arquero": {"hp": 10.0, "speed": 70.0, "dps": 0.0, "radius": 9.0, "xp": 2.0, "biomass": 1.5, "color": Color(0.55, 0.4, 0.75),
		"range": 260.0, "shot_cooldown": 2.2, "shot_damage": 4.0},
	"bruto": {"hp": 60.0, "speed": 60.0, "dps": 14.0, "radius": 16.0, "xp": 5.0, "biomass": 5.0, "color": Color(0.6, 0.3, 0.3)},
}
const MAX_MINIONS := 180
const MAX_MINIONS_NO_HERO := 60 # sin héroes vivos no aparecen más (los que están te siguen)
const MAX_GEMS := 150 # al pasarse, desaparece la más vieja
const MAX_CORPSES := 120 # al pasarse, desaparece el más viejo (los corazones no)
const CORPSE_LIFETIME := 20.0
const GEM_LIFETIME := 25.0
const SPAWN_MIN_DIST := 650.0
const SPAWN_MAX_DIST := 900.0


# La horda mejora por escalones: uno cada HORDE_TIER_MINUTES.
const HORDE_TIER_MINUTES := 2.0


static func horde_tier(minute: float) -> float:
	return floorf(minute / HORDE_TIER_MINUTES)


static func minion_hp_mult(minute: float) -> float:
	return 1.0 + horde_tier(minute) * 0.2


# Como en Vampire Survivors, tus compañeros se vuelven más fuertes con cada escalón.
static func minion_dps_mult(minute: float) -> float:
	return 1.0 + horde_tier(minute) * 0.15


static func minion_speed_mult(minute: float) -> float:
	return minf(1.0 + horde_tier(minute) * 0.04, 1.4)


static func spawns_per_second(minute: float) -> float:
	return 2.0 + minute * 0.9


static func pick_minion_type(minute: float, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if minute > 2.0 and r < minf(0.05 + minute * 0.025, 0.3):
		return "bruto"
	if minute > 1.0 and r < 0.4 and r >= 0.25:
		return "arquero"
	if r < 0.55:
		return "rata"
	return "zombi"


# --- Tanda 01 ------------------------------------------------------------------
# Evoluciones de mutaciones: arma al máximo + pasiva con al menos 1 rango.
# Lluvia ácida: cada escupitajo deja un charco que daña y frena al héroe.
const ACID_RADIUS := 40.0
const ACID_TIME := 3.0
const ACID_DPS_MULT := 0.5 # x mordida por segundo
const ACID_SLOW := 0.3
const ACID_MAX := 6
# Mandíbula sangrienta: la mordida cura y hace sangrar.
const JAW_HEAL := 0.35 # reemplaza a Mordida vampírica
const BLEED_MULT := 0.6 # x mordida, repartido en BLEED_TIME
const BLEED_TIME := 4.0
const BLEED_MAX_STACKS := 3
const JAW_BITE_RANGE := 10.0
# Señor de la carroña: compañeros que mueren cerca tuyo se levantan un rato.
const RAISE_RADIUS := 200.0
const RAISE_TIME := 8.0
const RAISE_MAX := 10
const RAISED_COLOR := Color(0.45, 0.9, 0.5)
# Coraza viva: al terminar la embestida sale una onda.
const SHELL_WAVE_RADIUS := 110.0
const SHELL_WAVE_DAMAGE := 1.0 # x mordida
const SHELL_WAVE_PUSH := 120.0
const SHELL_WAVE_MINION_PUSH := 60.0
const HERO_STUN_TIME := 0.8
const HERO_STUN_IMMUNE := 4.0

# Cofres en disputa: el héroe sube un nivel; vos ganás una mutación.
const CHEST_FIRST := 90.0
const CHEST_EVERY := 75.0
const CHEST_MIN_DIST := 400.0
const CHEST_MAX_DIST := 700.0
const CHEST_OPEN_RADIUS := 30.0
const CHEST_OPEN_TIME := 1.0
const CHEST_LIFETIME := 30.0
const CHEST_HERO_HEAL := 0.2
const CHEST_HERO_PULL := 3.0
const CHEST_HERO_SEEK_RADIUS := 900.0

# Eventos de oleada, en rotación: estampida, asedio, luna de sangre.
const EVENT_FIRST := 120.0
const EVENT_EVERY := 90.0
const EVENT_WARNING := 3.0
const STAMPEDE_COUNT := 40
const STAMPEDE_DIST := 700.0
const STAMPEDE_WIDTH := 600.0
const STAMPEDE_SPEED_MULT := 1.5
const STAMPEDE_BOOST_TIME := 6.0
const SIEGE_WARNING := 1.0
const SIEGE_COUNT := 24
const SIEGE_RADIUS := 220.0
const BLOOD_MOON_TIME := 30.0
const BLOOD_MOON_DAMAGE_MULT := 2.0

# Registro del daño que le hacés al héroe (cuerpo a cuerpo o a distancia), por estos segundos.
const ADAPT_WINDOW := 30.0

# Golpe con feedback: números de daño, parpadeo y temblor de pantalla.
const DMG_NUMBER_TIME := 0.6
const DMG_NUMBER_RISE := 20.0
const DMG_NUMBER_BIG := 0.08 # % de la vida máxima del héroe para el número grande
const DMG_TICK_EVERY := 0.5 # charcos y sangrado: un número sumado cada tanto
const HERO_HIT_FLASH := 0.08
const SHAKE_PX := 4.0
const SHAKE_TIME := 0.12


# --- Tanda 02: Infamia y Paladín del cielo --------------------------------------
# Infamia: sube cuando el héroe no puede con vos. Al llenarse llega un Paladín.
const INFAMY_NAME := "Infamia" # nombre visible de la barra (puede cambiar)
const INFAMY_MAX := 100.0
const INFAMY_PER_CIVILIAN := 6.0 # civiles que matás vos
const INFAMY_PER_SECOND_DETECTED := 1.0
const INFAMY_HERO_LOW := 15.0 # cada vez que el héroe baja del umbral de retirada
const INFAMY_HERO_LOW_HP := 0.3

# Paladín del cielo: se une al héroe, te caza y lo cura. Stats según el creep al aparecer.
const PALADIN_ARRIVAL := 2.0 # columna de luz antes de aparecer
const PALADIN_SPAWN_DIST := 150.0 # del héroe
const PALADIN_HP_MULT := 6.0 # x tu vida máxima
const PALADIN_SPEED_MULT := 0.85 # x tu velocidad
const PALADIN_RADIUS := 18.0
const PALADIN_HAMMER_WINDUP := 0.4
const PALADIN_HAMMER_DAMAGE := 0.2 # x tu vida máxima
const PALADIN_HAMMER_COOLDOWN := 1.5
const PALADIN_HAMMER_RANGE := 40.0 # se suma a los radios
const PALADIN_HAMMER_ARC_DEG := 120.0
const PALADIN_CHARGE_EVERY := 6.0
const PALADIN_CHARGE_RANGE := 350.0
const PALADIN_CHARGE_WINDUP := 0.6
const PALADIN_CHARGE_DAMAGE := 0.25 # x tu vida máxima
const PALADIN_CHARGE_SPEED := 650.0
const PALADIN_CHARGE_DIST := 420.0
const PALADIN_HEAL_RADIUS := 150.0
const PALADIN_HEAL := 0.02 # x vida máxima del héroe por segundo
const PALADIN_MAX_ALIVE := 3
# Escalón: cada PALADIN_TIER_EVERY soldados enviados (el 1.º al 3.º son escalón 0).
const PALADIN_TIER_EVERY := 3
const PALADIN_TIER_HP := 0.3 # +30% de vida por escalón
const PALADIN_TIER_DAMAGE := 0.35 # +35% de daño por escalón
# Cada 3.º soldado es un Capitán del cielo: más grande, más fuerte y con onda en el martillazo.
const CAPTAIN_HP_MULT := 1.4
const CAPTAIN_DAMAGE_MULT := 1.6
const CAPTAIN_RADIUS := 24.0
const CAPTAIN_WAVE_RADIUS := 90.0 # el martillazo además pega en este radio, con el mismo aviso
const CAPTAIN_HEART_MUTATIONS := 2
const HOLY_HEART_BIOMASS := 0.2 # x costo de tu próxima evolución
