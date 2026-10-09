extends Node2D
## Cadáver de un creep. El jugador lo absorbe al pasar por encima.

const B := preload("res://scripts/balance.gd")

var world
var value := 1.0
var heart := false # corazón de élite: da una mutación al comerlo
var holy := false # corazón celestial del Paladín: mutación y biomasa
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
	if holy:
		draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.95, 0.6, 0.3))
		draw_circle(Vector2(-3, -2), 4.5, Color(1.0, 0.9, 0.5))
		draw_circle(Vector2(3, -2), 4.5, Color(1.0, 0.9, 0.5))
		draw_colored_polygon(PackedVector2Array([Vector2(-7.5, -1), Vector2(7.5, -1), Vector2(0, 9)]), Color(1.0, 0.9, 0.5))
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(1.0, 1.0, 0.85, 0.9), 1.5)
		return
	if heart:
		draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.2, 0.3, 0.25))
		draw_circle(Vector2(-3, -2), 4.0, Color(1.0, 0.2, 0.3))
		draw_circle(Vector2(3, -2), 4.0, Color(1.0, 0.2, 0.3))
		draw_colored_polygon(PackedVector2Array([Vector2(-7, -1), Vector2(7, -1), Vector2(0, 8)]), Color(1.0, 0.2, 0.3))
		return
	var c := color.darkened(0.55)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, radius, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(Vector2(-3, -3), Vector2(3, 3), Color(0, 0, 0, 0.6), 1.5)
	draw_line(Vector2(3, -3), Vector2(-3, 3), Color(0, 0, 0, 0.6), 1.5)
