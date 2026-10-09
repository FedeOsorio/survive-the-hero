extends Node2D
## Fondo de la arena: piso con grilla y borde.

const B := preload("res://scripts/balance.gd")


func _ready() -> void:
	z_index = -10


func _draw() -> void:
	var size := B.ARENA_SIZE
	draw_rect(Rect2(Vector2(-2000, -2000), size + Vector2(4000, 4000)), Color(0.05, 0.04, 0.06))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.12, 0.15))
	var line := Color(0.17, 0.16, 0.2)
	var step := 100.0
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
		x += step
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += step
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.2, 0.25), false, 6.0)
