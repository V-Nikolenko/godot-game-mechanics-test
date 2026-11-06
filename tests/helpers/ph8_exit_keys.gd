## Phase 8's two measured Assault exits (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.14; task plan docs/plans/cmvqw0vo2018rqs2xxd8m1llu/3-plan.md
## §C; t14): the Twin-Laser Drone's and the Laser Tender's DISENGAGE, measured with `specialist_exit_probe.gd` over `corridor_starts()` (the Ram's
## start set), never a straight-line bound.
##
## **The only place their probe arguments are built.** `SpecialistExitProbe.worst_disengage()` memoises process-wide on every input (scene path,
## phase, speeds, cap, start set and the `prepare` Callable), so `test_laser_tender.gd` (t14, which pays for both in its `before_all()`) and
## `test_level1_specialist_spawns.gd` (t19) call `drone_exit()` / `tender_exit()` here and whichever GUT runs first measures; the other is a memo hit.
## The keys cannot drift apart because nobody else builds them (`test_laser_tender.gd` sweeps the tests for a hand-built Ph8 probe call). The hook is
## the static `prepare_probe`: a static function's `Callable` is equal (and hashes equal) on every reference, two identical lambdas are not.
##
## No `class_name` (test-only); preload it.
extends RefCounted

const PROBE: GDScript = preload("res://tests/helpers/specialist_exit_probe.gd")
const DRONE_SCENE_PATH := "res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone.tscn"
const TENDER_SCENE_PATH := "res://assault/scenes/enemies/laser_tender/laser_tender.tscn"
const DRONE_CONFIG_PATH := "res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres"
const TENDER_CONFIG_PATH := "res://assault/scenes/enemies/laser_tender/laser_tender_config.tres"
## The probe's per-run cap (s): Ph5 / Ph7's `_PROBE_CAP`.
const CAP := 20.0
## The slow start every probe runs (px/s): just a heading.
const SLOW_START := 10.0


## The drone's worst corridor exit: `{seconds, start, runs, capped}`. Speeds `[10]` only (task plan §C, review N1; logged in DECISIONS): without a
## frame its DISENGAGE exits along its own heading, so a start at `exit_speed` flies the same straight path as the 10 px/s start with the same
## heading and is ahead of it at every instant. A framed drone carrying velocity against its exit is bounded by `drone_reversal_seconds()`.
static func drone_exit(host: Node) -> Dictionary:
	var speeds: Array[float] = [SLOW_START]
	return PROBE.worst_disengage(host, load(DRONE_SCENE_PATH), TwinLaserDroneBrain.Phase.DISENGAGE, speeds, CAP, corridor_starts(host), prepare_probe)


## The tender's worst corridor exit: `{seconds, start, runs, capped}`, at `[exit_speed, 10]` (it always exits toward its nearest edge, so the
## fast start heading away from that edge is its worst).
static func tender_exit(host: Node) -> Dictionary:
	var cfg := load(TENDER_CONFIG_PATH) as LaserTenderConfig  # read only
	var speeds: Array[float] = [cfg.exit_speed, SLOW_START]
	return PROBE.worst_disengage(host, load(TENDER_SCENE_PATH), LaserTenderBrain.Phase.DISENGAGE, speeds, CAP, corridor_starts(host), prepare_probe)


## The drone's Assault exit bound everyone uses (t19's density and deadline rows): the measured exit plus the reversal term.
static func drone_exit_bound(host: Node) -> float:
	return float(drone_exit(host)["seconds"]) + drone_reversal_seconds()


## The extra time a framed drone needs when it enters DISENGAGE carrying up to `max_speed` against its exit (`-n`), over the probe's 10 px/s start
## along it (a kinematic reversal at `acceleration` up to `exit_speed`): `(u + 10) / a + (u^2 - 10^2) / (2 a V)`, from the shipped config. Slack in
## practice (framed Assault exits are axis-aligned and shorter than the probe's diagonal worst), kept as a conservative bound; `test_laser_tender.gd`
## ties it to the real mover.
static func drone_reversal_seconds() -> float:
	var cfg := load(DRONE_CONFIG_PATH) as TwinLaserDroneConfig  # read only
	var u := cfg.max_speed
	var a := cfg.acceleration
	return (u + SLOW_START) / a + (u * u - SLOW_START * SLOW_START) / (2.0 * a * cfg.exit_speed)


## `SpecialistExitProbe.corridor_starts()` over the shipped corridor, built exactly as `test_level1_specialist_spawns.gd::before_all()` builds it (an
## `ArenaCamera` under [param host] for `projectile_world_rect()`, freed; `AssaultCorridorConstraint.new().inner_rect()`). Deterministic, so equal
## on every call.
static func corridor_starts(host: Node) -> Array:
	var cam := ArenaCamera.new()
	host.add_child(cam)
	var world := cam.projectile_world_rect()
	cam.free()
	return PROBE.corridor_starts(AssaultCorridorConstraint.new().inner_rect(), world)


## The probe hook, called on each instance before it enters the tree (so it reaches the tree through the main loop).
## - Ph7's gate-time rule 3 (tests/README.md -> Gate time): **every** node in group `player` leaves the group. In the probe's own world that is only
##   its stub, so the brains' per-tick `TargetInfo.player()` finds nobody. Neither brain reads the player in DISENGAGE (checked in t14), so the exit
##   is bit-identical (`test_laser_tender.gd` pins it). A caller that runs it with its own harness player present loses that player's targeting.
## - The tender (`drone_scene = null`): its brain's `_setup()` skips instantiating and freeing a probe drone on each run (`drone_config` is read only
##   when planning a launch, never in DISENGAGE). This is the saving (about 0.6 s over 2166 runs).
static func prepare_probe(ship: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for player in tree.get_nodes_in_group(&"player"):
			player.remove_from_group(&"player")
	if ship is LaserTender:
		(ship as LaserTender).drone_scene = null
