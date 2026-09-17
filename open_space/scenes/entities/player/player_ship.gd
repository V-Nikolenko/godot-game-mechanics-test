# open_space/scenes/entities/player/player_ship.gd
## Open-space-mission player. Extends PlayerBase for shared health/shield/overheat,
## multiplier variables, and EventBus emission.
class_name OpenSpacePlayerShip
extends PlayerBase

@export_category("Movement")
@export var thrust_acceleration: float = 380.0
@export var reverse_acceleration: float = 220.0
@export var max_speed: float = 420.0
@export var damping: float = 0.6

@export_category("Boost")
## Shift boost. The nose's heading becomes the momentum, at a speed deliberately ABOVE
## max_speed — below it the redirect reads as a brake, which is exactly what the deleted
## flip-boost's 200 px/s was. These three are @exports because no headless gate can say
## whether 700 px/s FEELS right; they are meant to be fly-tested from the inspector.
@export var boost_exit_speed: float = 700.0
## How long the boost holds its ceiling and its cyan flame — and, doubling up, the floor
## under a retrigger, so mashing Shift cannot chain boosts.
@export var boost_hold_sec: float = 0.35
## px/s² the speed ceiling falls at once the hold window closes, back down to max_speed.
## 700 → 420 in 0.70 s, so the whole above-cruise signature is ~1.05 s.
@export var boost_ceiling_decay: float = 400.0
## Trauma injected into CameraShake on the boost's start frame (FLY-2) — between the
## existing 0.35 on a hit and nothing, so a boost reads as a punch, not a collision. Scaled
## by _camera_rig.get_motion_scale() so camera_motion = off (CAM-2) drops it to zero rather
## than shaking the screen outside the rig's own accessibility gate.
@export var boost_shake_trauma: float = 0.25

@export_category("Bank")
## The visual limit of the hull's lean into a turn, in radians (~7°). A sprite transform
## only — never a hull rotation, see _step_bank() below. 0.0 reverts the whole effect with
## no code change, which is the mitigation for "a shear on a top-down hull either reads as
## a lean or reads as a glitch and no headless test can tell the difference".
@export var bank_max_rad: float = 0.12
## The turn rate (deg/s) that saturates the lean at bank_max_rad. Below this the lean scales
## linearly with how hard the ship is actually turning.
@export var bank_rate_ref_deg: float = 150.0
## Exponential smoothing half-life (seconds) for the lean, both rising into a turn and
## decaying back to 0 once it stops.
@export var bank_half_life: float = 0.12

## Set true by WarpModule.apply(). Not used in open space (no DashState), but
## the property must exist so WarpModule can set/clear it without error.
var warp_module_active: bool = false

## Set true by OverclockModule.apply(). Allows firing past overheat.
var overclock_module_active: bool = false

## The ONE speed clamp on this ship, and the reason _handle_thrust() no longer carries a
## tail max_speed clamp of its own. It is floored at max_speed, so it can only ever PERMIT
## a boost's excess speed — it never yanks the ship's normal handling around.
var _speed_ceiling: float = 420.0
## Seconds left of the boost's MINIMUM burn window (a tap still buys boost_hold_sec of
## sustained thrust) and, doubling up, the anti-mash retrigger floor. No longer the flame's
## tell — see _boosting below.
var _boost_hold_left: float = 0.0
## True for the whole duration of a hold-to-boost burn, from the trigger frame through
## release or an empty meter. Drives the cyan flame and both thruster tells — NOT
## _boost_hold_left, which is now just the minimum-burn timer and can reach zero while a
## held boost is still running.
var _boosting: bool = false
var _overheat_bar: OverheatBar = null
var _boost_bar: BoostBar = null
## The lean carried between physics frames — _step_bank() reads and returns the smoothed
## value, the same shape _step_boost() uses for its own state (_boost_hold_left etc.).
var _bank_skew: float = 0.0

## Same node path EngineBoostModule uses (engine_boost_module.gd:15).
const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"

