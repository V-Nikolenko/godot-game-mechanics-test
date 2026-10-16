## The Support Ship's brain (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.11-§2.12; tasks t10 shell, t11 ward and
## follow; build choices in docs/plans/cmv9szqlz002bqs2x0h47xa3x/3-plan.md).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   SEEK_WARD  [SEARCH]     no ward: holds `follow_distance` from the nearest live ally (any `BaseEnemy`, never another
##                           support), or stands still with none. With a view rect (Assault) the hold point is clamped
##                           into the view, and after `no_ward_grace` s without a ward spent inside the view it
##                           DISENGAGEs.
##   FOLLOW     [POSITION]   shadows its ward on a soft anchor behind it (away from the player), jinks, breaks contact
##                           when the player comes inside `evade_radius`, faces the ward. Never pursues the player.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out (or the grace did). Release the corridor, curve away toward
##                           the nearest corridor edge at `exit_speed`, freed once outside the projectile rect (the
##                           Bomber's exit). It has no telegraphed attack, so nothing defers the exit.
##   ESCORT / IDLE / NOTICING / RETURNING  reserved for t13 and t15.
##
## The ward: chosen among candidates (`is_candidate`) by `threat_score`, held at least `min_ward_seconds`, then replaced
## only by a candidate scoring `ward_switch_margin` × as much. Claimed through the meta `CLAIM_META` so two supports never
## share one. Lost (freed, killed, railed, out of `ward_keep_radius`, out of the Assault view band) → dropped and a new one
## picked on the next tick. `_set_ward()` is the only writer of `ward`, the claim and the `tree_exiting` connection.
##
## Rails: `on_suspended()` drops the ward and folds the projector. The ship has no weapon, so there is no rail
## fallback.
##
## Requests only (single-writer gate): the writes on the mover are `arrive`, `request_velocity`, `face_toward`,
## `max_speed` and `release_constraint()` on DISENGAGE.
class_name SupportShipBrain
extends EnemyBrain

