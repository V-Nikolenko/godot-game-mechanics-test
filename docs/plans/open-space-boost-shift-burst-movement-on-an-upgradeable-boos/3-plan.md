# Open-space boost: Shift burst movement on an upgradeable boost meter

Epic: `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`
Stage: **PLAN**, 2026-09-14, against `agent/auto-dev` @ `aabc559`.
Builds on [`1-context.md`](./1-context.md) (what is already in the codebase) and
[`2-research.md`](./2-research.md) (how shipped games solve it). Neither is re-derived here.

---

## Problem

**Today.** In the sector hub the ship accelerates with W, reverses with S, and coasts on a
`damping = 0.6` first-order decay. That coast is good — the hull keeps 55% of its speed a second
after the key is released — but it means **turning around costs ~3.0 s** (0.82 s to rotate 180°
at 220°/s, then 2.22 s of thrust to push the velocity back through zero). Traversal is therefore
"hold W and wait", and the only fast direction change is a special case the player cannot see:
`_handle_thrust()` watches for **W pressed while flying backwards at ≥ 180 px/s** and quietly runs
`_trigger_flip_boost()`, which sets `velocity = forward * 200`. That is not a boost. Against
`max_speed = 420` it is a **brake**, it has no key of its own, no cost, no meter, no sound and no
UI, and nothing in the game tells the player it exists.

**After this epic.** Shift is a verb. Pressing it slams the ship's momentum onto whatever heading
the nose is pointing and launches it above cruise speed — so a 180° turn-and-burn that costs three
seconds today costs one keypress, and a boost while already flying straight is a genuine sprint.
It is not free: each boost spends one charge from a small meter drawn as cyan pips under the hull,
next to the existing overheat bar, and the meter refills over a couple of seconds. A pickup in the
hub permanently raises the ship's charge capacity, and that capacity persists across runs the way
the permanent shield count is *meant* to (the saved stat does persist; see the correction under
"Response to review round 1" — `player_ship.tscn`'s `ShieldComponent` does not currently read it,
which is a separate pre-existing bug this epic deliberately does not inherit). The blue afterburner flame the ship already owns
plays for the length of the burst, so the verb reads at a glance.

None of this exists outside open space. The assault mode's `EngineBoostModule` — the H-key
equippable dash — is not touched, not re-cast and not superseded.

---

## Design

### The one decision that shapes everything: an unconditional redirect

Every boost does the same thing, with no angle test and no second branch:

```gdscript
velocity = Vector2.UP.rotated(rotation) * boost_exit_speed
```

This is ULTRAKILL's rule verbatim (`2-research.md` finding 1: *"Dashing also completely resets
player momentum when performed"*), and it is the same single line `_trigger_flip_boost()` already
ships. It answers the epic's two movement asks with **one** behaviour:

- *"a significant burst of speed in the current direction the ship is facing"* — from cruise or
  from rest, the boost sets speed to `boost_exit_speed = 700` against `max_speed = 420`.
- *"turn ~180° and boost to rapidly reduce current movement and transition into the new
  direction"* — from `-420` on the facing axis the same assignment lands at `+700` in one frame,
  collapsing the measured 3.0 s reversal.

The one change from today's prototype is the number: **the exit speed must exceed cruise**, or the
boost reads as a brake, which is exactly the bug `boost_redirect_speed = 200` is.

**Rejected — a two-branch rule** (redirect above some angle threshold, additive burst below).
`1-context.md` open question 1(c) and the closest reading of the idea's wording. It is two
behaviours behind one key with no tell to distinguish them, it adds a threshold nobody can tune
without a fly-test, and the shipped precedent says the uniform rule is enough. Rejected.

**Rejected — an additive impulse** (`velocity += facing * impulse`). It cannot do the flip: from
`-420` an impulse large enough to reach a useful forward speed is enormous, and from `+420` the
same impulse is a mild nudge. The behaviour would be wildly non-uniform in the player's hands.
Rejected.

### The speed cap, and why the boost is not `engine_boost_active`

`_handle_thrust()` currently ends with a hard `if velocity.length() > max_speed: clamp`. A 700
px/s boost dies on the same frame unless something lifts that clamp. `EngineBoostModule` solves
this by setting `PlayerBase.engine_boost_active`, which makes `_handle_thrust()` return early and
hands the module total ownership of `velocity` for 0.55 s. **The core boost must not do that**:
`engine_boost_active` is declared in `global/entities/player_base.gd` and honoured in four assault
call sites (`player_fighter.gd:95-101`, `move_state.gd:39`, `dash_state.gd:126`), so borrowing it
puts open-space state on an assault code path, and adding a second such flag is worse.

Instead the clamp becomes a **decaying ceiling**, entirely local to `OpenSpacePlayerShip`:

```gdscript
var _speed_ceiling: float = max_speed        ## never below max_speed
var _boost_hold_left: float = 0.0            ## flame + retrigger window

## on a successful boost
velocity = facing * boost_exit_speed
_speed_ceiling = boost_exit_speed
_boost_hold_left = boost_hold_sec

## every frame, after thrust/damping
if _boost_hold_left > 0.0:
    _boost_hold_left = maxf(_boost_hold_left - delta, 0.0)
else:
    _speed_ceiling = maxf(move_toward(_speed_ceiling, max_speed, boost_ceiling_decay * delta),
                          max_speed)
if velocity.length() > _speed_ceiling:
    velocity = velocity.normalized() * _speed_ceiling
```

`move_toward` is a linear ramp, so it is exactly frame-rate independent — unlike the existing
`velocity.lerp(ZERO, damping * delta)` damping, which drifts 2.3% per second between 30 and 60 Hz
(`1-context.md`). **That damping is deliberately left alone.** Rewriting it is the sibling
mouse-aiming epic's business, not a boost change, and touching it here would make this epic's
tuning impossible to attribute.

Three properties fall out of this, all of them wanted:

1. **The ceiling only ever permits, never yanks.** It is clamped at `max_speed` from below, so the
   ship's normal handling is untouched the moment the window closes.
