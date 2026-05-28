# global/components/bubble_shield.gd
## Bubble-shield visual attached to the player's SpriteAnchor.
## Plays shield_pick_up when any shield is gained, shield_break when a charge
## is consumed by a hit.  Both animations are non-looping; after finishing,
## the sprite stays visible (last frame) if shields remain, or hides if empty.
##
## Created and wired automatically by PlayerBase._setup_bubble_shield().
## Do not add manually to player scenes.
class_name BubbleShield
extends AnimatedSprite2D

var _prev_total: int = 0

## Call once after add_child() with the player's Shield component.
func setup(shield: Shield) -> void:
	if shield == null:
		return
	_prev_total = shield.permanent_active + shield.temporary_count
	if _prev_total > 0:
		visible = true
		play(&"shield_idle")
	shield.shield_state_changed.connect(_on_shield_state_changed)
	## Play pickup animation even when shields are already at cap (total unchanged).
	shield.shield_pickup_collected.connect(_on_shield_pickup_collected)

func _ready() -> void:
	animation_finished.connect(_on_animation_finished)
	visible = false

func _on_shield_state_changed(snap: Dictionary) -> void:
	var new_total: int = snap.get("perm_active", 0) + snap.get("temp_count", 0)

	if new_total > _prev_total:
		## Shield gained (pickup / regen / permanent unlock).
		visible = true
		play(&"shield_pick_up")
	elif new_total < _prev_total and _prev_total > 0:
		## Shield charge consumed by a hit.
		visible = true
		play(&"shield_break")

	_prev_total = new_total

	## If all shields drained and nothing is playing, hide immediately.
	if new_total == 0 and not is_playing():
		visible = false

## Fired when a pickup was collected but shields were already at cap.
## Still play the animation so the player gets visual feedback.
func _on_shield_pickup_collected() -> void:
	visible = true
	play(&"shield_pick_up")

func _on_animation_finished() -> void:
	if _prev_total > 0:
		## Shields still active — loop idle animation as the resting visual.
		play(&"shield_idle")
	else:
		visible = false
