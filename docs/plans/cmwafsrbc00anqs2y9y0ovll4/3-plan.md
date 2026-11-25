# t8 — Carrier hangars: doors, launches, caps, emergency deployment

Epic plan §2.8 (approved). This task plan fixes the details §2.8 leaves open; it does not redesign it.

## Problem
Today the Carrier's two hangars are sealed parts that can never be hurt and never launch anything: the "carrier" carries nothing. The player
should see a hangar's doors open (yellow light, doors sliding apart) for 0.8 s before escorts come out, be able to shoot the hangar only while its
doors are open, see a destroyed hangar stay a broken wreck that never launches again, and, when the core is exposed, see every surviving hangar
empty itself at once. In Open Space the carrier keeps a few escorts out (never a swarm); in Assault each hangar launches once per crossing.

## Design

### Files
- **New** `assault/scenes/enemies/carrier/carrier_hangars.gd` — `class_name CarrierHangars extends RefCounted`, one per carrier, built by
  `carrier.gd` (it knows the owner group) and handed to the brain (`CarrierBrain.bind_hangars()`), which ticks it.
- **New** `assault/scenes/enemies/carrier/carrier_hangar_doors.gd` — `class_name CarrierHangarDoors extends Node2D`: the code-drawn placeholder doors
  (two leaves sliding apart along the hangar's long axis; `open_amount` 0..1, `broken`; redraws only on change — no `_process`). t9 replaces the art.
- `carrier.tscn`: under each hangar module, add `Light` (`StateLight`), `Mouth` (`Marker2D`, outboard: port (48, 0), starboard (−48, 0) in module
  space, i.e. hull x ±108, 20 px outside the 88 px half-width) and `Doors` (`CarrierHangarDoors`). **No shape, module position or `HomingPoint`
  change** (t9 / t11 / t12 measure against them).
- `carrier_config.gd` / `.tres`: a `Hangars` group (flat: payloads are `String` paths).
- `carrier_brain.gd`: `bind_hangars()`, `hangars()`, `_tick_hangars()`, and the t7 `_emergency_deploy()` hook filled.
- `carrier.gd`: `_build_hangars()` in `_ready()`, `hangars()` accessor.

### Config (`Hangars` group; §2.16 starting values)
| Field | Value | Note |
|---|---|---|
| `hangar_port_scene` | `res://…/swarm_drone/swarm_drone.tscn` | Open Space payload, port |
| `hangar_starboard_scene` | `res://…/fighter/fighter.tscn` | Open Space payload, starboard |
| `assault_hangar_scene` | swarm drone | both hangars in Assault (owner choice 6) |
| `launch_count` / `assault_launch_count` | 2 / 2 | children per launch |
| `door_open_seconds` / `door_hold_seconds` | 0.8 / 2.0 | OPENING / OPEN |
| `launch_period` | 9.0 | Open Space, per hangar, from its previous OPENING start |
| `hangar_live_cap` / `carrier_live_cap` | 3 / 6 | Open Space |
| `first_launch_delay` | 3.0 | port's first OPENING: Assault after the centre enters the view; Open Space after engaging |
| `starboard_launch_delay` | 4.0 | starboard's first OPENING this long after the port's (7.0 s) |
| `launch_boost_speed` / `launch_boost_seconds` | 300 / 0.4 | outward push |

Deviation (logged in DECISIONS): §2.8 names the first delay `assault_first_launch`; it is `first_launch_delay` because Open Space uses the same
3.0 / 7.0 s stagger after engaging (§2.8 gives Open Space only the 9 s period, and a carrier that opened both hangars the tick it engaged would
leave no closed window to read the doors from).

### `CarrierHangars`
```
enum Door { CLOSED, OPENING, LAUNCH, OPEN }   # append-only; LAUNCH is passed through inside one tick
signal door_changed(module_id: StringName, door: int)
signal launched(module_id: StringName, children: Array)
var assault: bool            # written by the brain's _start()
func _init(host: Node2D, hull: ModularHull, config: CarrierConfig, rng: RandomNumberGenerator, owner_group: StringName)
func tick(delta: float, active: bool) -> void
func emergency_deploy() -> void
func door(id) -> int; launches(id) -> int; children_of(id) -> Array[Node2D] (live only); live_count() -> int; clock() -> float
func force_open(id) -> void   # test hook: OPEN for door_hold_seconds, vulnerable, no launch, no launch spent
```
One `_Bay` per HANGAR module (`ModularHull.modules()` filtered on `Role.HANGAR`, keyed by `module_id`; port = `hangar_port`): module, doors, light,
mouth, door state, door clock, `due` (the clock time its next OPENING may start), launch count, its live children.

- **Clock.** `_clock` advances only on ticks where `active` is true. Brain: Assault `active` = the hull centre has been inside
  `EnemyWorld.view_rect()` at least once (latched); Open Space `active` = `target.has_target and phase in {SCREEN, PANIC}`. `due` starts at
  `first_launch_delay` (port) and `first_launch_delay + starboard_launch_delay` (starboard). Every clock comparison is `x >= limit - CLOCK_EPS`
  (1e-6, the project clock rule), so summed 1/60 steps never land a boundary one tick late.
- **Cycle per live bay, every tick** (a cycle in progress runs on even when `active` is false; only a new OPENING needs `active`):
  - CLOSED: if `active`, `_clock >= due` and `_may_launch(bay)` → OPENING: `module.set_vulnerable(true)`, light CHARGING (yellow), doors start
    opening; Open Space: `due = _clock + launch_period`. While closed the doors ease shut (visual only).
  - OPENING: door clock ≥ `door_open_seconds` → LAUNCH (spawn) → OPEN in the same tick; doors open_amount = door clock / 0.8.
  - OPEN: door clock ≥ `door_hold_seconds` → CLOSED: `set_vulnerable(false)`, light OFF.
  - `_may_launch`: Assault — the bay has not launched; Open Space — `_room(bay) > 0`, `_room = min(hangar_live_cap − bay live, carrier_live_cap − all
    live)`. **Live** = `is_instance_valid(child) and not child.is_queued_for_deletion()` (the `LaserTender._prune` rule), pruned on every read,
    so a child freed with `queue_free()` stops counting the moment it is queued. A hangar at its cap **does not open its doors**; its due launch waits until a child is gone.
  - At LAUNCH the count is `assault_launch_count` (Assault) or `min(launch_count, _room(bay))` (Open Space, re-read then).
- **A destroyed hangar.** `module.destroyed` → the bay is dead for good: no transition, no launch, ever; its doors hang open (`open_amount` 1,
  `broken` true); the module's own destroy already turns its `Light` OFF and its vulnerability no longer matters. Destroyed mid-OPENING → nothing
  launches (the LAUNCH check reads `is_destroyed()` first, so the order of a physics-callback kill and the next tick does not matter).
- **Spawning** (the `LaserTender.launch_pair()` rule, synchronous from the brain's tick; never from a physics callback): per child,
  `scene.instantiate()`; position = the bay's `Mouth` global position + `(i − (n−1)/2) · 28 px` along the hull axis, written in the parent's space;
  its `Brain`: `rng_seed = rng.randi_range(1, 0x7FFFFFFF)` (the carrier brain's rng) and `start_engaged = true` where the brain has the property;
  `"squad" in child` → one `SquadController` per payload scene path, held by `CarrierHangars` (so a squad outlives its last member only as long as
  the carrier); collision exceptions both ways; `host.get_parent().add_child(child)`; `add_to_group(owner_group)`; the child's `EnemyMover.boost(
  outward, launch_boost_speed, launch_boost_seconds)` with `outward = (Mouth − module).normalized()` in world space; then
  `EventBus.enemy_spawned_orphan.emit(child)` once. Children keep their own config (score, escape flag, Assault budget from spawn) and never dock.
  Payload scenes are `load()`ed once per path and cached.
- **Emergency deployment** (`emergency_deploy()`, from the brain's PANIC entry, once): every live bay that `_may_launch` (Assault: not launched;
  Open Space: room > 0) launches now from whatever door state it is in, without OPENING; then OPEN for `door_hold_seconds` (vulnerable). Open Space:
  `due = _clock + launch_period`. A destroyed bay deploys nothing; an Assault bay that already launched deploys nothing.

### Brain
- `bind_hangars(h)`; `_start()` writes `hangars.assault`.
- `tick()`: after `_tick_weapons()`, `_tick_hangars(delta, target)` (computes `active`, latches the Assault view entry).
- `_emergency_deploy()` → `hangars.emergency_deploy()` (already called once from `_on_panic_entered()`).
- EMP / rail: the brain is not ticked, so the hangars freeze in place (an open door stays open and vulnerable through the window). No new rule.

### Lights and doors (§2.9)
Hangar `Light` CHARGING (yellow) from OPENING start to the end of OPEN, OFF closed, OFF on a wreck (module rule). Doors closed / opening / open /
broken. All code-drawn placeholders until t9.

### Alternatives rejected
- Hangars inside the brain script: the brain is already ~600 lines; §2.8 names `CarrierHangars` (and Ph18 swaps the driver).
- Docking / recalling children: §2.8 says they never dock.
- Opening doors at cap and launching 0: reads as a launch that never comes; the closed hangar is the honest tell.

## Build sequence
1. Config fields + `.tres`; scene nodes (`Light`, `Mouth`, `Doors`) + `carrier_hangar_doors.gd`. Gate: project loads, `test_carrier.gd` green.
2. Write `tests/integration/test_carrier_hangars.gd` (rows below); watch it fail.
3. `carrier_hangars.gd`; wire `carrier.gd` / `carrier_brain.gd`. Rows green; `test_carrier.gd` still green (its engaged rows now see launches at
   3.0 / 7.0 s).
4. DECISIONS t8 notes, ENEMY.md / roster / PROJECT.md / assault.md / CLAUDE.md (updating-project-docs), gate-time row.
5. `bash /agent/verify.sh`, `scripts/check-test-leaks.sh`, `scripts/gate-time.sh` × 2.

## Test plan — `tests/integration/test_carrier_hangars.gd`
Hand-ticked at 1/60 (`_tick`: `_physics_process(dt)` then position integrated, the `test_carrier.gd` driver), both harnesses (string labels,
`use_parameters(MODES)`) unless marked. Several carriers share one world and one loop where a row compares scenarios. **Open Space placement:** the still player at
the origin, each carrier on the 775 px circle round it (bearings 0°, 120°, 240° for three), rotated so its port side (local +x) faces the player
(`rotation` = the angle of the carrier→player vector): that is `desired_nose()`, so no carrier turns; 775 px is inside the 600–950 band (no
movement) and beyond the 340 px pulse trigger (no ring). Assault carriers spawn
inside the view (y 60) so the view is entered on the first tick; Open Space carriers are engaged (`start_engaged`) (placement above).
Numbers read from the shipped `.tres`, never typed.
- **H1 door telegraph and window (both):** the port door enters OPENING at `first_launch_delay` (± 1 tick), its light turns CHARGING and the doors'
  `open_amount` rises; no child exists before; the first two children appear exactly `door_open_seconds` later (± 1 tick), at the port mouth, boosting
  outward; `is_vulnerable()` is false before OPENING, true from OPENING through the end of OPEN, false again after (light OFF, doors shut).
- **H2 hittable only while open (Open Space, real physics 16×, carrier physics on; on its private config `missile_min_range` raised so no
  rocket flies and `launch_count` 0 so the doors cycle but no child ever sits on the bullet's line — a drone at the mouth is 1 px from it):** a real player bullet at the port hangar from outboard (range ending short of the starboard hangar) flies on with HP unchanged
  while CLOSED before, is consumed with HP −50 in OPENING and in OPEN, and flies on again once CLOSED.
- **H3 Open Space period and caps over 60 s (Open Space):** live children never exceed 3 per hangar or 6 per carrier on any tick; each hangar's
  OPENING starts are ≥ `launch_period` apart; port launches 2 at 3.8 s and 1 at 12.8 s, then stays CLOSED (cap) — boundary: its doors never open
  while it holds 3; after two port children are freed with `queue_free()` at 30 s (still in the tree for the rest of the synchronous
  loop) the port opens on the next tick and launches 2.
- **H4 a destroyed hangar stops launching (Open Space; three carriers, one 40 s loop):** (a) `HangarPort` destroyed at 1.0 s (CLOSED): every child
  over 40 s came out of `HangarStarboard` (`launched` ids, `children_of`), and the carrier keeps fighting (still SCREEN, its missile bank fired);
  (b) both destroyed at 1.0 s: no child ever, and it keeps fighting the same way; (c) `HangarPort` destroyed mid-OPENING (3.4 s): no port child
  ever, its doors hang open and broken and its light stays OFF on every later tick, starboard launches as normal.
- **H5 Assault (three carriers, one crossing):** (a) port forced open (`force_open`) and shot (`received_damage` 220 on its hurtbox) 2.0 s after
  view entry → no launch at 3.0 s, starboard OPENING at 7.0 s, total children 2; (b) both destroyed at 2.0 s → no child in the whole crossing;
  (c) undisturbed → exactly one launch per hangar, 4 children, `launches` 1 / 1 at the end, never more.
- **H6 emergency deployment (both; carriers in one world):** (a) both hangars live and unlaunched: core exposed (both engines + `GunPort` destroyed)
  at 1.0 s → on the PANIC tick both hangars go CLOSED → OPEN with children (no OPENING in between); (b) `HangarPort` + both engines destroyed → only
  the starboard deploys; (c) Assault only: the core exposed at 5.0 s, after the port launched at 3.8 s → the port deploys nothing (`launches` stays
  1), the starboard deploys and never opens again (no OPENING at 7.0 s; `launches` 1); (d) Assault only: the core exposed at 3.4 s while the port
  doors are OPENING → the port launches once on the PANIC tick (OPEN; no second launch at 3.8 s; `launches` 1, 2 port children), the starboard
  deploys too.
- **H7 children (both):** each child is a sibling of the carrier (same parent), announced through `EventBus.enemy_spawned_orphan` exactly once (a
  spy), in the carrier's owner group, has a non-zero `rng_seed`, `start_engaged` true, a collision exception with the carrier, and the payload's
  shared squad; a pulse ring started by the carrier (`ring.start()`) is ticked until its radius has passed every child's distance (asserted) and
  leaves their health unchanged, while beside EACH child (same bearing from the hull centre, 20 px further out) a control victim outside the owner group (`test_carrier.gd::_victim` shape) is hurt — so a child sitting in a ring gap cannot pass the row, because its control would sit in the same gap and fail it (and the row also asserts `not ring.in_gap(bearing)` for each child at the tick the band reaches it); after the core's death frees the carrier
  (one frame awaited) every child is still valid.

Existing rows: `test_carrier.gd` engaged rows now see launches; they must stay green unchanged.

## Risks
- Existing `test_carrier.gd` rows ticking > 3 s now spawn children into the harness; they are not ticked by hand loops, so they should not move or
  fire mid-row, but they run real frames after the row ends (freed with the root). If one turns red, a test-only config prop
  (`first_launch_delay` large) on that row's private config is the fix, never a change to the hangar rule.
- Gate time (2.2 s): the 60 s / 40 s Open Space loops tick carriers with four mounts; scenarios share loops to stay inside it.
- Children added from the hand-ticked loop in Assault are swarm drones with budgets; if their `_ready()` needs something the harness lacks, the
  rows will show it.

## Out of scope
Final hangar / door art (t9); hub placement and engagement launch in the hub (t10); level-1 placement and the drone gate count (t12); docking;
module-tied launch rules on the boss machinery (Ph18).

## As built (deviations from this plan)
- H7 runs with `starboard_launch_delay` 0.5 on its private config (both launches within 45 px of descent in Assault, so every child is well inside the
  ring's 420 px reach), and in Assault moves the player beyond the pulse trigger so the row starts the only ring.
- H2 also sets `first_launch_delay` 1.0 on its private config (it tests the window; H1 pins the schedule).
- The Risks fallback was used for time, not for a red row: `test_carrier.gd::_spawn` keeps every hangar quiet (`first_launch_delay` 1e6, launch counts 0)
  because the launches cost those rows +0.4 s.
- PANIC is entered on the first tick after the exposing wrecks (the rows wreck between ticks), as in t7.
