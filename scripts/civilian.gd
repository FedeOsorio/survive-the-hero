extends Node2D
## Civil que deambula por el mapa. Huye del creep; comerlo da mucha biomasa.
## Al empezar a huir grita y atrae al héroe, que lo mata sin dejar comida.

const B := preload("res://scripts/balance.gd")

var world
var hp := B.CIVILIAN_HP
var radius := 7.0
var _wander := Vector2.ZERO
var _wander_t := 0.0
var _flash := 0.0
var _fleeing := false
var _scream_cd := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	if not world.running:
		return
	var away: Vector2 = position - world.player.position
	var d := away.length()
	var dir := Vector2.ZERO
	var spd := B.CIVILIAN_SPEED
	_scream_cd = maxf(_scream_cd - delta, 0.0)
	var flee := d < B.CIVILIAN_FLEE_RADIUS and d > 0.01
	if flee and not _fleeing and _scream_cd <= 0.0:
		_scream_cd = B.CIVILIAN_SCREAM_COOLDOWN
		world.raise_alarm(position)
	_fleeing = flee
	var dodge := _dodge_dir()
	if flee:
		dir = away / d
	elif dodge != Vector2.ZERO:
		# esquiva a la horda solo para que se vea: se corre al costado
		dir = dodge
		spd *= B.CIVILIAN_DODGE_SPEED
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


## Si un compañero de la horda está muy cerca, devuelve un paso al costado.
func _dodge_dir() -> Vector2:
	for m in world.minions_near(position):
		var away: Vector2 = position - m.position
		var d := away.length()
		if d < B.CIVILIAN_DODGE_RADIUS and d > 0.01:
			var side := away.orthogonal() / d
			return side if side.dot(_wander) >= 0.0 else -side
	return Vector2.ZERO


func take_damage(amount: float, by_hero := false) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash = 0.08
	if hp <= 0.0:
		world.on_civilian_killed(self, by_hero)


func _draw() -> void:
	var skin := Color.WHITE if _flash > 0.0 else Color(0.95, 0.8, 0.6)
	draw_rect(Rect2(-4, -2, 8, 9), Color(0.85, 0.75, 0.3))
	draw_circle(Vector2(0, -5), 4.0, skin)
