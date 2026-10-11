extends Node2D
## Último Bastión: si matás a los tres héroes antes de amanecer, el cielo lo manda.
## 1 contra 1 dentro de una pared de luz. Solo usa ataques de jefe (hero_attacks.gd)
## en 3 fases (B.BASTION_PHASES); al cambiar de fase se arrodilla (recibe el doble)
## y suelta trozos de carne que te curan. No se cura nunca. Dibuja su barra de vida
## y el destello dorado de la entrada en una capa propia (no en el HUD).

const B := preload("res://scripts/balance.gd")
const HeroAttacks := preload("res://scripts/hero_attacks.gd")
const HeroStatus := preload("res://scripts/hero_status.gd")

var world
var hp := 1.0
var max_hp := 1.0
var level := 99 # para hero_attacks: tiene todos sus ataques
var radius := B.BASTION_RADIUS
var title := "Último Bastión"
var article := "el"
var color := Color(1.0, 0.92, 0.6)
var shield_t := B.BASTION_LANDING
var attacks
var status
var phase := 0
var wall_center := Vector2.ZERO
var _kneel_t := 0.0
var _flash := 0.0
var _meat: Array = [] # posiciones de los trozos de carne
var _vanish: Array = [] # {pos, t}: destellos de lo que desapareció al empezar
var _glow_t := B.BASTION_INTRO_GLOW
var _layer: CanvasLayer
var _overlay: Control


func _ready() -> void:
	z_index = 2
	attacks = HeroAttacks.new()
	attacks.hero = self
	attacks.world = world
	add_child(attacks)
	status = HeroStatus.new()
	status.hero = self
	status.world = world
	add_child(status)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_layer.add_child(_overlay)


## Se llama después de agregarlo al árbol, con la vida máxima del jugador y el centro de la pared.
func setup(player_max_hp: float, center: Vector2, vanished: Array) -> void:
	max_hp = player_max_hp * B.BASTION_HP_MULT
	hp = max_hp
	wall_center = center
	for p in vanished:
		_vanish.append({"pos": p, "t": 0.6})
	_set_phase(0)


func _set_phase(i: int) -> void:
	phase = i
	var cfg: Dictionary = B.BASTION_PHASES[i]
	attacks.attacks = cfg.attacks
	attacks.every = cfg.every
	attacks._t = cfg.every * 0.5


# --- API que usan hero_attacks.gd, el creep y sus proyectiles ------------------

func can_boss_attack() -> bool:
	return shield_t <= 0.0 and _kneel_t <= 0.0 and not status.stunned()


func hunting_you() -> bool:
	return true # 1 contra 1: siempre sabe dónde estás


func suspect(_amount: float) -> void:
	pass


func ignores_stealth() -> bool:
	return true # el camuflaje no sirve contra él


func rolling() -> bool:
	return false


func full_name() -> String:
	return "El Último Bastión"


func take_damage(amount: float, from_player: bool, melee := false, tick := false) -> void:
	if hp <= 0.0 or shield_t > 0.0 or not from_player:
		return
	if _kneel_t > 0.0:
		amount *= B.BASTION_KNEEL_DAMAGE_MULT
	status.log_damage(amount, melee)
	status.show_damage(amount, tick)
	hp -= amount
	if not tick:
		_flash = B.HERO_HIT_FLASH
	if hp <= 0.0:
		hp = 0.0
		world.on_bastion_killed()
		return
	var next := phase
	while next < B.BASTION_PHASES.size() - 1 and hp / max_hp <= B.BASTION_PHASES[next].above:
		next += 1
	if next != phase:
		_enrage(next)


## Cambio de fase: se arrodilla, cancela lo que estaba cargando y suelta carne.
func _enrage(i: int) -> void:
	_set_phase(i)
	attacks.cancel()
	_kneel_t = B.BASTION_KNEEL_TIME
	for k in B.BASTION_MEAT:
		var off := Vector2.from_angle(randf() * TAU) * B.BASTION_MEAT_SCATTER
		_meat.append(_inside_wall(position + off, B.BASTION_MEAT_RADIUS))
	world.hud.banner("El Bastión se enfurece")
	world.shake()


