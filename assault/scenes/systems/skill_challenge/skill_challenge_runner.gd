## SkillChallengeRunner — runs one SkillChallengeResource for its duration.
##
## Spawned by Level1Director when a challenge fires. Spawns the hazard_pattern
## (if any), watches player damage via EventBus.player_health_changed, then at
## the end emits EventBus.skill_challenge_completed(clean, bonus).
##
## ScoreTracker is the only listener for skill_challenge_completed and is
## responsible for awarding the bonus + combo boost.
class_name SkillChallengeRunner
extends Node

signal finished

@export var challenge: SkillChallengeResource

var _took_damage: bool = false
var _last_known_health: int = -1
var _hazard_instance: Node = null

func _ready() -> void:
	if challenge == null:
		push_error("[SkillChallengeRunner] No challenge resource set.")
		queue_free()
		return
	EventBus.player_health_changed.connect(_on_player_health_changed)
	_run.call_deferred()

func _on_player_health_changed(current: int, _max: int) -> void:
	if _last_known_health < 0:
		_last_known_health = current
		return
	if current < _last_known_health:
		_took_damage = true
	_last_known_health = current

func _run() -> void:
	if challenge.hazard_pattern:
		_hazard_instance = challenge.hazard_pattern.instantiate()
		# Hazard inherits the level scene as parent so it shares the camera.
		get_parent().add_child(_hazard_instance)

	print("[SkillChallenge] START '%s' (duration=%.1fs)" % [challenge.challenge_name, challenge.duration])
	# TODO: emit a UI prompt event here once the HUD prompt component lands.

	await get_tree().create_timer(challenge.duration).timeout
	if not is_inside_tree():
		return

	var clean: bool = not _took_damage
	var bonus: int = challenge.clean_bonus if clean else challenge.partial_bonus
	print("[SkillChallenge] END '%s' — %s (+%d)" % [
		challenge.challenge_name, "CLEAN" if clean else "PARTIAL", bonus,
	])
	EventBus.skill_challenge_completed.emit(clean, bonus)

	if _hazard_instance and is_instance_valid(_hazard_instance):
		_hazard_instance.queue_free()
	finished.emit()
	queue_free()
