extends Control
## Menú principal (escena inicial): título, Jugar, Opciones, Salir y el mejor
## resultado guardado en user://records.cfg. Se maneja con mouse, teclado o joystick.

const UI := preload("res://scripts/ui.gd")
const Records := preload("res://scripts/records.gd")
const OptionsMenu := preload("res://scripts/options_menu.gd")
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
	_play = UI.button("Jugar", _on_play)
	box.add_child(_play)
	var options := UI.button("Opciones", _on_options)
	box.add_child(options)
	box.add_child(UI.button("Salir", get_tree().quit))
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
