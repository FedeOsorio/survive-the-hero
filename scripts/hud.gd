extends CanvasLayer
## Interfaz: vida, biomasa, nivel, reloj con la próxima llegada, amenaza,
## vida y nivel de cada héroe vivo con su flecha, elección de mutaciones y pantalla
## final (resultado, tabla por minuto y botón Copiar tabla). Corre aunque el juego esté en pausa.

const B := preload("res://scripts/balance.gd")
const Mutations := preload("res://scripts/mutations.gd")

var world
var _view: Control
var _banner_text := ""
var _banner_t := 0.0
var _copy: Button
var _copied_t := 0.0

const RESULTS := ["derrota", "escape", "victoria", "total"]
const RESULT_TITLES := {"derrota": "DERROTA", "escape": "VICTORIA POR ESCAPE", "victoria": "VICTORIA", "total": "VICTORIA TOTAL"}
const RESULT_SHORT := {"derrota": "Derrota", "escape": "Escape", "victoria": "Victoria", "total": "Victoria total"}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_hud)
	add_child(_view)
	_copy = Button.new()
	_copy.text = "Copiar tabla"
	_copy.visible = false
	_copy.pressed.connect(_on_copy)
	add_child(_copy)


func _on_copy() -> void:
	DisplayServer.clipboard_set(world.stats_text())
	_copied_t = 2.0


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
	_copied_t = maxf(_copied_t - delta, 0.0)
	_copy.visible = not world.running
	if _copy.visible:
		_copy.position = Vector2(_view.size.x * 0.5 - 70, _view.size.y - 70)
		_copy.size = Vector2(140, 32)
		_copy.text = "¡Copiada!" if _copied_t > 0.0 else "Copiar tabla"
	_view.queue_redraw()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var size := _view.size
	var p = world.player

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
	var next: float = world.heroes.next_arrival()
	var mark := ""
	if next >= 0.0:
		var nt := int(next)
		mark = "%s %02d:%02d" % [world.heroes.next_name(), nt / 60, nt % 60]
	elif world.elapsed < B.MATCH_MINUTES * 60.0:
		mark = "Amanece %02d:00" % int(B.MATCH_MINUTES)
	if mark != "":
		_text(font, Vector2(size.x * 0.5 + 46, 30), mark, 13, Color(0.75, 0.75, 0.85))
	if world.detected:
		_text_centered(font, Vector2(size.x * 0.5, 60), "TE CAZA", 16, Color(1, 0.3, 0.3))
	_bar(Rect2(size.x * 0.5 - 100, 80, 200, 10), world.infamy.bar / B.INFAMY_MAX, Color(1.0, 0.8, 0.25), "")
	_text_centered(font, Vector2(size.x * 0.5, 106), B.INFAMY_NAME, 12, Color(1.0, 0.88, 0.5))
	_wing(Vector2(size.x * 0.5 - 116, 85))

	# Héroes vivos: arriba a la derecha, uno debajo del otro
	var y := 30.0
	_text(font, Vector2(size.x - 280, y - 22), "Héroes caídos %d/%d" % [world.heroes.killed, world.heroes.total()], 12, Color(0.8, 0.8, 0.85))
	for h in world.heroes.list:
		_text(font, Vector2(size.x - 280, y), "%s nivel %d" % [h.title, h.level], 18, h.color)
		_bar(Rect2(size.x - 280, y + 8, 260, 12), h.hp / h.max_hp, Color(0.85, 0.25, 0.25), "Vida %d/%d" % [int(h.hp), int(h.max_hp)])
		var names: Array = []
		for id in h.powers.ranks:
			names.append("%s %d" % [h.powers.LIST[id].name, h.powers.ranks[id]])
		_view.draw_multiline_string(font, Vector2(size.x - 280, y + 36), ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, 260, 12, -1, Color(1.0, 0.85, 0.5))
		y += 74.0
		_pointer(h, Color(h.color, 0.95))
	if world.chest != null:
		_pointer(world.chest, Color(1.0, 0.8, 0.25, 0.95))
	for pal in world.infamy.paladins:
		_pointer(pal, Color(1.0, 0.95, 0.6, 0.95))
	if world.events.blood_moon_t > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, 0.08))
		_text_centered(font, Vector2(size.x * 0.5, 128), "Luna de sangre: %ds" % int(ceil(world.events.blood_moon_t)), 18, Color(1, 0.35, 0.3))

	_text_centered(font, Vector2(size.x * 0.5, size.y - 16),
		"WASD mover · Espacio embestida · Q camuflaje · E evolucionar · R reiniciar  (mordida y escupitajo son automáticos)", 13, Color(0.7, 0.7, 0.75))

	if _banner_t > 0.0:
		_text_centered(font, Vector2(size.x * 0.5, size.y * 0.3), _banner_text, 26, Color(1, 1, 1, minf(_banner_t, 1.0)))

	if not p.pending_choices.is_empty():
		_draw_choices(font, p)

	if not world.running:
		_draw_end(font, p)


