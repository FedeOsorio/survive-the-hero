extends HBoxContainer
## Fila de cartas de clase del menú principal (Engendro, Abisal, Reina...): nombre,
## regla y arma inicial. La elegida queda marcada y se guarda en options.cfg
## (Settings "creep_class"); las bloqueadas salen grises (records.gd).

const B := preload("res://scripts/balance.gd")
const Records := preload("res://scripts/records.gd")

var _group := ButtonGroup.new()


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 12)
	var chosen: String = Settings.get_option("creep_class")
	for id in B.CLASS_ORDER:
		add_child(_card(id, id == chosen))


func _card(id: String, selected: bool) -> Button:
	var c: Dictionary = B.CLASSES[id]
	var b := Button.new()
	b.custom_minimum_size = Vector2(240, 150)
	b.toggle_mode = true
	b.button_group = _group
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 15)
	b.mouse_entered.connect(b.grab_focus)
	if Records.class_unlocked(id):
		b.text = "%s\n\n%s\n\n%s" % [c.name.to_upper(), c.rule, c.weapon]
		b.button_pressed = selected
		b.pressed.connect(Settings.set_option.bind("creep_class", id))
	else:
		b.text = "%s\n\nBloqueada: ganá una partida para desbloquearla." % c.name.to_upper()
		b.disabled = true
	return b