## The ShipTurnController child — the only thing that writes this ship's rotation.
## Resolved by TYPE in _ready(), not by node path, so the wiring cannot be broken by a
## rename in the scene. Turning parameters (including the Classic 220 °/s that used to
## be this script's `rotation_speed_deg`) live on it as inspector-visible @exports.
var _turn: ShipTurnController = null

## The BoostMeter child — the boost's charge economy. Resolved by TYPE in _ready() for the same
## reason as _turn above. Null-checked at every use so a ship stripped of the node still flies
## (the node being present is asserted by tests/integration/test_open_space_boost_wiring.gd,
## not by a crash in the middle of a mission).
var _boost_meter: BoostMeter = null

## The OpenSpaceCameraRig child — the speed-zoom + camera-lead formula behind the
## speed_feel effect. Resolved by TYPE in _ready() for the same reason as _turn and
## _boost_meter above. Null-checked at every use so a ship stripped of the node still
## flies with no camera feel rather than crashing.
var _camera_rig: OpenSpaceCameraRig = null

## The AimReticle child — the ring that shows the dead zone, the aim lag and whether an
## assist is being honoured. Resolved by TYPE for the same reason as the three above.
## Null-checked at every use so a ship stripped of the node still flies with no ring.
var _reticle: AimReticle = null

## Active module instances — created lazily in _apply_module().
var _module_pool: Dictionary = {}  # { StringName: ShipModuleBase }

func _ready() -> void:
	super()  # add_to_group, _setup_components, _setup_effects

	## Seeded here, not at the declaration: an @export override from the scene lands after
	## _init() but before _ready(), so this is the first point at which max_speed is the
	## value the ship will actually fly at.
	_speed_ceiling = max_speed

	## Turning. The old `rotation = 0.0` that stood here is deliberately gone: it wiped
	## the hull angle before anything could read it, which would make the seed below a
	## no-op. It was behaviour-neutral to delete — player_ship.tscn's root sets no
	## rotation, so the scene default already supplies 0.0.
	for child: Node in get_children():
		if child is ShipTurnController and _turn == null:
			_turn = child as ShipTurnController
		elif child is BoostMeter and _boost_meter == null:
			_boost_meter = child as BoostMeter
		elif child is OpenSpaceCameraRig and _camera_rig == null:
			_camera_rig = child as OpenSpaceCameraRig
		elif child is AimReticle and _reticle == null:
			_reticle = child as AimReticle
	if _turn != null:
		## Seed the scheme from the persisted setting, and the target angle from the
		## hull's ACTUAL facing, rather than relying on the controller and the ship
		## both happening to default to 0.0.
		_turn.set_scheme(SettingsState.get_open_space_scheme(), rotation)
		SettingsState.open_space_scheme_changed.connect(
				func(scheme: StringName) -> void: _turn.set_scheme(scheme, rotation))

	## The crosshair replaces the OS arrow only under mouse steering — under &"keys" there
	## is no cursor aiming to call out, so the bare arrow stays. AimCursor's install is
	## process-global and sticky (survives scene changes), so _exit_tree() below MUST
	## restore it on every exit path: mission launch, the death reload_current_scene(),
	## and quit.
	if SettingsState.get_open_space_scheme() == &"mouse":
		AimCursor.apply()

	## Same scheme gate as the cursor above: under &"keys" there is nothing for the ring to
	## show, since the controller never reads the cursor and _target_angle == rotation.
	if _reticle != null:
		_reticle.set_scheme_visible(SettingsState.get_open_space_scheme() == &"mouse")

	if _camera_rig != null:
		## Seed the accessibility scale from the persisted setting and follow it live —
		## a player who turns camera_motion off mid-flight should feel it immediately,
		## not on the next scene load.
		_camera_rig.set_motion_scale(_camera_motion_scale(SettingsState.get_camera_motion()))
		SettingsState.camera_motion_changed.connect(
				func(value: StringName) -> void: _camera_rig.set_motion_scale(_camera_motion_scale(value)))

	## Overheat bar — top_level keeps it upright as the ship rotates;
	## _physics_process updates its global_position to track the player.
	_overheat_bar = OverheatBar.new()
	_overheat_bar.top_level = true
	add_child(_overheat_bar)
	_overheat_bar.setup(overheat_component)

	## Boost bar — same top_level pattern as the overheat bar, positioned 6 px under it
	## (OverheatBar.BAR_HEIGHT = 4) in _physics_process. Only created if the ship actually
	## carries a BoostMeter, so a ship stripped of the node does not crash.
	if _boost_meter != null:
		_boost_bar = BoostBar.new()
		_boost_bar.top_level = true
		add_child(_boost_bar)
		_boost_bar.setup(_boost_meter)

	## Connect module state signals for live equip/unequip during gameplay.
	ShipModuleState.module_equipped.connect(_on_module_equipped)
	ShipModuleState.module_unequipped.connect(_on_module_unequipped)
	## Apply modules already equipped from a previous session.
	for slot: StringName in ShipModuleState.SLOTS:
		var id: StringName = ShipModuleState.get_equipped(slot)
		if id != &"":
			_apply_module(id)
	_update_boost_tanks(ShipModuleState.get_equipped(&"engines"))

