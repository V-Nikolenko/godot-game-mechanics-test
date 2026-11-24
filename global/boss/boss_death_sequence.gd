## BossDeathSequence — a boss's death spectacle (Phase 11 t4; first built for the retired space station).
##
## HOST CONTRACT (duck-typed; the parent node is the host): a `Node2D` with a signal
## `death_started`, a `death_duration: float` property (read when the death starts), and
## optionally a `config` whose `death_blast_count` is copied in `_ready()`. This node writes the
## dying host's `rotation` / `modulate` AFTER the host has called `suspend_ai()` — the one allowed
## second writer, which is why it lives in `global/boss/`, outside the single-writer sweeps.
## Its host today is the Space Fortress (`space_fortress.tscn`, node `DeathSequence`).
##
## Resolves `_host` in `_ready()`, copies its tuning out of the config once, and drives itself off
## the host's signal.
##
## SPECTACLE ONLY. This node owns nothing the level's progression depends on — the host itself
## holds the death timer and calls `queue_free()` (`space_fortress.gd::_finish_death`). Deleting or
## renaming this node costs the explosions and nothing else. If it owned the free instead, a
## renamed node would hang `station_assault` for its full timeout with no error.
##
## What it does on the host's `death_started`:
##   - rolls `blast_count` explosions across the hull at deterministic hull-local offsets,
##   - rattles the camera a little per blast and hard on the finale,
##   - lets the hull drift with a decaying spin and darken toward a burnt grey.
class_name BossDeathSequence
extends Node2D

## Distance from the hull centre at which the chained blasts are placed, in on-screen pixels.
##
## Scene geometry, NOT a stat, so it lives here rather than on the host's config. The host scene
## authors it to sit inside its hull (the fortress: 150 px inside its r 176 ring), so every blast
## lands ON the boss rather than in the space around it.
##
## NOT a design-space value: the 640x360 authoring convention applies to wave and spawn
## positions, which `ArenaCamera.WORLD_SCALE` scales at runtime. This is measured against the
## hull's own sprite, which is already in final pixels.
@export var blast_spread_radius: float = 96.0

## Particles per chained blast. Below `ExplosionEffect`'s default 22, because seven of these fire
## in sequence and the final central blast should still be the biggest thing on screen.
@export var blast_particle_amount: int = 18

## Camera trauma per chained blast.
##
## Deliberately small. `CameraShake` decays at 1.5 units/s (`camera_shake.gd:24`) and the blasts
## are ~0.26 s apart, so this never accumulates — it peaks at 0.25 trauma, which the quadratic
## curve (`:46-50`) renders as a ~0.5 px offset. That is intended: research finding 3 records a
## genuine disagreement between two sources on shake volume, and the resolution was "a whisper
## for the chain, the spike for the finale". Do not raise this to make the chain visible without
## re-reading that finding.
@export var blast_shake: float = 0.25

## Camera trauma on the final central blast. `camera_shake.gd:11-13` documents 1.0 as exactly the
## "boss death / big impact" value, and nothing an enemy does in this game currently shakes the
## screen at all — so this is the budget being spent where it was reserved.
@export var final_shake: float = 1.0

## Radians per second the hull spins as it dies, decaying linearly to 0 over the sequence.
##
## Research finding 7: a wreck should visibly degrade rather than sit still. A boss hull is often
## already turning when it dies (the fortress spins for its hull-beam volleys), so a hard stop at
## the moment of death would be the more jarring option, not the safer one.
@export var death_spin: float = 1.2

## Colour the hull is driven toward across the sequence. Burnt grey, not black, so the silhouette
## stays readable against the starfield.
##
## This works because `hit_flash_vs.tres` passes the incoming vertex colour through when its
## `enabled` parameter is false — a shader that assigned `COLOR = texture(...)` outright would
## silently swallow it.
@export var burnt_tint: Color = Color(0.35, 0.32, 0.30, 1.0)

## Unit directions the chain walks, cycled by blast index. A FIXED table, never `randf()`.
##
## Fixed for the same two reasons every boss pattern is:
## random ordering cannot be balanced, and cannot be asserted in a test. Eight directions at 45
## degrees, ordered so consecutive blasts land on opposite sides of the hull rather than walking
## around the rim — a chain that crawls in a circle reads as a spinner, not a disintegration.
const _BLAST_DIRS: Array[Vector2] = [
	Vector2(-0.7071, -0.7071),
	Vector2(0.7071, 0.7071),
	Vector2(0.7071, -0.7071),
	Vector2(-0.7071, 0.7071),
	Vector2(0.0, -1.0),
	Vector2(0.0, 1.0),
	Vector2(-1.0, 0.0),
	Vector2(1.0, 0.0),
]

var _host: Node2D

## Copied from the config in `_ready()`. The DURATION is deliberately not copied — see
## `_on_death_started`.
var _blast_count: int = 3

var _blast_timer: Timer
var _fx: ExplosionEffect

