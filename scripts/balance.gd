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
	{"name": "Slime", "hp": 30.0, "speed": 170.0, "bite": 6.0, "radius": 10.0, "cost": 250.0, "color": Color(0.45, 0.85, 0.35)},
	{"name": "Esqueleto", "hp": 75.0, "speed": 180.0, "bite": 15.0, "radius": 13.0, "cost": 1000.0, "color": Color(0.9, 0.88, 0.75)},
	{"name": "Cultista", "hp": 190.0, "speed": 190.0, "bite": 38.0, "radius": 17.0, "cost": 3200.0, "color": Color(0.6, 0.35, 0.8)},
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
const CIVILIAN_RESPAWN := 6.0 # cada tanto aparece un caserío (S6-c: era 3)
# Aparecen en grupos, en un anillo alrededor del creep y lejos del héroe.
const CIVILIAN_GROUP_MIN := 2
const CIVILIAN_GROUP_MAX := 4
const CIVILIAN_GROUP_SPREAD := 40.0
const CIVILIAN_RING_MIN := 600.0 # del creep (S6-c: era 350)
const CIVILIAN_RING_MAX := 1000.0 # S6-c: era 800
const CIVILIAN_MIN_HERO_DIST := 600.0 # lejos de la pelea (S6-c: era 300)
const CIVILIAN_PLACE_TRIES := 8 # sin lugar que cumpla, ese caserío no aparece
# Esquivan a la horda (solo visual: la horda no los daña).
const CIVILIAN_DODGE_RADIUS := 40.0
const CIVILIAN_DODGE_SPEED := 0.6
const CIVILIAN_HP := 8.0
const CIVILIAN_SPEED := 85.0
const CIVILIAN_FLEE_RADIUS := 220.0
const CIVILIAN_TRAMPLE_MARGIN := 4.0 # tocar un civil (suma de radios + esto) lo come al instante
const CIVILIAN_BIOMASS := 7.0 # 09-d: era 12
# 09-g: todo lo que comés (civiles, horda, gemas, cadáveres) da esto × su valor; también
# escala la cura por biomasa y el avance a la próxima mutación. 1.0 = como antes.
const CREEP_BIOMASS_MULT := 0.7
# Comer civiles hace ruido: el héroe va a investigar el lugar.
# El grito empieza apenas un civil sale corriendo de vos, no cuando muere.
# Cada grito nuevo actualiza el lugar. La alarma dura hasta que llega (a ALARM_ARRIVE_DIST)
# y ALARM_SEARCH_TIME más buscando, con un máximo de ALARM_MAX_TIME desde el último grito.
const ALARM_CLOSE_DIST := 700.0 # 09-h: más cerca que esto el grito le gana a cofre, corazón y gemas; más lejos, va después
const ALARM_ARRIVE_DIST := 80.0
const ALARM_SEARCH_TIME := 3.0
const ALARM_MAX_TIME := 12.0
const CIVILIAN_SCREAM_COOLDOWN := 3.0 # cada civil grita como mucho cada tantos segundos

# Camuflaje (Q): corta la cacería al instante (el héroe pasa a buscarte). Una vez por minuto.
const STEALTH_COOLDOWN := 60.0
const STEALTH_TIME := 4.0 # segundos en que el héroe no te puede apuntar

# --- Te ve, te caza ----------------------------------------------------------
# Sospecha (0 a 100, una por héroe): sube por lo que ningún creep común hace, solo a menos
# de RECOGNIZE_RANGE de ese héroe y sin camuflaje. Pegarle no suma (toda la horda le pega).
# Cada suma varía ±SUSPICION_JITTER. A 100 (o por la mirada) te reconoce y te caza
# RECOGNIZE_TIME; mientras te caza, cada cosa de la tabla reinicia ese tiempo. Al vencer,
# a más de HUNT_LOSE_DIST o camuflado, va HUNT_SEARCH_TIME a tu última posición y la
# sospecha queda en SUSPICION_AFTER_HUNT.
const RECOGNIZE_RANGE := 500.0
const RECOGNIZE_TIME := 12.0
const SUSPICION_MAX := 100.0
const SUSPICION_EAT := 6.0 # comer un cadáver
const SUSPICION_GEM := 10.0 # pisarle una gema
const SUSPICION_DODGE := 35.0 # esquivar un ataque de jefe
const SUSPICION_CIVILIAN := 40.0
const SUSPICION_EVOLVE := 50.0
const SUSPICION_CULTIST_PER_SECOND := 2.0 # estar cerca siendo Cultista
const SUSPICION_DEMON_PER_SECOND := 6.0
const SUSPICION_DECAY := 8.0 # por segundo, lejos o camuflado
const SUSPICION_AFTER_HUNT := 50.0
const SUSPICION_JITTER := 0.3
const SUSPICION_GAZE_EVERY := 2.0 # cada tanto, chance sospecha/100 × esto de reconocerte antes de 100
const SUSPICION_GAZE_CHANCE := 0.25
const HUNT_LOSE_DIST := 600.0
const HUNT_SEARCH_TIME := 5.0
const HUNT_SEEN_BANNER_EVERY := 10.0 # "¡El Arquero te reconoció!" como mucho cada tantos segundos
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
const ELITE_HEART_HERO_HEAL := 0.1
const HERO_HEART_SEEK_RADIUS := 700.0

