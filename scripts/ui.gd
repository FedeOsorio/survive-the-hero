extends RefCounted
## Piezas de interfaz compartidas por el menú, la pausa y las opciones:
## fondo oscuro, columna centrada, títulos y botones con foco para teclado y joystick.


static func backdrop(alpha: float) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.05, alpha)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	return bg


## Columna centrada en pantalla; los hijos se agregan con add_child.
static func column(parent: Control, separation: int = 14) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


static func label(text: String, size: int, color := Color(0.9, 0.88, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_press)
	b.mouse_entered.connect(b.grab_focus) # mouse y teclado comparten el resaltado
	return b
