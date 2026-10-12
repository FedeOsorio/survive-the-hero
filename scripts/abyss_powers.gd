extends Node2D
## Poderes del Abisal que no viven en class_abyss.gd (hijo de la clase, dibuja en el
## mundo): Ancla (agarra al héroe y lo deja quieto), Kraken (tentáculo gigante bajo
## el héroe), Remolino (las grietas te mandan cadáveres), Tinta (nube alrededor tuyo:
## el héroe dispara más lento), Surco (franja de la embestida que frena y lastima) y
## Ojo del abismo (cerca de una grieta, el héroe recibe más daño). Además, cada grieta
## tiene su tentáculo propio (siempre, escala con Azote).
## Cada uno corre si tenés rango (creep.pmult / creep.pcd).

const B := preload("res://scripts/balance.gd")

var abyss # class_abyss.gd
var _anchor_cd := B.ABYSS_ANCHOR_EVERY
var _anchors: Array = [] # {target, t}
var _kraken_cd := B.ABYSS_KRAKEN_FIRST
var _krakens: Array = [] # {pos, t}
var _ink_cd := B.ABYSS_INK_EVERY
var _ink_t := 0.0
var _furrow: Array = [] # {pos, t}
var _rift_hits: Array = [] # {from, to, t}: dibujo del tentáculo de grieta


func _ready() -> void:
	top_level = true
	z_index = 2


func _process(delta: float) -> void:
	var world = abyss.world
	if not world.running:
		return
	var creep = abyss.creep
	_rift_lashes(delta, creep)
	if creep.rank("ancla") > 0:
		_update_anchor(delta, creep)
	if creep.rank("kraken") > 0 or not _krakens.is_empty():
		_update_kraken(delta, creep)
	if creep.rank("remolino") > 0:
		_whirl(delta, creep, world)
	if creep.rank("tinta") > 0:
		_update_ink(delta, creep)
	if creep.rank("surco") > 0 or not _furrow.is_empty():
		_update_furrow(delta, creep)
	if creep.rank("ojo") > 0:
		for h in world.heroes.list:
			for r in abyss.rifts():
				if r.pos.distance_to(h.position) < B.ABYSS_EYE_RADIUS:
					h.status.expose(B.ABYSS_EYE_VULN * creep.pmult("ojo"))
					break
	queue_redraw()


func _update_anchor(delta: float, creep) -> void:
	for a in _anchors.duplicate():
		a.t -= delta
		if a.t <= 0.0 or not is_instance_valid(a.target):
			_anchors.erase(a)
		elif not abyss.is_paladin(a.target):
			a.target.status.slow(1.0) # quieto, pero puede seguir disparando
	_anchor_cd -= delta
	if _anchor_cd > 0.0:
		return
	var t = abyss.nearest_target(creep.position, B.ABYSS_ANCHOR_RANGE)
	if t == null:
		return
	_anchor_cd = B.ABYSS_ANCHOR_EVERY * creep.pcd("ancla")
	var time: float = B.ABYSS_ANCHOR_TIME * creep.pmult("ancla")
	_anchors.append({"target": t, "t": time})
	if abyss.is_paladin(t):
		t.confuse(time)


func _update_kraken(delta: float, creep) -> void:
	for k in _krakens.duplicate():
		k.t -= delta
		if k.t <= 0.0:
			_krakens.erase(k)
			for t in abyss.targets():
				if k.pos.distance_to(t.position) < B.ABYSS_KRAKEN_RADIUS + t.radius:
					abyss.hurt(t, creep.bite * B.ABYSS_KRAKEN_DAMAGE * creep.pmult("kraken"))
			abyss.world.fx.explosion(k.pos, B.ABYSS_KRAKEN_RADIUS, Color(0.25, 0.5, 0.6))
			abyss.world.shake()
	if creep.rank("kraken") == 0:
		return
	_kraken_cd -= delta
	if _kraken_cd > 0.0:
		return
	var t = abyss.nearest_target(creep.position, B.ABYSS_KRAKEN_RANGE)
	if t == null:
		return
	_kraken_cd = B.ABYSS_KRAKEN_EVERY * creep.pcd("kraken")
	_krakens.append({"pos": t.position, "t": B.ABYSS_KRAKEN_WARN})


## Tentáculo de grieta: le pega a lo más cercano a menos de ABYSS_RIFT_LASH_RANGE.
func _rift_lashes(delta: float, creep) -> void:
	for h in _rift_hits:
		h.t -= delta
	_rift_hits = _rift_hits.filter(func(h): return h.t > 0.0)
	for r in abyss.rifts():
		r.lash = r.get("lash", 0.0) - delta
		if r.lash > 0.0:
			continue
		var t = abyss.nearest_target(r.pos, B.ABYSS_RIFT_LASH_RANGE)
		if t == null:
			continue
		r.lash = B.ABYSS_RIFT_LASH_EVERY
		abyss.hurt(t, creep.bite * B.ABYSS_RIFT_LASH_DAMAGE * creep.pmult("azote"))
		_rift_hits.append({"from": r.pos, "to": t.position, "t": 0.25})


