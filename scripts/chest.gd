extends Node2D
## Cofre en disputa. Se abre quedándose encima un segundo sin recibir daño.
## Si lo abre el héroe, sube un nivel y se cura; si lo abrís vos, mutación gratis.

const B := preload("res://scripts/balance.gd")

var world
var life := B.CHEST_LIFETIME
var _hero_prog := 0.0
var _creep_prog := 0.0
var _hero_hp := 0.0
var _creep_hp := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	if not world.running:
		return
	life -= delta
	if life <= 0.0:
		world.events.remove_chest()
		return
	var hero = world.hero
	var player = world.player
	_hero_prog = _progress(hero, _hero_prog, _hero_hp, delta)
	_creep_prog = _progress(player, _creep_prog, _creep_hp, delta)
	_hero_hp = hero.hp
	_creep_hp = player.hp
	if _creep_prog >= B.CHEST_OPEN_TIME:
		world.events.remove_chest()
		world.add_threat(B.CHEST_THREAT)
		world.hud.banner("¡Abriste el cofre! Mutación gratis")
		player.grant_mutation()
	elif _hero_prog >= B.CHEST_OPEN_TIME:
		world.events.remove_chest()
		hero._level_up()
		hero.hp = minf(hero.max_hp, hero.hp + hero.max_hp * B.CHEST_HERO_HEAL)
		world.hud.banner("El héroe abrió el cofre y subió de nivel")
	queue_redraw()


## Avanza mientras esté encima; recibir daño o salirse lo vuelve a 0.
func _progress(who, prog: float, last_hp: float, delta: float) -> float:
	if position.distance_to(who.position) > B.CHEST_OPEN_RADIUS:
		return 0.0
	if who.hp < last_hp - 0.01:
		return 0.0
	return prog + delta


func _draw() -> void:
	var blink := 1.0 if life > 5.0 or fmod(life, 0.4) > 0.2 else 0.4
	draw_rect(Rect2(-12, -9, 24, 18), Color(0.45, 0.28, 0.1, blink))
	draw_rect(Rect2(-12, -9, 24, 6), Color(0.85, 0.65, 0.2, blink))
	draw_rect(Rect2(-3, -5, 6, 6), Color(1, 0.9, 0.4, blink))
	draw_arc(Vector2.ZERO, B.CHEST_OPEN_RADIUS, 0.0, TAU, 28, Color(1, 0.85, 0.3, 0.3), 1.5)
	if _hero_prog > 0.0:
		draw_rect(Rect2(-16, -20, 32 * _hero_prog / B.CHEST_OPEN_TIME, 4), Color(0.4, 0.65, 1.0))
	if _creep_prog > 0.0:
		draw_rect(Rect2(-16, -26, 32 * _creep_prog / B.CHEST_OPEN_TIME, 4), Color(0.45, 0.95, 0.4))
