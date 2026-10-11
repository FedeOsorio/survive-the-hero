extends Node2D
## Datos y consultas chicas de un héroe (hero.gd hereda de acá, vía hero_brain y hero_combat).
## Todas las variables del héroe viven acá, para que las piezas compartan estado.

const B := preload("res://scripts/balance.gd")
const HeroPowers := preload("res://scripts/hero_powers.gd")
const HeroStatus := preload("res://scripts/hero_status.gd")
const HeroAttacks := preload("res://scripts/hero_attacks.gd")
const HeroTraits := preload("res://scripts/hero_traits.gd")

var world
var hp := B.HERO_HP
var max_hp := B.HERO_HP
var level := 1
var xp := 0.0
var damage := B.HERO_ARROW_DAMAGE
var cooldown := B.HERO_ARROW_COOLDOWN
var arrows := 1
var pierce := B.HERO_ARROW_PIERCE
var speed := B.HERO_SPEED
var radius := B.HERO_RADIUS

var target = null
var _move_dir := Vector2.ZERO
var _aim := Vector2.RIGHT
var _fire_t := 0.0
var _think_t := 0.0
var _pile_t := 0.0 # hasta recalcular el mejor montón de gemas
var _pile = null
var shield_t := 0.0 # invulnerable al llegar
var _flash := 0.0
var _hurt := 0.0
var _level_fx := 0.0
var _slash_cd := 0.0
var _slash_windup := 0.0
var _slash_dir := Vector2.RIGHT
var _slash_fx := 0.0
var _roll_t := 0.0
var _roll_cd := 0.0
var _roll_dir := Vector2.ZERO
var _aim_windup := 0.0
var _aim_locked := Vector2.RIGHT
var _horde_turn := false # cazando: el próximo disparo va a la horda
var _rng := RandomNumberGenerator.new()
var powers # hero_powers.gd: orbes, rayo, aura, nova, etc.
var status # hero_status.gd: sangrado, aturdimiento, lentitud
var attacks # hero_attacks.gd: ataques de jefe con zona roja
var traits # hero_traits.gd: trampas, escudo o parpadeo según el héroe
var damage_taken := {"jugador": 0.0, "horda": 0.0} # para los reportes de --sim
var title := "Arquero"
var article := "el"
var color := Color(0.3, 0.55, 1.0)
var speed_mult := 1.0 # del tipo de héroe
var damage_mult := 1.0
var fire_rate := 1.0
var table: Array = [] # poder que sube en cada nivel (índice 0 = nivel 2)
var was_low := false # para la Infamia: ya sumó por tenerlo con poca vida
enum Sight { FARM, HUNT, SEARCH }
var sight := Sight.FARM # te caza si te ve; si te pierde, te busca un rato
var _last_seen := Vector2.ZERO
var _search_t := 0.0
var _hunt_t := 0.0 # cuánto le queda cazándote si no te volvés a delatar
var suspicion := 0.0 # 0 a 100: a 100 te reconoce
var _gaze_t := 0.0
var fury := false # bajo HERO_FURY_HP: ataca más seguido
var _fury_run_t := 0.0


func rolling() -> bool:
	return _roll_t > 0.0


func pickup_radius() -> float:
	return B.HERO_PICKUP_RADIUS + level * B.HERO_PICKUP_PER_LEVEL


func slash_radius() -> float:
	return B.HERO_SLASH_RADIUS + level * B.HERO_SLASH_RADIUS_PER_LEVEL


func _nearest(list: Array, max_dist: float):
	var best = null
	var best_d := max_dist
	for n in list:
		var d := position.distance_to(n.position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _nearest_enemy(max_dist: float):
	var close = _nearest(world.minions, max_dist)
	var p = world.player
	var pd := position.distance_to(p.position)
	if pd < max_dist and (close == null or pd < position.distance_to(close.position)):
		return p
	return close


func _target_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == world.player:
		return not world.player_hidden()
	return world.minions.has(target)


## Ataques de jefe: no con escudo, en la carrera de la furia ni aturdido.
func can_boss_attack() -> bool:
	return shield_t <= 0.0 and _fury_run_t <= 0.0 and not status.stunned()


## Caballero: ¿el escudo cubre un golpe que viene desde "from"?
func blocks_from(from: Vector2) -> bool:
	return traits.blocks(from)


func ignores_stealth() -> bool:
	return false


func hunting_you() -> bool:
	return sight == Sight.HUNT


func _the_name() -> String:
	return "%s %s" % [article, title]


## "El Arquero", "La Maga".
func full_name() -> String:
	return "%s %s" % [article.capitalize(), title]


## "del Arquero", "de la Maga".
func of_name() -> String:
	return "del %s" % title if article == "el" else "de %s %s" % [article, title]
