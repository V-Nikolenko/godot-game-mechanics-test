# Plan review — Open-space boost: Shift burst movement on an upgradeable boost meter

VERDICT: CHANGES_REQUESTED

Epic: `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`
Reviewed: 2026-09-14, against `agent/auto-dev` @ `05e3764`.
Reviewed documents: `1-context.md`, `2-research.md`, `3-plan.md`, plus the six generated task
bodies in `BACKLOG.json`.

Two blocking findings, both narrow and both in the **test plan** rather than the design. The design
itself verified out cleanly — see "What I checked and found correct" at the end, which is not
boilerplate: every line number, node name, signal name, property name and asset dimension the plan
cites was opened and confirmed, and three of them are the kind of claim a plan usually gets wrong.

---

## Blocking

### B1 — The step-5 pickup test mutates the **live** `ShipProgressionState` and the plan has no restore, which makes the step-4 meter test fail

- Plan: `3-plan.md:439` — *"A real instance is collected against the live (sandboxed) autoload and
  `boost_charge_count` goes up by 1."*
- Plan: `3-plan.md:398` — *"`bind_progression = true`, **sandboxed autoload**: `max_charges` starts
  at `MIN_BOOST_CHARGES`"*
- Task: `a-pickup-in-the-hub-permanently-adds-a-boost-charge` — *"collect a **real instance against
  the live (sandboxed) autoload**"*

"Sandboxed autoload" is not a thing that exists. `tests/helpers/save_sandbox.gd:16-24` is a list of
`user://*.cfg` paths and `capture()`/`restore()` (`:29-47`) only back up and rewrite **files**. It
does nothing to the in-memory singleton. `test_weapon_unlock_sources.gd` spells this out in its
header at `:15-21`:

> ⚠️ Autoload state. `WeaponModeUnlockerPickup._collect()` calls the **`UpgradeState` autoload**,
> not any instance a test holds, and the whole suite shares it — so a fresh script instance would
> prove nothing about `_collect()`, and mutating the live one would leak `gatling` into every later
> test in the process. `before_all`/`after_all` therefore snapshot and restore the live `_unlocked`
> dictionary **on top of `SaveSandbox` (which only covers the file)**.

…and implements it at `test_weapon_unlock_sources.gd:40-47`. The plan cites that file as the
pattern to copy but copies only the placement half, not the snapshot half.

The consequence is not hypothetical. `ShipProgressionState.add_permanent_shield()`
(`ship_progression_state.gd:33-37`) — and the `add_boost_charge()` the plan mirrors from it —
writes `_permanent_shield_count` / `_boost_charge_count` in memory and never re-reads the file, so
after `test_boost_upgrade_source.gd`'s collect case and its at-cap case the live autoload sits at
3 (or at `MAX_BOOST_CHARGES`) for the rest of the GUT process. GUT walks `res://tests` with
`-ginclude_subdirs`, so `integration/test_boost_upgrade_source.gd` runs **before**
`unit/test_boost_meter.gd`. That file's step-4 case (`3-plan.md:398`) asserts `max_charges` starts
at `MIN_BOOST_CHARGES = 2` against a bound meter — which now reads 3 or 5. It fails, and it fails
*only* in a full-suite run, which is the most expensive failure mode this suite has.

The same pollution reaches `test_open_space_boost_wiring.gd` and `test_boost_bar.gd` the moment
task 4 flips `BoostMeter.bind_progression` to `true` by default (its own task body says to), because
both instantiate `player_ship.tscn` with the meter in it and — for the bar's overlap case — add it
to the tree, so `BoostMeter._ready()` runs and reads the live autoload. Those two files are written
in steps 2 and 3, *before* the binding exists, so nobody will think to sandbox them.

**Required changes**