# --- Cada frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	_glow_t = maxf(_glow_t - delta, 0.0)
	for v in _vanish.duplicate():
		v.t -= delta
		if v.t <= 0.0:
			_vanish.erase(v)
	_overlay.queue_redraw()
	queue_redraw()
	if not world.running:
		return
	shield_t = maxf(shield_t - delta, 0.0)
	_kneel_t = maxf(_kneel_t - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	var p = world.player
	# la pared de luz te empuja hacia adentro (sin daño)
	p.position = _inside_wall(p.position, p.radius)
	for m in _meat.duplicate():
		if p.position.distance_to(m) < p.radius + B.BASTION_MEAT_RADIUS:
			_meat.erase(m)
			p.hp = minf(p.max_hp, p.hp + p.max_hp * B.BASTION_MEAT_HEAL)
	if shield_t > 0.0 or _kneel_t > 0.0 or attacks.busy() or status.stunned():
		position = _inside_wall(position, radius)
		return
	var to_p: Vector2 = p.position - position
	if to_p.length() > B.BASTION_CHASE_DIST:
		var spd: float = B.BASTION_SPEED * status.speed_mult()
		if phase == B.BASTION_PHASES.size() - 1:
			spd *= B.BASTION_LAST_PHASE_SPEED
		position += to_p.normalized() * spd * delta
	position = _inside_wall(position, radius)


func _inside_wall(at: Vector2, r: float) -> Vector2:
	var rel := at - wall_center
	var lim := B.BASTION_WALL_RADIUS - r
	if rel.length() > lim:
		at = wall_center + rel.normalized() * lim
	return at.clamp(Vector2(r, r), B.ARENA_SIZE - Vector2(r, r))


# --- Dibujo ------------------------------------------------------------------------

func _draw() -> void:
	# pared de luz
	var wc := to_local(wall_center)
	draw_arc(wc, B.BASTION_WALL_RADIUS, 0.0, TAU, 96, Color(1.0, 0.92, 0.55, 0.35), 18.0)
	draw_arc(wc, B.BASTION_WALL_RADIUS, 0.0, TAU, 96, Color(1.0, 0.97, 0.8, 0.9), 3.0)
	for v in _vanish:
		var k: float = 1.0 - v.t / 0.6
		draw_circle(to_local(v.pos), 6.0 + 18.0 * k, Color(1.0, 0.95, 0.7, 0.8 * (1.0 - k)))
	for m in _meat:
		var lp := to_local(m)
		draw_circle(lp, B.BASTION_MEAT_RADIUS, Color(0.55, 0.1, 0.1))
		draw_circle(lp, B.BASTION_MEAT_RADIUS * 0.6, Color(0.85, 0.3, 0.3))
	# cuerpo
	if shield_t > 0.0:
		# columna de luz mientras baja
		draw_rect(Rect2(Vector2(-radius, -700), Vector2(radius * 2.0, 700)), Color(1.0, 0.92, 0.5, 0.25 * shield_t / B.BASTION_LANDING))
		draw_circle(Vector2.ZERO, radius + 10.0, Color(1.0, 0.85, 0.3, 0.4))
	var body := Color.WHITE if _flash > 0.0 else color
	draw_circle(Vector2.ZERO, radius + 3.0, Color(0.85, 0.65, 0.15))
	draw_circle(Vector2.ZERO, radius, body)
	draw_circle(Vector2.ZERO, radius * 0.45, Color(1.0, 0.8, 0.25))
	if _kneel_t > 0.0:
		draw_arc(Vector2.ZERO, radius + 12.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.25, 0.8), 3.0)


func _draw_overlay() -> void:
	var size := _overlay.size
	if _glow_t > 0.0:
		_overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.9, 0.5, 0.45 * _glow_t / B.BASTION_INTRO_GLOW))
	if not world.running:
		return
	var font := ThemeDB.fallback_font
	var w := minf(600.0, size.x - 40.0)
	var r := Rect2(size.x * 0.5 - w * 0.5, 40.0, w, 18.0)
	_overlay.draw_rect(r.grow(2.0), Color(0.1, 0.08, 0.02, 0.9))
	_overlay.draw_rect(Rect2(r.position, Vector2(w * hp / max_hp, r.size.y)), Color(1.0, 0.82, 0.3))
	for cut in [0.66, 0.33]:
		_overlay.draw_line(Vector2(r.position.x + w * cut, r.position.y), Vector2(r.position.x + w * cut, r.end.y), Color(0.1, 0.08, 0.02), 2.0)
	_overlay.draw_string(font, Vector2(r.position.x, r.position.y - 6.0), "Último Bastión", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.95, 0.75))
	_overlay.draw_string(font, Vector2(r.position.x, r.position.y - 6.0), "%d%%" % ceili(100.0 * hp / max_hp), HORIZONTAL_ALIGNMENT_RIGHT, w, 16, Color(1.0, 0.95, 0.75))