## Remolino: los cadáveres cerca de una grieta van hacia ella y, al llegar, te llegan a vos.
func _whirl(delta: float, creep, world) -> void:
	var reach: float = B.ABYSS_WHIRL_RADIUS * creep.pmult("remolino")
	for c in world.corpses:
		for r in abyss.rifts():
			var d: float = r.pos.distance_to(c.position)
			if d < reach:
				if d < B.ABYSS_RIFT_RADIUS * 0.5:
					c.position = creep.position # lo comés al toque
				else:
					c.position = c.position.move_toward(r.pos, B.ABYSS_WHIRL_PULL * delta)
				break


func _update_ink(delta: float, creep) -> void:
	if _ink_t > 0.0:
		_ink_t -= delta
		for h in abyss.world.heroes.list:
			if creep.position.distance_to(h.position) < B.ABYSS_INK_RADIUS + h.radius:
				h.status.ink()
		return
	_ink_cd -= delta
	var hero = abyss.world.hero
	if _ink_cd <= 0.0 and hero != null and creep.position.distance_to(hero.position) < B.ABYSS_INK_RADIUS * 2.5:
		_ink_cd = B.ABYSS_INK_EVERY * creep.pcd("tinta")
		_ink_t = B.ABYSS_INK_TIME * creep.pmult("tinta")


func _update_furrow(delta: float, creep) -> void:
	for f in _furrow:
		f.t -= delta
	_furrow = _furrow.filter(func(f): return f.t > 0.0)
	if creep.rank("surco") > 0 and creep.dashing():
		if _furrow.is_empty() or _furrow.back().pos.distance_to(creep.position) > B.ABYSS_FURROW_WIDTH * 0.5:
			_furrow.append({"pos": creep.position, "t": B.ABYSS_FURROW_TIME})
	if _furrow.is_empty():
		return
	for t in abyss.targets():
		for f in _furrow:
			if f.pos.distance_to(t.position) < B.ABYSS_FURROW_WIDTH + t.radius:
				abyss.slow(t, B.ABYSS_FURROW_SLOW)
				abyss.hurt(t, creep.bite * B.ABYSS_FURROW_DPS * creep.pmult("surco") * delta, true)
				break


func _draw() -> void:
	var creep = abyss.creep
	var t: float = abyss.world.elapsed
	for f in _furrow:
		draw_circle(f.pos, B.ABYSS_FURROW_WIDTH, Color(0.3, 0.1, 0.4, 0.35 * clampf(f.t / B.ABYSS_FURROW_TIME, 0.2, 1.0)))
	if _ink_t > 0.0:
		draw_circle(creep.position, B.ABYSS_INK_RADIUS, Color(0.05, 0.05, 0.08, 0.45))
		for i in 8:
			var a := TAU * i / 8.0 + t
			draw_circle(creep.position + Vector2.from_angle(a) * B.ABYSS_INK_RADIUS * 0.7, 18.0, Color(0.05, 0.05, 0.1, 0.3))
	for h in _rift_hits:
		var a: float = h.t / 0.25
		draw_line(h.from, h.to, Color(0.55, 0.2, 0.8, a), 8.0)
		draw_line(h.from, h.to, Color(0.9, 0.7, 1.0, a), 2.0)
	for k in _krakens:
		var p: float = 1.0 - k.t / B.ABYSS_KRAKEN_WARN
		draw_circle(k.pos, B.ABYSS_KRAKEN_RADIUS, Color(0.05, 0.1, 0.15, 0.2 + 0.4 * p))
		draw_arc(k.pos, B.ABYSS_KRAKEN_RADIUS * p, 0.0, TAU, 32, Color(0.3, 0.7, 0.8, 0.8), 3.0)
	for a in _anchors:
		if is_instance_valid(a.target):
			var tp: Vector2 = a.target.position
			for i in 3:
				var base: Vector2 = tp + Vector2.from_angle(TAU * i / 3.0 + 0.5) * 22.0
				draw_line(base, tp + Vector2(sin(t * 6.0 + i) * 4.0, 0.0), Color(0.4, 0.15, 0.55), 5.0)
	if creep.rank("ojo") > 0:
		for r in abyss.rifts():
			draw_arc(r.pos, B.ABYSS_EYE_RADIUS, 0.0, TAU, 40, Color(0.9, 0.3, 0.6, 0.15), 1.5)
			draw_circle(r.pos, 6.0, Color(0.95, 0.3, 0.6, 0.8))