## The symmetric half of the AimCursor.apply() call in _ready() above. restore() is a safe
## no-op if apply() was never called (the &"keys" scheme, or a ship freed before _ready()
## finished), which is what lets this run unconditionally on every exit path.
func _exit_tree() -> void:
	AimCursor.restore()

func _setup_effects() -> void:
	_hit_effect = HitEffect.new()
	_hit_effect.amount = 10
	_hit_effect.lifetime = 0.25
	_hit_effect.color = Color(1.0, 0.35, 0.1)
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

	var engine_left  := $SpriteAnchor/EngineLeft  as Node2D
	var engine_right := $SpriteAnchor/EngineRight as Node2D
	_thruster = ThrusterEffect.new()
	engine_left.add_child(_thruster)
	_thruster_right = ThrusterEffect.new()
	engine_right.add_child(_thruster_right)

func _physics_process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_thrust(delta)
	move_and_slide()
	## Keep overheat bar centred on the ship in world space.
	if _overheat_bar != null:
		_overheat_bar.global_position = global_position + Vector2(0.0, 20.0)
	if _boost_bar != null:
		_boost_bar.global_position = global_position + Vector2(0.0, 26.0)
	## Centred on the hull, unlike the two bars above — the ring measures the ship itself.
	if _reticle != null:
		_reticle.global_position = global_position
	_update_camera_feel(delta)
	## Tick all equipped modules every frame (handles cooldowns, timed effects).
	for id: StringName in _module_pool.keys():
		_module_pool[id].tick(self, delta)

