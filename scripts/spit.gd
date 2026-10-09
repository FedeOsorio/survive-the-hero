extends Node2D
## Proyectil de un creep (el escupitajo del jugador o el disparo de un arquero).
## Solo le hace daño al héroe.

const B := preload("res://scripts/balance.gd")

var world
var direction := Vector2.RIGHT
var damage := 1.0
var from_player := true
var dodge_roll := 0.0 # se sortea una vez: decide si el héroe intenta esquivarlo
var _travelled := 0.0


func _ready() -> void:
	z_index = 3
	dodge_roll = randf()


func _process(delta: float) -> void:
	if not world.running:
		return
	var step := B.SPIT_SPEED * delta
	position += direction * step
	_travelled += step
	if _travelled > B.SPIT_RANGE:
		world.remove_spit(self)
		return
	var hero = world.hero
	if position.distance_to(hero.position) < hero.radius + 5.0:
		hero.take_damage(damage, from_player)
		world.remove_spit(self)


func _draw() -> void:
	var c := Color(0.55, 0.95, 0.2) if from_player else Color(0.7, 0.5, 1.0)
	draw_circle(Vector2.ZERO, 5.0, c)
	draw_circle(-direction * 5.0, 3.0, Color(c, 0.5))