## Pantalla final: resultado, la escalera de resultados y la tabla de la partida.
func _draw_end(font: Font, p) -> void:
	var size := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.75))
	var col := Color(1, 0.35, 0.3) if world.result == "derrota" else Color(0.4, 1, 0.5)
	_text_centered(font, Vector2(size.x * 0.5, 70), RESULT_TITLES.get(world.result, ""), 44, col)
	_text_centered(font, Vector2(size.x * 0.5, 100), world.end_reason, 18, Color.WHITE)
	# de peor a mejor, con el obtenido resaltado
	var parts: Array = []
	for r in RESULTS:
		parts.append(RESULT_SHORT[r])
	var ladder := " · ".join(parts)
	var x := size.x * 0.5 - font.get_string_size(ladder, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5
	for i in RESULTS.size():
		var s: String = RESULT_SHORT[RESULTS[i]] + (" · " if i < RESULTS.size() - 1 else "")
		var on: bool = RESULTS[i] == world.result
		_text(font, Vector2(x, 124), s, 13, Color(1, 0.85, 0.3) if on else Color(0.55, 0.55, 0.6))
		x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var lines: PackedStringArray = world.stats_text().split("\n")
	var y := 156.0
	for i in range(2, lines.size()):
		_text(font, Vector2(size.x * 0.5 - 300, y), lines[i], 13, Color(0.9, 0.9, 0.95) if i > 2 else Color(1, 0.85, 0.5))
		y += 16.0
	_text_centered(font, Vector2(size.x * 0.5, size.y - 18), "R para jugar de nuevo", 16, Color(0.8, 0.8, 0.8))


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
		var evo := Mutations.is_evolution(id)
		var r := Rect2(x0 + i * (w + gap), size.y * 0.33, w, 190)
		_view.draw_rect(r, Color(0.2, 0.15, 0.05, 0.95) if evo else Color(0.12, 0.1, 0.16, 0.95))
		_view.draw_rect(r, Color(1.0, 0.8, 0.25) if evo else Color(0.6, 0.9, 1.0, 0.8), false, 3.0 if evo else 2.0)
		_text(font, r.position + Vector2(14, 30), "%d. %s" % [i + 1, m.name], 20, Color(1.0, 0.85, 0.35) if evo else Color.WHITE)
		_text(font, r.position + Vector2(14, 56), "EVOLUCIÓN" if evo else "Rango %d/%d" % [p.rank(id) + 1, m.max], 13, Color(1.0, 0.8, 0.3) if evo else Color(0.7, 0.7, 0.8))
		_view.draw_multiline_string(font, r.position + Vector2(14, 86), Mutations.desc(id), HORIZONTAL_ALIGNMENT_LEFT, w - 28, 16, -1, Color(0.9, 0.9, 0.95))


## Ala: ícono de la barra de Infamia.
func _wing(at: Vector2) -> void:
	_view.draw_colored_polygon(PackedVector2Array([at + Vector2(8, 0), at + Vector2(-10, -8), at + Vector2(-6, -2), at + Vector2(-10, 2), at + Vector2(-5, 4)]), Color(1.0, 0.9, 0.55))


## Flecha en el borde de pantalla hacia algo que está fuera de vista.
func _pointer(h, col: Color) -> void:
	var screen_pos: Vector2 = _view.get_viewport().get_canvas_transform() * h.global_position
	var rect := Rect2(Vector2.ZERO, _view.size).grow(-30)
	if rect.has_point(screen_pos):
		return
	var center := _view.size * 0.5
	var dir := (screen_pos - center).normalized()
	var edge := Vector2(clampf(screen_pos.x, rect.position.x, rect.end.x), clampf(screen_pos.y, rect.position.y, rect.end.y))
	var pts := PackedVector2Array([edge + dir * 12.0, edge + dir.orthogonal() * 8.0, edge - dir.orthogonal() * 8.0])
	_view.draw_colored_polygon(pts, col)


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