## The OS pointer stops updating while the window is unfocused, but
## get_global_mouse_position() keeps returning the last in-window position — so without
## this the ship holds a stale target angle and keeps turning toward it while the player
## is alt-tabbed away. Freezing (rather than clearing) the target means resuming on
## FOCUS_IN has no discontinuity: step() keeps running throughout, it just has nothing
## new to chase.
func _notification(what: int) -> void:
	if _turn == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_turn.set_steering_enabled(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_turn.set_steering_enabled(true)

func _input(event: InputEvent) -> void:
	## Real mouse motion releases an AITargetingModule snap. Deliberately NOT keyed off
	## cursor position: get_global_mouse_position() is a world position that moves with
	## the camera, so a physically still mouse would otherwise clear the snap on the
	## very next frame. Not marked handled — this must not steal the event from anything
	## else that reads mouse motion.
	if event is InputEventMouseMotion:
		if _turn != null:
			_turn.notify_mouse_moved()
		return
	## _input fires before _unhandled_input — modules get first pick of H-key.
	if not event.is_action_pressed("use_ability"):
		return
	for id: StringName in _module_pool.keys():
		var mod: ShipModuleBase = _module_pool[id]
		## Boost Drive is fired from Shift in open space (it spends a boost tank there —
		## see _step_boost()); leaving H wired to it too would fire the same burst for free.
		## player_fighter.gd's own H loop does not skip this — assault has no Shift boost to
		## conflict with.
		if mod.is_open_space_boost_verb():
			continue
		if mod.try_activate(self):
			get_viewport().set_input_as_handled()
			return  ## Consumed by module.

## Duck-typed entry point for AITargetingModule (and anything else that needs an
## instant snap): adopt `angle` as the hull's rotation AND the turn controller's
## target, and suppress cursor steering until the player's next real mouse motion —
## otherwise the controller's own step() would undo the snap within a frame or two.
func face_instant(angle: float) -> void:
	rotation = angle
	if _turn != null:
		_turn.face_instant(angle)

func _handle_rotation(delta: float) -> void:
	var turn: float = 0.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	if _turn == null:
		return
	## `get_global_mouse_position()` is a CanvasItem method: it accounts for the canvas
	## transform and the project's stretch/mode="canvas_items", so it is correct at any
	## window size where a raw DisplayServer.mouse_get_position() would not be. This is
	## the ONE place the mouse is read project-wide — everything downstream of here takes
	## the cursor as an injected argument, which is what makes the turn model testable in
	## a headless run that cannot place a cursor.
	_turn.set_aim_target(global_position, get_global_mouse_position())
	var previous_rotation: float = rotation
	rotation = _turn.step(rotation, turn, delta)
	## Fed what the controller just computed, on the very next line — never its own read of
	## the mouse. Ring radius comes straight from the controller's export; never duplicated.
	if _reticle != null:
		_reticle.set_aim(_turn.mouse_dead_zone_px, _turn.get_target_angle(), rotation,
				_turn.is_snap_held(), _turn.is_steering_enabled())
	## Sprite lean, computed from what _turn.step() just wrote — never the other way round.
	## Target is $SpriteAnchor/ShipSprite2D, NOT $SpriteAnchor itself: Node2D.skew propagates
	## to children, and SpriteAnchor also parents MuzzleLeft/MuzzleRight (WeaponState's bullet
	## spawn points) and EngineLeft/EngineRight — skewing the anchor would shear all four.
	var sprite := get_node_or_null(_SPRITE_PATH) as AnimatedSprite2D
	if sprite != null:
		sprite.skew = _step_bank(rotation - previous_rotation, delta)

## Pure apart from carrying its own smoothed state in _bank_skew (same shape as
## _step_boost()'s _boost_hold_left/_boosting): no Input, no node access, so a test can
## drive it directly with injected rotation deltas across repeated calls and see the
## smoothing accumulate. rotation_delta is the hull's rotation change over `delta`, exactly
## what _handle_rotation() just wrote to `rotation` minus what it was a moment before — this
## function never writes `rotation` itself, only ever reads the delta it was handed.
func _step_bank(rotation_delta: float, delta: float) -> float:
	var target: float = 0.0
	if delta > 0.0:
		var rate_deg: float = rad_to_deg(rotation_delta) / delta
		target = clampf(rate_deg / bank_rate_ref_deg, -1.0, 1.0) * bank_max_rad
	var weight: float = 1.0
	if bank_half_life > 0.0:
		weight = clampf(1.0 - pow(0.5, delta / bank_half_life), 0.0, 1.0)
	_bank_skew = lerpf(_bank_skew, target, weight)
	return _bank_skew

func _handle_thrust(delta: float) -> void:
	## EngineBoostModule controls velocity directly while active;
	## skip all thrust/damping/cap to preserve straight-line direction.
	if engine_boost_active:
		return
	var forward: Vector2 = Vector2.UP.rotated(rotation)
	var thrust_input: float = 0.0
	if Input.is_action_pressed("move_up"):
		thrust_input += 1.0
	if Input.is_action_pressed("move_down"):
		thrust_input -= 1.0

	if thrust_input > 0.0:
		velocity += forward * thrust_acceleration * delta
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boosting
				else ThrusterEffect.State.THRUST)
		_thruster_right.set_state(
				ThrusterEffect.State.BOOST if _boosting
				else ThrusterEffect.State.THRUST)
	elif thrust_input < 0.0:
		velocity -= forward * reverse_acceleration * delta
		_thruster.set_state(ThrusterEffect.State.THRUST)
		_thruster_right.set_state(ThrusterEffect.State.THRUST)
	else:
		velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boosting
				else ThrusterEffect.State.IDLE)
		_thruster_right.set_state(
				ThrusterEffect.State.BOOST if _boosting
				else ThrusterEffect.State.IDLE)

	## LAST, and the only Input reads this feature has. Everything the boost does — the
	## trigger, the sustain, the ceiling, and the speed clamp that used to sit right here —
	## lives in _step_boost(), which takes both the edge and the level as arguments so a
	## headless run (where neither Input.is_action_just_pressed() nor
	## Input.is_action_pressed() can ever return true) can still drive it.
	## MUST run AFTER the thrust/damping block above: a sustained hold re-asserts `velocity`
	## every frame (see _step_boost()), and that overwrite is what stops this block's own
	## damping branch from fighting a held boost. Reordering the call ahead of the block
	## would let a no-thrust-input frame damp the boost away underneath it.
	_step_boost(Input.is_action_just_pressed("boost"), Input.is_action_pressed("boost"), delta)