# --- Héroe -------------------------------------------------------------------
const HERO_HP := 600.0
const HERO_HP_PER_LEVEL := 60.0
const HERO_LEVEL_HEAL := 0.05 # al subir de nivel recupera este % de su vida máxima (no tiene regeneración)
const HERO_SPEED := 150.0
const HERO_RADIUS := 14.0
const HERO_ARROW_DAMAGE := 25.0 # 09-a: ×1,25 (era 20)
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
# Por nivel sobre el 1, lineal: daño de flecha +6%, espera entre disparos −2,5% (mínimo
# HERO_MIN_COOLDOWN), y después se divide por el "fire_rate" del héroe.
const HERO_DAMAGE_PER_LEVEL := 0.06
const HERO_COOLDOWN_PER_LEVEL := 0.025
const HERO_MIN_COOLDOWN := 0.15 # 09-j: era 0,30 (el Arquero sigue mejorando hasta nivel ~40)
const HERO_LEVELS_PER_EXTRA_ARROW := 6
# Cada flecha atraviesa a este número de enemigos extra (Flechas perforantes suma más).
const HERO_ARROW_PIERCE := 1
# Dibujo de la flecha: crece por nivel hasta un tope y desde un nivel deja estela.
const HERO_ARROW_GROW_PER_LEVEL := 0.04
const HERO_ARROW_GROW_MAX := 1.6
const HERO_ARROW_TRAIL_LEVEL := 8
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
# Furia: al bajar de HERO_FURY_HP por primera vez corre HERO_FURY_RUN_TIME alejándose y
# después ataca más seguido (espera × HERO_FURY_ATTACK_MULT) con el ataque 3 aunque no tenga nivel.
const HERO_FURY_HP := 0.3
# Antes de la furia no te reconoce (sin "?", sospecha ni caza); al enfurecerse arranca acá.
const HERO_SUSPICION_START_ON_FURY := 50.0
const HERO_FURY_RUN_TIME := 3.0
const HERO_FURY_ATTACK_MULT := 0.6
# Furia propia de cada héroe (07-g, hero_fury.gd), desde que se enfurece.
const HERO_FURY_SHIELD_TIME := 1.5 # invulnerable al enfurecerse, para que se vea la furia
const HERO_FURY_ARCHER_FIRE_MULT := 0.35 # Arquero: espera entre flechas
const HERO_FURY_ARCHER_MIN_COOLDOWN := 0.15
const HERO_FURY_ARCHER_HEAL_PER_KILL := 0.01 # de su vida máxima por creep que mata
const HERO_FURY_KNIGHT_LIFESTEAL := 0.15 # Caballero: del daño cuerpo a cuerpo que hace
const HERO_FURY_MAGE_SHIELD := 0.5 # Maga: escudo de maná, × su vida máxima, no vuelve
const HERO_FURY_MAGE_SPELL_EVERY := 1.5 # hechizo extra al azar: rayo, bola de fuego o hielo
const HERO_FURY_MAGE_FIREBALL := {"name": "Bola de fuego", "shape": "circle", "radius": 80.0, "warn": 0.6, "player_damage": 0.2}
const HERO_FURY_MAGE_ICE := {"name": "Hielo", "shape": "circle", "radius": 140.0, "warn": 0.5, "player_damage": 0.1, "slow": 0.4, "slow_time": 2.0}
const HERO_MISTAKE_CHANCE := 0.06
const HERO_DETECTED_TARGET_BONUS := 150.0 # chico: si tiene creeps encima, se defiende primero
# Cacería: con el jugador detectado, el héroe va por vos.
const HUNT_IDEAL_DIST := 220.0
# Gemas: va al montón que más vale (XP a HERO_GEM_CLUSTER_RADIUS / (distancia + HERO_GEM_DIST_BIAS)).
const HERO_GEM_CLUSTER_RADIUS := 100.0
const HERO_GEM_DIST_BIAS := 150.0
const HERO_GEM_SEEK_RADIUS := 600.0 # libre
# 09-h: solo rodeado (peligro HERO_SURROUNDED_DANGER) o con menos de HERO_PRIORITY_HP de vida
# manda alejarse de la horda; si no, va a su objetivo apartándose HERO_HORDE_SEPARATION.
const HERO_PRIORITY_HP := 0.5
const HERO_SURROUNDED_DANGER := 6.0
const HERO_HORDE_SEPARATION := 0.4 # × su objetivo (1,0)
const HUNT_ESCAPE_RADIUS := 80.0 # con tantos creeps así de cerca, primero zafa
const HUNT_ESCAPE_COUNT := 2
const HUNT_SHARE_RADIUS := 150.0 # con creeps así de cerca, alterna un disparo a vos y uno a la horda

# Tres héroes en 15 minutos: llegan a horario fijo, haya muerto o no el anterior.
# Ganás matando a los tres. "hp", "speed" y "damage" multiplican la vida, la velocidad
# y el daño de las flechas; "fire_rate" multiplica cuántas tira por segundo; "attacks" son sus
# ataques de jefe (HERO_ATTACKS; el 3.º desde HERO_ATTACK_THIRD_LEVEL), uno cada "attack_every" s; "powers" son los poderes con los que llega (rango 1).
# "level_bonus": llega en HERO_CURVE (ese minuto) + esto + bonus por ir adelantado, nunca
# por debajo del héroe más fuerte que hubo. Bonus: (tu nivel equivalente − CREEP_CURVE) / 2,
# redondeado, entre 0 y ARRIVAL_AHEAD_BONUS_MAX.
# "table": +1 rango del poder de cada nivel (índice 0 = nivel 2, hasta el 20; después solo stats).
# Al llegar se aplican en silencio todas las filas hasta su nivel de llegada.
const MATCH_MINUTES := 15.0 # amanece: los héroes vivos escapan y termina la partida
const HERO_ESCAPE_TIME := 2.0 # suben en una columna de luz; todo lo demás queda quieto
const HORDE_IDLE_DIST := 120.0 # sin héroes vivos, la horda te sigue a esta distancia
const HERO_ARRIVAL_WARNING := 5.0 # banner y portal antes de que llegue
const HERO_NEXT_AFTER_KILL := 30.0 # si matás a uno, el siguiente llega a más tardar en estos segundos
# Curvas objetivo [minuto, nivel] (del plan maestro), interpoladas lineal entre minutos.
const HERO_CURVE := [[0, 1], [1, 3], [3, 6], [5, 9], [8, 14], [10, 17], [12, 22], [15, 25]]
const CREEP_CURVE := [[0, 1], [1, 3], [3, 6], [5, 9], [8, 13], [10, 16], [12, 19], [15, 23]] # nivel equivalente
const ARRIVAL_AHEAD_BONUS_MAX := 2


