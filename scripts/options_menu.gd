extends Control
## Pantalla de Opciones (desde el menú principal o la pausa): pantalla completa,
## volumen general y de efectos, mostrar FPS. Cada cambio se guarda al instante
## en el autoload Settings. Volver o Esc la cierra y emite "closed".

signal closed

const UI := preload("res://scripts/ui.gd")

var _first: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop(0.92))
	var box := UI.column(self)
	box.add_child(UI.label("Opciones", 40))
	_first = _toggle(box, "Pantalla completa", "fullscreen")
	_slider(box, "Volumen general", "volume_master")
	_slider(box, "Volumen de efectos", "volume_sfx")
	_toggle(box, "Números de daño", "damage_numbers")
	_toggle(box, "Mostrar FPS", "show_fps")
	box.add_child(UI.button("Volver", _close))
	_first.grab_focus.call_deferred()


func _toggle(box: Control, text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = Settings.get_option(key)
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(func(on: bool): Settings.set_option(key, on))
	c.mouse_entered.connect(c.grab_focus)
	box.add_child(c)
	return c


func _slider(box: Control, text: String, key: String) -> void:
	box.add_child(UI.label(text, 18))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.1
	s.value = Settings.get_option(key)
	s.custom_minimum_size = Vector2(260, 24)
	s.value_changed.connect(func(v: float): Settings.set_option(key, v))
	s.mouse_entered.connect(s.grab_focus)
	box.add_child(s)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()
