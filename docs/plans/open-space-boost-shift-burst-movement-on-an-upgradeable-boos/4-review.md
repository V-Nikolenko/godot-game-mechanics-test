# Plan review — Open-space boost: Shift burst movement on an upgradeable boost meter

Rounds are appended, never overwritten. Each round keeps its own verdict line verbatim.

| Round | Verdict | Scope |
|---|---|---|
| 1 | CHANGES_REQUESTED | 2 blocking (both test-plan), 8 advisory. Design verified clean. |
| 2 | CHANGES_REQUESTED | 2 blocking, both task-body bookkeeping. Plan document confirmed good. |
| 3 | **APPROVED** | Confirmation pass over round 2's fixes and the new `set-body` CLI command. 4 non-blocking findings, all fixed after it ran. |

---

## Round 1

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


---

## Round 2

VERDICT: CHANGES_REQUESTED

# Plan review round 2 — Open-space boost: Shift burst movement on an upgradeable boost meter

Epic: `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`
Reviewed: 2026-09-14, against `agent/auto-dev` @ `969b18b` (working tree: `BACKLOG.json` /
`BACKLOG.md` modified by the harness only — run bookkeeping, no task bodies).
Round 1's verdict is in [`4-review.md`](./4-review.md) and is untouched by this file.

**The plan document is now good.** Every one of round 1's ten findings is answered in
`3-plan.md`, and eight of them are answered *correctly and completely*. The design did not change
and did not need to.

**The task bodies were not edited at all.** `git diff 05e3764 969b18b -- BACKLOG.json` contains
exactly two hunks: one appended `runs[]` record on the plan task, and `"state": "todo"` →
`"in_progress"` on the plan-review task. Not one character of any of the six implementation task
bodies changed. Round 1's B1 required change #3 and B2's required change both named specific task
bodies, and the revision's response table claims both landed. They did not. That is the exact
failure mode the round-2 brief singles out as blocking, and it matters in practice: tasks 2–5 are
executed from the body, and the bodies point at the plan's **Design** sections by name, never at
its **Test plan**, so the new "Autoload discipline" block is not on the path an implementer of
task 2 or 3 will read.

This is three task-body edits and one plan-body clarification. No design change, no re-plan.

---

## Round-1 findings, resolved

| # | Status | Evidence |
|---|---|---|
| **B1** | **PARTIAL — blocking** | Plan half: **done and correct.** `3-plan.md:437-492` is a new "Autoload discipline" block with the two-layer `before_all`/`after_all`/`before_each` pattern, and I verified it works against the real code: `tests/helpers/save_sandbox.gd:16-24` is still a file list and `:29-47` still only rewrites files; `ship_progression_state.gd:15-18` really is a `_permanent_shield_count` backing var behind a getter-only `permanent_shield_count`, so `ShipProgressionState._permanent_shield_count = _saved_shields` is a legal, complete restore, and the mirrored `_boost_charge_count` will be too; `test_weapon_unlock_sources.gd:38-53` is exactly the cited shape (`before_all` duplicates `UpgradeState._unlocked` on top of `_sandbox.capture()`; `before_each` assigns the backing field directly). Task half: **not done.** Neither `boosting-costs-a-charge-and-charges-come-back-on-their-own` nor `a-cyan-pip-bar-under-your-ship-shows-how-many-boosts-you-hav` mentions `SaveSandbox`, a snapshot, or the live autoload; and `a-pickup-in-the-hub-permanently-adds-a-boost-charge` still reads *"collect a **real instance against the live (sandboxed) autoload**"* — the exact phrase round 1 opened by calling "not a thing that exists". |
| **B2** | **PARTIAL — blocking** | Plan half: **done and correct.** `3-plan.md:150-153` shows `_step_boost()` opening with `if engine_boost_active: return`, `:160-169` is a new paragraph arguing the redundancy ("turns the precedence rule from *true* into *tested*"), and both affected cases (`:511`, `:542`) now carry "**If it fails, add the guard; do not weaken the case.**" Task half: **not done.** Task `shift-slams-your-ship-onto-its-new-heading-and-launches-it` still reads verbatim *"Do NOT: set or add anything like `engine_boost_active` (it is read-only here — a module boost wins and `_handle_thrust` already returns early)"*, which is the sentence round 1 said an implementer can read as "do not put a guard in `_step_boost`", and the body nowhere instructs that the guard be written. |
| **A1** | **Fixed** | `3-plan.md:112-121` is rewritten from the branch structure. I re-read `player_ship.gd:134-153`: `thrust_input > 0` adds `forward * thrust_acceleration * delta` with no damping, and only the `else` at `:146-147` runs `velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0, 1))`. The new text is right about the mechanism and adds the "do not reason from a force balance" warning. One residual arithmetic slip — see N5. |
| **A2** | **Fixed** | `3-plan.md:381` now shows both computations by one method. I reproduced them: 700 → `0.35·280 + (280/400)·140 = 98 + 98 = 196`; 600 → `0.35·180 + (180/400)·90 = 63 + 40.5 ≈ 104`. The derived ratios also check (196/104 = 1.88 ≈ "1.9×"; 700/600 = 1.17; 700/1500 = 0.47; 196/467 = 0.42). |
| **A3** | **Fixed** | Two invariant cases at `3-plan.md:544-545`, plus the honest `class_name`-is-global admission at `:188-195`. I confirmed the sweep case is meaningful and currently clean: `grep -rn 'is_action[a-z_]*("[^"]*boost' --include=*.gd .` returns nothing project-wide, and `project.godot`'s `[input]` has no `boost` action yet, so the case is green the day it lands and red the day the verb leaks. |
| **A4** | **Fixed** | `3-plan.md:326-332` now requires `BoostBar` to store `_charges: float` / `_max_charges: int` as members, citing `overheat_bar.gd:7`'s `_percentage` (confirmed — `OverheatBar` is 25 lines and keeps exactly that one member). Cases at `:554-556` read those members, and a fill case and a divide-by-zero boundary were added as asked. |
| **A5** | **Fixed** | `3-plan.md:197-210` is an explicit rejection of reusing/extracting `Shield`, and its factual claims hold: `shield_component.gd:20-22` (`bind_progression`, `permanent_charges`), `:38-45` (`_ready()` bind + signal connect), `:116-124` (`_on_progression_changed` with the immediate grant). The entanglement argument (`consume_one()` on the damage chain, temp charges, `is_hacked`, the `ShieldIconStrip` snapshot `Dictionary`) is all real in that file. |
| **A6** | **Fixed** | `3-plan.md:128-134` documents the meter freezing for the 0.55 s of an `EngineBoostModule` dash and explicitly forbids "fixing" it by hoisting `step()` above the early return. Correct: `player_ship.gd:118-119` returns before any tail call, and `engine_boost_module.gd:46` sets `_time_left = _BOOST_DURATION = 0.55`. |
| **A7** | **Fixed** | `3-plan.md:486-492` is a new "Ship instances go in the tree" block, and `:496` adds `add_child_autofree(ship)` to the verb file. The mechanism it states is real: `_thruster` is only assigned in `_setup_effects()` (`player_ship.gd:80-83`), called from `PlayerBase`'s `_ready()` chain, and `_handle_thrust` dereferences it at `:136-153`. Residual gap on the *bar* file — see N4. |
| **A8** | **Fixed** | Filed as its own item: `./scripts/backlog-cli.js epic show code-health-backlog` contains `the-open-space-ship-never-reads-the-permanent-shield-upgrade`, whose body cites `player_ship.tscn:223-224` and `player_fighter.tscn:301` and asks for a failing test. I confirmed both: `player_ship.tscn:223` declares `ShieldComponent` with no `bind_progression` line, `player_fighter.tscn:301` is the only `bind_progression = true` in the project, and `shield_component.gd:20` defaults it `false`. The plan's two "like the permanent shield already does" claims are corrected at `3-plan.md:26-30` and `:284-292`. |

