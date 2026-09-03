## LevelDebriefScreen — animated post-mission score breakdown.
##
## Shown after the existing level-complete dialog finishes, before
## LevelExitCutscene. Animates the score counter, fades in the breakdown
## lines, and pops in 1–3 stars based on the configured thresholds.
##
## Usage:
##   var debrief := LevelDebriefScreen.instantiate()
##   add_child(debrief)
##   debrief.show_debrief(total, breakdown, stars_earned)
##   await debrief.dismissed
class_name LevelDebriefScreen
extends CanvasLayer

signal dismissed

const _COUNTER_DURATION: float = 2.0
const _LINE_FADE_DURATION: float = 0.3
const _STAR_POP_INTERVAL: float = 0.25

@onready var _score_label:     Label = $Panel/ScoreLabel
@onready var _kills_label:     Label = $Panel/Breakdown/KillsLabel
@onready var _wave_label:      Label = $Panel/Breakdown/WaveLabel
@onready var _bonus_label:     Label = $Panel/Breakdown/BonusLabel
@onready var _skill_label:     Label = $Panel/Breakdown/SkillLabel
@onready var _survival_label:  Label = $Panel/Breakdown/SurvivalLabel
@onready var _stars_container: Node  = $Panel/Stars
@onready var _continue_label:  Label = $Panel/ContinueLabel

var _accepting_input: bool = false


func show_debrief(total: int, breakdown: Dictionary, stars: int) -> void:
	process_mode = PROCESS_MODE_ALWAYS

	# Hide breakdown lines until the score counter finishes its tick-up.
	for line: Label in [_kills_label, _wave_label, _bonus_label, _skill_label, _survival_label]:
		line.modulate.a = 0.0
	for i: int in range(3):
		var s: CanvasItem = _stars_container.get_child(i)
		s.modulate.a = 0.0
		s.scale = Vector2(0.4, 0.4)
	_continue_label.modulate.a = 0.0

	_score_label.text = "0"
	var counter_tween := create_tween()
	counter_tween.tween_method(_set_counter, 0, total, _COUNTER_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await counter_tween.finished

	# Categorised breakdown lines, scaled to whatever the run produced.
	_fade_in(_kills_label,    "Kills: %d" % breakdown.get("kills", 0))
	await get_tree().create_timer(_LINE_FADE_DURATION).timeout
	_fade_in(_wave_label,     "Wave bonuses: %d" % breakdown.get("wave_clear", 0))
	await get_tree().create_timer(_LINE_FADE_DURATION).timeout
	_fade_in(_bonus_label,    "Bonus targets: %d" % breakdown.get("bonus_target", 0))
	await get_tree().create_timer(_LINE_FADE_DURATION).timeout
	_fade_in(_skill_label,    "Skill bonuses: %d" % breakdown.get("skill", 0))
	await get_tree().create_timer(_LINE_FADE_DURATION).timeout
	_fade_in(_survival_label, "Survival: %d" % breakdown.get("survival", 0))

	# Pop the earned stars in left-to-right.
	for i: int in range(3):
		await get_tree().create_timer(_STAR_POP_INTERVAL).timeout
		_pop_star(i, i < stars)

	_fade_in(_continue_label, "Press any key to continue")
	_accepting_input = true


func _input(event: InputEvent) -> void:
	if not _accepting_input:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.is_pressed():
			_accepting_input = false
			dismissed.emit()
			queue_free()


func _set_counter(v: int) -> void:
	_score_label.text = str(v)


func _fade_in(label: Label, text: String) -> void:
	label.text = text
	var t := create_tween()
	t.tween_property(label, "modulate:a", 1.0, _LINE_FADE_DURATION)


func _pop_star(idx: int, earned: bool) -> void:
	var star: CanvasItem = _stars_container.get_child(idx)
	if star is Label:
		(star as Label).text = "★" if earned else "☆"
		(star as Label).modulate = Color(1.0, 0.85, 0.35, 1.0) if earned \
			else Color(0.4, 0.4, 0.4, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(star, "modulate:a", 1.0, 0.25)
	t.tween_property(star, "scale", Vector2(1.0, 1.0), 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
