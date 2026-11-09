## Phase 9's measured Assault exits (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.10; task plan docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md
## §3; t8): the Hacker Frigate's DISENGAGE, measured with `specialist_exit_probe.gd` over `corridor_starts()` (the Ram's start set), never a
## straight-line bound. t9's Disruptor and t14's level-1 rows add / read their keys here.
##
## **The only place their probe arguments are built** (the `ph8_exit_keys.gd` rule). `SpecialistExitProbe.worst_disengage()` memoises
## process-wide on every input (scene path, phase, speeds, cap, start set and the `prepare` Callable), so whichever test calls `hacker_exit()`
## first measures and every later call is a memo hit. The hook is the static `prepare_probe`: a static function's `Callable` is equal (and
## hashes equal) on every reference, two identical lambdas are not. `test_hacker_frigate.gd` sweeps the tests for a hand-built Ph9 probe call.
##
## No `class_name` (test-only); preload it.
extends RefCounted

const PROBE: GDScript = preload("res://tests/helpers/specialist_exit_probe.gd")
const HACKER_SCENE_PATH := "res://assault/scenes/enemies/hacker_frigate/hacker_frigate.tscn"
const HACKER_CONFIG_PATH := "res://assault/scenes/enemies/hacker_frigate/hacker_frigate_config.tres"
## The probe's per-run cap (s): Ph5 / Ph7 / Ph8's.
const CAP := 20.0
## The slow start every probe runs (px/s): just a heading.
const SLOW_START := 10.0


## The Hacker's worst corridor exit: `{seconds, start, runs, capped}`, at `[max_speed, 10]`. An Assault Hacker never boosts (its break-off is a
## clamped `max_speed` request), so `max_speed` is the fastest it can carry into DISENGAGE; it always exits toward its nearest edge, so the fast
## start heading away from that edge is its worst.
static func hacker_exit(host: Node) -> Dictionary:
	var cfg := load(HACKER_CONFIG_PATH) as HackerFrigateConfig  # read only
	var speeds: Array[float] = [cfg.max_speed, SLOW_START]
	return PROBE.worst_disengage(host, load(HACKER_SCENE_PATH), HackerFrigateBrain.Phase.DISENGAGE, speeds, CAP, corridor_starts(host), prepare_probe)


## `SpecialistExitProbe.corridor_starts()` over the shipped corridor, built exactly as `ph8_exit_keys.gd` builds it. Deterministic, so equal on
## every call.
static func corridor_starts(host: Node) -> Array:
	var cam := ArenaCamera.new()
	host.add_child(cam)
	var world := cam.projectile_world_rect()
	cam.free()
	return PROBE.corridor_starts(AssaultCorridorConstraint.new().inner_rect(), world)


## The probe hook, called on each instance before it enters the tree. Ph7's gate-time rule 3 (tests/README.md -> Gate time): every node in
## group `player` leaves the group, so the brain's per-tick `TargetInfo.player()` finds nobody. The Hacker's DISENGAGE never reads the player,
## so the exit is bit-identical (`test_hacker_frigate.gd` pins it). A caller that runs it with its own harness player present loses that
## player's targeting.
static func prepare_probe(_ship: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for player in tree.get_nodes_in_group(&"player"):
			player.remove_from_group(&"player")
