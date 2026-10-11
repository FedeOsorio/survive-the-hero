extends CanvasLayer
## Autoload "Settings": opciones del jugador (pantalla completa, volumen general y de
## efectos, mostrar FPS). Se leen de user://options.cfg al abrir el juego, se aplican
## y se guardan apenas cambian. También dibuja el contador de FPS.

const PATH := "user://options.cfg"
const DEFAULTS := {"fullscreen": false, "volume_master": 1.0, "volume_sfx": 1.0, "show_fps": false, "damage_numbers": true, "creep_class": "engendro"}
const SFX_BUS := "Efectos"

var values := DEFAULTS.duplicate()
var _fps: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(SFX_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, SFX_BUS)
	_add_pause_action()
	_fps = Label.new()
	_fps.position = Vector2(8, 696)
	_fps.add_theme_font_size_override("font_size", 14)
	add_child(_fps)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in DEFAULTS:
			values[key] = cfg.get_value("options", key, DEFAULTS[key])
	for key in values:
		_apply(key)


## Esc o Start: pausa en partida y "volver" en las pantallas de menú.
func _add_pause_action() -> void:
	if InputMap.has_action("pause"):
		return
	InputMap.add_action("pause")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_START
	InputMap.action_add_event("pause", pad)


func get_option(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_option(key: String, value) -> void:
	values[key] = value
	_apply(key)
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("options", k, values[k])
	cfg.save(PATH)


func _apply(key: String) -> void:
	match key:
		"fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != mode:
				DisplayServer.window_set_mode(mode)
		"volume_master":
			_set_volume("Master", values.volume_master)
		"volume_sfx":
			_set_volume(SFX_BUS, values.volume_sfx)
		"show_fps":
			_fps.visible = values.show_fps


func _set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.0)


func _process(_delta: float) -> void:
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()
