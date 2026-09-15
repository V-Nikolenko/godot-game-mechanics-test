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

## Set true by WarpModule.apply(). Not used in open space (no DashState), but
## the property must exist so WarpModule can set/clear it without error.
var warp_module_active: bool = false

## Camera feel ────────────────────────────────────────────────────────────────
## Zoom-out + camera lead applied together as the ship accelerates.
##   Zoom:  pulls back to _ZOOM_MIN at full threshold speed.
##   Lead:  shifts the viewport ahead in the direction of travel (facing).
## Both scale from 0 → full effect over 0 → _SPEED_THRESHOLD px/s.
##
## Hand-off to other systems (planet dwell, pause, shake) is managed by the
## CameraDirector child of Camera2D. We just push our target each frame; the
## director picks the highest-priority effect and smoothly blends to it.
const _ZOOM_MIN        : float = 0.85   ## Zoom level at full speed.
const _SPEED_THRESHOLD : float = 400.0  ## Speed (px/s) for full effect (zoom + lead).
const _LEAD_MAX        : float = 140.0  ## Max camera lead distance (px).
## Set true by OverclockModule.apply(). Allows firing past overheat.
var overclock_module_active: bool = false

## The ONE speed clamp on this ship, and the reason _handle_thrust() no longer carries a
## tail max_speed clamp of its own. It is floored at max_speed, so it can only ever PERMIT
## a boost's excess speed — it never yanks the ship's normal handling around.
var _speed_ceiling: float = 420.0
## Seconds left of the boost's hold window: the cyan flame, and the retrigger floor.
var _boost_hold_left: float = 0.0
var _overheat_bar: OverheatBar = null

## Same node path EngineBoostModule uses (engine_boost_module.gd:15).
const _SPRITE_PATH: String = "SpriteAnchor/ShipSprite2D"

## The ShipTurnController child — the only thing that writes this ship's rotation.
## Resolved by TYPE in _ready(), not by node path, so the wiring cannot be broken by a
## rename in the scene. Turning parameters (including the Classic 220 °/s that used to
## be this script's `rotation_speed_deg`) live on it as inspector-visible @exports.
var _turn: ShipTurnController = null

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
		if child is ShipTurnController:
			_turn = child as ShipTurnController
			break
	if _turn != null:
		## Seed the scheme from the persisted setting, and the target angle from the
		## hull's ACTUAL facing, rather than relying on the controller and the ship
		## both happening to default to 0.0.
		_turn.set_scheme(SettingsState.get_open_space_scheme(), rotation)
		SettingsState.open_space_scheme_changed.connect(
				func(scheme: StringName) -> void: _turn.set_scheme(scheme, rotation))

	## Overheat bar — top_level keeps it upright as the ship rotates;
	## _physics_process updates its global_position to track the player.
	_overheat_bar = OverheatBar.new()
	_overheat_bar.top_level = true
	add_child(_overheat_bar)
	_overheat_bar.setup(overheat_component)

	## Connect module state signals for live equip/unequip during gameplay.
	ShipModuleState.module_equipped.connect(_on_module_equipped)
	ShipModuleState.module_unequipped.connect(_on_module_unequipped)
	## Apply modules already equipped from a previous session.
	for slot: StringName in ShipModuleState.SLOTS:
		var id: StringName = ShipModuleState.get_equipped(slot)
		if id != &"":
			_apply_module(id)

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
	rotation = _turn.step(rotation, turn, delta)

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
				ThrusterEffect.State.BOOST if _boost_hold_left > 0.0
				else ThrusterEffect.State.THRUST)
		_thruster_right.set_state(
				ThrusterEffect.State.BOOST if _boost_hold_left > 0.0
				else ThrusterEffect.State.THRUST)
	elif thrust_input < 0.0:
		velocity -= forward * reverse_acceleration * delta
		_thruster.set_state(ThrusterEffect.State.THRUST)
		_thruster_right.set_state(ThrusterEffect.State.THRUST)
	else:
		velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_hold_left > 0.0
				else ThrusterEffect.State.IDLE)
		_thruster_right.set_state(
				ThrusterEffect.State.BOOST if _boost_hold_left > 0.0
				else ThrusterEffect.State.IDLE)

	## LAST, and the only Input read this feature has. Everything the boost does — the
	## trigger, the ceiling, and the speed clamp that used to sit right here — lives in
	## _step_boost(), which takes the press as an argument so a headless run (where
	## Input.is_action_just_pressed() can never return true) can still drive it.
	_step_boost(Input.is_action_just_pressed("boost"), delta)

## The whole boost model. Pure apart from the flame in the trigger branch (below): no Input,
## no Engine singletons, so every test calls it directly with an injected press.
func _step_boost(boost_pressed: bool, delta: float) -> void:
	## DELIBERATELY REDUNDANT with _handle_thrust()'s own early return, and not to be
	## "cleaned up": every test drives _step_boost() directly and so bypasses that return.
	## Without this line the two cases pinning module precedence fail on a CORRECT build,
	## and the cheapest way to green them would be to delete them. engine_boost_active is
	## READ here and never written — it stays owned by global/ship_modules/engine_boost_module.gd.
	if engine_boost_active:
		return

	## ORDER IS PART OF THE CONTRACT: the hold-window floor is checked BEFORE any spend, so
	## mashing Shift inside the window costs nothing once the meter lands (step 2 of the epic).
	if boost_pressed and _boost_hold_left <= 0.0:
		velocity = Vector2.UP.rotated(rotation) * boost_exit_speed
		_speed_ceiling = boost_exit_speed
		_boost_hold_left = boost_hold_sec
		_play_boost_flame()

	if _boost_hold_left > 0.0:
		_boost_hold_left = maxf(_boost_hold_left - delta, 0.0)
		if _boost_hold_left <= 0.0:
			_release_boost_flame()
	else:
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

func _on_module_unequipped(_slot: StringName, prev_id: StringName) -> void:
	if prev_id != &"":
		_remove_module(prev_id)

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

## Pushes the speed-zoom + camera-lead targets into the CameraDirector.
## The director blends smoothly between active effects, so no internal lerp
## is needed here — we just compute instantaneous targets each frame and let
## the director arbitrate against other effects (planet dwell, shake, etc).
func _update_camera_feel(_delta: float) -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var director := cam.get_node_or_null("CameraDirector") as CameraDirector
	if director == null:
		return

	var spd := velocity.length()
	var t   := clampf(spd / _SPEED_THRESHOLD, 0.0, 1.0)

	## Zoom out + camera lead — combined under one effect slot.
	## Lead direction tracks ship facing (not velocity) so rotation feels snappy.
	var target_zoom   := Vector2.ONE * lerpf(1.0, _ZOOM_MIN, t)
	var facing        := Vector2.UP.rotated(rotation)
	var target_offset := facing * _LEAD_MAX * t if spd > 1.0 else Vector2.ZERO
	director.set_effect(&"speed_feel", target_zoom, target_offset, 0)


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
