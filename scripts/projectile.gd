extends Node2D
## Flecha del héroe. Le pega al primer creep que toca, incluido el jugador.

const B := preload("res://scripts/balance.gd")

var world
var direction := Vector2.RIGHT
var damage := 10.0
var pierce := 0
var _hit := []
var _travelled := 0.0


func _ready() -> void:
	z_index = 3
	rotation = direction.angle()


func _process(delta: float) -> void:
	if not world.running:
		return
	var step := B.HERO_ARROW_SPEED * delta
	position += direction * step
	_travelled += step
	if _travelled > B.HERO_RANGE * 1.4:
		queue_free()
		return

	var player = world.player
	if not player.invulnerable and player._dash_t <= 0.0 and position.distance_to(player.position) < player.radius + 3.0:
		player.take_damage(damage)
		queue_free()
		return
	for m in world.minions_near(position):
		if _hit.has(m):
			continue
		if position.distance_to(m.position) < m.radius + 3.0:
			_hit.append(m)
			m.take_damage(damage)
			if pierce <= 0:
				queue_free()
				return
			pierce -= 1


func _draw() -> void:
	draw_line(Vector2(-8, 0), Vector2(4, 0), Color(1.0, 0.9, 0.4), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(3, -3), Vector2(3, 3)]), Color(1.0, 0.95, 0.6))
