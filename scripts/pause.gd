extends CanvasLayer
## Pausa y botones de la pantalla final. Esc o Start pausa (no con la elección de
## mutación abierta ni durante el amanecer): Seguir, Opciones, Volver al menú.
## Al terminar la partida guarda el récord y suma Reintentar y Menú junto a Copiar tabla.

const UI := preload("res://scripts/ui.gd")
const Records := preload("res://scripts/records.gd")
const OptionsMenu := preload("res://scripts/options_menu.gd")
const MENU_SCENE := "res://scenes/menu.tscn"

var world
var _panel: Control
var _options: Control
var _resume: Button
var _was_paused := false
var _ended := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or _options:
		return
	if _panel:
		get_viewport().set_input_as_handled()
		_on_resume()
	elif world.running and not world.escaping and world.player.pending_choices.is_empty():
		get_viewport().set_input_as_handled()
		_open()


func _process(_delta: float) -> void:
	if _panel:
		get_tree().paused = true # nada de la partida la despausa mientras está abierta
	if not _ended and not world.running:
		_ended = true
		_show_end_buttons()


func _open() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(UI.backdrop(0.7))
	add_child(_panel)
	var box := UI.column(_panel)
	box.add_child(UI.label("Pausa", 48))
	_resume = UI.button("Seguir", _on_resume)
	box.add_child(_resume)
	box.add_child(UI.button("Opciones", _on_options))
	box.add_child(UI.button("Volver al menú", _to_menu))
	_resume.grab_focus()


func _on_resume() -> void:
	_panel.queue_free()
	_panel = null
	get_tree().paused = _was_paused


func _on_options() -> void:
	_options = OptionsMenu.new()
	_options.closed.connect(func():
		_options = null
		_resume.grab_focus())
	add_child(_options)


func _retry() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _show_end_buttons() -> void:
	if world.sim_mode:
		return
	var record := Records.submit(world.result, world.elapsed)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var size: Vector2 = root.get_viewport_rect().size
	# Copiar tabla (hud.gd) ocupa el centro de esta fila: x ± 70, y = alto − 70.
	var retry := _small_button(root, "Reintentar", Vector2(size.x * 0.5 - 250, size.y - 70), _retry)
	var menu := _small_button(root, "Menú", Vector2(size.x * 0.5 + 90, size.y - 70), _to_menu)
	retry.focus_neighbor_right = retry.get_path_to(menu)
	menu.focus_neighbor_left = menu.get_path_to(retry)
	if record:
		var l := UI.label("¡Nuevo récord!", 20, Color(1, 0.85, 0.3))
		l.position = Vector2(size.x * 0.5 - 100, size.y - 104)
		l.size = Vector2(200, 28)
		root.add_child(l)
	retry.grab_focus()


func _small_button(root: Control, text: String, pos: Vector2, on_press: Callable) -> Button:
	var b := UI.button(text, on_press)
	b.custom_minimum_size = Vector2(160, 32)
	b.add_theme_font_size_override("font_size", 18)
	b.position = pos
	b.size = Vector2(160, 32)
	root.add_child(b)
	return b
