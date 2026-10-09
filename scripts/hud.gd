extends CanvasLayer
## Interfaz: vida, biomasa, reloj, amenaza, flecha hacia el héroe y pantalla final.

const B := preload("res://scripts/balance.gd")

var world
var _view: Control
var _banner_text := ""
var _banner_t := 0.0


func _ready() -> void:
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_hud)
	add_child(_view)


func banner(text: String) -> void:
	_banner_text = text
	_banner_t = 3.0


func _process(delta: float) -> void:
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
	var cost: float = p.evolve_cost()
	if cost > 0.0:
		_bar(Rect2(20, 60, 260, 14), p.biomass / cost, Color(0.75, 0.45, 0.9), "Biomasa %d/%d" % [int(p.biomass), int(cost)])
		if p.can_evolve():
			_text(font, Vector2(20, 96), "¡Pulsá E para evolucionar!", 18, Color(1, 0.9, 0.3))
	else:
		_text(font, Vector2(20, 72), "Forma final", 14, Color(0.9, 0.8, 0.8))

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

	_hero_pointer(h)

	_text_centered(font, Vector2(size.x * 0.5, size.y - 16),
		"WASD mover · Espacio morder · Q escupir · Shift embestida · E evolucionar · R reiniciar", 13, Color(0.7, 0.7, 0.75))

	if _banner_t > 0.0:
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.3), _banner_text, 26, Color(1, 1, 1, minf(_banner_t, 1.0)))

	if not world.running:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		var title := "¡GANASTE!" if world.won else "PERDISTE"
		var col := Color(0.4, 1, 0.5) if world.won else Color(1, 0.35, 0.3)
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.42), title, 56, col)
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.52), world.end_reason, 22, Color.WHITE)
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.6), "R para jugar de nuevo", 18, Color(0.8, 0.8, 0.8))


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