## The whole boost model. Pure apart from the flame calls in the trigger/stop branches: no
## Input, no Engine singletons, so every test calls it directly with injected edge/level bools.
func _step_boost(boost_pressed: bool, boost_held: bool, delta: float) -> void:
	## DELIBERATELY REDUNDANT with _handle_thrust()'s own early return, and not to be
	## "cleaned up": every test drives _step_boost() directly and so bypasses that return.
	## Without this line the two cases pinning module precedence fail on a CORRECT build,
	## and the cheapest way to green them would be to delete them. engine_boost_active is
	## READ here and never written — it stays owned by global/ship_modules/engine_boost_module.gd.
	if engine_boost_active:
		return

	## The meter has no _physics_process of its own — the ship owns its clock, so a meter on a
	## ship whose physics is off (a mission menu opening) is frozen with it. Stepped before the
	## trigger so the drain below (if any) sets a full, un-decremented recharge pause.
	## The same freeze also covers a Boost Drive burst (the early `return` above stops this
	## line from running at all while engine_boost_active is true) — that is correct, not a
	## gap to route around: the tank spend already sets recharge_delay_sec = 0.5 of the
	## module's 0.55 s burst, so at most ~0.05 s worth of regen is ever at stake.
	if _boost_meter != null:
		_boost_meter.step(delta)

	## Boost Drive equipped: Shift becomes a tank-spend trigger for the module's OWN burst
	## instead of the default hold-to-boost model below — the module's tick() drives
	## `velocity` directly once engine_boost_active is set, and the early return at the top
	## of this function is what stops the two systems fighting over it from the next frame.
	## ORDER IS PART OF THE CONTRACT here too, same discipline as the default press branch
	## below: can_activate() is checked BEFORE the spend, because try_activate() itself
	## refuses outright on the module's 2.0 s cooldown while the retrigger floor here is only
	## boost_hold_sec = 0.35 s — spending first would burn a whole tank on every press in
	## that window for a `try_activate()` that was always going to return false.
	var drive: ShipModuleBase = _module_pool.get(&"engine_boost", null) as ShipModuleBase
	if drive != null:
		if boost_pressed and drive.can_activate() \
				and (_boost_meter == null or _boost_meter.try_spend_tank()):
			drive.try_activate(self)
			## Return immediately (review R2-N4): the module's 1500 px/s frame-one burst
			## must not run into the tail clamp below, which would otherwise clip it straight
			## back down to _speed_ceiling on the very frame it started.
			return
	## ORDER IS PART OF THE CONTRACT: `not _boosting` and the hold-window floor are both
	## checked BEFORE anything else (`and` short-circuits left to right), so mashing Shift
	## while a boost is already running never restarts the minimum-burn timer, and a meter
	## below min_start_charge refuses outright — no velocity write, no drain.
	elif boost_pressed and not _boosting and _boost_hold_left <= 0.0 \
			and (_boost_meter == null or _boost_meter.charges >= _boost_meter.min_start_charge):
		_boosting = true
		_boost_hold_left = boost_hold_sec
		velocity = Vector2.UP.rotated(rotation) * boost_exit_speed
		_speed_ceiling = boost_exit_speed
		_play_boost_flame()
		## FLY-2: the start-frame punch. Falls back to a scale of 1.0 with no rig, so a bare
		## instantiated ship (no OpenSpaceCameraRig child) behaves as it does today.
		CameraShake.add(boost_shake_trauma
				* (_camera_rig.get_motion_scale() if _camera_rig != null else 1.0))
		if _camera_rig != null:
			_camera_rig.set_boosting(true)

	if _boost_hold_left > 0.0:
		## Ticks down unconditionally, independent of _boosting: it is what lets the floor
		## keep counting even across an empty-meter stop (below), rather than getting stuck.
		_boost_hold_left = maxf(_boost_hold_left - delta, 0.0)

	if _boosting:
		## THE SUSTAIN. drain() is the continuous spend; re-asserting `velocity` along the
		## CURRENT nose (not a direction captured at the trigger) every frame is what makes
		## the hold buy anything at all — _speed_ceiling is a clamp, never a force, so a
		## ceiling-only sustain would leave the thrust/damping block above free to slow the
		## ship down while the bar drains underneath it.
		var meter_ok: bool = _boost_meter == null or _boost_meter.drain(_boost_meter.drain_rate * delta)
		if meter_ok:
			_speed_ceiling = boost_exit_speed
			velocity = Vector2.UP.rotated(rotation) * boost_exit_speed
		if not meter_ok or (not boost_held and _boost_hold_left <= 0.0):
			_boosting = false
			_release_boost_flame()
			if _camera_rig != null:
				_camera_rig.set_boosting(false)

	if not _boosting:
		## move_toward is a linear ramp, so this is exactly frame-rate independent (unlike the
		## lerp damping above, which is deliberately left alone here). maxf keeps the ceiling
		## from ever dropping below cruise.
		_speed_ceiling = maxf(
				move_toward(_speed_ceiling, max_speed, boost_ceiling_decay * delta),
				max_speed)

	if velocity.length() > _speed_ceiling:
		velocity = velocity.normalized() * _speed_ceiling