enum Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)
## Emitted on every change of ward, with the new ward; null when the ward was lost or dropped. A loss followed by a
## re-pick emits null, then the new ward.
signal ward_changed(new_ward: Node)
## Emitted for every repair pulse that restored HP: the ward and the HP it gained.
signal repaired(ward: Node, amount: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The ship stops closing inside this distance of its SEEK_WARD hold point (px).
const HOLD_TOLERANCE := 12.0
## The ward's meta holding the instance id of the support that claimed it.
const CLAIM_META := &"support_claim"
## The distance to the player (px) at which a candidate's threat is halved.
const THREAT_DISTANCE_SCALE := 600.0
## The soft anchor's spring (1/s): near the anchor the seek speed is `distance × FOLLOW_GAIN`, so the jink and the
## evasion are visible against it; far away it is the full-speed `arrive`. Judgement (t11 plan).
const FOLLOW_GAIN := 2.0
## Inside this fraction of `evade_radius` only the escape steers; between it and `evade_radius` the anchor gives way
## linearly.
const EVADE_FULL_FRACTION := 0.8
## The escape's sideways share (`Steering.break_contact`'s `lateral_weight`; doubled for a closing threat). The default 0.6
## leaves ~154 px/s of radial escape at `evade_speed` 240 against a closing player, slower than a 200 px/s one; 0.3 leaves
## ~206 px/s. t11 plan, review round 2.
const EVADE_LATERAL_WEIGHT := 0.3
## The tether flashes pale green this long after a repair pulse (s).
const REPAIR_FLASH_SECONDS := 0.15
## The shield's radius is the ward's hull radius plus this (px), and the radius used when the hull has no shape.
const SHIELD_RADIUS_MARGIN := 6.0
const DEFAULT_HULL_RADIUS := 34.0

## Set by `support_ship.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: SupportShipConfig = SupportShipConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.SEEK_WARD
## The ally being supported, or null. Read it through `has_ward()`; written only by `_set_ward()` (a test may assign it
## directly; `_set_ward(null)` tolerates a ward it never claimed or connected).
var ward: BaseEnemy = null
## The current ward's threat score, refreshed every tick.
var ward_score: float = 0.0
## Seconds since the current ward was selected.
var ward_held_for: float = 0.0
## Non-null selections so far.
var wards_selected: int = 0
## The FOLLOW target this tick (after the Assault clamp); `Vector2.INF` with no ward.
var anchor: Vector2 = Vector2.INF
## ±1, drawn at each selection: which side of the ward line the anchor sits on, and the evasion's side.
var follow_side: float = 1.0
## ±1, the jink's current direction across the ward line; redrawn every `jink_period`.
var jink_sign: float = 1.0
## 0 = folded, 1 = unfolded: the dish. Rises while supporting over `projector_unfold_seconds`, falls over `projector_fold_seconds`.
var projector_open: float = 0.0
## HP restored so far this life, against `repair_budget`.
var repair_spent: int = 0
## The shield this support projects on its current ward, or null. The ward owns it (it is the ward's child); this
## reference only says whether one needs creating. Cleared on a ward change and when the shield lapses.
var shield: EnemyShield = null

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
var _expiry_seen: bool = false
var _jink_clock: float = 0.0
var _repair_clock: float = 0.0
var _repair_flash_left: float = 0.0
## Seconds without a ward spent inside the Assault view (the grace clock).
var _no_ward_time: float = 0.0
## The exact callable connected to the ward's `tree_exiting`, so the disconnect is guarded and exact.
var _ward_exit_cb: Callable = Callable()


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if budget.update(delta) and not _expiry_seen:
		_expiry_seen = true
		if phase != Phase.DISENGAGE:
			enter_phase(Phase.DISENGAGE)
	if phase == Phase.DISENGAGE:
		_tick_disengage(delta)
		_tick_support(delta)
		return

	if ward != null and not _ward_still_valid():
		_set_ward(null)
	_update_selection()

	if has_ward():
		ward_held_for += delta
		_no_ward_time = 0.0
		if phase != Phase.FOLLOW:
			enter_phase(Phase.FOLLOW)
	else:
		if phase != Phase.SEEK_WARD:
			enter_phase(Phase.SEEK_WARD)
		if budget.active and _inside_view(actor.global_position, config.view_band):
			_no_ward_time += delta
			if _no_ward_time >= config.no_ward_grace:
				enter_phase(Phase.DISENGAGE)
				_tick_disengage(delta)
				_tick_support(delta)
				return

	match phase:
		Phase.SEEK_WARD: _tick_seek_ward()
		Phase.FOLLOW: _tick_follow(delta)
	_tick_support(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	if p == Phase.DISENGAGE:
		_enter_disengage()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. Drop the ward and fold the dish; there is no weapon.
func on_suspended() -> void:
	_set_ward(null)
	projector_open = 0.0
	_repair_flash_left = 0.0
	if actor is SupportShip:
		(actor as SupportShip).fold_projector()


func _exit_tree() -> void:
	_set_ward(null)


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


# ── The ward ────────────────────────────────────────────────────────────────────────────────────

func has_ward() -> bool:
	return ward != null and is_instance_valid(ward)


## The §2.12 filter, in its order: a `BaseEnemy`, not this ship, not a support, AI-driven (brain + mover, not on a
## rail), alive, not queued, a combatant (`counts_toward_wave_clear`), worth at least `ward_min_score`, within
## `ward_search_radius`, in Assault inside `view.grow(ward_view_band)`, and not claimed by another live support.
func is_candidate(e: BaseEnemy) -> bool:
	if e == null or not is_instance_valid(e) or e == actor or e is SupportShip:
		return false
	if not e.is_ai_driven() or e.is_queued_for_deletion() or e.health == null or e.health.current_health <= 0:
		return false
	if not e.counts_toward_wave_clear or e.score_value < config.ward_min_score:
		return false
	if actor.global_position.distance_to(e.global_position) > config.ward_search_radius:
		return false
	if EnemyWorld.has_view_rect(get_tree()) and not _inside_view(e.global_position, config.ward_view_band):
		return false
	return not _claimed_by_another(e)


## `score_value × 1 / (1 + d_player / 600) × (1 + (1 − hp_fraction))`: kind weight, closeness to the player, damage
## taken. `d_player` is 0 with no player.
func threat_score(e: BaseEnemy) -> float:
	var target := TargetInfo.player(get_tree())
	var d_player := target.position.distance_to(e.global_position) if target.has_target else 0.0
	var hp_fraction := 1.0
	if e.health != null and e.health.max_health > 0:
		hp_fraction = float(e.health.current_health) / float(e.health.max_health)
	return float(e.score_value) / (1.0 + d_player / THREAT_DISTANCE_SCALE) * (1.0 + (1.0 - hp_fraction))


## The highest-scoring candidate, or null. Ties keep scan order.
func best_candidate() -> BaseEnemy:
	var best: BaseEnemy = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as BaseEnemy
		if e == null or not is_candidate(e):
			continue
		var s := threat_score(e)
		if s > best_score:
			best_score = s
			best = e
	return best


## §2.12 `is_supporting()`: a valid ward within `beam_range`; with a view rect, this ship inside `view.grow(view_band)`
## and the ward inside `view.grow(ward_view_band)`.
func is_supporting() -> bool:
	if not has_ward() or ward.is_queued_for_deletion():
		return false
	if actor.global_position.distance_to(ward.global_position) > config.beam_range:
		return false
	if EnemyWorld.has_view_rect(get_tree()):
		if not _inside_view(actor.global_position, config.view_band):
			return false
		if not _inside_view(ward.global_position, config.ward_view_band):
			return false
	return true


## The nearest live ally that is not another support, or null (the SEEK_WARD hold; any `BaseEnemy`, candidate or not).
func nearest_ally() -> BaseEnemy:
	var best: BaseEnemy = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var ally := node as BaseEnemy
		if ally == null or ally == actor or ally is SupportShip or ally.is_queued_for_deletion():
			continue
		var d := actor.global_position.distance_squared_to(ally.global_position)
		if d < best_d:
			best_d = d
			best = ally
	return best


## No ward → take the best candidate. A ward held at least `min_ward_seconds` → switch only to a candidate scoring at
## least `ward_switch_margin` × the ward's own (refreshed) score.
func _update_selection() -> void:
	if not has_ward():
		var first := best_candidate()
		if first != null:
			_set_ward(first)
		return
	ward_score = threat_score(ward)
	if ward_held_for < config.min_ward_seconds:
		return
	var best := best_candidate()
	if best != null and best != ward and threat_score(best) >= config.ward_switch_margin * ward_score:
		_set_ward(best)


## Still a ward this tick: alive, AI-driven (not railed), inside `ward_keep_radius`, and in Assault inside
## `view.grow(ward_view_band)`. The minimum hold does not protect a lost ward.
func _ward_still_valid() -> bool:
	if not has_ward() or ward.is_queued_for_deletion() or not ward.is_inside_tree():
		return false
	if ward.health == null or ward.health.current_health <= 0 or not ward.is_ai_driven():
		return false
	if actor.global_position.distance_to(ward.global_position) > config.ward_keep_radius:
		return false
	if EnemyWorld.has_view_rect(get_tree()) and not _inside_view(ward.global_position, config.ward_view_band):
		return false
	return true


func _claimed_by_another(e: BaseEnemy) -> bool:
	if not e.has_meta(CLAIM_META):
		return false
	var id: int = e.get_meta(CLAIM_META)
	if id == 0 or id == actor.get_instance_id():
		return false
	return instance_from_id(id) != null


## The only writer of `ward`, its claim and its `tree_exiting` connection.
func _set_ward(new_ward: BaseEnemy) -> void:
	var old: BaseEnemy = ward if has_ward() else null
	if old == new_ward and new_ward != null:
		return
	if old != null:
		if _ward_exit_cb.is_valid() and old.tree_exiting.is_connected(_ward_exit_cb):
			old.tree_exiting.disconnect(_ward_exit_cb)
		if actor != null and old.has_meta(CLAIM_META) and old.get_meta(CLAIM_META) == actor.get_instance_id():
			old.remove_meta(CLAIM_META)
	_ward_exit_cb = Callable()
	ward = new_ward
	ward_held_for = 0.0
	ward_score = 0.0
	_repair_clock = 0.0
	shield = null  # the old ward's shield is no longer sustained: it lapses on its own
	if new_ward != null:
		new_ward.set_meta(CLAIM_META, actor.get_instance_id())
		_ward_exit_cb = _on_ward_tree_exiting.bind(new_ward)
		new_ward.tree_exiting.connect(_ward_exit_cb)
		follow_side = -1.0 if rng.randf() < 0.5 else 1.0
		jink_sign = -1.0 if rng.randf() < 0.5 else 1.0
		_jink_clock = 0.0
		wards_selected += 1
		ward_score = threat_score(new_ward)
	else:
		anchor = Vector2.INF
	if old != new_ward:
		ward_changed.emit(new_ward)


func _on_ward_tree_exiting(which: BaseEnemy) -> void:
	if which == ward:
		_set_ward(null)


# ── Motion ──────────────────────────────────────────────────────────────────────────────────────

## Soft anchor behind the ward (away from the player), a spring seek toward it, a sideways jink, and inside
## `evade_radius` a break-contact escape that the anchor gives way to. One request; the mover caps the sum.
func _tick_follow(delta: float) -> void:
	var pos := actor.global_position
	var ward_pos := ward.global_position
	var target := TargetInfo.player(get_tree())
	var away := Vector2.ZERO
	if target.has_target:
		away = (ward_pos - target.position).normalized()
	if away == Vector2.ZERO:
		away = (pos - ward_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	var lateral := away.orthogonal()
	var raw := ward_pos + away * config.follow_distance + lateral * config.follow_lateral * follow_side
	anchor = _clamp_into_view(raw)

	_jink_clock += delta
	if config.jink_period > 0.0 and _jink_clock >= config.jink_period:
		_jink_clock -= config.jink_period
		jink_sign = -1.0 if rng.randf() < 0.5 else 1.0

	var decel := mover.braking if mover.braking > 0.0 else mover.acceleration
	var seek_speed := minf(config.max_speed, pos.distance_to(anchor) * FOLLOW_GAIN)
	var move := Steering.arrive(pos, actor.velocity, anchor, seek_speed, decel)
	move += lateral * jink_sign * config.jink_strength

	if target.has_target:
		var d_player := pos.distance_to(target.position)
		if d_player < config.evade_radius:
			var full := EVADE_FULL_FRACTION * config.evade_radius
			var band := config.evade_radius - full
			var w := clampf((d_player - full) / band, 0.0, 1.0) if band > 0.0 else 0.0
			move *= w
			var to_player := (target.position - pos).normalized()
			var toward := move.dot(to_player)
			if toward > 0.0:
				move -= to_player * toward
			move += Steering.break_contact(pos, target.position, target.velocity, follow_side, config.evade_speed,
					EVADE_LATERAL_WEIGHT)

	mover.request_velocity(move)
	mover.face_toward(ward_pos)


func _tick_seek_ward() -> void:
	var ally := nearest_ally()
	var pos := actor.global_position
	var hold_point: Vector2
	if ally == null:
		if not EnemyWorld.has_view_rect(get_tree()):
			mover.request_velocity(Vector2.ZERO)
			return
		hold_point = _clamp_into_view(pos)
	else:
		var away := pos - ally.global_position
		var dir := away.normalized() if away.length_squared() > 1e-6 else Vector2.UP
		hold_point = _clamp_into_view(ally.global_position + dir * config.follow_distance)
	if pos.distance_to(hold_point) <= HOLD_TOLERANCE:
		mover.request_velocity(Vector2.ZERO)
	else:
		mover.arrive(hold_point, config.max_speed)


## With a view rect (Assault), `p` clamped component-wise into `view.grow(−view_margin)`; unchanged otherwise.
func _clamp_into_view(p: Vector2) -> Vector2:
	if not EnemyWorld.has_view_rect(get_tree()):
		return p
	var r := EnemyWorld.view_rect(get_tree()).grow(-config.view_margin)
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


## True when `p` is inside `view.grow(band)`; always true with no view rect.
func _inside_view(p: Vector2, band: float) -> bool:
	if not EnemyWorld.has_view_rect(get_tree()):
		return true
	return EnemyWorld.view_rect(get_tree()).grow(band).has_point(p)


func _enter_disengage() -> void:
	_set_ward(null)
	mover.release_constraint()
	mover.max_speed = config.exit_speed
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	var to_left := pos.x - rect.position.x
	var to_right := rect.end.x - pos.x
	var to_top := pos.y - rect.position.y
	var to_bottom := rect.end.y - pos.y
	var nearest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if nearest == to_left:
		_exit_point = Vector2(rect.position.x - EXIT_OVERSHOOT, pos.y)
	elif nearest == to_right:
		_exit_point = Vector2(rect.end.x + EXIT_OVERSHOOT, pos.y)
	elif nearest == to_top:
		_exit_point = Vector2(pos.x, rect.position.y - EXIT_OVERSHOOT)
	else:
		_exit_point = Vector2(pos.x, rect.end.y + EXIT_OVERSHOOT)


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The curve's rate is
## capped by what the mover's acceleration can follow at exit speed.
func _tick_disengage(delta: float) -> void:
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	var rate := config.max_turn_rate
	if config.exit_speed > 0.0:
		rate = minf(rate, config.acceleration / config.exit_speed)
	var dir := Steering.turn_toward(_heading(), _exit_point - pos, rate, delta)
	mover.request_velocity(dir * config.exit_speed)


## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


# ── Support: the dish, the repair pulse and the projected shield (t12) ──────────────────────────────

## Every tick: while `is_supporting()` the dish unfolds, the tether is drawn, a pulse repairs the ward every
## `repair_period` and, once the dish is fully open, the ward carries a `ProjectedShield` that this ship sustains.
## Anything else folds the dish and stops feeding the shield, which then lapses on its own (it belongs to the ward).
func _tick_support(delta: float) -> void:
	var ship := actor as SupportShip
	var supporting := is_supporting()
	_repair_flash_left = maxf(0.0, _repair_flash_left - delta)
	if supporting:
		projector_open = minf(projector_open + delta / maxf(config.projector_unfold_seconds, 0.001), 1.0)
	else:
		projector_open = maxf(projector_open - delta / maxf(config.projector_fold_seconds, 0.001), 0.0)
		_repair_flash_left = 0.0
	if ship != null:
		ship.set_projector_open(projector_open)
		if not supporting:
			ship.hide_tether()
	if not supporting:
		return

	var line_clear := _line_clear()
	_tick_repair(delta, line_clear)
	_tick_shield()
	if ship != null:
		var color := SupportShip.TETHER_COLOR
		if _repair_flash_left > 0.0:
			color = SupportShip.TETHER_REPAIR_COLOR
		elif not line_clear:
			color.a = SupportShip.TETHER_DIM_ALPHA
		ship.show_tether(ward.global_position, color)


## No blocker (an asteroid) between the support and its ward. One ray per supporting tick, on the brain's physics tick.
func _line_clear() -> bool:
	if not actor.is_inside_tree():
		return true
	var exclude: Array[RID] = [actor.get_rid(), ward.get_rid()]
	return LineOfSight.clear(actor.get_world_2d().direct_space_state, actor.global_position, ward.global_position, exclude)


## One pulse per `repair_period` of supporting time: `round(max_health × repair_fraction)` HP (at least 1), never more
## than the budget left. Plates are never repaired: `repair()` heals the hull `Health` only.
func _tick_repair(delta: float, line_clear: bool) -> void:
	_repair_clock += delta
	if _repair_clock < config.repair_period:
		return
	_repair_clock -= config.repair_period
	var left := config.repair_budget - repair_spent
	if left <= 0 or not line_clear or not ward.can_be_repaired():
		return
	var amount := mini(maxi(1, roundi(float(ward.health.max_health) * config.repair_fraction)), left)
	var gained := ward.repair(amount)
	if gained <= 0:
		return
	repair_spent += gained
	_repair_flash_left = REPAIR_FLASH_SECONDS
	repaired.emit(ward, gained)


## Creates the ProjectedShield once the dish is open, then feeds it the player's position every tick.
func _tick_shield() -> void:
	if shield != null and not is_instance_valid(shield):
		shield = null
	if shield == null:
		if projector_open < 1.0:
			return
		shield = _make_shield()
		if shield == null:
			return
	var target := TargetInfo.player(get_tree())
	shield.sustain(target.position if target.has_target else ward.global_position + shield.facing() * 100.0)


## An `EnemyShield` in sustain mode on the ward's hurtbox, or null when another absorber holds the slot (the projection
## is skipped and the shield freed).
func _make_shield() -> EnemyShield:
	var s := EnemyShield.new()
	s.name = &"ProjectedShield"
	s.sustain_mode = true
	s.arc_deg = config.assault_shield_arc_deg if EnemyWorld.has_view_rect(get_tree()) else config.shield_arc_deg
	s.capacity = config.shield_capacity
	s.regen_delay = config.shield_regen_delay
	s.regen_seconds = config.shield_regen_seconds
	s.reboot_seconds = config.shield_reboot_seconds
	s.turn_rate = config.shield_turn_rate
	s.radius = _hull_radius(ward) + SHIELD_RADIUS_MARGIN
	if not s.attach(ward.hurt_box):
		s.free()
		return null
	ward.add_child(s, true)
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		s.face(target.position - ward.global_position)
	s.lapsed.connect(_on_shield_lapsed.bind(s))
	return s


func _on_shield_lapsed(which: EnemyShield) -> void:
	if which == shield:
		shield = null


## The ward's body radius (its `CollisionShape2D`, circle or otherwise), else `DEFAULT_HULL_RADIUS`.
func _hull_radius(e: BaseEnemy) -> float:
	var body := e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body == null or body.shape == null:
		return DEFAULT_HULL_RADIUS
	var scale_max := maxf(absf(body.global_scale.x), absf(body.global_scale.y))
	if body.shape is CircleShape2D:
		return (body.shape as CircleShape2D).radius * scale_max
	return body.shape.get_rect().size.length() * 0.5 * scale_max
