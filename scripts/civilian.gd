extends Node2D
## Civil que deambula por el mapa. Huye del creep; comerlo da mucha biomasa.
## El héroe y la horda lo ignoran.

const B := preload("res://scripts/balance.gd")

var world
var hp := B.CIVILIAN_HP
var radius := 7.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _flash := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	if not world.running:
		return
	var away: Vector2 = position - world.player.position
	var d := away.length()
	var dir := Vector2.ZERO
	var spd := B.CIVILIAN_SPEED
	if d < B.CIVILIAN_FLEE_RADIUS and d > 0.01:
		dir = away / d
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.5, 3.5)
			_wander = Vector2.from_angle(randf() * TAU) if randf() < 0.7 else Vector2.ZERO
		dir = _wander
		spd *= 0.35
	position += dir * spd * delta
	position = position.clamp(Vector2(radius, radius), B.ARENA_SIZE - Vector2(radius, radius))
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func take_damage(amount: float) -> void:
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		world.on_civilian_killed(self)


func _draw() -> void:
	var skin := Color.WHITE if _flash > 0.0 else Color(0.95, 0.8, 0.6)
	draw_rect(Rect2(-4, -2, 8, 9), Color(0.85, 0.75, 0.3))
	draw_circle(Vector2(0, -5), 4.0, skin)
