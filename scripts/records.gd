extends RefCounted
## Récord del jugador en user://records.cfg: el resultado más alto de la escalera
## (derrota < escape < victoria < total) y su tiempo, y las victorias que desbloquean
## clases del Anti Hero. A igual resultado gana el tiempo
## más largo si perdiste o escapaste, y el más corto si ganaste.

const PATH := "user://records.cfg"
const LADDER := ["derrota", "escape", "victoria", "total"]
const NAMES := {"derrota": "Derrota", "escape": "Victoria por escape", "victoria": "Victoria", "total": "Victoria total"}


## {"result": String, "time": float}, o vacío si todavía no hay récord.
static func best() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section_key("best", "result"):
		return {}
	return {"result": cfg.get_value("best", "result"), "time": float(cfg.get_value("best", "time", 0.0))}


## Guarda el resultado si es mejor que el récord. Devuelve true si lo es.
## Cada victoria (de cualquier tipo) suma una al contador que desbloquea clases.
static func submit(result: String, time: float) -> bool:
	var rank := LADDER.find(result)
	if rank < 0:
		return false
	if rank > 0:
		_add_win()
	var old := best()
	if not old.is_empty():
		var old_rank := LADDER.find(old.result)
		if rank < old_rank:
			return false
		if rank == old_rank:
			var faster_wins := rank >= 2
			if (faster_wins and time >= old.time) or (not faster_wins and time <= old.time):
				return false
	var cfg := ConfigFile.new()
	cfg.load(PATH) # sin perder las victorias guardadas
	cfg.set_value("best", "result", result)
	cfg.set_value("best", "time", time)
	cfg.save(PATH)
	return true


static func describe(rec: Dictionary) -> String:
	var t := int(rec.time)
	return "%s (%d:%02d)" % [NAMES.get(rec.result, rec.result), t / 60, t % 60]


static func wins() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return 0
	return int(cfg.get_value("classes", "wins", 0))


static func _add_win() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("classes", "wins", int(cfg.get_value("classes", "wins", 0)) + 1)
	cfg.save(PATH)


## El Engendro siempre; las demás, una por victoria en CLASS_UNLOCK_ORDER.
static func class_unlocked(id: String) -> bool:
	var B := preload("res://scripts/balance.gd")
	if B.CLASSES_ALL_UNLOCKED or id == "engendro":
		return true
	var i: int = B.CLASS_UNLOCK_ORDER.find(id)
	return i >= 0 and i < wins()
