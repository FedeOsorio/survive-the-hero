extends Node2D
## Poderes de cuerpo del Engendro (hijo de creep_abilities.gd, dibuja en el mundo):
## Espinas (la embestida lastima lo que tocás), Coraza viva (onda al terminar la
## embestida) y Pegote (charcos que frenan). Cada uno corre si tenés rango.

const B := preload("res://scripts/balance.gd")

var abilities # creep_abilities.gd
var _goo: Array = [] # {pos, t}
var _goo_cd := B.GOO_EVERY
var _thorn_victims: Array = []
var _was_dashing := false
var _wave_fx := 0.0


func _ready() -> void:
	top_level = true
	z_index = 3


func _process(delta: float) -> void:
	if not abilities.world.running:
		return
	_update_goo(delta)
	_wave_fx = maxf(_wave_fx - delta, 0.0)
	_thorns()
	queue_redraw()


# --- Embestida: Espinas y Coraza viva --------------------------------------------

## Espinas: durante la embestida, cada cosa que tocás recibe daño una vez.
## Coraza viva: al terminar la embestida sale la onda.
func _thorns() -> void:
	var dashing: bool = abilities.creep.dashing()
	if dashing and not _was_dashing:
		_thorn_victims.clear()
	if _was_dashing and not dashing and abilities.creep.rank("coraza") > 0:
		_shell_wave()
	_was_dashing = dashing
	if not dashing or abilities.creep.rank("espinas") == 0:
		return
	var dmg: float = abilities.creep.bite * B.THORNS_DAMAGE * abilities.creep.pmult("espinas")
	for v in abilities._targets() + abilities.world.civilians:
		if not _thorn_victims.has(v) and abilities.creep.position.distance_to(v.position) <= abilities.creep.radius + v.radius:
			_thorn_victims.append(v)
			if v in abilities.world.civilians:
				v.take_damage(dmg)
			else:
				abilities._hurt(v, dmg)


## Coraza viva: daña, empuja y aturde al héroe; empuja a la horda.
func _shell_wave() -> void:
	_wave_fx = 0.25
	var pos: Vector2 = abilities.creep.position
	for hero in abilities.world.heroes.targets():
		var to_h: Vector2 = hero.position - pos
		if to_h.length() < B.SHELL_WAVE_RADIUS + hero.radius and not hero.rolling():
			hero.take_damage(abilities.creep.bite * B.SHELL_WAVE_DAMAGE * abilities.creep.pmult("coraza"), true, true)
			abilities.world.shake()
			hero.position = (hero.position + to_h.normalized() * B.SHELL_WAVE_PUSH).clamp(Vector2(20, 20), B.ARENA_SIZE - Vector2(20, 20))
			hero.status.stun(B.HERO_STUN_TIME)
	for h in abilities.world.infamy.paladins:
		if pos.distance_to(h.position) < B.SHELL_WAVE_RADIUS + h.radius:
			h.take_damage(abilities.creep.bite * B.SHELL_WAVE_DAMAGE * abilities.creep.pmult("coraza"))
	for m in abilities.world.minions_near(pos):
		var to_m: Vector2 = m.position - pos
		if to_m.length() < B.SHELL_WAVE_RADIUS and to_m.length() > 0.01:
			m.position += to_m.normalized() * B.SHELL_WAVE_MINION_PUSH


# --- Pegote ---------------------------------------------------------------------

## Pegote: un charco cada GOO_EVERY que frena a los héroes que lo pisan.
func _update_goo(delta: float) -> void:
	if abilities.creep.rank("pegote") > 0:
		_goo_cd -= delta
		if _goo_cd <= 0.0:
			_goo_cd = B.GOO_EVERY * abilities.creep.pcd("pegote")
			_goo.append({"pos": abilities.creep.position, "t": B.GOO_TIME})
	var slow: float = minf(B.GOO_SLOW * abilities.creep.pmult("pegote"), 0.6)
	for g in _goo.duplicate():
		g.t -= delta
		if g.t <= 0.0:
			_goo.erase(g)
			continue
		for h in abilities.world.heroes.targets():
			if g.pos.distance_to(h.position) < B.GOO_RADIUS + h.radius:
				h.status.slow(slow)


func _draw() -> void:
	if _wave_fx > 0.0:
		draw_arc(abilities.creep.position, B.SHELL_WAVE_RADIUS * (1.0 - _wave_fx * 2.0), 0.0, TAU, 32, Color(0.9, 0.85, 0.6, 0.9), 5.0)
	for g in _goo:
		var a := clampf(g.t / B.GOO_TIME, 0.2, 1.0)
		draw_circle(g.pos, B.GOO_RADIUS, Color(0.85, 0.75, 0.3, 0.22 * a))
		draw_arc(g.pos, B.GOO_RADIUS, 0.0, TAU, 28, Color(0.95, 0.85, 0.35, 0.5 * a), 1.5)