2. **Holding W sustains a boost; releasing it bleeds.** Thrust and damping are **mutually
   exclusive branches**, not simultaneous forces — `player_ship.gd:134-153` adds
   `forward * 380 * delta` when `thrust_input > 0` and applies **no** damping, and only the `else`
   branch runs `velocity.lerp(ZERO, damping * delta)`. So: W held → thrust cannot outrun the
   ceiling once it starts falling (380 px/s² of push against 400 px/s² of ceiling decay), and the
   ship rides the ceiling down, staying above cruise for the whole window. W released → the damping
   bleeds `0.6 x 700 = 420 px/s` in the first second, marginally faster than the ceiling falls, so
   speed is actively lost rather than merely permitted to be lost. That asymmetry is free, readable
   depth, and it keeps W meaningful during a boost. *(Do not reason from a "damping plus thrust"
   force balance — the two branches never both run.)*
3. **A module boost still wins.** `_handle_thrust()` returns early while `engine_boost_active`
   (`player_ship.gd:118-119`), so the core boost is not reachable during a module dash — no
   double-write, and no charge spent either. **`_step_boost()` repeats that guard as its own first
   line.** See "the precedence guard is deliberately doubled" below: without it the rule is true but
   not testable, because every test drives `_step_boost()` directly.

   A consequence worth writing down rather than rediscovering: because `_step_boost()` is only
   reached from the tail of `_handle_thrust()`, **the meter does not tick during a module dash** —
   `meter.step(delta)` is skipped for the 0.55 s of an `EngineBoostModule` boost, so recharge
   pauses and resumes afterwards. That is harmless and arguably correct (the ship is already
   boosting), but it is a real behaviour, not an accident. Leave it as is; do not "fix" it by
   hoisting `step()` above the early return, which would also make the meter tick while a mission
   menu is opening.

### Where `Input` is read, and the testable seam

`Input` cannot be driven in a headless GUT run. So, exactly as the sibling epic concluded for the
mouse, the boost model is a **pure step over injected input** and `Input` is read in one place:

```gdscript
## player_ship.gd — the only Input read for this feature
func _handle_thrust(delta: float) -> void:
    if engine_boost_active:
        return
    ... existing thrust / reverse / damping, unchanged ...
    _step_boost(Input.is_action_just_pressed("boost"), delta)   ## replaces the tail clamp

## the whole boost model — no Input, no Engine singletons, no tree access
func _step_boost(boost_pressed: bool, delta: float) -> void:
    if engine_boost_active:
        return                      ## deliberately redundant — see below
    ...
```

`_step_boost()` owns the meter tick, the trigger decision, the ceiling decay **and the final speed
clamp** (it replaces `_handle_thrust()`'s existing tail clamp, so there is exactly one place that
clamps). Every test drives `_step_boost()` directly.