1. In `3-plan.md`'s test plan, replace every "sandboxed autoload" with the explicit two-layer
   pattern: `SaveSandbox.capture()/restore()` for the file **plus** `before_all`/`after_all`
   snapshot and restore of the live `ShipProgressionState._boost_charge_count` (and
   `_permanent_shield_count`, since B1's independence case at `3-plan.md:430` touches it), citing
   `test_weapon_unlock_sources.gd:40-47`.
2. Add a `before_each` that resets the live counters to the known fixture value, the way
   `test_weapon_unlock_sources.gd:50-53` assigns `_unlocked` directly rather than going through the
   code under test.
3. Say in the plan and in the task bodies for steps 2, 3 and 5 that **any test that instantiates
   `player_ship.tscn` after step 4 touches the persisting autoload** and needs the same treatment.
   Put that sentence in task `boosting-costs-a-charge-and-charges-come-back-on-their-own` and task
   `a-cyan-pip-bar-under-your-ship-shows-how-many-boosts-you-hav` now, not retroactively.

### B2 — `_step_boost()`'s contract contradicts two of its own test cases

The plan defines the seam at `3-plan.md:124-132`:

```gdscript
func _handle_thrust(delta: float) -> void:
    if engine_boost_active:
        return
    ... existing thrust / reverse / damping, unchanged ...
    _step_boost(Input.is_action_just_pressed("boost"), delta)
```

and justifies the module-precedence rule at `3-plan.md:113-115`: *"`_handle_thrust()` returns early
while `engine_boost_active`, so the core boost is simply not reachable during a module dash"*. That
is true of `_handle_thrust` — I confirmed the early return at `player_ship.gd:118-119` and all four
honouring sites (`player_base.gd:45`, `player_fighter.gd:97`, `move_state.gd:39`,
`dash_state.gd:126`).

But two test cases drive `_step_boost()` **directly** and expect it to honour the flag by itself:

- `3-plan.md:379` — *"A module boost wins | `engine_boost_active = true`; `_step_boost(true, d)`
  leaves `velocity` unchanged."*
- `3-plan.md:410` — *"Boundary: a boost refused by a module burns no charge | `engine_boost_active
  = true`, full meter; `_step_boost(true, d)` → `charges` unchanged."*

As specified, `_step_boost()` never reads `engine_boost_active`, so both cases fail — the first
would see `velocity` slammed to `UP * 700`, the second would see a charge spent. The task body for
`shift-slams-your-ship-onto-its-new-heading-and-launches-it` makes this worse by saying *"Do NOT:
set or add anything like `engine_boost_active` (it is read-only here — a module boost wins and
`_handle_thrust` already returns early)"*, which an implementer can reasonably read as "do not put
a guard in `_step_boost`". The likely outcome under unattended implementation is that the two
highest-value precedence cases get quietly deleted or weakened to make the build green.

**Required change.** State explicitly in `3-plan.md` and in task
`shift-slams-your-ship-onto-its-new-heading-and-launches-it` that `_step_boost()` opens with
`if engine_boost_active: return`, that this is deliberately redundant with `_handle_thrust`'s
guard, and that the redundancy is what makes the precedence rule *testable* rather than merely
*true*. Reword the "Do NOT" line so it forbids writing the flag, not reading it.

---

## Advisory

### A1 — Design property 2's arithmetic is wrong; the conclusion survives, the reasoning does not

`3-plan.md:110-112`: *"At 700 px/s the existing damping removes ~420 px/s² while W adds 380 px/s²,
so a coasting boost decays noticeably inside the hold window and a thrusting one nearly holds."*

Damping and thrust are **mutually exclusive branches** in the code, not simultaneous forces —
`player_ship.gd:134-153`: `thrust_input > 0` adds `forward * 380 * delta` and applies **no**
damping; only the `else` branch runs `velocity.lerp(Vector2.ZERO, damping * delta)`. So the real
behaviour is: W held → velocity is pinned to the decaying `_speed_ceiling` (thrust 380 px/s² never
catches the ceiling once it starts falling at 400 px/s²); W released → `0.6 × 700 = 420 px/s²` of
bleed, marginally faster than the ceiling. "Holding sustains, releasing bleeds" is still correct;
the numbers offered for it are not. Fix the sentence so a later tuner does not reason from it.

### A2 — The "~54 px" cell in the numbers table does not reproduce

`3-plan.md:306`: *"600 is only 1.43× cruise, and with the ceiling decaying over 0.6 s that buys ~54
px of extra travel over simply cruising … 700 with the hold window below buys ~196 px."*

The 196 px figure is exactly right — `0.35 × (700−420) + 0.70 × (560−420) = 98 + 98 = 196`. Running
the identical method on 600 with the plan's own `boost_ceiling_decay = 400` gives
`0.35 × 180 + 0.45 × 90 = 63 + 40.5 ≈ 104 px`, roughly double the quoted 54. Since the table says
this is *"the arithmetic that forced the change"*, it should be reproducible. 700 still wins; only
the margin is overstated.

### A3 — Nothing tests the idea's last bullet ("should not alter movement in other mission types")

Every other constraint in `sourceIdea.text` gets a test. Exclusivity gets a structural argument
(`3-plan.md:150-153`) and nothing else — and it is not actually structural: `class_name BoostMeter`
registers globally regardless of the directory it sits in, so `global.md`-style isolation here is a
convention, not an enforcement. This project's habit is to gate exactly this kind of
silently-regressible claim (`test_module_unlock_sources.gd`, `test_weapon_unlock_sources.gd`,
`test_player_bullet_lifetime.gd`). A two-case invariant is cheap: `assault/scenes/player/player_fighter.tscn`
and the infiltration player scene contain no `BoostMeter`, and no `.gd` outside `open_space/`
references the `boost` action. Consider adding it to step 2.

### A4 — `test_boost_bar.gd`'s "Segments follow capacity" has no stated observable

`3-plan.md:420`: *"Emitting `charges_changed(2.0, 4)` leaves the bar rendering 4 segments."* A
`_draw()`-only `Node2D` exposes nothing to assert on — `OverheatBar` keeps `_percentage` as a
member (`overheat_bar.gd:7`) precisely so state is inspectable. Say in the plan that `BoostBar`
stores `_max_charges` / `_charges` as members and that the test reads those, or the case is
unwritable and will be dropped. Also, no case asserts the *fill* tracks `current` — only capacity.

### A5 — The `Shield` component is a closer prior art than the plan admits, and is never rejected in writing

`3-plan.md:176-189` argues `BoostMeter` against `Overheat`. But `global/components/shield_component.gd`
is the component that already implements **discrete charges + regeneration + `bind_progression` to
`ShipProgressionState` + a mid-session grant** (`:20-22`, `:38-46`, `:116-124`) — i.e. four of
`BoostMeter`'s five behaviours. The plan copies `Shield`'s binding code verbatim without saying why
it does not extract or reuse the component. I believe a new component is the right call (Shield is
entangled with `consume_one()` in the damage chain, temp charges, the hacked state and the snapshot
`Dictionary` the `ShieldIconStrip` consumes), but CLAUDE.md's "reinvents something that already
exists in `global/components/`" bar means that should be one explicit sentence in the plan, not an
omission.

### A6 — The meter silently freezes during a module boost

Because `_step_boost()` is called from the tail of `_handle_thrust()` and `_handle_thrust()` returns
at `player_ship.gd:118-119`, `meter.step(delta)` does not run for the 0.55 s of an
`EngineBoostModule` dash. Harmless and arguably correct, but undocumented and surprising; the
wiring test's "the ship drives the meter" case does not cover it. One line in the plan.

### A7 — The verb test needs the ship in the tree, and the plan implies otherwise

`3-plan.md:365`: *"Instantiates `player_ship.tscn`, `set_physics_process(false)`, drives
`_step_boost()` by hand."* That works for `_step_boost()` alone, but the wiring file's last case
drives `ship._handle_thrust(d)` (`3-plan.md:411`), which reaches `_thruster.set_state(...)` at
`player_ship.gd:144-153`. `_thruster` is created in `_setup_effects()` from `_ready()`
(`player_ship.gd:64-83`), so on an instance that was never added to the tree it is `null` and the
call is a hard error, which GUT fails. Say `add_child_autofree(ship)` explicitly, and note that
doing so also runs `PlayerBase._setup_components()` → `SessionState.apply_to(self)` and the ship's
`ShipModuleState` hookups (`player_ship.gd:56-62`), which is why B1's autoload discipline applies
to these files too.

### A8 — Pre-existing bug adjacent to this epic: the open-space ship's shield is **not** bound to the progression stat

Not caused by this plan, but it undermines a premise the plan states twice (`3-plan.md:26-28`,
`:227`) — that capacity *"persists across runs exactly like the permanent shield count already
does"*. The saved stat does persist. The open-space ship does not consume it:
`player_ship.tscn:223-224` authors `ShieldComponent` with **no** `bind_progression` property, so it
falls back to the `false` default at `shield_component.gd:20` and `permanent_max = permanent_charges
= 1`. The only scene in the project that sets it is `assault/scenes/player/player_fighter.tscn:301`.
Net effect today: collecting `ShipShieldUpPickup` on the hub bench raises a number the open-space
ship never reads. Task 4 already says to set `bind_progression = true` on the new `BoostMeter` node,
so the boost track will not inherit the omission — but the shield bug should be filed separately
(`./scripts/backlog-cli.js add-task code-health-backlog …`) rather than left implied as working
precedent.

---

## Decomposition, complexity and dependencies — no findings

Checked and correct:

- Six tasks map 1:1 onto the plan's build sequence (`3-plan.md:340-352`), and the dependency chain
  in `BACKLOG.json` (1 ← 2 ← {3, 4}, 4 ← 5 ← 6) matches. 3 and 4 both depend on 2 and touch disjoint
  files (`boost_bar.gd` + `player_ship.gd::_ready` vs `ship_progression_state.gd` +
  `boost_meter.gd`), so either order works and neither stalls — as the plan claims at `3-plan.md:519`.
- Each task is one session's work with a written design to follow rather than one to invent.
  `medium`/`opus` on 1 and 2 is right: both change the movement model in the file two epics are
  editing and both introduce a testable seam. `small`/`sonnet` on 3, 5 and 6 is right. 4 is the
  borderline one — it edits a shared autoload under `global/` — but it is a line-for-line mirror of
  an existing stat with no new machinery, so `small` is defensible.
- The scheduling constraint against `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
  is correctly kept out of the dependency graph and correctly written into the task bodies
  (task 1: *"Do not work this in the same window as a mouse-aiming task"*, plus the re-read-from-HEAD
  instruction). Encoding it as a `--depends-on` edge would have stalled this epic behind six
  unrelated tasks, as `3-plan.md:523-525` says.
- Task bodies carry the things that are usually missed: the `uid://` rule verbatim (task 5), the
  `save_sandbox.gd` requirement (task 4), `scripts/check-test-leaks.sh` (task 2), the mandatory
  `pixel-art-generation` skill and the visual check (task 6), and `updating-project-docs` on all
  five code tasks. Task 6 is correctly marked droppable because it spends the irreversible PixelLab
  allowance and task 5 ships a complete playable pickup without it.

## Conventions — no findings

- Composition over inheritance: `BoostMeter` is a child `Node`, `PlayerBase` gains nothing
  (`3-plan.md:484`). ✓
- Config-driven `.tres`: that convention is scoped to assault enemy stats; `@export` on the scene
  node is what `1-context.md:284` and `2-research.md`'s numbers table call for so the fly-test is an
  inspector change. ✓
- 640×360 × `ArenaCamera.WORLD_SCALE`: correctly identified as assault-only and explicitly *not*
  applied (`1-context.md:168-170`). The hub is authored in world pixels — I confirmed the bench row
  at `sector_hub.tscn:88-103`. ✓
- Signal arity: `charges_changed(current: float, maximum: int)` and
  `boost_charge_count_changed(new_count: int)` are both declared with parameters, and the plan
  names `test_signal_emit_arity.gd` as the sweep. ✓
- UID rules: task 5 carries the prohibition and the `ResourceUID.create_id()` escape hatch. ✓
- Projectile ownership: not touched. ✓

## Research — no findings

Six findings, each with a stated tradeoff, and the sourcing note is honest about what it could not
read (TV Tropes hard-403, the Quod Soler page recorded as an *unverified snippet*, not a finding).
Finding 6 self-labels as "weakest sourcing in this table" and is cited for a design observation, not
a number. Most importantly, finding 3 **contradicts the epic's own framing** — Jet Lancer, the
idea's stated reference, uses a held thruster on an overheat gauge and upgrades *cooling*, not a
spend-a-pip meter that upgrades capacity — and the research surfaces that contradiction rather than
burying it, then the plan resolves it deliberately at `3-plan.md:176-181` and records the
cooling-upgrade fallback at `:229-230`. That is the behaviour this review stage exists to reward.

## The original idea, bullet by bullet

| Idea bullet | Plan | Verdict |
|---|---|---|
| Dedicated boost for open space | `_step_boost()` in `OpenSpacePlayerShip` only | ✓ |
| Reuse the blue boost flames | `flame_boost` + `ThrusterEffect.State.BOOST`; I confirmed the cyan is `Color(0.35, 0.9, 1.0, 1.0)` at `thruster_effect.gd:77` and that `flame_boost` is a real 15-frame animation at `player_ship.tscn:164` | ✓ |
| Shift activates, consumes a meter | new `boost` action; `BoostMeter.try_spend()` | ✓ |
| Significant burst in the facing direction | 700 px/s vs `max_speed = 420` (`player_ship.gd:11`) | ✓ |
| Meter improves via collectibles like health/shield | `ShipProgressionState` second key + `ShipBoostUpPickup`; the plan correctly records that the idea's health-upgrade premise is false (`1-context.md:218-222` — nothing raises `max_health = 50`) | ✓ |
| **Move existing thrust/braking into the boost system** | **Loose reading taken, flagged for the user to overturn at approval** (`3-plan.md:278-296`) | see below |
| 180° + boost kills momentum and re-aims | unconditional `velocity = facing * boost_exit_speed` | ✓ |
| Quick direction changes over continuous thrust | the redirect collapses the measured ~3.0 s reversal | ✓ |
| Jet Lancer momentum feel | damping deliberately untouched; discrete pips chosen over the reference's held gauge, argued | ✓ with a documented divergence |
| UI near the overheat meter | world-space `BoostBar` at `(0, 26)`, 6 px under the overheat bar at `(0, 20)` | ✓ |
| Boost must not alter other mission types | `EngineBoostModule`, `PlayerBase` and all of `assault/` untouched | ✓ design, ✗ test (A3) |

On the "move thrust/braking into the boost system" bullet: I am **satisfied with the loose
reading**, and I want to be explicit that I am not treating it as a defect. The strict reading is
not merely bigger, it is broken against code I verified: `MissionTrigger._MAX_APPROACH_SPEED = 150.0`
(`mission_select_hub.gd:56`) gates every planet's dwell timer at `:97`, so a propulsion system whose
only output is a 700 px/s burst cannot produce a docking approach at all without reinventing W under
another name. The plan states the assumption in its own section, explains the cost, and routes the
decision to the user at epic approval — which is the correct handling for an ambiguous line in the
source idea, not a dodge. It also honours the defensible half of the strict reading by deleting the
hidden `move_up` flip-boost from the thrust path entirely.

## What I checked and found correct

Every code claim I could test, I tested. All of the following were verified first-hand, not taken
from the plan:

- `player_ship.gd:129-132` — the `move_up`-just-pressed / `boost_speed_threshold >= 180` trigger.
  Exact.
- `player_ship.gd:158-160` — `_trigger_flip_boost()` sets `velocity = forward * 200` against
  `max_speed = 420`. The plan's central framing ("that is not a boost, it is a brake") is correct.
- `player_ship.gd:155-156` — the unconditional tail `max_speed` clamp the boost has to survive.
- `player_ship.gd:90-91` — `_overheat_bar.global_position = global_position + Vector2(0, 20)`.
- `player_ship.gd:46` — `rotation = 0.0`, the line the mouse-aiming epic deletes.
- `overheat_bar.gd:4-5` — `BAR_WIDTH 32`, `BAR_HEIGHT 4`. The claimed 6 px gap clears
  `BAR_HEIGHT`, so the bar test's boundary assertion is satisfiable.
- `overheat_component.gd:17` — `_SHOOT_GRACE = 0.5`, reused as `recharge_delay_sec`.
- `shield_component.gd:38-46` and `:116-124` — the `_ready()` bind and `_on_progression_changed`
  mid-session grant. Both ranges exact.
- `ship_progression_state.gd` — `MIN_SHIELDS 1` / `MAX_SHIELDS 5`, the clamping no-op setter, the
  `add_*` returning false at cap, the `push_warning` clamp-on-load at `:51-54`. The "second key"
  design is a clean fit; `ConfigFile.get_value` with a default tolerates the missing key.
- `ship_shield_up_pickup.gd` is **9 lines** and its `.tscn` has **3 nodes**, `collision_layer = 16`,
  `collision_mask = 4`, `CircleShape2D` radius 8 at `scale = 3.111`. The plan's count is right;
  `1-context.md:27`'s "12-line" is the stale one.
- `sector_hub.tscn:88-103` — the bench row is exactly `x = 27, 104, 205, 304, 413, 519` at
  `y ≈ -212`, so `x = 620` is genuinely the next free slot.
- `project.godot` — `dash` and `race_brake` are both `physical_keycode 4194325`. A third action on
  Shift is safe: I checked `MovementController`'s `SINGLE_PRESS_ACTIONS` / `DOUBLE_PRESS_ACTIONS`
  (`movement_controller.gd:7-22`), which is the one input consumer living inside `player_ship.tscn`,
  and it reads neither.
- `open_space/scenes/gui/hud.tscn` contains **no** overheat element — `grep -i overheat` returns
  nothing. The plan's placement decision rests on this and it holds.
- `icon_ship_module_engine_boost.png` is **40×30** and `ship_shield_up.png` is **48×48**, exactly as
  the plan and task 5 state.
- `engine_boost_active` has exactly the sites the plan claims (`player_base.gd:45`,
  `player_fighter.gd:97`, `move_state.gd:39`, `dash_state.gd:126`, `player_ship.gd:118`, written
  only by `engine_boost_module.gd:60,106`).
- `mission_select_hub.gd:56` `_MAX_APPROACH_SPEED = 150.0`, `:97` the fast check, `:155-156`
  `set_physics_process(false)` + `set_process_input(false)`, `:170` `get_tree().paused = true`. All
  four exact, and they do settle the "boost during a mission menu" edge case in the plan's favour.
- **No existing test breaks.** `grep -rl 'player_ship\|OpenSpacePlayerShip\|boost' tests/` returns
  only `tests/unit/test_session_state.gd`, which is unrelated — `player_ship.gd` has no coverage
  today, so deleting `_trigger_flip_boost()` and the two exports breaks nothing. The project-wide
  sweeps (`test_project_load_integrity.gd`, `test_suite_integrity.gd`,
  `test_signal_emit_arity.gd`, `test_resource_uid_integrity.gd`) will all see the new files, which
  the task bodies already account for. `test_entity_sprite_transparency.gd`'s `SCOPE_ROOTS` (`:84-89`)
  does not cover `global/pickups`, and task 6 says so explicitly rather than assuming coverage.
- `PlayerBase.apply_knockback_motion()` — `1-context.md`'s risk 2 lists it as a fourth writer of
  `velocity`, but it is only called from `player_fighter.gd:76` and the race `wall_impact.gd`, never
  in open space. The plan is right not to design around it.

Fix B1 and B2 — both are edits to `3-plan.md` and two task bodies, no design change — and this is an
approve.
