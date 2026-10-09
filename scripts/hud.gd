extends CanvasLayer
## Interfaz: vida, biomasa, nivel, reloj, amenaza, flecha hacia el héroe,
## elección de mutaciones y pantalla final. Corre aunque el juego esté en pausa.

const B := preload("res://scripts/balance.gd")
const Mutations := preload("res://scripts/mutations.gd")

var world
var _view: Control
var _banner_text := ""
var _banner_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_hud)
	add_child(_view)


func banner(text: String) -> void:
	_banner_text = text
	_banner_t = 3.0


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	var p = world.player
	if not p.pending_choices.is_empty():
		for i in 3:
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				p.choose_mutation(i)
				break
	_banner_t = maxf(_banner_t - delta, 0.0)
	_view.queue_redraw()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var size := _view.size
	var p = world.player
	var h = world.hero

	# Creep: arriba a la izquierda
	_text(font, Vector2(20, 30), "%s (etapa %d)" % [p.stage_name(), p.stage + 1], 20, p.color)
	_bar(Rect2(20, 40, 260, 14), p.hp / p.max_hp, Color(0.35, 0.85, 0.35), "Vida %d/%d" % [int(p.hp), int(p.max_hp)])
	_bar(Rect2(20, 60, 260, 10), p.mut_xp / p.mut_xp_needed(), Color(0.3, 0.75, 1.0), "")
	_text(font, Vector2(286, 70), "Nv %d" % p.level, 13, Color(0.6, 0.85, 1.0))
	var cost: float = p.evolve_cost()
	if cost > 0.0:
		_bar(Rect2(20, 76, 260, 14), p.biomass / cost, Color(0.75, 0.45, 0.9), "Evolución %d/%d" % [int(p.biomass), int(cost)])
		if p.can_evolve():
			_text(font, Vector2(20, 112), "¡Pulsá E para evolucionar!", 18, Color(1, 0.9, 0.3))
	else:
		_text(font, Vector2(20, 88), "Forma final", 14, Color(0.9, 0.8, 0.8))
	var st := "Camuflaje (Q): listo" if p.stealth_cd <= 0.0 else "Camuflaje (Q): %ds" % int(ceil(p.stealth_cd))
	_text(font, Vector2(20, 180), st, 14, Color(0.6, 0.9, 0.7) if p.stealth_cd <= 0.0 else Color(0.6, 0.6, 0.65))
	if p.hunger() > 1.0:
		_text(font, Vector2(20, 158), "Hambre x%.2f" % p.hunger(), 16, Color(0.9, 0.4, 0.4))
	if p.combo > 1.0:
		_text(font, Vector2(20, 136), "Combo x%.2f" % p.combo, 18, Color(1, 0.55, 0.3))

	# Reloj: arriba al centro
	var t := int(world.elapsed)
	_text_centered(font, Vector2(size.x * 0.5, 34), "%02d:%02d" % [t / 60, t % 60], 28, Color.WHITE)
	if world.detected:
		_text_centered(font, Vector2(size.x * 0.5, 60), "TE DETECTÓ", 16, Color(1, 0.3, 0.3))
	else:
		_bar(Rect2(size.x * 0.5 - 100, 46, 200, 10), world.threat / B.DETECTION_THRESHOLD, Color(1, 0.6, 0.2), "")
		_text_centered(font, Vector2(size.x * 0.5, 72), "Amenaza", 12, Color(0.9, 0.8, 0.7))

	# Héroe: arriba a la derecha
	_text(font, Vector2(size.x - 280, 30), "Héroe nivel %d" % h.level, 20, Color(0.5, 0.7, 1.0))
	_bar(Rect2(size.x - 280, 40, 260, 14), h.hp / h.max_hp, Color(0.85, 0.25, 0.25), "Vida %d/%d" % [int(h.hp), int(h.max_hp)])
	var y := 74.0
	for id in h.powers.ranks:
		_text(font, Vector2(size.x - 280, y), "%s %d" % [h.powers.LIST[id].name, h.powers.ranks[id]], 13, Color(1.0, 0.85, 0.5))
		y += 16.0

	_hero_pointer(h)

	_text_centered(font, Vector2(size.x * 0.5, size.y - 16),
		"WASD mover · Espacio embestida · Q camuflaje · E evolucionar · R reiniciar  (mordida y escupitajo son automáticos)", 13, Color(0.7, 0.7, 0.75))

	if _banner_t > 0.0:
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.3), _banner_text, 26, Color(1, 1, 1, minf(_banner_t, 1.0)))

	if not p.pending_choices.is_empty():
		_draw_choices(font, p)

	if not world.running:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		var title := "¡GANASTE!" if world.won else "PERDISTE"
		var col := Color(0.4, 1, 0.5) if world.won else Color(1, 0.35, 0.3)
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.42), title, 56, col)
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.52), world.end_reason, 22, Color.WHITE)
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.6), "R para jugar de nuevo", 18, Color(0.8, 0.8, 0.8))


func _draw_choices(font: Font, p) -> void:
	var size := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	_text_centered(font, Vector2(size.x * 0.5, size.y * 0.25), "¡Mutación! Elegí una (1, 2, 3)", 30, Color(0.6, 0.9, 1.0))
	var w := 300.0
	var gap := 24.0
	var n: int = p.pending_choices.size()
	var x0 := size.x * 0.5 - (w * n + gap * (n - 1)) * 0.5
	for i in n:
		var id: String = p.pending_choices[i]
		var m: Dictionary = Mutations.LIST[id]
		var r := Rect2(x0 + i * (w + gap), size.y * 0.33, w, 170)
		_view.draw_rect(r, Color(0.12, 0.1, 0.16, 0.95))
		_view.draw_rect(r, Color(0.6, 0.9, 1.0, 0.8), false, 2.0)
		_text(font, r.position + Vector2(14, 30), "%d. %s" % [i + 1, m.name], 20, Color.WHITE)
		_text(font, r.position + Vector2(14, 56), "Rango %d/%d" % [p.rank(id) + 1, m.max], 13, Color(0.7, 0.7, 0.8))
		_view.draw_multiline_string(font, r.position + Vector2(14, 86), m.desc, HORIZONTAL_ALIGNMENT_LEFT, w - 28, 16, -1, Color(0.9, 0.9, 0.95))


func _hero_pointer(h) -> void:
	var screen_pos: Vector2 = _view.get_viewport().get_canvas_transform() * h.global_position
	var rect := Rect2(Vector2.ZERO, _view.size).grow(-30)
	if rect.has_point(screen_pos):
		return
	var center := _view.size * 0.5
	var dir := (screen_pos - center).normalized()
	var edge := Vector2(clampf(screen_pos.x, rect.position.x, rect.end.x), clampf(screen_pos.y, rect.position.y, rect.end.y))
	var pts := PackedVector2Array([edge + dir * 12.0, edge + dir.orthogonal() * 8.0, edge - dir.orthogonal() * 8.0])
	_view.draw_colored_polygon(pts, Color(0.4, 0.65, 1.0, 0.9))


func _bar(r: Rect2, ratio: float, col: Color, label: String) -> void:
	_view.draw_rect(r, Color(0, 0, 0, 0.6))
	_view.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)), col)
	if label != "":
		_text(ThemeDB.fallback_font, r.position + Vector2(6, r.size.y - 2), label, 11, Color.WHITE)


func _text(font: Font, pos: Vector2, s: String, fsize: int, col: Color) -> void:
	_view.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _text_centered(font: Font, pos: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_view.draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
