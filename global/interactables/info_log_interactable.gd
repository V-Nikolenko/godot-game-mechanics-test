class_name InfoLogInteractable
extends Area2D

## A re-readable environmental message: a tablet, terminal, or scrap of hull. On `interact`
## while the player is in range, plays `message` inline via DialogPlayer (pause_gameplay = false)
## and does NOT consume itself — the same object can be read again after walking away and back.
## Never touches LogState: information logs don't count toward completion.

@export_multiline var message: String = ""
@export var prompt_text: String = "Press F to read"

@onready var _prompt: Label = $PromptLabel

var _in_range: Array[Node2D] = []


func _ready() -> void:
	_prompt.text = prompt_text
	_prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not _in_range.has(body):
		_in_range.append(body)
	_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	_in_range.erase(body)
	if _in_range.is_empty():
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _in_range.is_empty():
		return
	if not event.is_action_pressed("interact"):
		return
	if DialogPlayer.is_active:
		return
	get_viewport().set_input_as_handled()
	_read()


func _read() -> void:
	if message.is_empty():
		return
	DialogPlayer.play(_build_script(message))


## Split out from _read() so a test can assert the resource's shape (single INSTANT
## inner-thought line, pause_gameplay = false) without ever calling DialogPlayer.play() —
## starting a real play() cannot be resolved synchronously inside a test (see the sibling
## lore-log-pickup task's stuck review for why).
func _build_script(text: String) -> DialogScriptResource:
	var line := DialogLineResource.new()
	line.text = text
	line.side = DialogLineResource.Side.INNER_THOUGHT
	line.reveal = DialogLineResource.Reveal.INSTANT
	line.post_delay = 0.4
	var script_res := DialogScriptResource.new()
	script_res.lines = [line]
	script_res.pause_gameplay = false
	return script_res
