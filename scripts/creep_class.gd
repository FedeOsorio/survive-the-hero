extends Node2D
## Clase del Anti Hero (player.klass, hija del creep, dibuja en coordenadas del mundo).
## Esta base es el Engendro, el kit de siempre: no cambia nada. Las demás clases la
## extienden (class_abyss.gd, class_swarm.gd) y pisan los ganchos que necesitan;
## creep.gd y creep_abilities.gd los llaman con una línea. Números en la sección
## "Clases del Anti Hero" al final de balance.gd.

const B := preload("res://scripts/balance.gd")
const SCRIPTS := {
	"engendro": "res://scripts/creep_class.gd",
	"abisal": "res://scripts/class_abyss.gd",
	"reina": "res://scripts/class_swarm.gd",
}

var id := "engendro"
var creep
var world


## La clase elegida: "--class=x" en la línea de comandos (pruebas) o la del menú.
static func chosen() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class="):
			return arg.trim_prefix("--class=")
	var saved: String = Settings.get_option("creep_class")
	return saved if SCRIPTS.has(saved) else "engendro"


static func make(class_id: String):
	var k = load(SCRIPTS.get(class_id, SCRIPTS.engendro)).new()
	k.id = class_id if SCRIPTS.has(class_id) else "engendro"
	return k


func _ready() -> void:
	top_level = true
	z_index = 3


func title() -> String:
	return B.CLASSES[id].name


func hp_mult() -> float:
	return B.CLASSES[id].hp


## El escupitajo y Huesos / Detonar / Aliento son del Engendro; las demás traen su arma.
func replaces_kit() -> bool:
	return false


func eats_gems() -> bool:
	return true


## Comiste un cadáver ("c", antes de sacarlo del mundo).
func on_eat(_c) -> void:
	pass


## Daño que recibís. Devuelve true si la clase lo maneja sola (la Reina no tiene vida normal).
func take_hit(_amount: float) -> bool:
	return false


## C o RT (la misma tecla que Llamado).
func ability() -> void:
	pass


## Texto de la barra de vida del HUD.
func hp_text() -> String:
	return "Vida %d/%d" % [int(creep.hp), int(creep.max_hp)]


# --- Ayudas para las clases -------------------------------------------------------

## Héroes, Bastión y Paladines.
func targets() -> Array:
	return world.heroes.targets() + world.infamy.paladins


func is_paladin(t) -> bool:
	return t in world.infamy.paladins


func hurt(t, amount: float, tick := false) -> void:
	if is_paladin(t):
		t.take_damage(amount)
	else:
		t.take_damage(amount, true, false, tick)


func slow(t, amount: float) -> void:
	if not is_paladin(t):
		t.status.slow(amount)


## Aturde a un héroe; al Paladín le hace perder el objetivo.
func stun(t, time: float) -> void:
	if is_paladin(t):
		t.confuse(time)
	else:
		t.status.stun(time)


func nearest_target(from: Vector2, max_dist: float):
	var best = null
	var best_d := max_dist
	for t in targets():
		var d: float = from.distance_to(t.position) - t.radius
		if d < best_d:
			best_d = d
			best = t
	return best