## Nivel de una curva [minuto, nivel] en "minute", interpolando lineal.
static func curve_at(curve: Array, minute: float) -> float:
	if minute <= curve[0][0]:
		return curve[0][1]
	for i in range(1, curve.size()):
		if minute <= curve[i][0]:
			var a: Array = curve[i - 1]
			var b: Array = curve[i]
			return lerpf(a[1], b[1], (minute - a[0]) / float(b[0] - a[0]))
	return curve[-1][1]

# Ataques de jefe (hero_attacks.gd): zona roja que se llena durante "warn" y después golpea.
# Formas: "circle" (radius), "line" (length, width), "cone" (length, angle en grados),
# "donut" (crece desde el héroe hasta radius en "grow" segundos, frente de "width").
# "center": "hero" (alrededor suyo), "target" (sobre el blanco) o "line" (desde él hacia el blanco).
# "count"/"spread"/"stagger": varias zonas (meteoros, terremoto); "cross": dos líneas en cruz.
# "player_damage": × tu vida máxima (una vez por ataque). "dash": el héroe recorre la línea al golpear.
const HERO_ATTACKS := {
	"lluvia_flechas": {"name": "Lluvia de flechas", "shape": "circle", "center": "target", "radius": 160.0, "warn": 1.2, "player_damage": 0.3},
	"disparo_cargado": {"name": "Disparo cargado", "shape": "line", "center": "line", "length": 1400.0, "width": 40.0, "warn": 1.0, "player_damage": 0.3},
	"abanico": {"name": "Abanico", "shape": "cone", "center": "line", "length": 450.0, "angle": 70.0, "warn": 0.8, "player_damage": 0.4},
	"tajo_giratorio": {"name": "Tajo giratorio", "shape": "circle", "center": "hero", "radius": 200.0, "warn": 1.0, "player_damage": 0.3, "melee": true},
	"embestida": {"name": "Embestida", "shape": "line", "center": "line", "length": 500.0, "width": 60.0, "warn": 1.0, "player_damage": 0.3, "dash": true},
	"terremoto": {"name": "Terremoto", "shape": "circle", "center": "line", "radius": 110.0, "warn": 0.8, "player_damage": 0.4,
		"count": 3, "stagger": 0.6},
	"meteoros": {"name": "Meteoros", "shape": "circle", "center": "target", "radius": 130.0, "warn": 1.5, "player_damage": 0.3,
		"count": 3, "spread": 150.0},
	"cruz_rayos": {"name": "Cruz de rayos", "shape": "line", "center": "target", "length": 900.0, "width": 40.0, "warn": 1.2, "player_damage": 0.3, "cross": true},
	"anillo_fuego": {"name": "Anillo de fuego", "shape": "donut", "center": "hero", "radius": 350.0, "width": 40.0, "warn": 1.0, "grow": 0.6, "player_damage": 0.4},
}
# Último Bastión (bastion.gd): si matás a los tres antes de amanecer, 1 contra 1.
const BASTION_HP_MULT := 70.0 # × tu vida máxima al empezar (09-b: era 25)
const BASTION_SPEED := 140.0
const BASTION_RADIUS := 30.0
const BASTION_CHASE_DIST := 150.0 # te persigue hasta esta distancia (para que llegue el Tajo giratorio)
const BASTION_WALL_RADIUS := 650.0 # pared de luz alrededor tuyo
const BASTION_SPAWN_DIST := 400.0
const BASTION_LANDING := 3.0 # invulnerable mientras aterriza
const BASTION_INTRO_GLOW := 2.0 # la pantalla se aclara en dorado
# Fases por vida restante: ataques (HERO_ATTACKS, en orden) y cada cuánto.
const BASTION_PHASES := [
	{"above": 0.66, "attacks": ["tajo_giratorio", "lluvia_flechas", "embestida"], "every": 3.0},
	{"above": 0.33, "attacks": ["tajo_giratorio", "lluvia_flechas", "embestida", "cruz_rayos", "terremoto"], "every": 2.5},
	{"above": 0.0, "attacks": ["tajo_giratorio", "lluvia_flechas", "embestida", "cruz_rayos", "terremoto", "meteoros", "anillo_fuego"], "every": 2.0},
]
const BASTION_LAST_PHASE_SPEED := 1.25
const BASTION_KNEEL_TIME := 2.0 # al cambiar de fase: no ataca y recibe el doble
const BASTION_KNEEL_DAMAGE_MULT := 2.0
const BASTION_MEAT := 2 # trozos de carne que suelta al arrodillarse
const BASTION_MEAT_HEAL := 0.2 # × tu vida máxima cada uno
const BASTION_MEAT_SCATTER := 90.0
const BASTION_MEAT_RADIUS := 12.0
const HERO_ATTACK_THIRD_LEVEL := 8 # el ataque 3 aparece desde este nivel
const HERO_ATTACK_TARGET_RANGE := 500.0 # sin cazarte, apunta al montón de horda más denso a esta distancia
const HERO_ATTACK_CLUSTER_RADIUS := 120.0 # "montón": el creep con más vecinos a esta distancia
const HERO_ATTACK_RETRY := 1.0 # sin blanco, vuelve a probar en estos segundos
const HERO_ATTACK_BIG_DAMAGE := 0.6 # brutos y élites pierden esto de su vida máxima (los menores mueren)
const HERO_ATTACK_DASH_TIME := 0.2 # la Embestida recorre la línea en estos segundos
const HERO_ATTACK_FLASH := 0.15
const HERO_ARRIVAL_WAVE_RADIUS := 300.0 # onda sagrada al llegar: mata a los menores, empuja a brutos y élites
const HERO_ARRIVAL_SHIELD := 3.0 # segundos invulnerable al llegar (brilla dorado)
const HERO_GEM_PILE_EVERY := 0.3 # cada cuánto recalcula el mejor montón de gemas
const HERO_GEM_PILE_LOOK := 40 # cuántas gemas cercanas mira para elegir montón
const HERO_PORTAL_MIN := 600.0 # distancia del portal a vos
const HERO_PORTAL_MAX := 900.0
const HEROES := [
	{"name": "Arquero", "article": "el", "minute": 0.0, "level": 1, "hp": 1.0, "speed": 1.0, "damage": 1.0, "fire_rate": 0.55,
		"attacks": ["lluvia_flechas", "disparo_cargado", "abanico"], "attack_every": 7.0,
		"powers": [], "color": Color(0.3, 0.55, 1.0),
		"table": ["perforante", "multiple", "botas", "rayo", "perforante", "multiple", "trampa", "rayo", "botas",
			"perforante", "multiple", "rayo", "trampa", "botas", "rayo", "trampa", "rayo", "trampa", "trampa"]},
	{"name": "Caballero", "article": "el", "minute": 5.0, "level_bonus": 2, "hp": 1.5, "speed": 0.9, "damage": 0.8, "fire_rate": 0.5,
		"attacks": ["tajo_giratorio", "embestida", "terremoto"], "attack_every": 6.0,
		"powers": ["aura", "nova"], "color": Color(0.78, 0.8, 0.88),
		"table": ["aura", "escudo", "nova", "aura", "botas", "escudo", "rayo", "nova", "aura",
			"escudo", "botas", "nova", "rayo", "aura", "escudo", "nova", "botas", "rayo", "escudo"]},
	{"name": "Maga", "article": "la", "minute": 10.0, "level_bonus": 4, "hp": 0.8, "speed": 1.05, "damage": 1.15, "fire_rate": 0.7,
		"attacks": ["meteoros", "cruz_rayos", "anillo_fuego"], "attack_every": 5.0,
		"powers": ["rayo", "orbes"], "color": Color(0.72, 0.4, 0.95),
		"table": ["rayo", "orbes", "parpadeo", "rayo", "nova", "orbes", "aura", "rayo", "parpadeo",
			"nova", "orbes", "rayo", "aura", "nova", "parpadeo", "orbes", "nova", "aura", "nova"]},
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
	"arquero": {"hp": 10.0, "speed": 85.0, "dps": 0.0, "radius": 9.0, "xp": 2.0, "biomass": 1.5, "color": Color(0.55, 0.4, 0.75),
		"range": 300.0, "shot_cooldown": 1.6, "shot_damage": 6.0}, # 09-j: antes 260 / 2,2 / 4 / vel. 70
	"bruto": {"hp": 60.0, "speed": 60.0, "dps": 14.0, "radius": 16.0, "xp": 5.0, "biomass": 5.0, "color": Color(0.6, 0.3, 0.3)},
}
const MAX_MINIONS_BY_STAGE := [198, 220, 220, 220] # 09-f: según tu etapa (280 pasaba los 16,6 ms)
const MAX_MINIONS_NO_HERO := 60 # sin héroes vivos no aparecen más (los que están te siguen)
const MAX_GEMS := 225 # 09-h: era 150, con gemas más largas el tope las borraba; al pasarse, desaparece la más vieja
const MAX_CORPSES := 120 # al pasarse, desaparece el más viejo (los corazones no)
const CORPSE_LIFETIME := 20.0
const GEM_LIFETIME := 37.5 # 09-h: era 25
# 09-j: más cerca del héroe para que lleguen (antes 650-900). Nunca dentro de la pantalla:
# si cae en SPAWN_VIEW_HALF alrededor del creep, prueba otro ángulo (hasta SPAWN_TRIES).
const SPAWN_MIN_DIST := 500.0
const SPAWN_MAX_DIST := 750.0
const SPAWN_VIEW_HALF := Vector2(680.0, 400.0) # media pantalla 1280×720 y un margen
const SPAWN_TRIES := 8


