## Phase 10's measured Assault exits (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.4.3; task plan docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md;
## t4): the Heavy Gunship's DISENGAGE, measured with `specialist_exit_probe.gd` over `corridor_starts()`, never a straight-line bound. t11's level-1
## rows read the same key here.
##
## **Any change to an exit lever (`exit_speed`, `exit_acceleration`, `max_turn_rate`) re-runs the view-grid comparison** (`PROBE.starts()` against
## `corridor_starts()`, t4 DECISIONS note) before the corridor-only start set stands.
##
## **The only place its probe arguments are built** (the `ph8_exit_keys.gd` / `ph9_exit_keys.gd` rule). `SpecialistExitProbe.worst_disengage()`
## memoises process-wide on every input (scene path, phase, speeds, cap, start set and the `prepare` Callable), so whichever test calls
## `heavy_gunship_exit()` first measures and every later call is a memo hit. The hook is the static `prepare_probe`: a static function's
## `Callable` is equal (and hashes equal) on every reference, two identical lambdas are not. `test_heavy_gunship.gd` sweeps the tests for a
## hand-built Ph10 probe call.
##
## No `class_name` (test-only); preload it.
extends RefCounted

const PROBE: GDScript = preload("res://tests/helpers/specialist_exit_probe.gd")
const HEAVY_GUNSHIP_SCENE_PATH := "res://assault/scenes/enemies/heavy_gunship/heavy_gunship.tscn"
const HEAVY_GUNSHIP_CONFIG_PATH := "res://assault/scenes/enemies/heavy_gunship/heavy_gunship_config.tres"
## The probe's per-run cap (s): Ph5 / Ph7 / Ph8 / Ph9's.
const CAP := 20.0
## The slow start every probe runs (px/s): just a heading.
const SLOW_START := 10.0


## The Heavy Gunship's worst corridor exit: `{seconds, start, runs, capped}`, at `[break_speed, 10]`. Its cruise cap is `max_speed` (140) but a
## break-away boost carries `break_speed` (360), the fastest it can be moving when DISENGAGE starts; it always exits toward its nearest edge, so
## the fast start heading away from that edge is its worst.
static func heavy_gunship_exit(host: Node) -> Dictionary:
	var cfg := load(HEAVY_GUNSHIP_CONFIG_PATH) as HeavyGunshipConfig  # read only
	var speeds: Array[float] = [cfg.break_speed, SLOW_START]
	return PROBE.worst_disengage(host, load(HEAVY_GUNSHIP_SCENE_PATH), HeavyGunshipBrain.Phase.DISENGAGE, speeds, CAP, corridor_starts(host),
			prepare_probe)


## `SpecialistExitProbe.corridor_starts()` over the shipped corridor, built exactly as `ph9_exit_keys.gd` builds it. Deterministic, so equal on
## every call.
static func corridor_starts(host: Node) -> Array:
	var cam := ArenaCamera.new()
	host.add_child(cam)
	var world := cam.projectile_world_rect()
	cam.free()
	return PROBE.corridor_starts(AssaultCorridorConstraint.new().inner_rect(), world)


## The probe hook, called on each instance before it enters the tree.
## 1. Ph7's gate-time rule 3 (tests/README.md -> Gate time): every node in group `player` leaves the group, so `TargetInfo.player()` finds
##    nobody. DISENGAGE never reads the player.
## 2. The whole `Modules` node is freed, so the hull has no parts, no mounts and no pools (six parts, four mounts and their round pools per run
##    otherwise; `ModularHull._ready()` returns cleanly without it). DISENGAGE reads no part and a mount never writes the hull's motion.
## 3. The hull `Sprite2D`, the `ContactHitBox`, the `StateLight` and the body `CollisionShape2D` are freed too (t4 review round 1: per-run
##    setup is a third of the probe). DISENGAGE draws nothing, touches nothing and turns its light off on entry; the harness world has no
##    environment body, and the probe overwrites the position `move_and_slide()` produced (`before + velocity * DT`), so a shapeless body
##    moves the same. `BaseEnemy` reads `ContactHitBox` with `get_node_or_null` and the brain the light the same way.
## So the exit is bit-identical (`test_heavy_gunship.gd` pins two starts with and without this hook; all 2166 runs were compared once when
## step 3 landed, t4 DECISIONS). A caller that runs it with its own harness player present loses that player's targeting.
static func prepare_probe(ship: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for player in tree.get_nodes_in_group(&"player"):
			player.remove_from_group(&"player")
	for path in _PROBE_STRIP:
		var node := ship.get_node_or_null(path)
		if node != null:
			ship.remove_child(node)
			node.free()


## What `prepare_probe` frees from each probe instance (see there).
const _PROBE_STRIP: Array[NodePath] = [^"Modules", ^"Sprite2D", ^"ContactHitBox", ^"StateLight", ^"CollisionShape2D"]
