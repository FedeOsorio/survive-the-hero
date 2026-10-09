extends Node2D
## Proyectil de un creep (el escupitajo del jugador o el disparo de un arquero).
## Le hace daño al héroe; el del jugador también a los civiles.

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
		_land()
		return
	for hero in world.heroes.list:
		if not hero.rolling() and position.distance_to(hero.position) < hero.radius + 5.0:
			hero.take_damage(damage, from_player)
			_land()
			return
	if from_player:
		for pal in world.infamy.paladins:
			if position.distance_to(pal.position) < pal.radius + 5.0:
				pal.take_damage(damage)
				_land()
				return
		for c in world.civilians:
			if position.distance_to(c.position) < c.radius + 5.0:
				c.take_damage(damage)
				_land()
				return


## Termina el escupitajo; con Lluvia ácida deja un charco donde cae.
func _land() -> void:
	if from_player and world.player.rank("lluvia") > 0:
		world.spawn_puddle(position, world.player.bite * B.ACID_DPS_MULT)
	world.remove_spit(self)


func _draw() -> void:
	var c := Color(0.55, 0.95, 0.2) if from_player else Color(0.7, 0.5, 1.0)
	draw_circle(Vector2.ZERO, 5.0, c)
	draw_circle(-direction * 5.0, 3.0, Color(c, 0.5))