**The precedence guard is deliberately doubled.** `_handle_thrust()` already returns on
`engine_boost_active`, so in the shipped call path `_step_boost()` can never run during a module
dash and the inner guard is dead code. It is required anyway, because the seam this whole design
rests on is "every test calls `_step_boost()` directly" — and a test that calls it directly bypasses
the outer guard entirely. Without the inner line the two cases that pin module precedence ("a module
boost wins", "a boost refused by a module burns no charge") assert something the code does not do,
fail on a **correct** build, and the cheapest way to make the suite green is to delete the two most
valuable cases in the file. The redundancy is what turns the precedence rule from *true* into
*tested*. `engine_boost_active` is **read** here and **never written** by anything in this epic — it
stays owned by `engine_boost_module.gd:60,106`.

Reading the press from `_physics_process` rather than `_input`/`_unhandled_input` is deliberate and
settles an edge case for free: `MissionTrigger._open_menu()` calls
`player.set_physics_process(false)` before `get_tree().paused = true`
(`mission_select_hub.gd:155-156, :170`), so a boost pressed while a mission menu is opening is
already dead. An `_unhandled_input` read would fly the ship out of the planet's `Area2D` mid-menu.

### The meter: `BoostMeter`, a component beside the ship

**`open_space/scenes/entities/player/boost_meter.gd`** — `class_name BoostMeter extends Node`,
added as a child node in `player_ship.tscn`.

Not `global/components/`. The idea's last line is *"Boost should be exclusive to open-space
gameplay"*, and in this project mode isolation is structural, not a flag: `player_ship.tscn` is
instantiated by exactly one scene. A class under `global/` is visible to assault and infiltration
and invites exactly the leak the ask forbids. `ShipTurnController` in the sibling epic sets the
same precedent.

Be honest about how strong that is: `class_name BoostMeter` registers in the **global** script
class list whatever directory the file sits in, so an assault scene *could* add one. The directory
is a convention that signals intent, not an enforcement — which is why the idea's last bullet
(*"should not alter movement in other mission types"*) gets the two invariant cases in
`test_open_space_boost_wiring.gd` below rather than only a structural argument. This project gates
exactly this kind of silently-regressible claim (`test_module_unlock_sources.gd`,
`test_player_bullet_lifetime.gd`); an untested "it is structural" is how the boost ends up in
assault two epics from now.

**Rejected — reuse or extract `global/components/shield_component.gd`.** This is the closest prior
art in the project and `CLAUDE.md`'s "composition over inheritance" bar means it has to be rejected
explicitly rather than ignored: `Shield` already implements **four** of `BoostMeter`'s five
behaviours — discrete charges (`:20-22`), regeneration, `bind_progression` against
`ShipProgressionState` (`:38-46`) and a mid-session capacity grant (`:116-124`) — and this plan
copies its binding code near-verbatim on purpose, because that is the house pattern. It is still the
wrong thing to share. `Shield`'s charge is entangled with `consume_one()` on the incoming-damage
chain, with temporary (non-permanent) charges, with the hacked state, and with the snapshot
`Dictionary` that `ShieldIconStrip` consumes; a boost charge is spent by a *verb*, refills on a
timer, and has none of that. Generalising the two into one component would mean a damage-path
component growing a recharge-delay concept and a movement component inheriting a damage API — churn
in a file assault depends on, to save roughly 20 lines. **The duplication is the cheaper side of the
trade, and it is deliberate.** (If a third such meter ever appears, extract then — with two,
extracting is premature.)

```gdscript
class_name BoostMeter
extends Node

signal charges_changed(current: float, maximum: int)

@export var recharge_rate: float = 0.7          ## charges per second
@export var recharge_delay_sec: float = 0.5     ## pause after a spend
@export var bind_progression: bool = true       ## take max_charges from ShipProgressionState

var max_charges: int = 2
var charges: float = 2.0
var _delay_left: float = 0.0

func can_spend() -> bool                        ## charges >= 1.0
func try_spend() -> bool                        ## -1.0 and reset delay, or false
func step(delta: float) -> void                 ## delay countdown, then refill, clamped
```

Three shape decisions, each with a reason:

- **Continuous internal float, discrete spend, segmented render.** `2-research.md` implication 2:
  the shipped precedent (3 pips), this project's own upgrade precedent
  (`permanent_shield_count`, 1→5, drawn as icons) and finding 4's integer-stability argument all
  point at discrete charges; the idea says "meter" and the reference game uses a continuous gauge.
  A float that only ever spends whole units, drawn as pips, is the middle both readings accept, and
  it makes "+1 boost" legible in a way a longer bar is not.
- **`step(delta)` is called by the ship, not by the component's own `_physics_process`.** This
  differs from `Overheat`, deliberately. `set_physics_process(false)` on the ship does **not** stop
  a child's own `_physics_process`, so a self-ticking meter would keep charging while a mission
  menu is opening; and a tree-less `BoostMeter.new()` with a hand-driven `step()` is the
  `tests/README.md` house pattern for unit-testing a component.
- **A refill pause after every spend** (`2-research.md` finding 3, and `Overheat._SHOOT_GRACE = 0.5`
  is the identical mechanism 30 lines away, reused at the same value so the project has one such
  constant). Without it a mashed key trickle-charges between activations.

**No exhaustion state.** `2-research.md` finding 4 recommends a soft-failure "~10% recovery
threshold" instead of a hard refusal. Rejected for v1: this is a *traversal* verb the player needs
to cross the hub and reach every mission trigger, and a lockout on a traversal verb is where a
meter starts feeling punitive. An empty meter refuses the boost and W/S still fly the ship. If
play-testing says boosts are spammed at the edge of empty, the threshold is a two-line addition.

**No i-frames.** `2-research.md` findings 2 and 5, and implication 4: `EngineBoostModule`'s whole
value as an equippable is its 0.55 s of blanket immunity plus 45 contact damage. A free, always
available, metered boost with the same immunity makes the module pointless, which is the outcome
the idea's "keep boost open-space-only" line is trying to avoid. `PlayerBase.invincibility_sec =
0.5` still covers the post-hit case. This is the axis that differentiates the two abilities, and
it is stated here so nobody quietly adds it later.

### Persistence and the upgrade

`global/autoloads/ship_progression_state.gd` gains a **second key** on the existing `ConfigFile`,
mirroring the shield stat line for line:

```gdscript
const KEY_BOOST := "boost_charge_count"
const MIN_BOOST_CHARGES: int = 2
const MAX_BOOST_CHARGES: int = 5
signal boost_charge_count_changed(new_count: int)
func set_boost_charge_count(n: int) -> void     ## clamp, no-op if unchanged, save, emit
func add_boost_charge() -> bool                 ## false at cap
```

A second key rather than a new autoload: strictly less machinery, and `ConfigFile` tolerates a
missing key so an existing save loads at the default. `_save()` writes both keys; `_load()` reads
both and clamps each independently, with the existing out-of-range `push_warning`.

`BoostMeter._ready()` with `bind_progression = true` takes `max_charges` from the autoload and
stays subscribed to `boost_charge_count_changed`, copying `Shield._ready()` /
`Shield._on_progression_changed` (`shield_component.gd:38-46, :116-124`) — including **granting the
new charge immediately**, so a pickup collected mid-flight is usable now rather than next session.

⚠️ **`bind_progression = true` must be set on the `BoostMeter` node in `player_ship.tscn`, and the
scene diff must show it.** The `@export` default is not enough on its own to trust: the exact
failure this warns about is live in the project today. `player_ship.tscn:223-224` authors
`ShieldComponent` with **no** `bind_progression` line, so it falls back to
`shield_component.gd:20`'s `false` and the open-space ship never reads the permanent shield stat —
only `player_fighter.tscn:301` sets it. A boost meter that silently ignores the upgrade would make
steps 5 and 6 ship a pickup that does nothing visible, and no test outside
`test_open_space_boost_wiring.gd` would notice. **Follow `player_fighter.tscn:301`, not
`player_ship.tscn`'s `ShieldComponent`.**

**The upgrade axis is capacity (+1 charge).** `1-context.md` open question 4; capacity is the only
axis a player can see on the meter and the one the shield precedent supports. `2-research.md`
finding 3 notes the reference game upgrades *cooling* instead — that is the documented fallback if
capacity tests flat, and it is a change to one `@export` plus the pickup's `_collect()`.

**`global/pickups/ship_boost_up_pickup.gd`** + `scenes/ship_boost_up_pickup.tscn`: a
`PickupBase` subclass calling `ShipProgressionState.add_boost_charge()`, a copy of
`ShipShieldUpPickup` (9 lines, 3 nodes, `collision_layer = 16`, `collision_mask = 4`,
`CircleShape2D` radius 8 scaled 3.111). Placed on the hub's pickup bench at `y = -212`; the row
runs `x = 27, 104, 205, 304, 413, 519`, so **`x = 620`** is the next free slot.

Pickups live in `global/pickups/` — that is where all eleven of them are, and a pickup class is
inert unless a level places it, so this does not breach the exclusivity constraint the way a
`global/components/` meter would.

### The bar

**`open_space/scenes/gui/boost_bar.gd`** — `class_name BoostBar extends Node2D`, a sibling of
`OverheatBar` created in `OpenSpacePlayerShip._ready()` the same way (`top_level = true`,
repositioned every physics frame). `1-context.md` settles the placement question: the open-space
HUD (`hud.tscn`) has **no overheat element at all** — the overheat meter is a world-space bar under
the hull at `global_position + (0, 20)`. So *"near the existing weapon overheat meter"* means
**`global_position + (0, 26)`**, 2 px under the 4 px-tall overheat bar. Putting it in the HUD would
satisfy the words and break the intent.

Draw: `OverheatBar`'s 32×4 shape, split into `max_charges` segments with a 1 px gap, dark backing
throughout, filled segments in the thruster's cyan `Color(0.35, 0.9, 1.0)`; the partially-recharged
segment fills proportionally so the refill is visible rather than a pop. Always visible — it is a
persistent resource, and a boost meter you cannot see is precisely the failure the epic names.
Subscribes to `BoostMeter.charges_changed`; the segment count follows `maximum`, so an upgrade
collected mid-session widens the bar with no extra wiring.

**The handler stores what it draws.** `_on_charges_changed` assigns `_charges: float` and
`_max_charges: int` as members and then calls `queue_redraw()` — it must not compute geometry
inline in `_draw()` from a held `BoostMeter` reference. This is the same shape `OverheatBar` uses
(`overheat_bar.gd:7` keeps `_percentage` as a member) and it exists for a testability reason: a
`_draw()`-only `Node2D` exposes nothing a headless test can assert on, so the step-3 cases below
would be unwritable and would get dropped. `_max_charges` is what the segment-count case reads and
`_charges` is what the fill case reads.

### Input

`project.godot` `[input]` gains **`boost`**, bound to Shift (`physical_keycode 4194325`).

That makes **three** actions on Shift (`dash`, `race_brake`, `boost`), which is stated here
deliberately rather than discovered later. It is safe because the three consumers are separate
scenes that each read only their own action name: `dash` is infiltration's, `race_brake` is the
assault race sub-mode's, and `boost` is `OpenSpacePlayerShip`'s. Reusing `dash` would avoid the
third binding at the cost of coupling open-space movement to infiltration's action name, and would
make a future rebind of infiltration's dash silently move the open-space boost. Rejected.

### What is deleted

`_trigger_flip_boost()`, its `move_up`-just-pressed trigger (`player_ship.gd:129-132`), and the
`boost_redirect_speed` / `boost_speed_threshold` exports. Their behaviour is absorbed into the
Shift boost, which is the one reading of *"move the existing thrust/braking behavior into the boost
system"* that this plan implements — see the assumption below. `boost_duration_sec` survives,
renamed `boost_hold_sec`.

### Assumption on record: the loose reading of "move thrust/braking into the boost system"

The idea's line *"Move the existing thrust/braking behavior into the boost system"* has a strict
reading — W/S stop accelerating the ship and boost becomes the only propulsion — and a loose one —
momentum manipulation becomes the primary verb, with the existing hidden thrust special-case
folded into it. **This plan takes the loose reading**, and the user can overturn it at epic
approval.

Why: the strict reading makes the ship **unflyable on an empty meter** in a hub the player must
cross to reach every mission trigger, and it collides with `MissionTrigger`'s
`_MAX_APPROACH_SPEED = 150 px/s` docking gate (`mission_select_hub.gd:56`) — a propulsion system
whose only output is a 700 px/s burst cannot produce a sub-150 px/s approach without a second
low-power mode, which is just W under another name. It would also need a non-empty floor on the
meter or the player can strand themselves. That is a materially larger epic for a worse hub.

What is honoured from the strict reading: the invisible `move_up` flip-boost special case is
**removed from the thrust path entirely** and lives only in the boost system, and the epic's stated
goal — *"quick direction changes and momentum manipulation rather than requiring continuous
thrusting"* — is delivered by the redirect. W and S keep their current numbers unchanged.

### Numbers

All `@export` on `OpenSpacePlayerShip` or `BoostMeter`, so the fly-test is an inspector change.
Provenance per `2-research.md`'s starting-numbers table; the two marked **revised** are changed
from it, with the arithmetic that forced the change.

| Parameter | Value | Where it comes from |
|---|---|---|
| `boost_exit_speed` | **700.0** px/s | **Revised** from research's 600. Must exceed `max_speed = 420` (finding 1's tradeoff). 600 is only 1.43× cruise. Excess travel over simply cruising, by the same method for both: hold window at full excess, plus the decay ramp at half its excess. 700 → `0.35 x (700-420) + 0.70 x 140 = 98 + 98 =` **196 px**. 600 → `0.35 x 180 + 0.45 x 90 = 63 + 41 =` **~104 px**, i.e. 700 buys ~1.9x the extra travel for 1.17x the peak speed, and 104 px is barely over one hull-length of separation from a cruising ship. Still 0.47× `EngineBoostModule`'s 1500 and 0.42× its 467 px of travel, so the module stays the heavier ability. |
| `boost_hold_sec` | **0.35** s | Research's 0.25–0.35 window; today's `boost_duration_sec = 0.3` sits in it. Doubles as the flame window and the retrigger floor. |
| `boost_ceiling_decay` | **400.0** px/s² | **Revised** (new parameter). 700 → 420 in 0.70 s, so the whole above-cruise signature is ~1.05 s. |
| `BoostMeter.recharge_rate` | **0.7** charges/s | Finding 1's Standard-difficulty value, adopted directly. One boost per ~1.43 s. |
| `BoostMeter.recharge_delay_sec` | **0.5** s | Finding 4's regen pause, at the value `Overheat._SHOOT_GRACE` already uses. |
| `MIN_BOOST_CHARGES` | **2** | Finding 1 ships 3 for a game with far more movement verbs; 2 leaves upgrade room and makes the first pickup feel large. |
| `MAX_BOOST_CHARGES` | **5** | Mirrors `MAX_SHIELDS = 5` exactly, so the two upgrade tracks read as one system. |
| Core-boost i-frames | **none** | Findings 2 and 5; the differentiation argument above. |

Empty-to-full at base capacity: 0.5 + 2/0.7 ≈ **3.4 s**. At cap: 0.5 + 5/0.7 ≈ **7.6 s**.

### Sequencing against the mouse-aiming epic

`open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr` is `status: active` with an approved
plan and **six `todo` implementation tasks**, all in `player_ship.gd` / `player_ship.tscn`. This
epic is still `draft` and needs user approval, so **mouse-aiming lands first by construction**.
Both epics add a child node to `player_ship.tscn` and an `@export` block to `player_ship.gd`; the
functions are independent (`_handle_rotation` vs `_handle_thrust`) so the conflict is textual, but
that scene is where a real merge problem would appear. Two consequences, carried into every task
body below:

- **Do not implement a task from this epic in the same window as a mouse-aiming task.**
- The first task here **re-reads `player_ship.gd` and `player_ship.tscn` from HEAD before editing**.
  In particular, mouse-aiming deletes `player_ship.gd:46`'s `rotation = 0.0`; boost reads
  `rotation` for its facing, so that deletion is fine but the line numbers in this plan will have
  moved.

---

## Build sequence

Each step is independently testable, verifiable with `bash /agent/verify.sh`, and sized to one
session.

1. **The verb.** `boost` input action; `_step_boost()` seam in `player_ship.gd` owning the trigger,
   the decaying ceiling and the single speed clamp; unconditional redirect at `boost_exit_speed`;
   `flame_boost` animation + `ThrusterEffect.State.BOOST` on both engines for `boost_hold_sec`;
   deletion of `_trigger_flip_boost()` and its `move_up` trigger. **No meter yet** — the boost is
   limited only by the `boost_hold_sec` retrigger floor, so at worst an interrupted epic leaves a
   0.35 s-cooldown boost on a dev branch, not an unbounded one. Step 2 replaces that floor.
2. **The cost.** `BoostMeter` component, added to `player_ship.tscn`, ticked from `_step_boost()`,
   gating the trigger. Includes the anti-inert wiring test.
3. **The readout.** `BoostBar`, created in `_ready()` alongside `OverheatBar` at `(0, 26)`.
4. **The persistence.** `ShipProgressionState.boost_charge_count` and `BoostMeter`'s binding to it,
   including the mid-session grant.
5. **The source.** `ShipBoostUpPickup` + hub placement + the placement invariant test.
6. **The art.** A dedicated top-down pickup sprite, replacing the reused module icon.

---

## Test plan

Everything below asserts **intent**, not characterization — this is new code. Tree-less component
instances are `free()`d in `after_each`, and `scripts/check-test-leaks.sh` is run after any step
that awaits.

#### Autoload discipline — mandatory, and `SaveSandbox` alone is **not** enough

`tests/helpers/save_sandbox.gd` backs up and rewrites a list of `user://*.cfg` **files**
(`:16-24`, `:29-47`). It does **nothing** to the in-memory singleton. `ShipProgressionState`
mutates `_permanent_shield_count` / `_boost_charge_count` in memory and never re-reads the file,
so a test that collects a pickup leaves the **live autoload** raised for the rest of the GUT
process — and GUT walks `res://tests` with `-ginclude_subdirs`, so `integration/` runs before
`unit/`. The concrete failure that costs a window: `test_boost_upgrade_source.gd` pushes the live
count to 3 (or to `MAX_BOOST_CHARGES`), and `test_boost_meter.gd`'s bound case then reads
`max_charges == 3` where it asserts `MIN_BOOST_CHARGES == 2`. It fails **only in a full-suite
run**, which is the most expensive failure mode this suite has.

So every file below that touches the autoload uses the **two-layer** pattern
`test_weapon_unlock_sources.gd:40-53` established — `SaveSandbox` for the file, *plus* an explicit
snapshot of the live singleton's members:

```gdscript
var _sandbox := SaveSandbox.new()
var _saved_boost: int = 0
var _saved_shields: int = 0

func before_all() -> void:
    _sandbox.capture()
    _saved_boost = ShipProgressionState.boost_charge_count
    _saved_shields = ShipProgressionState.permanent_shield_count   ## the two share one ConfigFile

func after_all() -> void:
    ShipProgressionState._boost_charge_count = _saved_boost
    ShipProgressionState._permanent_shield_count = _saved_shields
    _sandbox.restore()

func before_each() -> void:
    ## Assigned to the backing fields directly, not via add_boost_charge(), so the fixture does
    ## not depend on the code under test and writes nothing to disk. Same reasoning as
    ## test_weapon_unlock_sources.gd:50-53.
    ShipProgressionState._boost_charge_count = ShipProgressionState.MIN_BOOST_CHARGES
    ShipProgressionState._permanent_shield_count = 1
```

**Which files need it, and when.** `test_boost_upgrade_source.gd` (step 5) and
`test_ship_progression_state.gd` (step 4) obviously do. Less obviously, **so do
`test_open_space_boost_wiring.gd` (step 2) and `test_boost_bar.gd` (step 3)**: both instantiate
`player_ship.tscn`, and from step 4 onwards that scene carries a `BoostMeter` with
`bind_progression = true`, whose `_ready()` reads the live autoload. Those two files are **written
in steps 2 and 3, before the binding exists**, so the discipline will not be obvious to whoever
writes them — it is therefore written into their task bodies now rather than retrofitted after step
4 breaks them. Add the block above to all four files from the start; it is inert until step 4 and
correct afterwards.

**Ship instances go in the tree.** Any case that calls `ship._handle_thrust(delta)` (rather than
`ship._step_boost()` alone) must `add_child_autofree(ship)` first: `_handle_thrust` reaches
`_thruster.set_state(...)` at `player_ship.gd:144-153`, and `_thruster` is built by
`_setup_effects()` from `_ready()` (`:64-83`), so on an un-parented instance it is `null` and the
call is a hard error. Adding the ship to the tree also runs `PlayerBase._setup_components()` →
`SessionState.apply_to(self)` and the `ShipModuleState` hookups (`:56-62`) — which is a second,
independent reason the autoload discipline above applies to these files.

### `tests/integration/test_open_space_boost_verb.gd` — step 1

Instantiates `player_ship.tscn`, `add_child_autofree(ship)`, `set_physics_process(false)`, then
drives `_step_boost()` by hand. Note that `Input.is_action_pressed()` returns `false` headless, so
`_handle_thrust(delta)` is callable in a test and behaves as "no keys held" — but only on a ship
that is in the tree (see "Ship instances go in the tree" above).

| Case | Assertion |
|---|---|
| Boost from rest | `rotation = 0`, `velocity = ZERO`; one `_step_boost(true, d)` → `velocity ≈ UP * boost_exit_speed`. |
| **The headline case** — flying backwards | `velocity = DOWN * 420`, `rotation = 0`; one `_step_boost(true, d)` → `velocity ≈ UP * 700` in a single frame. |
| **Boundary: boost while already at cruise must not brake** | `velocity = UP * 420`; after the boost `velocity.length() > max_speed`. Fails on today's `boost_redirect_speed = 200`. |
| Facing, not velocity, sets direction | `rotation = PI`, `velocity = UP * 300`; boost → `velocity ≈ DOWN * 700`. |
| **Boundary: zero velocity** | `velocity = ZERO` → result is finite and equals `UP * 700`, i.e. the hull `rotation` is used and `Vector2.ZERO.angle()`'s `0.0` singularity is never consulted. |
| The ceiling permits, then closes | After a boost, step with `boost_pressed = false`: at `t = boost_hold_sec / 2` the ship may exceed `max_speed`; at `t = boost_hold_sec + 700/boost_ceiling_decay + 0.1` `velocity.length() <= max_speed + 0.5`. |
| The ceiling never drops below cruise | After the window has fully closed, `_speed_ceiling == max_speed` exactly. |
| Retrigger floor | A second `_step_boost(true, d)` inside `boost_hold_sec` leaves `velocity` on its existing decay curve (no re-slam to 700). |
| **A module boost wins** | `engine_boost_active = true`; `_step_boost(true, d)` leaves `velocity` unchanged. This is the case the doubled guard exists for — it calls `_step_boost()` directly and so bypasses `_handle_thrust()`'s early return. **If it fails, add the guard; do not weaken the case.** |
| **Regression: the hidden flip-boost is gone** | `ship.has_method("_trigger_flip_boost")` is false and `"boost_speed_threshold" not in ship`. Fails on today's build. |

### `tests/unit/test_boost_meter.gd` — steps 2 and 4

Tree-less `BoostMeter.new()` with `bind_progression = false`, `free()`d in `after_each`.

| Case | Assertion |
|---|---|
| Starts full | `charges == float(max_charges)`. |
| A spend costs exactly one | `try_spend()` → true, `charges` down by exactly 1.0. |
| **Boundary: a partial charge refuses** | `charges = 0.99`; `try_spend()` → false and `charges` unchanged. Pins "refuse", not "fire weakly" (`1-context.md` edge case 2). |
| Empty refuses | `charges = 0.0`; `try_spend()` → false, nothing spent, no signal. |
| No refill during the pause | Spend, then `step()` for `recharge_delay_sec - 0.01` → `charges` unchanged. |
| Refills at the stated rate | Then `step()` for 1.0 s → `charges` up by `recharge_rate ± 0.01`. |
| **Boundary: refill clamps at max** | `step()` for 60 s → `charges == float(max_charges)`, never above. |
| A second spend restarts the pause | Spend, `step(0.4)`, spend, `step(0.4)` → still no refill. |
| `step(0.0)` is a no-op | No state change, no signal. |
| Signal arity | `charges_changed` is emitted with `(float, int)` on spend and on a refill tick, matching the declaration (`test_signal_emit_arity.gd` sweeps this too). |
| **Step 4 — the mid-session upgrade** | `bind_progression = true`, under the full two-layer autoload discipline above (`before_each` pins the live count to `MIN_BOOST_CHARGES`): `max_charges` starts at `MIN_BOOST_CHARGES`; emitting `boost_charge_count_changed(3)` raises `max_charges` to 3 **and** grants the extra charge immediately. |

### `tests/integration/test_open_space_boost_wiring.gd` — step 2, the anti-inert test

The hole the sibling epic's review caught: everything implemented, nothing connected. Every case
here passes on a build where `BoostMeter` exists but is not in the scene — except these.

| Case | Assertion |
|---|---|
| The meter is in the scene | The instantiated `player_ship.tscn` has exactly one `BoostMeter` child, found **by class, not by node path**, so a rename does not silently pass. |
| Boosting spends from *that* meter | `_step_boost(true, d)` → that node's `charges` down by exactly 1.0. |
| **An empty meter refuses, and costs nothing** | `charges = 0.0`; `_step_boost(true, d)` → `velocity` unchanged, `charges` still 0.0. |
| **Boundary: a boost refused by a module burns no charge** | `engine_boost_active = true`, full meter; `_step_boost(true, d)` → `charges` unchanged. Same note as the verb file's precedence case: this passes on `_step_boost()`'s own `if engine_boost_active: return` and on nothing else. |
| The ship drives the meter | The meter does not tick itself: after a spend, repeated `ship._handle_thrust(d)` calls (on a ship **in the tree**) restore the charge over `recharge_delay_sec + 1/recharge_rate`. |
| **Invariant: the boost is open-space only** | `assault/scenes/player/player_fighter.tscn` and the infiltration player scene, walked by class, contain **no** `BoostMeter` and no `BoostBar`. |
| **Invariant: nothing outside `open_space/` reads the `boost` action** | A directory sweep of `.gd` files outside `open_space/` and `tests/` finds no `"boost"` action string passed to an `Input.is_action_*` call. |

### `tests/integration/test_boost_bar.gd` — step 3

| Case | Assertion |
|---|---|
| The bar is in the scene | The instantiated ship has a `BoostBar` child with `top_level == true`. |
| It is visible at full | `visible == true` with a full meter — a resource readout that hides itself is the failure mode. |
| **Boundary: it does not overlap the overheat bar** | Ship added to the tree, one physics frame awaited: `abs(boost_bar.global_position.y - overheat_bar.global_position.y) >= OverheatBar.BAR_HEIGHT`. |
| Segments follow capacity | Emitting `charges_changed(2.0, 4)` leaves `bar._max_charges == 4` — the member the `_draw()` segment loop reads (see "The handler stores what it draws"). A `_draw()`-only bar would make this case unwritable. |
| **The fill tracks `current`, not just capacity** | `charges_changed(2.0, 4)` then `charges_changed(3.5, 4)` → `bar._charges` is `3.5`, so a partially-recharged segment is representable and the refill animates rather than popping. |
| **Boundary: capacity 0 does not divide by zero** | `charges_changed(0.0, 0)` — defensive only; the meter never emits it, but `_draw()`'s segment width is `BAR_WIDTH / max_charges`. Asserts no error is logged. |

### `tests/unit/test_ship_progression_state.gd` — step 4 (extends the existing file)

| Case | Assertion |
|---|---|
| Default | `boost_charge_count == MIN_BOOST_CHARGES`. |
| Add | `add_boost_charge()` → true, count +1, `boost_charge_count_changed` emitted once. |
| **Boundary: the cap** | At `MAX_BOOST_CHARGES`, `add_boost_charge()` → false, count unchanged, **no signal**. |
| **Boundary: a corrupt save clamps** | Write `boost_charge_count = 99` into the sandboxed cfg, reload → clamped to `MAX_BOOST_CHARGES`. |
| **Boundary: the two keys are independent** | Adding a boost charge and reloading leaves `permanent_shield_count` at its stored value — the two stats share one `ConfigFile`. |

### `tests/integration/test_boost_upgrade_source.gd` — step 5, the placement invariant

Same family as `test_module_unlock_sources.gd` / `test_weapon_unlock_sources.gd`.

| Case | Assertion |
|---|---|
| A source exists in the world | `sector_hub.tscn` contains at least one `ShipBoostUpPickup`, found by class over a full node walk. |
| **It actually does something** | A real instance is collected against the **live** autoload — snapshotted in `before_all` and restored in `after_all` per the discipline above, because `_collect()` calls the singleton and a fresh script instance would prove nothing — and `boost_charge_count` goes up by 1. Every placement test passes on a pickup whose `_collect()` is empty; this is the case that does not. |
| **Boundary: collecting at the cap** | At `MAX_BOOST_CHARGES`, collecting leaves the count at the cap and logs no error. The cap is reached by assigning `_boost_charge_count` directly, not by collecting five pickups — the fixture must not depend on the code under test. |

### What the gate cannot tell us

Nothing headless can say whether 700 px/s over 1.05 s *feels* like Jet Lancer, whether 2 charges is
mean or generous, or whether a boost aimed at a planet makes docking annoying. Every number is an
`@export`. A human has to fly the hub — that is called out in each task body.

---

## Risks

1. **Docking gets harder right after a boost.** `MissionTrigger` only starts its dwell while the
   player is under `_MAX_APPROACH_SPEED = 150 px/s` (`mission_select_hub.gd:97`), and it already
   draws the "too fast" tell by hiding the progress arc. A boost aimed at a planet is a guaranteed
   missed approach for ~1 s longer than today. **Accepted, unmitigated in v1** — the existing
   coast still brings the ship under 150 px/s, the tell already exists, and the alternative
   (auto-braking near a trigger) is a bigger behaviour change than the epic asks for. Flagged as
   the first thing to watch in the fly-test.
2. **`boost_exit_speed = 700` may read as too weak or too strong.** The only mitigation is that it
   is an `@export`, along with the hold window and the decay rate. The arithmetic in the numbers
   table is the reasoning; it is not a play-test.
3. **The camera tops out below the boost.** `_SPEED_THRESHOLD = 400.0` drives zoom-out and lead, so
   everything from 400 to 700 px/s looks identical. Out of scope here (it is a camera change that
   would also affect non-boost flight), but it means the boost's *visual* punch rests entirely on
   the cyan flame. If the fly-test says the burst does not read, raising `_SPEED_THRESHOLD` is the
   first thing to try.
4. **Textual merge pressure on `player_ship.gd` / `player_ship.tscn`** from the mouse-aiming epic.
   Handled by the sequencing rule above.
5. **Three actions on the Shift key.** Deliberate and argued above, but it reads as a bug to a
   future reader; the `boost` action's purpose is recorded in this plan and in the open-space
   module doc.
6. **Art budget.** Step 6 spends the capped monthly PixelLab allowance and cannot be undone. Step 5
   therefore ships with the existing `icon_ship_module_engine_boost.png` (40×30) so the feature is
   complete and playable without it, and step 6 is separable and droppable.

---

## Out of scope

- **Any change to `global/ship_modules/engine_boost_module.gd` or to assault.** `EngineBoostModule`
  keeps its H key, its 1500 px/s, its blanket i-frames and its 45 contact damage. It stays a
  distinct, heavier, equippable ability, differentiated on **immunity + damage** (which it has and
  the core boost does not) rather than on visuals, which both share.
- **`PlayerBase`.** No new field. `engine_boost_active` is read, never written.
- **The `damping` rewrite** to frame-rate-independent form. Real (2.3%/s of drift) but it belongs
  to whoever rewrites velocity handling; changing it here would confound this epic's tuning.
- **Boost i-frames, boost contact damage, boost-through-asteroids.** See the differentiation
  argument.
- **An exhaustion / soft-failure state** on the meter. Deferred with a stated reason.
- **Boost in assault or infiltration**, and any HUD (`hud.tscn`) change — the bar is world-space.
- **Camera tuning** (`_SPEED_THRESHOLD`), and any sound. There is no audio system in play here.
- **Upgrading refill rate or burst strength.** Capacity only; the alternative is recorded as the
  fallback if capacity tests flat.

---

## The task list

Created with `backlog-cli.js add-task`; this is the mapping the plan review should check against
the build sequence above.

| # | Task id | Type | Cx | Model | Depends on |
|---|---|---|---|---|---|
| 1 | `shift-slams-your-ship-onto-its-new-heading-and-launches-it` | feature | medium | opus | — |
| 2 | `boosting-costs-a-charge-and-charges-come-back-on-their-own` | feature | medium | opus | 1 |
| 3 | `a-cyan-pip-bar-under-your-ship-shows-how-many-boosts-you-hav` | feature | small | sonnet | 2 |
| 4 | `extra-boost-charges-you-earn-stay-with-your-ship-between-run` | feature | small | sonnet | 2 |
| 5 | `a-pickup-in-the-hub-permanently-adds-a-boost-charge` | feature | small | sonnet | 4 |
| 6 | `the-boost-up-pickup-has-its-own-sprite-instead-of-a-borrowed` | art | small | sonnet | 5 |

Notes on the shape of that list:

- **1 and 2 are `medium`/`opus`** because each is a movement-model change plus a new testable seam
  in the file two epics are editing. Neither is `large`: both work inside one function and one new
  ~70-line component, and both have a written design here rather than a design to invent.
- **3, 4 and 5 are genuinely `small`** — a `_draw()` node, a second key on an existing autoload
  copied line for line from the shield stat, and a 9-line pickup copied from `ShipShieldUpPickup`.
  None invents anything.
- **3 and 4 both depend on 2 but not on each other**, and they touch different files (`player_ship.gd`
  + a new GUI script vs the autoload + `boost_meter.gd`). Either order works.
- **6 depends on 5** and is explicitly droppable: it spends the irreversible PixelLab allowance,
  and 5 ships a complete, playable pickup with a reused texture.
- **Nothing here depends on the mouse-aiming epic in the backlog graph** — that dependency is a
  *scheduling* constraint (do not work both in one window), recorded in each task body, not an
  `--depends-on` edge. Encoding it as one would stall this epic behind six unrelated tasks.

---

## Response to review round 1

`4-review.md` returned **CHANGES_REQUESTED** with two blocking findings and eight advisories. Both
blocking findings were in the test plan, not the design; no design decision changed. Every claim
was re-verified against the code before editing — `save_sandbox.gd:16-47` really is files-only,
`test_weapon_unlock_sources.gd:40-53` really does snapshot the live singleton on top of it,
`player_ship.gd:118-119` really holds the only `engine_boost_active` guard on this path, and
`player_ship.gd:134-153` really does make thrust and damping mutually exclusive branches.

| Finding | Change |
|---|---|
| **B1** — "sandboxed autoload" is not a thing; `SaveSandbox` covers files only, so the step-5 pickup test poisons the live `ShipProgressionState` and breaks step 4's meter test in a full-suite run | New **"Autoload discipline"** block in the test plan with the explicit two-layer `before_all`/`after_all`/`before_each` pattern and the reason it is needed; the two offending cases reworded; **and the requirement pushed into the step 2 and step 3 task bodies now**, since those files are written before the binding that makes them vulnerable exists |
| **B2** — two test cases drive `_step_boost()` directly and expect it to honour `engine_boost_active`, which as specified it never reads | `_step_boost()` now opens with `if engine_boost_active: return`; new **"the precedence guard is deliberately doubled"** paragraph explains why the redundancy is required rather than sloppy; both cases annotated **"if it fails, add the guard, do not weaken the case"**; task 1's "Do NOT" line reworded to forbid *writing* the flag, not reading it |
| **A1** — "damping removes 420 while W adds 380" treats exclusive branches as simultaneous forces | Design property 2 rewritten from the actual branch structure. Conclusion unchanged, reasoning fixed, with an explicit warning not to reason from a force balance |
| **A2** — the "~54 px" figure does not reproduce | Corrected to **~104 px**, with both computations shown by the same method so a tuner can check them. 700 still wins |
| **A3** — nothing tests the idea's "must not alter other mission types" bullet | Two invariant cases added to `test_open_space_boost_wiring.gd` (no `BoostMeter`/`BoostBar` in the assault or infiltration player scenes; no `boost` action read outside `open_space/`), plus an honest note that `class_name` is global regardless of directory |
| **A4** — `BoostBar`'s segment case has no observable | `BoostBar` now specified to store `_charges` / `_max_charges` as members (the `OverheatBar` shape), the case rewritten to read them, and a fill case and a divide-by-zero boundary added |
| **A5** — `Shield` is closer prior art than the plan admits and is never rejected in writing | Explicit rejection paragraph added: what `Shield` already does, why sharing it is churn in a file assault depends on, and that the ~20 lines of duplication are the cheaper side of the trade |
| **A6** — the meter silently freezes during a module boost | Documented in design property 3, including the instruction not to "fix" it by hoisting `step()` above the early return |
| **A7** — the wiring test's `_handle_thrust` case needs the ship in the tree | **"Ship instances go in the tree"** added to the test-plan preamble, with the `_thruster`-is-null mechanism and the note that parenting also runs `SessionState.apply_to()` |
| **A8** — pre-existing: `player_ship.tscn:223` authors `ShieldComponent` with no `bind_progression`, so the hub's shield-up pickup raises a number the open-space ship never reads | Not this epic's to fix. **Filed separately** on `code-health-backlog`. The two places this plan leaned on shields as working precedent are corrected below |

**Correction carried into the plan body:** the persistence sections claim boost capacity will
persist *"exactly like the permanent shield count already does"*. The **stat** does persist; the
open-space **ship** does not currently consume it. This plan's step 4 sets
`bind_progression = true` on the `BoostMeter` node explicitly, so the boost track does not inherit
that omission — the precedent being followed is `player_fighter.tscn:301`, the one scene that gets
it right, not `player_ship.tscn`'s `ShieldComponent`.
