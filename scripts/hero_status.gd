extends Node2D
## Estados del héroe (hijo del nodo del héroe): sangrado, aturdimiento,
## lentitud de los charcos ácidos y el registro del daño que le hace el jugador
## (cuerpo a cuerpo o a distancia).

const B := preload("res://scripts/balance.gd")

var hero
var world
var _bleeds: Array = [] # {dps, t}
var _stun_t := 0.0
var _stun_immune := 0.0
var _slow_t := 0.0
var _log: Array = [] # {time, amount, melee}
var _drip := 0.0
var _numbers: Array = [] # {amount, t, big}
var _tick_sum := 0.0
var _tick_t := 0.0


func _ready() -> void:
	z_index = 1


func stunned() -> bool:
	return _stun_t > 0.0


func speed_mult() -> float:
	return 1.0 - B.ACID_SLOW if _slow_t > 0.0 else 1.0


## Los charcos lo llaman cada frame mientras está adentro.
func slow() -> void:
	_slow_t = 0.1


func stun(time: float) -> void:
	if _stun_immune > 0.0:
		return
	_stun_t = time
	_stun_immune = time + B.HERO_STUN_IMMUNE


func bleed(total: float) -> void:
	if _bleeds.size() >= B.BLEED_MAX_STACKS:
		_bleeds.pop_front()
	_bleeds.append({"dps": total / B.BLEED_TIME, "t": B.BLEED_TIME})


func bleeding() -> bool:
	return not _bleeds.is_empty()


func log_damage(amount: float, melee: bool) -> void:
	# junta los golpes seguidos del mismo tipo (el sangrado pega cada frame)
	if not _log.is_empty():
		var last: Dictionary = _log[-1]
		if last.melee == melee and world.elapsed - last.time < 0.5:
			last.amount += amount
			return
	_log.append({"time": world.elapsed, "amount": amount, "melee": melee})


## Número flotante del daño del jugador. Lo que pega cada frame (charcos,
## sangrado) se suma y se muestra uno cada DMG_TICK_EVERY.
func show_damage(amount: float, tick: bool) -> void:
	if tick:
		_tick_sum += amount
		return
	_add_number(amount)


func _add_number(amount: float) -> void:
	_numbers.append({"amount": amount, "t": B.DMG_NUMBER_TIME, "big": amount > hero.max_hp * B.DMG_NUMBER_BIG})


## Parte del daño reciente del jugador que fue cuerpo a cuerpo (-1 si no hubo daño).
func melee_share() -> float:
	var melee := 0.0
	var total := 0.0
	for e in _log:
		total += e.amount
		if e.melee:
			melee += e.amount
	return melee / total if total > 0.0 else -1.0


func _process(delta: float) -> void:
	if not world.running:
		return
	while not _log.is_empty() and world.elapsed - _log[0].time > B.ADAPT_WINDOW:
		_log.pop_front()
	_stun_t = maxf(_stun_t - delta, 0.0)
	_stun_immune = maxf(_stun_immune - delta, 0.0)
	_slow_t = maxf(_slow_t - delta, 0.0)
	for b in _bleeds.duplicate():
		b.t -= delta
		hero.take_damage(b.dps * delta, true, true, true)
		if b.t <= 0.0:
			_bleeds.erase(b)
	_tick_t += delta
	if _tick_t >= B.DMG_TICK_EVERY:
		_tick_t = 0.0
		if _tick_sum >= 1.0:
			_add_number(_tick_sum)
			_tick_sum = 0.0
	for n in _numbers.duplicate():
		n.t -= delta
		if n.t <= 0.0:
			_numbers.erase(n)
	_drip = fmod(_drip + delta, 0.6)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for n in _numbers:
		var k: float = 1.0 - n.t / B.DMG_NUMBER_TIME
		var pos := Vector2(-8.0, -28.0 - B.DMG_NUMBER_RISE * k)
		var col := Color(1.0, 0.85, 0.2, 1.0 - k * 0.6) if n.big else Color(1, 1, 1, 1.0 - k * 0.6)
		draw_string(font, pos, str(roundi(n.amount)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if n.big else 14, col)
	if bleeding():
		for i in _bleeds.size():
			var x := -8.0 + i * 8.0
			draw_circle(Vector2(x, -22.0 + _drip * 20.0), 2.5, Color(0.85, 0.05, 0.05))
	if _slow_t > 0.0:
		draw_arc(Vector2.ZERO, hero.radius + 4.0, 0.0, TAU, 20, Color(0.55, 0.95, 0.2, 0.6), 2.0)
	if stunned():
		for i in 3:
			var a: float = world.elapsed * 6.0 + TAU * i / 3.0
			draw_circle(Vector2(cos(a) * 12.0, -24.0 + sin(a) * 4.0), 2.5, Color(1, 1, 0.4))