## _step_boost()'s one tree touch, following engine_boost_module.gd:15,63-67 — the cyan flame is
## the epic's chosen tell for "that was a boost". _handle_thrust()'s branches hold both thrusters
## in BOOST for as long as _boost_hold_left is positive; setting them here too means the trigger
## frame itself is not missing the flame.
func _play_boost_flame() -> void:
	var sprite := get_node_or_null(_SPRITE_PATH) as AnimatedSprite2D
	if sprite != null:
		sprite.play(&"flame_boost")
	if _thruster != null:
		_thruster.set_state(ThrusterEffect.State.BOOST)
	if _thruster_right != null:
		_thruster_right.set_state(ThrusterEffect.State.BOOST)

## The counterpart of the above, and not optional: flame_boost has `loop = false`, so without it
## the hull sits on the animation's last frame for the rest of the scene. Guarded on the current
## animation so it cannot stomp an EngineBoostModule boost or the hub's planet_dive that started
## inside our window.
func _release_boost_flame() -> void:
	var sprite := get_node_or_null(_SPRITE_PATH) as AnimatedSprite2D
	if sprite != null and sprite.animation == &"flame_boost":
		sprite.play(&"idle")

func _get_or_create_module(id: StringName) -> ShipModuleBase:
	if not _module_pool.has(id):
		var inst: ShipModuleBase = _create_module(id)
		if inst != null:
			_module_pool[id] = inst
	return _module_pool.get(id, null)

func _create_module(id: StringName) -> ShipModuleBase:
	return ShipModuleBase.create(id)

