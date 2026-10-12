extends Node2D
## Furia propia de cada héroe (hijo del nodo del héroe). Se suma a la furia común
## (hero_combat._enrage) y vale desde que se enfurece (también durante la carrera) hasta que muere:
## Arquero: dispara el doble de rápido, se cura por cada creep que mata y deja estela amarilla.
## Caballero: sus golpes cuerpo a cuerpo (tajo y Tajo giratorio) le roban vida.
## Maga: escudo de maná que absorbe daño y no vuelve, y hechizos extra (rayo, bola de fuego, hielo).

const B := preload("res://scripts/balance.gd")

var hero
var world
var kind := "" # "Arquero", "Caballero" o "Maga"
var mana := 0.0
var _mana_max := 0.0
var _started := false
var _spell_t := 0.0
var _trail: Array = [] # {pos, t}
var _trail_t := 0.0
var _shatter := {} # {pos, t}: el escudo de maná se rompió


func _ready() -> void:
	z_as_relative = false
	z_index = 0


func active() -> bool:
	return hero.fury


# --- Arquero -----------------------------------------------------------------------

func fire_cooldown(base: float) -> float:
	if kind == "Arquero" and active():
		return maxf(base * B.HERO_FURY_ARCHER_FIRE_MULT, B.HERO_FURY_ARCHER_MIN_COOLDOWN)
	return base


## Una flecha o un tajo suyo mató a un creep.
func on_kill() -> void:
	if kind == "Arquero" and active():
		hero.hp = minf(hero.max_hp, hero.hp + B.HERO_FURY_ARCHER_HEAL_PER_KILL)


# --- Caballero ---------------------------------------------------------------------

## Daño que acaba de hacer cuerpo a cuerpo (a vos y a la horda).
func on_melee_damage(amount: float) -> void:
	if kind != "Caballero" or not active() or amount <= 0.0:
		return
	var before: float = hero.hp
	hero.hp = minf(hero.max_hp, hero.hp + amount * B.HERO_FURY_KNIGHT_LIFESTEAL)
	if hero.hp > before:
		world.fx.heal_number(hero.position, hero.hp - before)


# --- Maga --------------------------------------------------------------------------

## El escudo de maná se come el daño antes que la vida. Devuelve lo que pasa.
func absorb(amount: float) -> float:
	if mana <= 0.0:
		return amount
	var take := minf(mana, amount)
	mana -= take
	if mana <= 0.0:
		mana = 0.0
		_shatter = {"pos": hero.position, "t": 0.5}
		world.shake()
	return amount - take


func _cast() -> void:
	var p = world.player
	var aim = null
	if hero.hunting_you() and not world.player_hidden(hero):
		aim = p.position
	else:
		var close = hero._nearest(world.minions_near(hero.position), B.BOLT_RANGE)
		if close != null:
			aim = close.position
	var pick := randi_range(0, 2)
	if pick == 2 or aim == null:
		hero.attacks.spawn_zone(B.HERO_FURY_MAGE_ICE, hero.position)
	elif pick == 1:
		hero.attacks.spawn_zone(B.HERO_FURY_MAGE_FIREBALL, aim)
	else:
		hero.powers.cast_bolt(aim)


# --- Cada frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not world.running:
		return
	if not _shatter.is_empty():
		_shatter.t -= delta
		if _shatter.t <= 0.0:
			_shatter = {}
	for tr in _trail.duplicate():
		tr.t -= delta
		if tr.t <= 0.0:
			_trail.erase(tr)
	queue_redraw()
	if not active():
		return
	if not _started:
		_started = true
		if kind == "Maga":
			_mana_max = hero.max_hp * B.HERO_FURY_MAGE_SHIELD
			mana = _mana_max
			_spell_t = B.HERO_FURY_MAGE_SPELL_EVERY
	match kind:
		"Arquero":
			_trail_t -= delta
			if _trail_t <= 0.0:
				_trail_t = 0.04
				_trail.append({"pos": hero.position, "t": 0.35})
		"Maga":
			_spell_t -= delta
			if _spell_t <= 0.0 and not hero.status.stunned():
				_spell_t = B.HERO_FURY_MAGE_SPELL_EVERY
				_cast()


func _draw() -> void:
	for tr in _trail:
		var k: float = tr.t / 0.35
		draw_circle(to_local(tr.pos), hero.radius * (0.4 + 0.5 * k), Color(1.0, 0.9, 0.3, 0.45 * k))
	if mana > 0.0:
		var c := to_local(hero.position)
		var k: float = mana / _mana_max
		draw_circle(c, hero.radius + 9.0, Color(0.4, 0.65, 1.0, 0.12 + 0.12 * k))
		draw_arc(c, hero.radius + 9.0, 0.0, TAU, 28, Color(0.55, 0.8, 1.0, 0.4 + 0.5 * k), 2.5)
	if not _shatter.is_empty():
		# vidrio azul que vuela
		var c := to_local(_shatter.pos)
		var k: float = 1.0 - _shatter.t / 0.5
		for i in 10:
			var dir := Vector2.from_angle(TAU * i / 10.0 + 0.3)
			var at: Vector2 = c + dir * (hero.radius + 8.0 + 50.0 * k)
			draw_line(at, at + dir.rotated(0.8) * 7.0, Color(0.6, 0.85, 1.0, 1.0 - k), 2.5)
