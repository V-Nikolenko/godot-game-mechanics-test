## HazardSystem — one per race level (sibling of RaceLevelConfig). Each physics frame it
## checks every ship (player + AI racers) against every currently-lethal track hazard
## (group "race_hazards", duck-typed danger_rect()/is_lethal_now()). On overlap it applies
## a shield-bypassing one-shot: the player fails the race, an AI racer is eliminated.
## Centralising contact here keeps "where is lethal" identical to what the AI reads for
## avoidance (Sensors), so what the AI dodges is exactly what kills it.
class_name HazardSystem
extends Node

## Grows each hazard rect slightly so a ship touching the edge still registers.
const CONTACT_MARGIN: float = 6.0

var _director: RaceDirector = null
var _killed: Dictionary = {}   ## instance_id -> true (avoid double-processing a dying ship)

func _ready() -> void:
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector

func _physics_process(_delta: float) -> void:
	var hazards := get_tree().get_nodes_in_group("race_hazards")
	if hazards.is_empty():
		return
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ship := n as Node2D
			if ship == null or not is_instance_valid(ship):
				continue
			if _killed.has(ship.get_instance_id()):
				continue
			var pos := ship.global_position
			for h in hazards:
				var hz := h as Node2D
				if hz == null or not is_instance_valid(hz):
					continue
				if not hz.has_method("is_lethal_now") or not hz.is_lethal_now():
					continue
				if not hz.has_method("danger_rect"):
					continue
				var rect: Rect2 = hz.danger_rect().grow(CONTACT_MARGIN)
				if rect.has_point(pos):
					_kill(ship)
					break

func _kill(ship: Node2D) -> void:
	_killed[ship.get_instance_id()] = true
	if ship.is_in_group("player"):
		if _director:
			_director.fail_race()
	elif ship.has_method("apply_lethal_hazard"):
		ship.apply_lethal_hazard()
