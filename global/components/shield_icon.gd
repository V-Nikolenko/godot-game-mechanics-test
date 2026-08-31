# global/components/shield_icon.gd
## Single animated shield slot. PERMANENT and TEMPORARY tiers use different
## animation prefixes ("shield_*" vs "additional_shield_*") in the shared
## SpriteFrames resource at global/components/shield_animations.tres.
class_name ShieldIcon
extends AnimatedSprite2D

enum Tier { PERMANENT, TEMPORARY }

const _INTERFERENCE_MIN_SEC: float = 3.0
const _INTERFERENCE_MAX_SEC: float = 4.0

var tier: int = Tier.PERMANENT
var _is_empty: bool = false   ## true after destroy for PERMANENT; TEMPORARY queue_frees instead
var _interference_timer: Timer = null

func _ready() -> void:
	_interference_timer = Timer.new()
	_interference_timer.one_shot = true
	_interference_timer.timeout.connect(_on_interference_tick)
	add_child(_interference_timer)

func setup(t: int) -> void:
	tier = t
	_is_empty = false
	play("%s_idle" % _prefix())

func play_destroy() -> void:
	if _is_empty:
		return
	var done := animation_finished
	play("%s_destroy" % _prefix())
	await done
	if tier == Tier.TEMPORARY:
		queue_free()
		return
	_is_empty = true
	## The destroy animation's last frame is authored as the "empty slot" sprite,
	## so we stop here and leave it shown. Calling stop() would reset to frame 0.

func play_recharge() -> void:
	var done := animation_finished
	play("%s_recharge" % _prefix())
	await done
	_is_empty = false
	play("%s_idle" % _prefix())

func play_hacked() -> void:
	play("%s_hacked_idle" % _prefix())
	_schedule_next_interference()

func play_restore() -> void:
	_interference_timer.stop()
	var done := animation_finished
	play("%s_restore_after_hacking" % _prefix())
	await done
	play("%s_idle" % _prefix())

func _prefix() -> String:
	return "shield" if tier == Tier.PERMANENT else "additional_shield"

func _schedule_next_interference() -> void:
	var wait: float = randf_range(_INTERFERENCE_MIN_SEC, _INTERFERENCE_MAX_SEC)
	_interference_timer.start(wait)

func _on_interference_tick() -> void:
	if not is_inside_tree():
		return
	var done := animation_finished
	play("%s_hacked_interference" % _prefix() if tier == Tier.PERMANENT \
			else "%s_hacked" % _prefix())
	await done
	if not is_inside_tree():
		return
	play("%s_hacked_idle" % _prefix())
	_schedule_next_interference()
