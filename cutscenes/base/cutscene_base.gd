## CutsceneBase — base class for cinematic cutscenes.
##
## Subclasses override `_run_cutscene()` and use the helpers below to compose
## a sequence with `await`. Common features handled here:
##   - Skip via `skip_action` (default "ui_cancel")
##   - Persistence: when `persistence_id` is non-empty, marks the cutscene as
##     seen via MissionState on finish (skipped or natural completion both count)
##   - Scene transition: when `next_scene_path` is non-empty, loads it on finish
##   - `finished` signal so external code can react if needed
##
## Subclasses should check `is_skipped()` between awaitable calls and return
## early — this is what makes the skip feel responsive.
class_name CutsceneBase
extends Node2D

signal finished

@export var skip_action: String = "ui_cancel"
## Scene loaded automatically when the cutscene finishes (skipped or naturally).
## Leave empty to do nothing.
@export_file("*.tscn") var next_scene_path: String = ""
## Persistence key passed to MissionState.mark_cutscene_seen() on finish.
## Leave empty for cutscenes that should always replay (debug/menu).
@export var persistence_id: String = ""

var _skipped: bool = false
var _finished: bool = false

func _ready() -> void:
	_run_cutscene()

func _unhandled_input(event: InputEvent) -> void:
	if not _finished and event.is_action_pressed(skip_action):
		skip()

## Override in subclass — define the cutscene's beat sequence here.
func _run_cutscene() -> void:
	push_warning("CutsceneBase._run_cutscene() not overridden — finishing immediately")
	_on_finish()

## End the cutscene right now. Pending awaits in the subclass should detect this
## via `is_skipped()` and return early.
func skip() -> void:
	if _skipped or _finished:
		return
	_skipped = true
	_on_finish()

func is_skipped() -> bool:
	return _skipped

# ── Awaitable helpers ───────────────────────────────────────────────────────

## Wait for `seconds`. Use between beats.
func wait_secs(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

## Tween a single property to `final_value` over `seconds`. Returns when done.
## If `seconds` <= 0 the value is set instantly without creating a Tween.
func tween_property(node: Object, property: String, final_value: Variant,
		seconds: float, transition: int = Tween.TRANS_QUAD,
		ease_type: int = Tween.EASE_IN_OUT) -> void:
	if seconds <= 0.0:
		node.set(property, final_value)
		return
	var t := create_tween()
	t.set_trans(transition).set_ease(ease_type)
	t.tween_property(node, property, final_value, seconds)
	await t.finished

## Build a parallel Tween. Caller stacks tween_property calls on it then awaits
## the returned Tween's `.finished`.
##
## Example:
##   var t := parallel_tween()
##   t.tween_property(camera, "zoom", Vector2(2,2), 3.0)
##   t.tween_property(camera, "position", Vector2.ZERO, 3.0)
##   await t.finished
func parallel_tween() -> Tween:
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return t

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _on_finish() -> void:
	if _finished:
		return
	_finished = true
	if not persistence_id.is_empty():
		MissionState.mark_cutscene_seen(persistence_id)
	finished.emit()
	if not next_scene_path.is_empty():
		get_tree().change_scene_to_file(next_scene_path)
