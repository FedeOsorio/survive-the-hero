extends Node2D
## Gema de experiencia. El héroe la junta para subir de nivel;
## si el jugador la come primero, se la roba.

const B := preload("res://scripts/balance.gd")

var world
var xp := 1.0
var _t := 0.0
var _age := 0.0


func _ready() -> void:
	z_index = 0
	_t = randf() * TAU


func _process(delta: float) -> void:
	if not world.running:
		return
	_t += delta * 4.0
	_age += delta
	if _age >= B.GEM_LIFETIME:
		world.remove_gem(self)
		return
	queue_redraw()


func _draw() -> void:
	var y := sin(_t) * 1.5
	var s := 4.0 + minf(xp, 5.0)
	var pts := PackedVector2Array([Vector2(0, -s + y), Vector2(s * 0.6, y), Vector2(0, s + y), Vector2(-s * 0.6, y)])
	draw_colored_polygon(pts, Color(0.35, 0.85, 1.0))
