extends Node2D
## Charco de Lluvia ácida: daña y frena al héroe mientras está adentro.

const B := preload("res://scripts/balance.gd")

var world
var dps := 1.0
var t := B.ACID_TIME


func _ready() -> void:
	z_index = 0


func _process(delta: float) -> void:
	if not world.running:
		return
	t -= delta
	if t <= 0.0:
		world.remove_puddle(self)
		return
	for hero in world.heroes.list.duplicate():
		if position.distance_to(hero.position) < B.ACID_RADIUS + hero.radius:
			hero.take_damage(dps * delta, true, false, true)
			hero.status.slow()
	for h in world.infamy.paladins:
		if position.distance_to(h.position) < B.ACID_RADIUS + h.radius:
			h.take_damage(dps * delta)
	queue_redraw()


func _draw() -> void:
	var a := clampf(t / B.ACID_TIME, 0.2, 1.0)
	draw_circle(Vector2.ZERO, B.ACID_RADIUS, Color(0.55, 0.95, 0.2, 0.22 * a))
	draw_arc(Vector2.ZERO, B.ACID_RADIUS, 0.0, TAU, 28, Color(0.6, 1.0, 0.25, 0.5 * a), 1.5)
