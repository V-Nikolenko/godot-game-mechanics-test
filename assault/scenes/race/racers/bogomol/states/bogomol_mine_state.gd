## BogomolMineState — drop a mine at the panel just crossed (so trailing ships eat it), then
## resume seeking the next panel. The mine is added as a child of the Track node so it scrolls
## with the world. Its position is converted from world space to Track's local space.
class_name BogomolMineState
extends State

var host: RaceShip
var drop_at: Vector2 = Vector2.ZERO

const _MINE: PackedScene = preload("res://assault/scenes/race/track/mine.tscn")

func enter() -> void:
	var mine := _MINE.instantiate() as Mine
	var track := host.get_tree().get_first_node_in_group("race_track") as Node2D
	if track:
		## Convert the world-space drop position to Track's local space so the mine
		## scrolls with the track container (and thus stays at the correct track location).
		mine.position = track.to_local(drop_at)
		track.add_child(mine)
	else:
		## Fallback: add to the scene root (mine won't scroll, but won't crash either).
		mine.global_position = drop_at
		host.get_parent().add_child(mine)
	host.brain.transition_to(&"BogomolSeek")

func process_physics(_delta: float) -> void:
	pass
