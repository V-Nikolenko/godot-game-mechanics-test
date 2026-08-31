## ScorePopupSpawner — listens to EventBus.score_event and instantiates a
## floating ScorePopup label for each event. Lives under the HUD root.
extends Node2D

const _POPUP_SCENE: PackedScene = preload("res://assault/scenes/gui/score_popup.tscn")

func _ready() -> void:
	EventBus.score_event.connect(_on_score_event)

func _on_score_event(world_position: Vector2, points: int, reason: String) -> void:
	var popup := _POPUP_SCENE.instantiate() as ScorePopup
	add_child(popup)
	popup.show_for(world_position, points, reason)