# La horda mejora por escalones: uno cada HORDE_TIER_MINUTES.
const HORDE_TIER_MINUTES := 2.0


static func horde_tier(minute: float) -> float:
	return floorf(minute / HORDE_TIER_MINUTES)


# 09-f: la horda que nace también escala con tu etapa (Slime, Esqueleto, Cultista, Demonio).
const HORDE_STAGE_MULT := [1.0, 1.5, 2.2, 3.2] # vida y daño
const HORDE_STAGE_SPAWN := 0.15 # más apariciones por etapa


static func minion_hp_mult(minute: float, stage := 0) -> float:
	return (1.0 + horde_tier(minute) * 0.2) * HORDE_STAGE_MULT[stage]


# Como en Vampire Survivors, tus compañeros se vuelven más fuertes con cada escalón.
static func minion_dps_mult(minute: float, stage := 0) -> float:
	return (1.0 + horde_tier(minute) * 0.15) * HORDE_STAGE_MULT[stage]


static func minion_speed_mult(minute: float) -> float:
	return minf(1.0 + horde_tier(minute) * 0.04, 1.4)


# 09-j: además, cada HORDE_WAVE_SECONDS las apariciones suben HORDE_WAVE_STEP (× 1 + 0,08 · escalones).
const HORDE_WAVE_SECONDS := 30.0
const HORDE_WAVE_STEP := 0.08


static func spawns_per_second(minute: float, stage := 0) -> float:
	var waves := floorf(minute * 60.0 / HORDE_WAVE_SECONDS)
	return (2.2 + minute * 0.99) * (1.0 + HORDE_STAGE_SPAWN * stage) * (1.0 + HORDE_WAVE_STEP * waves)


