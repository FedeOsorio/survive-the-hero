extends Node2D
## Escupitajo ácido del creep. Solo le hace daño al héroe.

const B := preload("res://scripts/balance.gd")

var world
var direction := Vector2.RIGHT
var damage := 1.0
var _travelled := 0.0


func _ready() -> void:
	z_index = 3


func _process(delta: float) -> void:
	if not world.running:
		return
	var step := B.SPIT_SPEED * delta
	position += direction * step
	_travelled += step
	if _travelled > B.SPIT_RANGE:
		queue_free()
		return
	var hero = world.hero
	if position.distance_to(hero.position) < hero.radius + 5.0:
		hero.take_damage(damage, true)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.55, 0.95, 0.2))
	draw_circle(-direction * 5.0, 3.0, Color(0.55, 0.95, 0.2, 0.5))
