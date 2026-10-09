extends Node2D
## Cadáver de un creep. El jugador lo absorbe al pasar por encima.

const B := preload("res://scripts/balance.gd")

var world
var value := 1.0
var radius := 8.0
var color := Color.GRAY
var _age := 0.0


func _ready() -> void:
	z_index = -1


func _process(delta: float) -> void:
	if not world.running:
		return
	_age += delta
	if _age >= B.CORPSE_LIFETIME:
		world.remove_corpse(self)
		return
	var left := B.CORPSE_LIFETIME - _age
	modulate.a = clampf(left / 5.0, 0.2, 1.0)


func _draw() -> void:
	var c := color.darkened(0.55)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, radius, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(Vector2(-3, -3), Vector2(3, 3), Color(0, 0, 0, 0.6), 1.5)
	draw_line(Vector2(3, -3), Vector2(-3, 3), Color(0, 0, 0, 0.6), 1.5)