static func pick_minion_type(minute: float, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if minute > 2.0 and r < minf(0.05 + minute * 0.025, 0.3):
		return "bruto"
	if minute > 0.5 and r >= 0.3 and r < 0.5: # 09-j: 20% desde el minuto 0,5 (el bruto llega hasta 0,3)
		return "arquero"
	if r < 0.6:
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
const CHEST_HERO_HEAL := 0.1
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
const DMG_NUMBER_RISE := 30.0
const DMG_NUMBER_BIG := 0.05 # % de la vida máxima para el número grande (amarillo)
const DMG_TICK_EVERY := 0.5 # charcos y sangrado: un número sumado cada tanto
const HERO_HIT_FLASH := 0.08
const SHAKE_PX := 4.0
const SHAKE_TIME := 0.12
const EVOLVE_FLASH := 0.3 # destello blanco al evolucionar de etapa


# --- Tanda 02: Infamia y Paladín del cielo --------------------------------------
# Infamia: sube cuando el héroe no puede con vos. Al llenarse llega un Paladín.
const INFAMY_NAME := "Infamia" # nombre visible de la barra (puede cambiar)
const INFAMY_MAX := 100.0
const INFAMY_PER_CIVILIAN_BY_STAGE := [6.0, 10.0, 15.0, 22.0] # por civil que matás, según tu etapa
const INFAMY_PER_SECOND_DETECTED := 1.0 # en Slime; se multiplica por INFAMY_STAGE_MULT
const INFAMY_STAGE_MULT := [1.0, 1.6, 2.5, 3.6] # Slime, Esqueleto, Cultista, Demonio
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
const PALADIN_HEAL := 0.01 # x vida máxima del héroe por segundo
const PALADIN_HEAL_CAP := 0.6 # no lo cura por encima de este % de su vida máxima
const PALADIN_MAX_ALIVE := 5
const PALADIN_STAGE_MULT := [1.0, 1.3, 1.8, 2.5] # vida y daño x tu etapa al aparecer (Slime..Demonio)
const PALADIN_PER_CALL := [1, 1, 2, 3] # soldados por llamado según tu etapa
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

# Mecánica propia de cada héroe (hero_traits.gd). Los rangos (trampa, escudo, parpadeo)
# los sube su tabla; el rango 0 es la versión base, desde nivel 1.
# Arquero: rueda más seguido y donde termina deja una trampa.
const ARCHER_ROLL_COOLDOWN := 2.0
const TRAP_RADIUS := 40.0
const TRAP_RADIUS_PER_RANK := 8.0
const TRAP_TIME := 6.0
const TRAP_ROOT := 1.0 # te inmoviliza
const TRAP_ROOT_PER_RANK := 0.2
const TRAP_DAMAGE := 0.15 # × tu vida máxima
const TRAP_MAX := 4
const TRAP_MAX_PER_RANK := 1
# Caballero: escudo al frente; de frente tus golpes hacen SHIELD_BLOCK_MULT.
const SHIELD_ARC := 120.0
const SHIELD_ARC_PER_RANK := 10.0
const SHIELD_TURN := 120.0 # grados por segundo
const SHIELD_TURN_PER_RANK := 15.0
const SHIELD_BLOCK_MULT := 0.2
const SHIELD_DASH_PUSH := 40.0 # embestirlo de frente lo empuja sin dañarlo
# Maga: si la mordés BLINK_HITS veces en BLINK_WINDOW, se teletransporta y deja una nova.
const BLINK_HITS := 3
const BLINK_WINDOW := 4.0
const BLINK_DIST := 350.0
const BLINK_NOVA_RADIUS := 120.0
const BLINK_NOVA_RADIUS_PER_RANK := 20.0
const BLINK_NOVA_WARN := 0.5
const BLINK_NOVA_DAMAGE := 0.25
const BLINK_COOLDOWN := 8.0
const BLINK_COOLDOWN_PER_RANK := 1.5

# Hachas giratorias del Caballero (09-d B, hero_traits.gd): golpean horda y a vos.
const KNIGHT_AXES := 2
const KNIGHT_AXES_FURY := 4
const KNIGHT_AXE_RADIUS := 85.0
const KNIGHT_AXE_RADIUS_FURY := 100.0
const KNIGHT_AXE_SPIN := 1.4 # segundos por vuelta
const KNIGHT_AXE_SPIN_FURY := 0.9
const KNIGHT_AXE_DAMAGE_MULT := 0.8 # × daño de flecha
const KNIGHT_AXE_HIT_EVERY := 0.5 # como mucho un golpe por blanco cada tanto
const KNIGHT_AXE_SIZE := 12.0 # radio de golpe de cada hacha

# --- FX (jugo visual, tanda S2; los maneja el programador de sistemas) ---------
const FX_MAX_PARTICLES := 400 # tope de partículas vivas; se van las más viejas
const FX_PARTICLE_TIME := 0.4
const FX_DEATH_PARTICLES := Vector2i(6, 10) # por creep de la horda que muere
const FX_DEATH_SPEED := Vector2(60.0, 160.0)
const FX_BLAST_SPEED := Vector2(320.0, 520.0) # despedidas por un ataque de jefe
const FX_BLAST_WINDOW := 0.1 # s: una muerte tan cerca del golpe cuenta como del golpe
const FX_CIVILIAN_PARTICLES := 6
const FX_HERO_DEATH_PARTICLES := 40
const FX_HERO_DEATH_RADIUS := 220.0 # anillo de luz al morir un héroe
const FX_SLOWMO_TIME := 0.5 # s reales de cámara lenta al morir un héroe
const FX_SLOWMO_SCALE := 0.3
const FX_HITSTOP_MELEE := 0.05 # mordida o embestida al héroe
const FX_HITSTOP_BOSS := 0.12 # un ataque de jefe te golpea
const FX_FLASH := 0.08 # destello blanco al recibir daño
const FX_GROUP_EVERY := 0.3 # golpes chicos (horda al héroe, daño a vos) sumados en un número
const FX_MUTATE_RING := Vector2(0.3, 80.0) # duración, radio
const FX_EVOLVE_RING := Vector2(0.6, 200.0)
const FX_LEVEL_COLUMN := 0.4 # columna de luz del héroe al subir de nivel
const FX_PICK_LOCK := 0.3 # s en que la elección de mutación no acepta nada al abrir
const FX_PICK_ANIM := 0.15 # s de entrada de las cartas

# --- Habilidades del creep (tanda S4; las maneja el programador de sistemas) ---
# Habilidad por etapa (se suman: el Demonio tiene las tres)
const BONES_EVERY := 2.5 # Esqueleto: huesos que rebotan entre blancos
const BONES_COUNT := 3
const BONES_BOUNCES := 2
const BONES_DAMAGE := 0.5 # x mordida
const BONES_RANGE := 350.0 # busca un blanco a esta distancia para tirarlos
const BONES_BOUNCE_RANGE := 300.0
const BONES_SPEED := 520.0
const CORPSE_BLAST_EVERY := 4.0 # Cultista: detonar un cadáver cerca del héroe
const CORPSE_BLAST_REACH := 120.0 # el cadáver tiene que estar a esta distancia del héroe
const CORPSE_BLAST_RADIUS := 90.0
const CORPSE_BLAST_DAMAGE := 1.5 # x mordida
const BREATH_EVERY := 5.0 # Demonio: aliento en cono
const BREATH_ANGLE := 60.0 # grados
const BREATH_LENGTH := 220.0
const BREATH_TIME := 1.2
const BREATH_TICK := 0.2
const BREATH_DAMAGE := 0.6 # x mordida por tick
# Mutaciones de arma
const THORNS_DAMAGE := 0.6 # Espinas: x mordida a lo que tocás en la embestida
const GOO_EVERY := 3.0 # Pegote: charco pegajoso
const GOO_RADIUS := 50.0
const GOO_TIME := 4.0
const GOO_SLOW := 0.25 # sube con el rango (POWER_RANK_EFFECT)
const RALLY_RADIUS := 250.0 # Llamado: la horda a esta distancia corre hacia donde apuntás
const RALLY_SPEED_MULT := 1.8
const RALLY_TIME := 3.0
const RALLY_COOLDOWN := 12.0 # baja con el rango (POWER_RANK_COOLDOWN)
const RALLY_AIM_DIST := 250.0 # con stick, el punto queda a esta distancia

# --- Arbustos (tanda S5; los maneja el programador de sistemas) ---------------
const BUSH_COUNT := 14
const BUSH_RADIUS := 70.0
const BUSH_MIN_GAP := 250.0 # entre matas
const BUSH_CENTER_CLEAR := 300.0 # lejos de donde arrancás
const BUSH_HIDE_TIME := 8.0 # s de uso seguido antes de marchitarse
const BUSH_WITHER_TIME := 20.0 # marchita (o quemada por un ataque de jefe) no esconde
const BUSH_REVEAL_ON_ATTACK := 2.0 # atacar desde adentro te deja a la vista
const BUSH_HUNT_ESCAPE_DIST := 250.0 # cazándote, te pierde en el arbusto solo si estás más lejos


# --- Clases del Anti Hero (tanda S7, programador de sistemas) -------------------
# Daños × mordida de la etapa; "hp" × vida de la etapa. Se elige en el menú.

const CLASSES_ALL_UNLOCKED := true # para probar; apagado, cada victoria desbloquea la siguiente de CLASS_UNLOCK_ORDER
const CLASS_ORDER := ["engendro", "abisal", "reina"] # las que salen en el menú, en orden
const CLASS_UNLOCK_ORDER := ["nigromante", "glotona", "espectral", "abisal", "reina"]
const CLASSES := {
	"engendro": {"name": "Engendro", "hp": 1.0, "rule": "El de siempre: escupe, muerde y evoluciona.",
		"weapon": "Escupitajo, y Huesos, Detonar cadáver y Aliento por etapa."},
	"abisal": {"name": "Abisal", "hp": 1.0, "rule": "Abrí grietas (C): sus tentáculos frenan, y viajás entre ellas (doble embestida).",
		"weapon": "Azote: un tentáculo golpea el piso en línea hacia el héroe."},
	"reina": {"name": "Reina del enjambre", "hp": 1.0, "rule": "Tu vida es tu enjambre: los golpes matan insectos y comer cría más.",
		"weapon": "Manda parte del enjambre a picar al héroe."},
}

# Abisal
const ABYSS_RIFT_COOLDOWN := 6.0
const ABYSS_RIFT_MAX := 3 # la más vieja se cierra
const ABYSS_RIFT_RADIUS := 60.0
const ABYSS_GRAB_RADIUS := 100.0 # Agarre: héroe o Paladín a esta distancia de una grieta
const ABYSS_GRAB_SLOW := 0.35
const ABYSS_GRAB_DPS := 0.25 # × mordida por segundo
const ABYSS_TIDE_SLOW := 0.25 # Marea negra: líneas entre grietas
const ABYSS_TIDE_WIDTH := 24.0
const ABYSS_TELEPORT_COOLDOWN := 5.0
const ABYSS_DOUBLE_TAP := 0.3 # s entre los dos toques de embestida
const ABYSS_LASH_EVERY := 1.5 # Azote (arma inicial; S7-a'': era 2,5)
const ABYSS_LASH_RANGE := 350.0
const ABYSS_LASH_LENGTH := 260.0
const ABYSS_LASH_WIDTH := 36.0
const ABYSS_LASH_WARN := 0.5
const ABYSS_LASH_DAMAGE := 1.4
const ABYSS_LASH_PUSH := 40.0
const ABYSS_MAW_EVERY := 14.0 # Fauces (desde Esqueleto)
const ABYSS_MAW_TIME := 4.0
const ABYSS_MAW_DPS := 2.0 # × mordida por segundo
const ABYSS_MAW_SLOW := 0.6
const ABYSS_SLAM_RADIUS := 120.0 # Aplastar (desde Cultista, al cerrarse Fauces)
const ABYSS_SLAM_DAMAGE := 2.0
const ABYSS_SLAM_STUN := 0.5

# Reina del enjambre
const SWARM_START := 20
const SWARM_MAX := [20, 35, 55, 80] # por etapa
const SWARM_PER_CORPSE := 1
const SWARM_PER_CIVILIAN := 3
const SWARM_BREED_EVERY := 4.0 # cría pasiva (Colmena: -1 s por rango)
const SWARM_HIVE_MULT := 0.8 # Colmena: la cría pasiva tarda x esto por rango
const SWARM_SEND_SHARE := 0.25 # arma inicial: parte del enjambre que sale a picar
const SWARM_SEND_MIN := 3
const SWARM_SEND_RANGE := 320.0
const SWARM_SEND_EVERY := 3.0 # una salida cada 3 s (S7-a'': era 5); pican 4 s y vuelven, se pueden pisar
const SWARM_STING_TIME := 4.0
const SWARM_STING_DPS := 0.12 # × mordida por segundo, por insecto
const SWARM_STINGER_BLEED := 0.05 # Aguijón: × mordida por segundo, 3 s
const SWARM_STINGER_TIME := 3.0
const SWARM_BUZZ_CONFUSE := 1.0 # Zumbido: el Paladín picado pierde el objetivo
const SWARM_CLOUD_EVERY := 15.0 # Nube (desde Esqueleto)
const SWARM_CLOUD_RANGE := 300.0
const SWARM_CLOUD_TIME := [3.0, 3.0, 3.5, 4.0] # por etapa


# --- Poderes por clase (tanda S8, estilo HoloCure) ------------------------------
# Cada clase tiene 10 poderes; el primero es fijo (lo tenés desde el arranque).
# Máximo POWERS_MAX distintos, POWER_MAX_RANK rangos cada uno. Cada rango arriba del 1:
# +POWER_RANK_EFFECT de daño o efecto y -POWER_RANK_COOLDOWN de recarga (salvo excepciones).

const POWERS_MAX := 5
const POWER_MAX_RANK := 5
const POWER_RANK_EFFECT := 0.2
const POWER_RANK_COOLDOWN := 0.08
const PICK_WEIGHT_NEW := 4 # en el sorteo de cartas: poder nuevo
const PICK_WEIGHT_RANK := 4 # subir de rango un poder tuyo
const PICK_WEIGHT_STAT := 2 # Colmillos, Patas, Caparazón...
const SPIT_EXTRA_AT := [3, 5] # Escupitajo: +1 escupitajo en estos rangos

const CLASS_POWERS := {
	"engendro": [
		{"id": "escupitajo", "name": "Escupitajo", "icon": "Es", "color": Color(0.55, 0.95, 0.2), "desc": "Escupís ácido al héroe. Rangos 3 y 5: +1 escupitajo."},
		{"id": "huesos", "name": "Huesos", "icon": "Hu", "color": Color(0.95, 0.93, 0.85), "desc": "Cada 2,5 s tirás 3 huesos que rebotan entre blancos."},
		{"id": "detonar", "name": "Detonar cadáver", "icon": "De", "color": Color(0.75, 0.3, 0.9), "desc": "Cada 4 s explota un cadáver cerca del héroe."},
		{"id": "aliento", "name": "Aliento", "icon": "Al", "color": Color(1.0, 0.45, 0.1), "desc": "Cada 5 s echás fuego en cono 1,2 s."},
		{"id": "espinas", "name": "Espinas", "icon": "Ep", "color": Color(0.6, 0.85, 0.4), "desc": "Durante la embestida, todo lo que tocás recibe mordida x0,6."},
		{"id": "pegote", "name": "Pegote", "icon": "Pg", "color": Color(0.95, 0.85, 0.35), "desc": "Cada 3 s dejás un charco que frena al héroe 25%."},
		{"id": "llamado", "name": "Llamado", "icon": "Ll", "color": Color(1.0, 0.9, 0.4), "desc": "C o RT: la horda cercana corre hacia donde apuntás (recarga 12 s)."},
		{"id": "lluvia", "name": "Lluvia ácida", "icon": "Lu", "color": Color(0.4, 0.9, 0.3), "desc": "Cada escupitajo deja un charco que quema y frena."},
		{"id": "coraza", "name": "Coraza viva", "icon": "Co", "color": Color(0.9, 0.85, 0.6), "desc": "Al terminar la embestida sale una onda que daña, empuja y aturde."},
		{"id": "carronia", "name": "Señor de la carroña", "icon": "Ca", "color": Color(0.45, 0.9, 0.5), "desc": "Los compañeros que mueren cerca se levantan 8 s como zombis."},
	],
	"abisal": [
		{"id": "azote", "name": "Azote", "icon": "Az", "color": Color(0.6, 0.3, 0.9), "desc": "Cada 1,5 s un tentáculo golpea el piso en línea hacia el héroe y lo empuja."},
		{"id": "fauces", "name": "Fauces", "icon": "Fa", "color": Color(0.85, 0.2, 0.3), "desc": "Cada 14 s una grieta se vuelve boca 4 s: come civiles y muerde al héroe."},
		{"id": "aplastar", "name": "Aplastar", "icon": "Ap", "color": Color(0.5, 0.25, 0.75), "desc": "Al cerrarse Fauces (o cada 8 s sin Fauces) golpea alrededor de la grieta y aturde."},
		{"id": "marea", "name": "Marea negra", "icon": "Ma", "color": Color(0.3, 0.1, 0.45), "desc": "Las grietas se unen con líneas que frenan al héroe 25%."},
		{"id": "ancla", "name": "Ancla", "icon": "An", "color": Color(0.4, 0.15, 0.55), "desc": "Cada 6 s un tentáculo agarra al héroe y lo deja quieto 0,8 s."},
		{"id": "kraken", "name": "Kraken", "icon": "Kr", "color": Color(0.25, 0.5, 0.6), "desc": "Cada 18 s un tentáculo gigante sale bajo el héroe (aviso 1 s, mordida x4)."},
		{"id": "remolino", "name": "Remolino", "icon": "Re", "color": Color(0.35, 0.35, 0.7), "desc": "Las grietas chupan cadáveres cercanos y te los mandan."},
		{"id": "tinta", "name": "Tinta", "icon": "Ti", "color": Color(0.1, 0.1, 0.15), "desc": "Cada 8 s una nube de tinta alrededor tuyo 3 s: adentro, el héroe dispara 50% más lento."},
		{"id": "surco", "name": "Surco", "icon": "Su", "color": Color(0.45, 0.2, 0.6), "desc": "La embestida deja una franja 2 s que frena al héroe 40% y lo lastima."},
		{"id": "ojo", "name": "Ojo del abismo", "icon": "Oj", "color": Color(0.9, 0.3, 0.6), "desc": "Cerca de una grieta, el héroe recibe +15% de daño de todo."},
	],
	"reina": [
		{"id": "picar", "name": "A picar", "icon": "Pi", "color": Color(0.85, 0.7, 0.2), "desc": "Mandás parte del enjambre a picar. Cada rango: +1 insecto y -0,3 s."},
		{"id": "nube", "name": "Nube", "icon": "Nu", "color": Color(0.3, 0.25, 0.1), "desc": "Cada 15 s el enjambre envuelve al héroe y lo ciega. Mientras, quedás sin insectos."},
		{"id": "aguijon", "name": "Aguijón", "icon": "Ag", "color": Color(0.85, 0.2, 0.2), "desc": "Cada salida a picar hace sangrar al héroe."},
		{"id": "zumbido", "name": "Zumbido", "icon": "Zu", "color": Color(0.7, 0.7, 0.5), "desc": "Los Paladines picados pierden el objetivo 1 s."},
		{"id": "colmena", "name": "Colmena", "icon": "Cm", "color": Color(0.95, 0.75, 0.3), "desc": "Criás insectos más rápido."},
		{"id": "avispas", "name": "Avispas de fuego", "icon": "Av", "color": Color(1.0, 0.5, 0.15), "desc": "Los insectos que te matan explotan alrededor tuyo."},
		{"id": "alas", "name": "Escudo de alas", "icon": "Es", "color": Color(0.7, 0.85, 0.95), "desc": "Con 10+ insectos, cada 10 s recibís 50% menos daño por 2 s."},
		{"id": "larvas", "name": "Larvas", "icon": "La", "color": Color(0.95, 0.95, 0.8), "desc": "Cada cadáver que comés deja una larva: en 4 s, +2 insectos."},
		{"id": "madre", "name": "Reina madre", "icon": "Rm", "color": Color(0.8, 0.5, 0.9), "desc": "+15% de máximo de insectos por rango."},
		{"id": "cazador", "name": "Enjambre cazador", "icon": "Ec", "color": Color(0.6, 0.5, 0.2), "desc": "El héroe cerca tuyo recibe picaduras de los insectos en casa."},
	],
}

# Abisal (S8)
const ABYSS_SLAM_EVERY := 8.0 # Aplastar sin Fauces
const ABYSS_ANCHOR_EVERY := 6.0
const ABYSS_ANCHOR_RANGE := 400.0
const ABYSS_ANCHOR_TIME := 0.8
const ABYSS_KRAKEN_EVERY := 18.0
const ABYSS_KRAKEN_RANGE := 450.0
const ABYSS_KRAKEN_WARN := 1.0
const ABYSS_KRAKEN_RADIUS := 90.0
const ABYSS_KRAKEN_DAMAGE := 4.0
const ABYSS_WHIRL_RADIUS := 200.0 # Remolino
const ABYSS_WHIRL_PULL := 160.0 # velocidad a la que vienen los cadáveres
const ABYSS_INK_EVERY := 8.0
const ABYSS_INK_RADIUS := 120.0
const ABYSS_INK_TIME := 3.0
const ABYSS_INK_FIRE_SLOW := 0.5 # el héroe dispara x(1 + esto) más lento
const ABYSS_FURROW_TIME := 2.0 # Surco
const ABYSS_FURROW_WIDTH := 30.0
const ABYSS_FURROW_SLOW := 0.4
const ABYSS_FURROW_DPS := 0.5
const ABYSS_EYE_RADIUS := 200.0 # Ojo del abismo
const ABYSS_EYE_VULN := 0.15

# Reina del enjambre (S8)
const SWARM_PICK_EXTRA_PER_RANK := 1 # A picar: +1 insecto por salida por rango
const SWARM_PICK_CD_PER_RANK := 0.3
const SWARM_FIRE_WASP_RADIUS := 50.0 # Avispas de fuego
const SWARM_FIRE_WASP_DAMAGE := 0.3 # x mordida por insecto muerto
const SWARM_WINGS_MIN := 10 # Escudo de alas
const SWARM_WINGS_EVERY := 10.0
const SWARM_WINGS_TIME := 2.0
const SWARM_WINGS_REDUCTION := 0.5
const SWARM_LARVA_TIME := 4.0
const SWARM_LARVA_INSECTS := 2
const SWARM_MOTHER_PER_RANK := 0.15
const SWARM_HUNTER_RADIUS := 130.0 # Enjambre cazador
const SWARM_HUNTER_DPS := 0.2 # x mordida por segundo
