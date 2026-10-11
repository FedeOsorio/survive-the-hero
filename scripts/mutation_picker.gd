extends Control
## Elección de mutación (hijo del HUD): tres cartas en la mitad de abajo de la pantalla.
## Se elige con clic, con 1/2/3 o X/A/B, o moviendo el resaltado con stick o flechas
## y confirmando con A o Enter. Al abrir entra con una animación corta y queda
## bloqueada FX_PICK_LOCK segundos, para no elegir sin querer en medio de una pelea.

const B := preload("res://scripts/balance.gd")
const Mutations := preload("res://scripts/mutations.gd")

const CARD := Vector2(300, 190)
const GAP := 24.0

var world
var _open := false
var _t := 0.0 # tiempo desde que se abrió (real, corre en pausa)
var _selected := 1 # arranca en la del medio: A sin mover elige la 2 como antes
var _hover := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _choices() -> Array:
	return world.player.pending_choices


func _process(delta: float) -> void:
	var n: int = _choices().size()
	if n == 0:
		if _open:
			_open = false
			queue_redraw()
		return
	if not _open:
		_open = true
		_t = 0.0
		_selected = mini(1, n - 1)
		_hover = -1
	_t += delta
	if _t >= B.FX_PICK_LOCK:
		_read_input(n)
	queue_redraw()


func _read_input(n: int) -> void:
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left"):
		_selected = posmod(_selected - 1, n)
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		_selected = posmod(_selected + 1, n)
	# A del joystick es ui_accept y pick_2 a la vez: gana el resaltado
	if Input.is_action_just_pressed("ui_accept"):
		_pick(_selected)
		return
	for i in n:
		if Input.is_action_just_pressed("pick_%d" % (i + 1)):
			_pick(i)
			return


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		_hover = _card_at(event.position)
		if _hover >= 0:
			_selected = _hover
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _card_at(event.position)
		if i >= 0 and _t >= B.FX_PICK_LOCK:
			get_viewport().set_input_as_handled()
			_pick(i)


func _pick(i: int) -> void:
	_open = false
	world.player.choose_mutation(i)


func _card_rect(i: int, n: int) -> Rect2:
	var size := get_viewport_rect().size
	var x0 := size.x * 0.5 - (CARD.x * n + GAP * (n - 1)) * 0.5
	return Rect2(Vector2(x0 + i * (CARD.x + GAP), size.y * 0.56), CARD)


func _card_at(pos: Vector2) -> int:
	var n: int = _choices().size()
	for i in n:
		if _card_rect(i, n).has_point(pos):
			return i
	return -1


func _draw() -> void:
	if not _open:
		return
	var p = world.player
	var size := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var choices := _choices()
	var n: int = choices.size()
	var k := clampf(_t / B.FX_PICK_ANIM, 0.0, 1.0)
	var locked := _t < B.FX_PICK_LOCK
	var slide := (1.0 - k) * 40.0
	draw_rect(Rect2(Vector2(0, size.y * 0.48), Vector2(size.x, size.y * 0.52)), Color(0, 0, 0, 0.45 * k))
	_centered(font, Vector2(size.x * 0.5, size.y * 0.53 + slide), "¡Mutación! Elegí una", 26, Color(0.6, 0.9, 1.0, k))
	for i in n:
		var id: String = choices[i]
		var m: Dictionary = Mutations.LIST[id]
		var evo := Mutations.is_evolution(id)
		var sel := i == _selected and not locked
		var r := _card_rect(i, n)
		r.position.y += slide - (6.0 if sel else 0.0)
		var a := k * (0.5 if locked else 1.0)
		var bg := Color(0.2, 0.15, 0.05, 0.95) if evo else Color(0.12, 0.1, 0.16, 0.95)
		if sel:
			bg = bg.lightened(0.12)
		bg.a *= a
		draw_rect(r, bg)
		var edge := Color(1.0, 0.8, 0.25) if evo else Color(0.6, 0.9, 1.0, 0.8)
		if sel:
			edge = Color.WHITE
		edge.a *= a
		draw_rect(r, edge, false, 4.0 if sel else (3.0 if evo else 2.0))
		var title_col := Color(1.0, 0.85, 0.35, a) if evo else Color(1, 1, 1, a)
		draw_string(font, r.position + Vector2(14, 30), "%d. %s" % [i + 1, m.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_col)
		var rank_text := "EVOLUCIÓN" if evo else ("Rango %d" % (p.rank(id) + 1) if m.max == 0 else "Rango %d/%d" % [p.rank(id) + 1, m.max])
		draw_string(font, r.position + Vector2(14, 56), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.3, a) if evo else Color(0.7, 0.7, 0.8, a))
		draw_multiline_string(font, r.position + Vector2(14, 86), Mutations.desc(id), HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 28, 16, -1, Color(0.9, 0.9, 0.95, a))


func _centered(font: Font, pos: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
