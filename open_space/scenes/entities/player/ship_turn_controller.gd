# open_space/scenes/entities/player/ship_turn_controller.gd
## The ONLY writer of the open-space ship's rotation.
##
## A pure step function over injected inputs — cursor world position, the A/D turn
## axis, and `delta`. It reads no `Input` and never asks for the mouse itself, because
## `Input.warp_mouse()` cannot place a cursor in a headless GUT run: the mouse is read
## in exactly one place project-wide (`player_ship.gd::_handle_rotation`) and passed in.
##
## Two schemes, selected by `scheme`:
##   &"mouse" — clamped exponential chase toward the cursor angle. The ship LEANS into
##              the cursor: it starts turning a beat after the cursor moves and is
##              rate-limited, so it never snaps.
##   &"keys"  — today's pre-epic behaviour to the degree: instantaneous A/D turning at
##              `keyboard_turn_rate_deg`, cursor ignored entirely.
##
## The two mouse parameters have two distinct jobs. `mouse_turn_half_life` decides how it
## FEELS (the lag); `mouse_max_turn_rate_deg` decides how STRONG it is (the balance). A
## designer can lower the cap without making the ship mushy, or raise the half-life
## without making it stronger. Neither can be validated headlessly — the gate proves the
## model is frame-rate correct, capped and wrap-safe, not that it feels good. A human has
## to fly the sector hub; that is why all four numbers are `@export`s on the ship scene.
##
## It is a scene node rather than a `RefCounted` for exactly that reason: a `.new()`
## object's exports are not inspector-visible.
##
## It declares no signals. The ship calls it; nothing listens to it.
class_name ShipTurnController
extends Node

## &"mouse" or &"keys". Seeded from SettingsState by the ship.
@export var scheme: StringName = &"mouse"

@export_category("Classic (keys) scheme")
## Today's `OpenSpacePlayerShip.rotation_speed_deg`. Classic is the pre-epic behaviour
## exactly, so this must stay 220.0.
@export var keyboard_turn_rate_deg: float = 220.0

@export_category("Mouse scheme")
## The balance lever: the hard per-second cap on turn rate. 180° in 1.2 s.
@export var mouse_max_turn_rate_deg: float = 150.0
## The feel lever: seconds to close half the remaining angle, before the cap bites.
@export var mouse_turn_half_life: float = 0.14
## Ship→cursor world distance below which the target angle is HELD rather than
## recomputed, so the aim does not thrash when the cursor sits under the hull.
## Measured ship-to-cursor in world space, never from screen centre — the camera
## already leads the ship by up to 140 px.
@export var mouse_dead_zone_px: float = 48.0

## The angle the ship is chasing. Held (not recomputed) inside the dead zone, while
## steering is disabled, and while a snap is being honoured.
var _target_angle: float = 0.0
## Set by `face_instant()`, cleared by `notify_mouse_moved()`. While true the cursor
## does not move the target, so an AI-Targeting snap survives until the player's next
## mouse movement instead of being undone on the very next frame.
var _snap_held: bool = false
## False while the window has lost focus: the target freezes where it was rather than
## chasing a cursor the player is no longer driving.
var _steering_enabled: bool = true


## Updates the target angle from the cursor, honouring the dead zone, the snap hold and
## the steering gate. Safe (and meaningless) to call under the &"keys" scheme.
func set_aim_target(ship_pos: Vector2, cursor_pos: Vector2) -> void:
	if not _steering_enabled or _snap_held:
		return
	var to_cursor: Vector2 = cursor_pos - ship_pos
	## A zero-length vector reports angle() == 0.0, which would snap the nose to world
	## right; the dead zone is what makes "cursor exactly on the ship" hold instead.
	if to_cursor.length() >= mouse_dead_zone_px:
		## +90°: the sprite's nose is Vector2.UP, so an angle of 0 rad points up.
		_target_angle = to_cursor.angle() + PI * 0.5


## Returns the ship's new rotation. The ONLY place rotation is computed.
func step(current_rotation: float, turn_input: float, delta: float) -> float:
	if scheme == &"keys":
		## Today's behaviour, to the degree: instantaneous, cursor ignored.
		return current_rotation + deg_to_rad(keyboard_turn_rate_deg) * turn_input * delta

	## Frame-rate-correct exponential approach: `1 - exp(-lambda * delta)` closes the
	## same fraction per unit of TIME at any frame rate, which `lerp(a, b, 0.1)` does not.
	var half_life: float = maxf(mouse_turn_half_life, 0.0001)
	var lambda: float = log(2.0) / half_life
	## Signed and wrap-correct: never takes the long way round ±PI.
	var diff: float = angle_difference(current_rotation, _target_angle)
	var turn_step: float = diff * (1.0 - exp(-lambda * delta))

	## The hard cap is the balance guarantee, not an emergent property of the half-life.
	var cap: float = deg_to_rad(mouse_max_turn_rate_deg) * delta
	turn_step = clampf(turn_step, -cap, cap)

	## Applied through the engine primitive so the wrap case cannot be got wrong and so
	## a large step can never overshoot the target.
	return rotate_toward(current_rotation, _target_angle, absf(turn_step))


## Snap: adopt `angle` as the target and hold it against the cursor until the mouse next
## moves. The caller owns the actual `rotation` write.
func face_instant(angle: float) -> void:
	_target_angle = angle
	_snap_held = true


## Releases a `face_instant()` hold. Called from the ship on InputEventMouseMotion.
func notify_mouse_moved() -> void:
	_snap_held = false


## While disabled, the target angle is frozen. Used on window focus loss so the ship does
## not keep turning toward a cursor the player has alt-tabbed away from.
func set_steering_enabled(enabled: bool) -> void:
	_steering_enabled = enabled


## Sets the scheme and re-seeds the target from the hull's actual facing. Also the
## ready-time seeder: the ship calls it in `_ready()` so the target starts at the hull's
## angle instead of relying on both defaulting to 0.0.
##
## The re-seed matters while steering is disabled, inside the dead zone and under
## &"keys"; under &"mouse" the next `set_aim_target()` overwrites it. The thing that
## actually prevents a visible jump on a mid-flight scheme flip is the per-frame rate
## cap above, which no code path can bypass.
func set_scheme(new_scheme: StringName, current_rotation: float) -> void:
	scheme = new_scheme
	_target_angle = current_rotation


## Test/inspection accessor. Not used by gameplay code — the ship reads the rotation
## `step()` returns, not the target.
func get_target_angle() -> float:
	return _target_angle
