## DialogTrigger — declarative wrapper around DialogPlayer.play().
##
## Drop into any scene, set `script_resource`, and either:
##   - call fire() from code, OR
##   - connect any signal to the trigger's fire_from_signal() method, OR
##   - set fire_on_ready = true to fire as soon as the trigger enters the tree.
##
## Honors play_once — second fire is ignored once consumed.
class_name DialogTrigger
extends Node

signal triggered
signal completed(was_skipped: bool)

@export var script_resource: DialogScriptResource

@export var fire_on_ready: bool = false

@export var play_once: bool = true

var _consumed: bool = false


func _ready() -> void:
	if fire_on_ready:
		fire()


## Trigger the dialog. Awaitable — resolves on completed.
func fire() -> void:
	if _consumed and play_once:
		return
	if script_resource == null:
		push_warning("[DialogTrigger] fire() called with no script_resource.")
		return
	_consumed = true
	triggered.emit()
	await DialogPlayer.play(script_resource)
	completed.emit(false)


## Connectable to any zero-arg signal.
func fire_from_signal() -> void:
	fire()
