## DialogScriptResource — an ordered conversation of DialogLineResources.
## Pass to DialogPlayer.play() to run it.
class_name DialogScriptResource
extends Resource

## Optional identifier for telemetry / save state ("seen this dialog?").
## Empty = not tracked.
@export var script_id: StringName = &""

## The lines, played in order.
@export var lines: Array[DialogLineResource] = []

## If true, get_tree().paused is set true while this script plays.
## Set false for ambient banter that shouldn't freeze the world.
@export var pause_gameplay: bool = true
