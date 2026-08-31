## HUDScoreWidget — top-right score + combo display.
##
## Subscribes to EventBus.score_changed / combo_changed. Owns no scoring logic.
## Tweens the displayed score smoothly so it ticks up rather than snapping.
class_name HUDScoreWidget
extends Control

const _COMBO_BAR_FULL_SECONDS: float = 4.0
const _SCORE_TWEEN_DURATION: float = 0.4

@onready var _score_label: Label    = $ScoreLabel
@onready var _combo_label: Label    = $ComboLabel
@onready var _combo_bar:   ColorRect = $ComboDecayBar

var _displayed_score: int = 0
var _target_score: int = 0
var _score_tween: Tween

func _ready() -> void:
	_combo_label.visible = false
	_combo_bar.visible = false
	_score_label.text = "0"

	EventBus.score_changed.connect(_on_score_changed)
	EventBus.combo_changed.connect(_on_combo_changed)

func _on_score_changed(total: int) -> void:
	_target_score = total
	if _score_tween and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.tween_method(_set_displayed_score, _displayed_score, total, _SCORE_TWEEN_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_displayed_score(v: int) -> void:
	_displayed_score = v
	_score_label.text = str(v)

func _on_combo_changed(multiplier: float, decay_remaining: float) -> void:
	if multiplier <= 1.0:
		_combo_label.visible = false
		_combo_bar.visible = false
		return
	_combo_label.visible = true
	_combo_bar.visible = true
	_combo_label.text = "x%.1f" % multiplier
	var pct: float = clampf(decay_remaining / _COMBO_BAR_FULL_SECONDS, 0.0, 1.0)
	_combo_bar.scale.x = pct