var _blasts_fired: int = 0
var _spin: float = 0.0
var _spin_initial: float = 0.0
var _elapsed: float = 0.0
var _total: float = 0.0
var _running: bool = false


func _ready() -> void:
	set_physics_process(false)

	var host := get_parent() as Node2D
	if host == null or not host.has_signal(&"death_started") or not ("death_duration" in host):
		push_warning("[BossDeathSequence] host lacks death_started / death_duration — sequence disabled")
		return
	_host = host

	## Godot readies children before parents, so this runs BEFORE the host's _ready(). Safe for
	## `config`: an @export initialised at property-init time, whose PRIVATE per-host copy is
	## installed by `BaseEnemy._init()` / `_enter_tree()` before any child is ready. NOT safe for
	## anything the host derives in its own _ready() — which is the other reason the duration is
	## read later.
	var cfg: Object = _host.get("config")
	if cfg != null and "death_blast_count" in cfg:
		_blast_count = cfg.death_blast_count

	_blast_timer = Timer.new()
	_blast_timer.one_shot = false
	_blast_timer.timeout.connect(_fire_next_blast)
	add_child(_blast_timer)

	_host.death_started.connect(_on_death_started)


## Hull-LOCAL offset of blast [param i].
##
## A pure function of the index: no transform, no time, no RNG. That is what makes "the blast
## offsets are deterministic" an assertable property — comparing WORLD positions instead would
## fold in the decaying spin and turn the test into a frame-timing race.
func blast_offset(i: int) -> Vector2:
	return _BLAST_DIRS[i % _BLAST_DIRS.size()] * blast_spread_radius


func is_running() -> bool:
	return _running


func _on_death_started() -> void:
	if _host == null:
		return

	## The cadence is derived from the HOST's already-copied field, not from a second copy of
	## the config taken in _ready(). This is deliberate and load-bearing: the host owns the
	## timer that frees the wreck, so two independent copies could disagree — and a test that
	## shortens `fortress.death_duration` to 0.05 would otherwise leave a 2.4 s chain firing into a
	## host that no longer exists. Reading the parent's per-instance var is not a shared-.tres read.
	_total = _host.death_duration

	## The host emits `death_started` BEFORE calling `_finish_death()` in the zero case, so
	## without this guard we would start a chain against a host being freed in the same call.
	## Note `Timer.start(0.0)` does not error — Godot silently falls back to the default 1.0 s
	## wait_time — so the bad case would be quiet rather than loud.
	if _total <= 0.0:
		return

	_running = true
	_blasts_fired = 0
	_elapsed = 0.0
	_spin_initial = death_spin
	_spin = death_spin

	## `maxi(..., 1)` guards a config of 0, which would otherwise make the interval INF.
	var interval := _total / float(maxi(_blast_count, 1))

	## The ExplosionEffect is a child of the HOST, never of this node.
	##
	## `explosion_effect.gd`'s `explode()` resolves `actor` by walking up from its parent to the
	## nearest Node2D, and defaults `container` to `actor.get_parent()`. This node (DeathSequence)
	## is itself a Node2D, so parenting `_fx` here instead would resolve `actor` to THIS node on
	## the very first hop — the walk does not help — and `container` to the host, so every
	## blast would land INSIDE the hull — freed with the wreck, invisible to the container
	## `_wait_enemies_cleared()` polls, and rotating with the spin applied below. A boss's bullet pools
	## sit on the host root for the same reason.
	##
	## Added HERE rather than in _ready() because `Node::_propagate_ready()` marks the parent
	## blocked while it readies its children, so `_host.add_child()` from our _ready() would
	## fail hard.
	_fx = ExplosionEffect.new()
	_fx.amount = blast_particle_amount
	_host.add_child(_fx)

	set_physics_process(true)
	_blast_timer.start(interval)
	_fire_next_blast()


func _fire_next_blast() -> void:
	if not _running or _host == null or not is_instance_valid(_host):
		return

	if _blasts_fired >= _blast_count:
		_finish()
		return

	if _fx != null and is_instance_valid(_fx):
		_fx.explode(_host.to_global(blast_offset(_blasts_fired)))
	CameraShake.add(blast_shake)
	_blasts_fired += 1


## The finale: one big central blast and the full boss-death camera kick. The host frees itself
## a moment later on its own timer — this node never calls queue_free() on it.
func _finish() -> void:
	_running = false
	_blast_timer.stop()
	set_physics_process(false)
	if _fx != null and is_instance_valid(_fx):
		_fx.explode()
	CameraShake.add(final_shake)


func _physics_process(delta: float) -> void:
	if not _running or _host == null or not is_instance_valid(_host):
		return

	_elapsed += delta

	## Linear decay to zero across the sequence: the wreck coasts to a stop rather than spinning
	## at a constant rate until it vanishes.
	var t := clampf(_elapsed / _total, 0.0, 1.0)
	_spin = _spin_initial * (1.0 - t)
	_host.rotation += _spin * delta
	_host.modulate = Color.WHITE.lerp(burnt_tint, t)
