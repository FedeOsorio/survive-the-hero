extends Control
## Menú principal (escena inicial): título, cartas de clase (class_select.gd), Jugar, Opciones, Salir y el mejor
## resultado guardado en user://records.cfg. Se maneja con mouse, teclado o joystick.

const UI := preload("res://scripts/ui.gd")
const Records := preload("res://scripts/records.gd")
const OptionsMenu := preload("res://scripts/options_menu.gd")
const ClassSelect := preload("res://scripts/class_select.gd")
const GAME_SCENE := "res://scenes/main.tscn"

var _play: Button


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop(1.0))
	var box := UI.column(self)
	box.add_child(UI.label("Survive the Hero", 64, Color(0.85, 0.3, 0.35)))
	box.add_child(UI.label("Sos el creep. Ellos son los héroes.", 20, Color(0.7, 0.68, 0.78)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	box.add_child(gap)
	box.add_child(UI.label("Elegí tu clase", 22, Color(0.85, 0.8, 0.95)))
	box.add_child(ClassSelect.new())
	_play = UI.button("Jugar", _on_play)
	box.add_child(_play)
	var options := UI.button("Opciones", _on_options)
	box.add_child(options)
	box.add_child(UI.button("Salir", get_tree().quit))
	for b in [_play, options, box.get_child(box.get_child_count() - 1)]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # la fila de clases es más ancha
	var rec := Records.best()
	if not rec.is_empty():
		box.add_child(UI.label("Mejor resultado: " + Records.describe(rec), 18, Color(0.75, 0.72, 0.6)))
	_play.grab_focus.call_deferred()


func _on_play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_options() -> void:
	var opts := OptionsMenu.new()
	opts.closed.connect(get_viewport().gui_get_focus_owner().grab_focus)
	add_child(opts)