---

## New findings

### Blocking

**N1 — The three task-body edits round 1 required were never made; the response table says they were.**
File: `BACKLOG.json`. Tasks: `shift-slams-your-ship-onto-its-new-heading-and-launches-it`,
`boosting-costs-a-charge-and-charges-come-back-on-their-own`,
`a-cyan-pip-bar-under-your-ship-shows-how-many-boosts-you-hav`,
`a-pickup-in-the-hub-permanently-adds-a-boost-charge`.

Evidence: `git diff 05e3764 969b18b -- BACKLOG.json` is 24 lines and contains no `"body"` change.
The three false claims are `3-plan.md:676` (*"and the requirement pushed into the step 2 and step 3
task bodies now"*) and `3-plan.md:677` (*"task 1's 'Do NOT' line reworded to forbid writing the
flag, not reading it"*).

Why it is not cosmetic. Tasks 3, 4 and 5 are `sonnet`, and every body's "Plan section" pointer
names a **Design** heading, never the **Test plan**. Nothing routes the implementer of task 2 or 3
to `3-plan.md:437-492`. The concrete sequence round 1 described is still available: task 4 flips
`bind_progression` to `true` on the `BoostMeter` node, `BoostMeter._ready()` then reads the live
`ShipProgressionState` on every `player_ship.tscn` instantiation, GUT walks `res://tests` with
`-ginclude_subdirs` so `integration/` precedes `unit/`, and an unsnapshotted
`test_boost_upgrade_source.gd` leaves the live count raised for the rest of the process.

Required edits (exact, and sufficient):

1. `boosting-costs-a-charge-and-charges-come-back-on-their-own` and
   `a-cyan-pip-bar-under-your-ship-shows-how-many-boosts-you-hav`: add a line saying these test
   files instantiate `player_ship.tscn`, which from the persistence task onward carries a
   `BoostMeter` that reads the live `ShipProgressionState` in `_ready()`, so they must carry the
   two-layer block in **`3-plan.md` → Test plan → "Autoload discipline"** *from the start* —
   `SaveSandbox.capture()`/`restore()` **plus** a `before_all`/`after_all` snapshot of
   `ShipProgressionState._boost_charge_count` and `_permanent_shield_count`. Point at that heading
   by name.
2. `a-pickup-in-the-hub-permanently-adds-a-boost-charge`: delete "(sandboxed)" from *"the live
   (sandboxed) autoload"* and replace it with the two-layer requirement, citing
   `test_weapon_unlock_sources.gd:38-53`.
3. `shift-slams-your-ship-onto-its-new-heading-and-launches-it`: reword the "Do NOT" line to
   *"do not **write** `engine_boost_active` (it stays owned by `engine_boost_module.gd`)"*, and add
   to the Touches list that `_step_boost()` opens with `if engine_boost_active: return` —
   deliberately redundant with `_handle_thrust`'s guard, because every test calls `_step_boost()`
   directly and so bypasses the outer one. Mirror `3-plan.md:160-169`'s "if the case fails, add the
   guard; do not weaken the case".

**N2 — Task 4's body contradicts the plan hardening that A8 produced.**
Task `extra-boost-charges-you-earn-stay-with-your-ship-between-run` says: *"`player_ship.tscn` — set
`bind_progression = true` on the node **if it is not the resource default**."*
`3-plan.md:284-292` says the opposite, in bold, with a ⚠️: *"`bind_progression = true` **must** be set
on the `BoostMeter` node in `player_ship.tscn`, and the scene diff must show it. The `@export`
default is not enough on its own to trust."* That warning exists precisely because
`player_ship.tscn:223` is the live instance of the failure. As written, the body licenses the
implementer to rely on the export default — which is exactly how the shield stat became inert.
Reword the body to require the explicit scene line.

### Non-blocking (fix in the same edit round, or leave to the implementer)

**N3 — `BoostBar` will render nothing until the first charge changes, and no case catches it.**
`3-plan.md:324` gives `setup()` only "Subscribes to `BoostMeter.charges_changed`". Children `_ready()`
before parents, so `BoostMeter._ready()` (which, copying `shield_component.gd:38-45`, emits its
initial state) fires *before* `OpenSpacePlayerShip._ready()` creates the bar and calls `setup()`.
At full charges nothing emits again until the first spend, so `_max_charges` sits at its initial
value and `_draw()` paints an empty backing rect on a bar the plan requires to be "always visible".
`OverheatBar` hides the same hole with `visible = false` (`overheat_bar.gd:11`) — `BoostBar` cannot.
Fix: `setup(meter)` seeds `_charges` / `_max_charges` from the meter and calls `queue_redraw()`, and
add a case — *"immediately after `_ready()`, with no signal emitted, `bar._max_charges ==
meter.max_charges`"*. The existing "It is visible at full" case passes on the broken build
(`visible` defaults `true`), so this is a real hole, not a hypothetical.

**N4 — Only one `test_boost_bar.gd` case is told to put the ship in the tree; all of them need it.**
`3-plan.md:553` scopes "Ship added to the tree" to the overlap boundary alone. But the bar is
*constructed* in `_ready()` (the plan's own `:311-313`, mirroring `player_ship.gd:50-53`), so on a
merely-instantiated ship there is no `BoostBar` child at all and even "The bar is in the scene"
(`:551`) fails. Say `add_child_autofree(ship)` at the top of the file, the way the verb file now does.

**N5 — A1's replacement arithmetic has a units slip.**
`3-plan.md:118`: *"the damping bleeds `0.6 x 700 = 420 px/s` in the first second"*. `0.6 × 700` is
420 px/s **²**, the instantaneous rate at 700 px/s; the actual loss over one second of
`v *= (1 - 0.6·dt)` is `700·(1−0.01)^60 ≈ 383`, i.e. ~317 px/s. The conclusion survives — I
simulated the release curve against a ceiling falling at 400 px/s² from t = 0.35 s and velocity
stays strictly under it throughout (567 vs 700 at 0.35 s, 460 vs 560 at 0.70 s, 373 vs 420 at
1.05 s), so "released → speed is actively lost" is correct. Only the sentence is wrong, and A1 was
raised precisely so a later tuner does not reason from a wrong sentence.

**N6 — A boost refused by the `boost_hold_sec` retrigger floor has no specified charge cost and no test.**
The plan pins "refused by a module burns no charge" (`:542`) and "empty meter costs nothing"
(`:541`), but the retrigger case (`:510`) only asserts `velocity`. `_step_boost()`'s internal order
— hold-window check before or after `meter.try_spend()` — is never stated, so "mash Shift inside
0.35 s and lose a charge for nothing" is an implementable reading. One sentence of ordering in the
plan plus one case (`_step_boost(true, d)` twice inside `boost_hold_sec` → `charges` down by exactly
1.0) closes it.

**N7 — The prescription for `test_ship_progression_state.gd` is right by accident, wrong by reason.**
`3-plan.md:476` says that file "obviously" needs the live-singleton discipline. It does not: the
existing file constructs tree-less `ProgressionScript.new()` instances via `_fresh()`
(`test_ship_progression_state.gd:18-19`) and never touches the autoload, which is `tests/README.md`'s
own house rule ("Prefer a tree-less `Script.new()` instance to the live autoload"). Adding the
snapshot block there is harmless, but the step-4 cases should be written against `_fresh()` like
their shield siblings; say so, or a `sonnet` implementer will convert the file to the live singleton
to match the plan.

**N8 — Nothing in the Design section owns the `flame_boost` playback, and no case asserts it.**
The animation appears only in the build sequence (`3-plan.md:418`) and task 1's body; the Design
section describes `_step_boost()` as having "no tree access" (`:149`), yet playing the animation
needs `get_node_or_null("SpriteAnchor/ShipSprite2D")` — `engine_boost_module.gd:15,63-67` is the
only existing precedent. Reconcile the two sentences (the ship is in the tree in every test now, so
it is fine — just say where the call lives), and note that `sprite.animation == &"flame_boost"` is
headless-assertable, so the epic's "reuse the blue boost flames" bullet can have a real case instead
of none.

**N9 — The A3 invariant names "the infiltration player scene" without a path.** It is under
`infiltration/scenes/entities/player/`. Name the file, or the sweep quietly covers one scene.

**N10 — One-frame lag on the thruster visual.** `_step_boost()` runs at the *tail* of
`_handle_thrust()` (`3-plan.md:147`) while the `ThrusterEffect` state is chosen in the branches
above it (`player_ship.gd:136-153`), so the cyan flame starts and ends one physics frame after the
boost. Today's code sets `_boost_timer` at `:129-132`, *before* the branches, so this is a (tiny)
behaviour change. Worth one line so it is not rediscovered as a bug.

---

## What I checked and found correct

Verified first-hand this round, not taken from `3-plan.md` or from `4-review.md`:

- `tests/helpers/save_sandbox.gd` — 54 lines; `PATHS` (`:16-24`) includes
  `user://ship_progression.cfg`; `capture()`/`restore()` (`:29-47`) only read and rewrite files;
  there is a third method, `clear_all()` (`:51-54`), that the plan does not need but that would also
  not help with in-memory state. Round 1's premise holds exactly.
- `global/autoloads/ship_progression_state.gd` — all 54 lines. `KEY_SHIELDS` `:9`, `MIN_SHIELDS 1` /
  `MAX_SHIELDS 5` `:10-11`, the getter-only property `:17-18`, the no-op-if-unchanged clamping
  setter `:23-29`, `add_permanent_shield()` returning `false` at cap `:33-37`, `_save()` writing one
  key `:39-44`, `_load()`'s `get_value(..., MIN_SHIELDS)` default and out-of-range `push_warning`
  `:46-54`. The plan's "second key, `_save()` writes both, `_load()` clamps each independently"
  is a clean, faithful mirror, and a pre-existing `.cfg` without the boost key loads at the default.
- `tests/integration/test_weapon_unlock_sources.gd:38-53` — the cited two-layer pattern, including
  the `before_each` that assigns `UpgradeState._unlocked` directly "so the fixture does not depend
  on the very code under test". The plan's block is the same shape.
- `open_space/scenes/entities/player/player_ship.gd` — the whole file. `:118-119` the
  `engine_boost_active` early return; `:127` the `_boost_timer` decrement; `:129-132` the
  `move_up`-just-pressed / `boost_speed_threshold >= 180` flip trigger; `:134-153` the three
  mutually-exclusive branches; `:155-156` the unconditional tail clamp; `:158-160`
  `_trigger_flip_boost()` setting `velocity = forward * 200`; `:11` `max_speed = 420`; `:90-91` the
  overheat bar at `+ Vector2(0, 20)`; `:50-53` how `OverheatBar` is constructed (`top_level`,
  `add_child`, `setup`); `:80-83` `_thruster` / `_thruster_right` built in `_setup_effects()`.
  Every line number the revised plan cites is exact.
- `assault/scenes/player/overheat_bar.gd` — 25 lines, `BAR_WIDTH 32` / `BAR_HEIGHT 4` `:4-5`,
  `_percentage` member `:7`, `visible = false` in `setup()` `:11`. The 6 px offset clears
  `BAR_HEIGHT`, so the overlap boundary case is satisfiable.
- `global/ship_modules/engine_boost_module.gd` — `_BOOST_SPEED 1500` `:5`, `_BOOST_END_SPEED 500`
  `:6`, `_BOOST_DURATION 0.55` `:7`, `_COOLDOWN 2.0` `:10`, `_SPRITE_PATH` `:15`,
  `engine_boost_active` written at `:60` and in `_end_boost()`, `damage_reduction = 1.0` `:52`.
  The differentiation argument (immunity + contact damage, not visuals) is sound and the
  out-of-scope list is honoured.
- `open_space/scenes/mission_select_hubs/mission_select_hub.gd` — `_MAX_APPROACH_SPEED = 150.0`
  `:56`, the `spd > _MAX_APPROACH_SPEED` dwell gate `:97`, `set_physics_process(false)` +
  `set_process_input(false)` + `velocity = Vector2.ZERO` `:155-158`, `get_tree().paused = true`
  `:170`. Both the "read the press from `_physics_process`" argument and the strict-reading
  rejection rest on real code.
- `open_space/scenes/levels/sector_hub.tscn` — the full position list. The bench row at
  `y ≈ -212` is `x = -130, 27, 104, 205, 304, 413, 519`, and nothing in the scene sits near
  `(620, -212)`. The proposed slot is genuinely free.
- `project.godot` — `dash` is `physical_keycode 4194325`; there is no `boost` action today, and no
  `.gd` anywhere reads a `"boost"` action. Adding it is purely additive and A3's sweep starts green.
- `player_ship.tscn` node list — 22 nodes, `SpriteAnchor/ShipSprite2D` is the `AnimatedSprite2D`,
  `flame_boost` is a real animation at `:164`, and there is no `BoostMeter`-shaped node to collide
  with. `ShieldComponent` at `:223` still has no `bind_progression` line.
- `tests/README.md` house rules — the `SaveSandbox` rule, "GUT fails a test on any unexpected
  engine error" (which is what makes the plan's divide-by-zero boundary case assertable at all),
  "prefer a tree-less `Script.new()`", and the arity trap. The plan is consistent with all four.
- **Decomposition, dependencies, complexity, models** — re-derived independently and I agree with
  round 1. Six tasks map 1:1 onto `3-plan.md:415-427`; the graph (1 ← 2 ← {3, 4}, 4 ← 5 ← 6) has no
  cycle and no stall; 3 and 4 touch disjoint files (`boost_bar.gd` + `player_ship.gd::_ready` vs
  `ship_progression_state.gd` + `boost_meter.gd`, with 4 also adding one scene property) so either
  order works; `medium`/`opus` on 1 and 2 and `small`/`sonnet` on 3, 5, 6 are right; 4 is the
  borderline call (a shared `global/` autoload) but is a line-for-line mirror with no new machinery,
  so `small` stands. The mouse-aiming scheduling constraint is correctly a task-body note rather
  than a `--depends-on` edge.
- **The source idea, bullet by bullet** — re-read against `epic show`'s `sourceIdea.text`. Every
  bullet is answered, and the only loose one ("move the existing thrust/braking behavior into the
  boost system") is explicitly flagged for the user at `3-plan.md:353-371` with a reason I verified
  (the 150 px/s docking gate makes the strict reading unflyable). That remains the correct handling.
- **Conventions** — composition (a child `Node`, no `PlayerBase` field), `.tres` config convention
  correctly scoped to assault enemies, 640×360 × `WORLD_SCALE` correctly identified as not applying,
  both new signals declared with parameters, `uid://` prohibition carried in task 5, projectile
  ownership untouched, no per-frame printing introduced. No finding.
- **Research** — six findings, each with a tradeoff, honest about the two unread sources, and
  finding 3 still contradicts the epic's own reference framing in the open rather than burying it.
  The two numbers the plan adopts directly (0.7 charges/s, 3 pips → 2) trace to the ULTRAKILL wiki
  row; nothing in the numbers table is attached to the weakly-sourced finding 6. No finding.

Fix N1 (three task bodies) and N2 (one task body), and this is an approve. N3–N10 are advisory;
N3 and N6 are the two I would most want folded into the same edit because each is one plan sentence
plus one test case, and each closes a hole the current test plan cannot catch.


---

## Round 3

VERDICT: APPROVED

# Plan review round 3 (confirmation pass) — Open-space boost: Shift burst movement on an upgradeable boost meter

Epic: `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`
Reviewed: 2026-09-14, against `agent/auto-dev` @ `969b18b` **plus the uncommitted working tree**
(`BACKLOG.json`, `BACKLOG.md`, `3-plan.md`, `4-review.md`, `scripts/backlog-cli.js`).
Rounds 1 and 2 are in [`4-review.md`](./4-review.md); this file does not modify it.

Scope of this pass, as briefed: judge whether round 2's fixes are **real**, review the new
`set-body` CLI command, check the four/five rewritten task bodies for silent losses, and confirm
`4-review.md` is intact. Design questions settled in rounds 1 and 2 were not re-opened.

**Result: both blocking findings (N1, N2) are genuinely fixed in the artifacts, not just in the
response table.** I verified every one against `BACKLOG.json` itself (`git diff -- BACKLOG.json`
plus a field-by-field old/new comparison), which is the check round 2 failed. Eight of the ten
findings are fully fixed; N7 and N9 are *partially* fixed — both were advisory, and neither now
misroutes an implementer whose task body is explicit, but N7's edit left a self-contradicting
sentence behind that should be cleaned up before task 4 runs (see **New findings**, NF-1). The new
`set-body` command is correct, safe, and passes the whole harness suite (78/78).

---

## Per-finding table

| # | Status | Evidence |
|---|---|---|
| **N1** — round 1's three task-body edits never made | **FIXED, verified in `BACKLOG.json`** | All three required edits are present, and I confirmed them from the store rather than from the table. (1) `boosting-costs-a-charge-and-charges-come-back-on-their-own` now opens *"Plan sections **Design → The meter…** AND **Test plan → Autoload discipline** (read both — the second one is not optional, see below)"* and carries *"⚠️ **`test_open_space_boost_wiring.gd` must carry the autoload-snapshot block from day one**… Copy the two-layer `before_all` / `after_all` / `before_each` pattern from **`3-plan.md` → Test plan → "Autoload discipline"** (the shape is `tests/integration/test_weapon_unlock_sources.gd:38-53`): sandbox the file **plus** snapshot and restore `ShipProgressionState._boost_charge_count` and `_permanent_shield_count`."* (2) `a-cyan-pip-bar-under-your-ship-shows-how-many-boosts-you-hav` carries the same block verbatim-equivalent (*"⚠️ **This file needs the autoload-snapshot block from day one.**… Copy the two-layer pattern from **`3-plan.md` → Test plan → "Autoload discipline"**"*). Both point at the **Test plan** heading *by name*, which was round 2's specific complaint that every pointer named a **Design** heading. (3) `a-pickup-in-the-hub-permanently-adds-a-boost-charge`: the string `(sandboxed)` is **gone** (`grep` over the store returns nothing), replaced by *"collect a **real instance** and assert the count went up"* plus *"there is no such thing as a 'sandboxed autoload'"* and the two-layer requirement citing `test_weapon_unlock_sources.gd:38-53`. (4) `shift-slams-your-ship-onto-its-new-heading-and-launches-it`: the old *"Do NOT: set or add anything like `engine_boost_active`"* is replaced by *"Do NOT: **write** `engine_boost_active` — it is read here and stays owned by `global/ship_modules/engine_boost_module.gd`"*, and a new Touches bullet reads *"**`_step_boost()` opens with `if engine_boost_active: return`.** This is deliberately redundant… If either precedence case fails, add the guard — do not weaken the case."* That is exactly round 2's required edit #3, mirror included. |
| **N2** — task 4 licensed relying on the `@export` default | **FIXED** | `extra-boost-charges-you-earn-stay-with-your-ship-between-run`'s old bullet (*"set `bind_progression = true` on the node if it is not the resource default"*) is gone. It now reads: *"⚠️ `…player_ship.tscn` — **set `bind_progression = true` explicitly on the `BoostMeter` node, and make sure the scene diff shows that line.** The `@export` default is not enough to rely on, and this is not hypothetical: `player_ship.tscn:223` authors its `ShieldComponent` with no `bind_progression` line… (filed as `the-open-space-ship-never-reads-the-permanent-shield-upgrade`). Follow `assault/scenes/player/player_fighter.tscn:301`, the one scene that gets this right."* This now matches `3-plan.md:284-292`'s ⚠️ instead of contradicting it. |
| **N3** — bar renders nothing until the first charge change | **FIXED (plan + body)** | `3-plan.md`: *"`setup(meter)` **seeds `_charges` / `_max_charges` from the meter and calls `queue_redraw()`, then subscribes to `BoostMeter.charges_changed`**"* followed by *"⚠️ **The seed is not optional.** Children `_ready()` before parents…"*. New case in `test_boost_bar.gd`'s table: *"**Seeded at `_ready()`, before any signal** — With **no** `charges_changed` emitted, `bar._max_charges == meter.max_charges`. This is the N3 hole; 'visible at full' passes on the broken build because `visible` defaults `true`."* Task 3's body carries the same ⚠️ bullet and the same assertion. |
| **N4** — only one bar case told to parent the ship | **FIXED (plan + body)** | Plan section preamble: *"**Every case here needs `add_child_autofree(ship)`, not just the overlap one.**… on a merely-instantiated ship there is no `BoostBar` child at all and even 'the bar is in the scene' fails."* The overlap case row no longer owns the requirement (*"One physics frame awaited"*). Task 3's body repeats it. |
| **N5** — units slip on `0.6 x 700 = 420` | **FIXED, arithmetic re-checked** | `3-plan.md` now reads *"(Careful with the units: `0.6 x 700 = 420` is px/s**²**… one second at 60 Hz leaves `700·(1−0.01)^60 ≈ 383 px/s`, a loss of ~317 px/s… 567 vs 700 at 0.35 s, 460 vs 560 at 0.70 s, 373 vs 420 at 1.05 s…)"*. I recomputed: `0.99^60 = 0.5472`, `700 × 0.5472 = 383.0`, loss `317`. Correct. Conclusion unchanged, as round 2 said it should be. |
| **N6** — retrigger-refused boost had no specified cost | **FIXED (plan + two bodies)** | New case row: *"**Boundary: a retriggered boost burns no charge** — **Ordering is part of the contract: the `boost_hold_sec` window is checked BEFORE `meter.try_spend()`**… Two `_step_boost(true, d)` calls inside `boost_hold_sec` → `charges` down by exactly 1.0. (Meter exists from step 2; until then assert the `velocity` half only.)"* Task 1's body: *"**Order inside `_step_boost()` is part of the contract:** the `boost_hold_sec` retrigger floor is checked **before** any spend"*, with the step-1-only variant spelled out; task 2's body: *"**Check the hold window before the spend**, so a boost refused by the retrigger floor costs nothing; assert it"*. |
| **N7** — `test_ship_progression_state.gd` wrongly told to use the live singleton | **PARTIAL — non-blocking, but clean it up** | The substantive fix landed, in both places: plan — *"`test_ship_progression_state.gd` (step 4) **does not, and must not start**: it builds tree-less `ProgressionScript.new()` instances through its own `_fresh()` helper (`:18-19`)… Write the new boost cases against `_fresh()` exactly like their shield siblings"*; task 4's body — *"**Write the autoload cases against a tree-less `ProgressionScript.new()` via the existing `_fresh()` helper…**, like their shield siblings — that file does not touch the live singleton today and should not start."* **But the edit left the old paragraph's tail in place**, and it now contradicts the new text: the same paragraph still ends *"Add the block above to **all four files** from the start; it is inert until step 4 and correct afterwards."* The only fourth file is the one just excluded. The paragraph also contains a botched splice — *"Less obviously, \*\*the two that do need it are Less obviously, \*\*so do `test_open_space_boost_wiring.gd`…"* — with duplicated words and unbalanced `**`. See NF-1. |
| **N8** — nobody owned `flame_boost` playback | **FIXED** | New plan block: *"**One tree touch, named here so the 'no tree access' line above is not read too literally.** The trigger branch plays `flame_boost` on `SpriteAnchor/ShipSprite2D` and sets both `ThrusterEffect`s to `State.BOOST`, following `engine_boost_module.gd:15,63-67`… `sprite.animation == &"flame_boost"` is readable headless."* Task 1's body carries the same under *"**Who plays the flame:**"*. |
| **N9** — invariant said "the infiltration player scene" with no path | **PARTIAL — acceptable** | Plan case row now reads *"…and the infiltration player scene under `infiltration/scenes/entities/player/` — **name the actual file, do not write "the infiltration player scene"**, or the sweep quietly covers one scene — walked by class…"*, and task 2's body repeats it. The *risk* N9 named is now explicit and the directory is given, so the implementer cannot miss it. It is still the instruction rather than the answer: the file is `infiltration/scenes/entities/player/player.tscn` (confirmed — it is the only `.tscn` in that directory) and could simply have been written. Advisory, harmless. |
| **N10** — one-frame thruster lag | **FIXED** | Plan: *"Because `_step_boost()` runs at the **tail** of `_handle_thrust()`… the cyan flame starts and ends one physics frame after the boost. Today's code sets `_boost_timer` at `:129-132`, *before* the branches, so this is a real (if imperceptible) behaviour change. Accepted; recorded so it is not rediscovered as a bug."* Task 1's body carries the same note ("a known, accepted one-frame difference, not a bug to chase"). |

**Verification method, stated because it is the thing round 2 caught:** none of the above is taken
from `3-plan.md`'s "Response to review round 2" table. Each body quote is `console.log(...task.body)`
from the live `BACKLOG.json`, and each plan quote is from the working-tree file. I also diffed the
store structurally (old vs new task objects, field by field) rather than eyeballing the JSON hunks.

---

## The new `set-body` subcommand

**Correct and safe. No blocking finding.** `scripts/backlog-cli.js:206-221`.

| Property | Finding |
|---|---|
| Lock / persist path | **Same as every other mutating command.** It calls `mutate(...)`, i.e. `S.withLock(LOCK, …)` → `S.load` → callback → `persist` (atomic `S.save` + `S.render` to `BACKLOG.md`). It does not touch `FILE` or `MD` directly. |
| Field preservation | **Complete.** It assigns exactly `t.body` on the object returned by `S.findTask`. I proved it empirically: ran `set-body` against a scratch copy (`BACKLOG_REPO=/tmp/sb`) and compared every task object field-by-field plus top-level keys, `ideas`, and epic metadata against the original — the **only** difference in the whole store was that one task's `body`. |
| `BACKLOG.md` render | **Preserved.** `persist()` re-renders it; the scratch run produced a 139 KB `BACKLOG.md`, and the real repo's `BACKLOG.md` is byte-identical to `S.render(S.load(BACKLOG.json))` today, so the author did go through the CLI and did not hand-edit either file. `BACKLOG.json` parses. |
| Corruption risk | **None found.** Body content is never interpolated into anything — it is a JS string written through `JSON.stringify`. I round-tripped a body containing `"quotes"`, a backslash, a blank line and `⚠️`/non-ASCII; it came back exactly. `die()` inside the callback throws *before* `persist()`, so a bad taskId cannot leave a half-written store, and (per the file's own comment) throwing rather than `process.exit()` lets `withLock`'s `finally` release the lock. |
| Failure modes vs the rest of the CLI | **Consistent.** Missing taskId → `backlog-cli: usage: set-body <taskId>   (new body on stdin, replaces the whole body)`, exit 1. Unknown taskId → `backlog-cli: no such task: nope-nope`, exit 1, store untouched, **no lock file left in the repo dir** (checked). Empty stdin *and* whitespace-only stdin → `backlog-cli: set-body: refusing to write an empty body…`, exit 1. That empty-guard is *stricter* than `add-task` (which happily writes an empty body) and is the right asymmetry: a rewrite that silently blanks a body is the expensive failure. No-stdin (tty) hits `readStdin()`'s catch → `""` → same guard. |
| Harness tests | **All 78 pass with the modified CLI** (`/agent/test/*.test.js`, run with `helpers.js`'s `CLI_PATH`/`AGENT` repointed at this container's real layout — `/agent/test.sh` as shipped resolves the CLI at `/repo/scripts/backlog-cli.js` and fails for every command, which is a **pre-existing** container/path mismatch, not something this change caused). `cli`, `store`, `concurrency`, `review`, `ui`: 64 + 14, zero failures. |

Two notes, neither blocking:

- **NF-2 (minor, one-word fix): `set-body` does not `trim()` the body; `add-task` does.**
  `backlog-store.js:418` stores `body: String(body || "").trim()`, and load-time normalization
  (`:187`) does not trim. `set-body` writes raw stdin, so every body written this round ends with
  `\n`, and the renderer (`:616`, `t.body.split(NL).map(l => "      " + l)`) emits one extra
  six-space line before each task's `after:` line — visible in `BACKLOG.md` at the end of all five
  rewritten tasks. Cosmetic only, but it is a gratuitous divergence from `add-task`. Fix:
  `const body = readStdin().trim();` (keep the empty guard, which then reads `if (!body)`).
- **No harness test covers `set-body`.** `/agent/test/cli.test.js` has cases for `set-state`,
  `set-badge`, `set-plandir`, `set-meta`; the new command has none. `/agent` is mounted read-only,
  so the agent could not add one — worth flagging to the user rather than holding the epic for it.

---

## Did the body rewrites drop anything?

**No.** I extracted the old and new bodies for all five changed tasks from `git show HEAD:BACKLOG.json`
vs the working tree and diffed them line by line. Every diff is purely additive except five
intentional replacements, each of which is a required edit or a strict improvement:

| Task | Removed text | Assessment |
|---|---|---|
| 1 (verb) | *"all **ten** cases of the new `test_open_space_boost_verb.gd` pass"* → *"all cases"* | Correct — round 2's N6 added a case, so a hard count would have been stale. |
| 1 (verb) | *"Do NOT: set or add anything like `engine_boost_active` (it is read-only here…)"* | This **is** N1's required edit #3. Replacement preserves both halves of the original prohibition (don't write the flag; module boost wins). |
| 3 (bar) | *"The overlap boundary case needs **the ship in the tree** for one physics frame"* | Not lost — promoted to a file-wide *"Every case in this file needs `add_child_autofree(ship)`"* (N4). Strictly stronger. |
| 4 (persistence) | *"Every test here touches a `user://`-persisting autoload, so it MUST use `tests/helpers/save_sandbox.gd` (`tests/README.md`)."* | The only place a constraint was **softened** rather than kept verbatim. The replacement retains it — *"`SaveSandbox` still applies wherever a save path is exercised"* — but as a clause rather than a MUST. Acceptable (the `_fresh()` instruction is what N7 required, and `test_ship_progression_state.gd` already uses the sandbox), though restoring the imperative would cost nothing. |
| 5 (pickup) | *"…against the live (sandboxed) autoload… Copy that pattern from `test_weapon_unlock_sources.gd`."* | This is N1's required edit #2. The vaguer citation is replaced by `test_weapon_unlock_sources.gd:38-53` plus the full two-layer spec and the GUT ordering reason. Strictly stronger. |

Everything else in all five bodies — the `uid://` prohibition, the "find the node by class, not by
node path" rule, the `BoostMeter` must-not-`_physics_process` rationale, the "where the bar goes is
settled" paragraph, the mouse-aiming sequencing warning, the `scripts/check-test-leaks.sh` line, the
three at-cap/clamp/shared-`ConfigFile` boundary cases, and every `updating-project-docs` invocation —
survives unchanged. No other task, epic, or idea in the store was modified (one addition,
`the-open-space-ship-never-reads-the-permanent-shield-upgrade` on `code-health-backlog`, which is
round 1's A8 filing and which round 2 already verified).

---

## Is `4-review.md` intact?

**Yes.** `git diff --numstat` on that file is **`255 0`** — 255 insertions, **zero deletions**, and
`git diff -U0 | grep -c '^-[^-]'` is `0`. Nothing in round 1's text was altered. The additions are
the rounds table at the top, a `## Round 1` heading above the existing content, and the appended
`## Round 2` section. Both verdict lines survive verbatim and in place: `:16 VERDICT:
CHANGES_REQUESTED` (round 1) and `:354 VERDICT: CHANGES_REQUESTED` (round 2). I did not modify the
file.

---

## New findings

**NF-1 (must fix before task 4 runs; not worth another review round).** `3-plan.md`, Test plan →
"Autoload discipline" → "Which files need it, and when". The N7 edit spliced in correct new text but
left the old tail attached, producing (a) a garbled clause and (b) a direct contradiction:

> …adding the snapshot block there would be harmless but it would also invite an implementer to
> convert the file to the live singleton to match this plan. **Less obviously, \*\*the two that do
> need it are Less obviously, \*\*so do** `test_open_space_boost_wiring.gd` (step 2) and
> `test_boost_bar.gd` (step 3)**: … Add the block above to **all four files** from the start;

There are three such files now, and the excluded fourth is `test_ship_progression_state.gd`, which
the same paragraph has just said in bold **must not** get it. Task 4's body header sends its
implementer to this exact section, so the contradiction reaches the person N7 was written to
protect. Mitigation is real — task 4's body states the correct rule explicitly and at length, and
N7's own worst case is "harmless extra block" — which is why this is not a blocking verdict. Fix:
replace the mangled clause with *"The two that **do** need it are `test_open_space_boost_wiring.gd`
(step 2) and `test_boost_bar.gd` (step 3):"*, and change the closing sentence to *"Add the block
above to those three files from the start"*.

**NF-2** — `set-body` missing `.trim()`; see the CLI section.

**NF-3 (minor, accuracy).** `3-plan.md`'s round-1 response table now says B1's requirement was
*"pushed into the step 1, 2, 3, 4 and 5 task bodies"*. It was pushed into **2, 3 and 5**; task 1
carries no autoload requirement at all, and task 4 carries the *opposite* (correctly, per N7). The
underlying edits are right and verified, so this is only wording — but given that round 2's central
finding was a response table claiming more than happened, this row should say "step 2, 3 and 5
bodies (and the step 4 body records why it is exempt)".

**NF-4 (trivial).** The round-2 response opens *"`4-review-round2.md` returned CHANGES_REQUESTED"*.
No such file exists; round 2 is the `## Round 2` section of `4-review.md`. Retarget the reference.

**NF-5 (process, for the user not the author).** All of this is uncommitted: `BACKLOG.json`,
`BACKLOG.md`, `3-plan.md`, `4-review.md` and `scripts/backlog-cli.js`. Per `CLAUDE.md` it belongs on
`agent/auto-dev` with a green gate. Note that `/agent/verify.sh` is a **Godot** gate and says nothing
about `backlog-cli.js`; the relevant evidence for the CLI change is the harness suite, which I ran
(78/78, with the path caveat above).

---

## Verdict

**APPROVED.** N1 and N2 — the two blocking findings — are fixed in the artifacts themselves, which
is the standard round 2 set and the standard this pass was convened to apply. Six of the eight
advisories are fully fixed; N7 and N9 are partially fixed in ways that do not misdirect an
implementer, because each affected task body states the rule correctly on its own. The `set-body`
command is a sound addition: same lock, same persist, same failure vocabulary, no field loss, no
render loss, whole harness suite green. The body rewrites lost nothing.

NF-1 (two sentences in `3-plan.md`) and NF-2 (one `.trim()`) should be applied before the first
implementation task starts. Neither warrants a fourth review round, and neither is a reason to hold
the epic from the user.


---

## Round 3 follow-up (applied after the verdict)

Round 3 approved with four non-blocking findings. All four were introduced by round 2's own fix
pass, so all four were fixed rather than deferred:

- **NF-1** — the N7 edit left a garbled splice ("the two that do need it are Less obviously, **so do")
  and a surviving "Add the block above to all four files" that contradicted the new bold text two
  sentences above it. Both rewritten: the list is now the three files that need the block, naming
  them, and explicitly excluding `test_ship_progression_state.gd`.
- **NF-2** — `set-body` did not `.trim()` stdin while `add-task` does, leaving one trailing newline
  per rewritten body. Fixed in `scripts/backlog-cli.js` with a comment saying why, and the five
  already-written bodies were re-applied through the fixed command. `BACKLOG.md` is byte-identical
  to `S.render(S.load(BACKLOG.json))`. (The *indented* blank lines inside bodies are the renderer's
  own body indentation and appear identically on tasks created by `add-task`; not a defect.)
- **NF-3** — the round-1 response row overclaimed which task bodies were edited. Corrected to the
  three that actually were (2, 3, 5), with the reason step 4 is excluded.
- **NF-4** — the plan cited `4-review-round2.md`, which no longer exists as a separate file.
  Corrected to name the `## Round 2` section of this file.

Not fixed, and deliberately left: round 3's note that task 4's "MUST use `save_sandbox.gd`" became
a clause rather than an imperative. The body still carries the requirement, and N7 is the reason
that sentence was softened — the file must stay tree-less, so a blanket imperative there would be
the very instruction N7 asked to remove.