func _apply_module(id: StringName) -> void:
	var mod := _get_or_create_module(id)
	if mod:
		mod.apply(self)

func _remove_module(id: StringName) -> void:
	var mod: ShipModuleBase = _module_pool.get(id, null) as ShipModuleBase
	if mod:
		mod.remove(self)
		_module_pool.erase(id)

func _on_module_equipped(_slot: StringName, module_id: StringName) -> void:
	if module_id != &"":
		_apply_module(module_id)
	_update_boost_tanks(ShipModuleState.get_equipped(&"engines"))

## `slot` deliberately NOT prefixed `_` here, unlike the sibling above: it is read below.
func _on_module_unequipped(slot: StringName, prev_id: StringName) -> void:
	if prev_id != &"":
		_remove_module(prev_id)
	## NOT ShipModuleState.get_equipped(&"engines") here — ShipModuleState.equip() emits
	## module_unequipped BEFORE it writes _equipped[slot], so querying it from this handler
	## would read back prev_id, the module that is in the process of being removed, and an
	## unequip-to-nothing (no module_equipped emit to follow and correct it) would leave the
	## bar stuck at 3/4 tanks forever. Reason from what this signal actually tells us instead.
	var engines_now: StringName = \
			&"" if slot == &"engines" else ShipModuleState.get_equipped(&"engines")
	_update_boost_tanks(engines_now)

## The tier switch (BST-3): no new state beyond what the caller already knows about the
## engines slot. tanks = 1 (one long bar) without Boost Drive equipped; 3 with it; 4 once
## ShipProgressionState.boost_charge_count is maxed out — the player's own "3-4 parts
## depending on the amount of upgrades".
func _update_boost_tanks(engines_equipped: StringName) -> void:
	if _boost_meter == null:
		return
	if engines_equipped != &"engine_boost":
		_boost_meter.set_tanks(1)
		return
	var at_max_capacity: bool = \
			ShipProgressionState.boost_charge_count >= ShipProgressionState.MAX_BOOST_CHARGES
	_boost_meter.set_tanks(4 if at_max_capacity else 3)

## Scene-connected: HurtBox.received_damage → _on_received_damage.
func _on_received_damage(damage: int) -> void:
	_apply_damage(damage)
	_hit_effect.burst()
	CameraShake.add(0.35)

## Override: emit EventBus, handle death with delayed scene reload.
func _on_health_changed(current: int) -> void:
	super(current)  # emits EventBus.player_health_changed
	if current == 0:
		_explosion_effect.explode()
		CameraShake.add(1.0)
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(self):
			get_tree().reload_current_scene()

## SettingsState.camera_motion (&"full"/&"reduced"/&"off") -> the rig's _motion_scale.
## An unrecognised value reads as &"full" here too, matching SettingsState's own fallback.
static func _camera_motion_scale(value: StringName) -> float:
	match value:
		&"off":
			return 0.0
		&"reduced":
			return 0.5
		_:
			return 1.0

## Pushes the speed-zoom + camera-lead targets (computed by _camera_rig) into the
## CameraDirector. The director blends smoothly between active effects, so no internal
## lerp is needed here beyond the rig's own smoothing — we just step the rig and forward
## its output, and let the director arbitrate against other effects (planet dwell, shake).
func _update_camera_feel(delta: float) -> void:
	if _camera_rig == null:
		return
	_camera_rig.step(velocity, delta)
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var director := cam.get_node_or_null("CameraDirector") as CameraDirector
	if director == null:
		return
	director.set_effect(&"speed_feel", _camera_rig.get_zoom(velocity), _camera_rig.get_offset(), 0)


## Override: overheat gating with overclock and overdrive module support.
func _on_overheat_updated(pct: float) -> void:
	super(pct)  # emits EventBus.player_overheat_changed
	## Overclock module: never lock weapons, even at 100% heat.
	if overclock_module_active:
		can_attack = true
		return
	## Overdrive module: suppresses overheat lock while active.
	if overdrive_active:
		can_attack = true
		return
	can_attack = pct < 100.0
