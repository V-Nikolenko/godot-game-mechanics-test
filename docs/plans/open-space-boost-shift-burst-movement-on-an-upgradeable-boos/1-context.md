# Context — Open-space boost: Shift burst movement on an upgradeable boost meter

Epic: `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`
Stage: **RESEARCH**, 2026-09-14, against `agent/auto-dev` @ `28a53e8`.
Companion to [`2-research.md`](./2-research.md), which covers how shipped games solve the same
problem. This file covers only **what is already in this codebase**, read first-hand.

> **Headline for the plan stage.** Roughly 70% of this feature already exists, in two places that
> do not know about each other, and one of them is **shared with the assault mode the idea
> forbids touching**. The plan's central job is not to write a boost — it is to decide the
> ownership split between `OpenSpacePlayerShip._handle_thrust()` and `EngineBoostModule`, and to
> add the one genuinely new thing: a persisted, upgradeable meter.

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `open_space/scenes/entities/player/player_ship.gd` | `OpenSpacePlayerShip extends PlayerBase`. Owns open-space movement: `_handle_rotation`, `_handle_thrust`, camera feel, module pool. | **The file the feature lands in.** Already holds the momentum model *and* a prototype flip-boost. |
| `open_space/scenes/entities/player/player_ship.tscn` | The ship scene. `HealthComponent`, `ShieldComponent`, `OverheatComponent`, `TempHealthComponent`, `HurtBox`, `AttackStateMachine`, `MovementController`, `SpriteAnchor/ShipSprite2D` (`idle` / `flame_boost` / `planet_dive`), `EngineLeft`/`EngineRight` markers. | Where a `BoostMeter` node and its `@export` tuning would be authored; `flame_boost` is the animation the idea asks to reuse. |
| `global/entities/player_base.gd` | Shared player base: components, damage chain, `damage_reduction`, `engine_boost_active`, `apply_knockback*`. | `engine_boost_active` is the existing "a module owns velocity this frame" flag, and it is **declared here, i.e. shared with assault**. |
| `global/ship_modules/engine_boost_module.gd` | `EngineBoostModule` — the equippable engines-slot ability. H key, 1500→500 px/s ease-out over 0.55 s, full i-frames, 45 contact damage, 2 s cooldown, forces both thrusters to `BOOST` and plays `flame_boost`. | **The open question.** It is already a facing-direction burst with the exact visual the idea asks for. |
| `assault/scenes/player/player_fighter.gd` | `AssaultPlayer`. Applies, ticks and `try_activate`s the *same* module pool. `_physics_process` honours `engine_boost_active` by running `move_and_slide()` itself and returning early. | Proof that `EngineBoostModule` is **live in assault**. Any edit to it is an assault edit. |
| `assault/scenes/player/states/move_state.gd:39`, `states/dash_state.gd:126` | Both yield while `actor.engine_boost_active`. | Three more assault call sites of the same flag. |
| `global/autoloads/ship_progression_state.gd` | Persists `permanent_shield_count` (1–5) to `user://ship_progression.cfg`; clamps, saves, emits `permanent_shield_count_changed`. | **The precedent for the meter's upgrade axis**, and the file a boost stat most plausibly joins. |
| `global/pickups/ship_shield_up_pickup.gd` + `scenes/ship_shield_up_pickup.tscn` | 12-line `PickupBase` subclass calling `ShipProgressionState.add_permanent_shield()`; `Area2D` layer 16 / mask 4, an 8 px circle scaled 3.111, one `Sprite2D`. | **The precedent for the collectible**, and the template a `ShipBoostUpPickup` copies almost verbatim. |
| `open_space/scenes/levels/sector_hub.tscn` | The hub. Pickup bench at `y = -212` (`ShipShieldUpPickup` at `x = 413`), module unlockers at `y = -315` / `-415`, weapon unlockers at `y = -515`. | Where the boost-up pickup gets placed, and what an unlock-source invariant test would read. |
| `assault/scenes/player/overheat_bar.gd` | `OverheatBar extends Node2D` — a 32×4 `_draw()` bar, `visible = percentage > 0.0`, colour lerps orange→red. | **The bar the idea says to sit next to.** In open space it is `top_level`, repositioned to `global_position + (0, 20)` every physics frame (`player_ship.gd:90-91`). |
| `open_space/scenes/gui/hud.tscn` + `global/ui/mission_hud.gd` | The open-space HUD: health/shield bar, shield strip, weapon chip/frame, player menu, pause menu. **No overheat element at all.** | Settles the "where does the bar go" question below: in open space the overheat meter is *not* in the HUD. |
| `global/components/overheat_component.gd` | `Overheat extends Node`: `heat` accumulates to `heat_limit`, dissipates at `heat_limit / cooldown_time` but only after a `_SHOOT_GRACE = 0.5 s` no-use window; emits `overheat(percentage)`. | **The closest existing shape to a boost meter** — a depleting/regenerating float resource with a post-use regen delay. Worth reading before inventing one. |
| `global/components/thruster_effect.gd` | `ThrusterEffect.State.{IDLE, THRUST, BOOST, POWER, BOOST_PANEL}`. `BOOST` = 24 particles, 0.42 s life, 100–190 px/s, cyan `(0.35,0.9,1.0)` → blue `(0,0.4,1)`. | The "blue/cyan afterburner" the idea names. Already wired to both engines and already driven from `_handle_thrust()`. |
| `project.godot` `[input]` | `dash` = Shift (`physical_keycode 4194325`), `race_brake` = **the same Shift key**, `use_ability` = H. | Shift is already bound twice. A third binding is possible but the plan must say which action open space reads. |
| `docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/` | The sibling epic: `status: review`, plan **APPROVED**, six implementation tasks all `todo`. Rewrites `_handle_rotation` into a `ShipTurnController` node. | The other epic editing this same `_physics_process`. Its plan already names this one as a collision risk (lines 193, 592, 621). |

---

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `player_ship.gd:158-160` `_trigger_flip_boost()` | **A working prototype of the 180°-redirect half of the ask**, already shipped: `velocity = forward * boost_redirect_speed`. Total momentum kill and re-aim in one assignment. |
| `player_ship.gd:129-132` | The trigger condition: `move_up` *just pressed* while `-velocity.dot(forward) >= boost_speed_threshold (180)`. The "am I flying backwards fast enough for this to be a flip" test, already written. |
| `player_base.gd:45` `engine_boost_active` | The established protocol for "something else owns `velocity` this frame — skip damping and the `max_speed` cap". Four honouring call sites. A core boost needs the same escape hatch, or the `max_speed` clamp eats it. |
| `engine_boost_module.gd:79-85` | A frame-by-frame ease-out that re-asserts a **locked direction vector** every tick so the burst stays perfectly straight: `speed = lerpf(END, START, progress²)`. Directly reusable as the burst curve. |
| `engine_boost_module.gd:52-54` | i-frames done by stashing and restoring `damage_reduction`, rather than by a second invincibility system. |
| `overheat_component.gd` | Capacity + drain + **delayed** regen + a `0–100` percentage signal, in 30 lines. The meter's whole shape, minus persistence. |
| `ship_progression_state.gd` | `MIN`/`MAX` constants, a clamping setter that is a no-op when unchanged, `add_*()` returning `false` at the cap, `ConfigFile` save/load with a clamp-on-corrupt path, and one `*_changed` signal. Copy the shape exactly. |
| `shield_component.gd:38-41` | How a component binds itself to `ShipProgressionState` at `_ready()` **and** stays subscribed to the change signal — the pattern a `BoostMeter` uses to pick up a mid-session upgrade. |
| `overheat_bar.gd` | A complete world-space meter: `BAR_WIDTH 32`, `BAR_HEIGHT 4`, `_draw()` with a dark backing rect and a colour-lerped fill. A boost bar is this file with a different signal and palette. |
| `ship_shield_up_pickup.gd` / `.tscn` | The whole collectible: 12 lines of script plus a 5-node scene. |
| `pickup_base.gd` | `body_entered` → group check → `_collect(player)` → optional `DialogPlayer` notification → `queue_free`. Optional `persistent_id` for one-time pickups. |
| `tests/helpers/save_sandbox.gd` | Mandatory for any test of a `user://`-persisting autoload. |

---

## Verified in-engine (Godot 4.6.3 headless, this container)

Simulated with the shipped constants (`thrust_acceleration 380`, `max_speed 420`, `damping 0.6`,
`rotation_speed_deg 220`) at a 60 Hz step:

```
coast 420 -> 10 px/s                     : 6.20 s
speed 1.0 s after releasing thrust @60Hz : 229.8 px/s (55% retained)
   ... the same run @30Hz                : 224.5 px/s   (2.3% frame-rate drift)
accelerate 0 -> max_speed 420            : 1.12 s
thrust-only reversal -420 -> +420        : 2.22 s
180 deg turn @220 deg/s                  : 0.82 s
EngineBoostModule distance over 0.55 s   : 467 px
```

Four things the plan should take from this:

1. **The ship already coasts like the idea wants.** `damping = 0.6` is a ~1.16 s half-life; the
   hull keeps 55% of its speed a full second after the key is released and takes 6.2 s to stop.
   The momentum model is not the missing piece.
2. **A full reversal costs ~3.0 s today** (0.82 s to turn + 2.22 s to thrust through zero). That
   is the number the flip-boost is meant to collapse, and the honest measure of the feature's
   value.
3. **`EngineBoostModule` is enormous** — 467 px is more than a third of the 1280 px viewport, in
   half a second. Whatever a metered Shift boost does, it should not silently be *this*.
4. **The existing damping is mildly frame-rate dependent** (`velocity.lerp(Vector2.ZERO,
   damping * delta)` is a first-order Euler step, not `1 - exp(-λ·dt)`). 2.3% over one second is
   not a bug anyone will notice, but if the plan rewrites velocity handling anyway, the correct
   form is free — see `2-research.md`, and the sibling epic's finding 3.

---

## What the "prototype" actually does (read this before designing around it)

The idea's triage summary calls `_trigger_flip_boost()` a "boost". It is not a speed burst:

```gdscript
@export var boost_redirect_speed: float = 200.0   # < max_speed (420)
func _trigger_flip_boost(forward: Vector2) -> void:
	velocity = forward * boost_redirect_speed
	_boost_timer = boost_duration_sec               # 0.3 s, cosmetic only
```

- It **reduces** speed — from ≥180 px/s backwards to 200 px/s forwards, against a 420 cap.
- `_boost_timer` does nothing but hold the thrusters in `ThrusterEffect.State.BOOST` for 0.3 s
  and re-gate the next trigger. It applies no force.
- It fires on **`move_up`**, not Shift — it is a hidden special case of the thrust key, invisible
  to a player who does not already know it exists, and there is no HUD, sound or meter for it.
- It is **unconditionally free**: no cost, no cooldown beyond its own 0.3 s window.

So the honest framing for the plan: the *momentum-redirect* half of the ask is implemented and
under-sold; the *burst of speed*, the *cost*, the *input*, the *meter* and the *upgrade* are all
absent. Promoting the redirect into a visible, metered, Shift-driven verb is the feature.

---

## The `EngineBoostModule` question, settled on one point

The triage summary asks whether the module is "superseded, re-cast as a meter upgrade, or kept as
a distinct heavier ability". One constraint removes a whole branch:

**`EngineBoostModule` is not open-space-only.** `AssaultPlayer` builds the same `_module_pool`
(`player_fighter.gd:29-35`), offers it the same H key (`:108-118`), ticks it every frame
(`:92-93`), and handles `engine_boost_active` in its own `_physics_process` (`:95-101`) and in
`move_state.gd:39` and `dash_state.gd:126`. The module's 45 contact damage is dealt against
`get_tree().get_nodes_in_group("enemies")`, which is populated in assault.

The idea's last line is *"Boost should be exclusive to open-space gameplay and should not alter
movement in other mission types."* **Re-casting `EngineBoostModule` as the Shift boost therefore
contradicts the ask directly** — it would move assault's dash-module behaviour onto a new key, a
new resource and a new curve. Superseding it (deleting it) is worse: it is one of only two
`engines`-slot modules (`ShipModuleState.SLOT_MODULES[&"engines"] == [&"", &"warp",
&"engine_boost"]`), it has an unlocker pickup in the hub, an icon, a description, and
`test_module_unlock_sources.gd` asserts the slot stays populated.

That leaves **"kept as a distinct heavier ability"** as the only branch that satisfies the ask as
written, and the plan's real job is differentiation, not arbitration. The three axes available:

| Axis | Core Shift boost | `EngineBoostModule` today |
|---|---|---|
| Cost | A meter that depletes and refills | A flat 2 s cooldown |
| Power | Redirect + a modest burst | 1500 px/s, 467 px of travel |
| Combat | Movement only | i-frames + 45 contact damage |

Both would still play `flame_boost` and drive `ThrusterEffect.State.BOOST`, which is acceptable
(same engine, same fiction) but means the **visual cannot be the thing that tells them apart** —
the plan should say what does. It must also decide what happens when both are active at once;
today `engine_boost_active` makes `_handle_thrust()` return early, so a naive core boost written
inside `_handle_thrust()` is silently dead during a module boost.

---

## Conventions that constrain this

- **Composition over inheritance.** A boost meter is a component node (`global/components/` or,
  if open-space-only, beside the ship scene), not new fields sprayed across `PlayerBase`. The
  `Overheat`/`Shield` components are the models.
- **Mode isolation in open space is structural, not a flag.** `player_ship.tscn` is instantiated
  by exactly one scene, `sector_hub.tscn`. Anything placed in `open_space/` is open-space-only by
  construction. Anything placed in `global/ship_modules/` is **not** — see above.
- **Unlockable content needs a source in the world**, and both existing unlock stores are
  invariant-tested (`PROJECT.md` → Conventions; `test_module_unlock_sources.gd`,
  `test_weapon_unlock_sources.gd`). A new upgradeable stat with no pickup in `sector_hub.tscn` is
  the same class of dead content those tests exist to prevent.
- **Signal arity is declared exactly** (`signal boost_changed(percentage: float)`, never bare),
  and `tests/integration/test_signal_emit_arity.gd` sweeps every self-emit project-wide.
- **Per-frame logging goes behind `if OS.is_stdout_verbose():`.**
- **Never hand-type a `uid://`.** A new `.tscn` either goes UID-less or mints one with the
  headless `ResourceUID.create_id()` snippet in `tests/README.md`.
- **Tests are GUT, characterization by default** — but this is new code, so its tests assert
  intent. Any test of a `user://`-persisting autoload must use `helpers/save_sandbox.gd`.
- **Design-unit coordinates (640×360 × `WORLD_SCALE`) do not apply here.** That convention is for
  assault wave authoring; open space is authored in world pixels (the hub's pickups sit at
  `y = -212`, planets at ±600). Do not scale boost speeds by `WORLD_SCALE`.

---

## Dependencies and blast radius

**Inside open space (expected):** `player_ship.gd` `_physics_process` / `_handle_thrust`,
`player_ship.tscn`, `sector_hub.tscn` (one pickup), and whatever draws the bar.

**Outside open space (must be justified, and the idea forbids behaviour change):**

- `global/autoloads/ship_progression_state.gd` — adding a second stat. Low risk: additive, and
  `ConfigFile` tolerates a missing key. But `tests/unit/test_ship_progression_state.gd` and
  `tests/unit/test_shield_component.gd` both read this autoload and both sandbox `user://`.
- `global/entities/player_base.gd` — only if a new "something owns velocity" flag is added there.
  Prefer reusing `engine_boost_active` or keeping any new flag local to `OpenSpacePlayerShip`;
  a new `PlayerBase` field is visible to assault and infiltration.
- `global/pickups/` — a new `PickupBase` subclass is additive and touches nothing existing.
- `project.godot` `[input]` — a new `boost` action is additive. **Binding it to Shift puts three
  actions on one key** (`dash`, `race_brake`, `boost`). That is legal — the three modes are
  separate scenes and each reads only its own action — but it is exactly the kind of thing that
  reads as a bug later, so the plan should state it deliberately. Reusing `dash` instead avoids
  the third binding but couples open space to infiltration's action name.
- `global/ship_modules/engine_boost_module.gd` — **treat as assault code.** Do not edit it to
  make room for the core boost.

**Files the sibling mouse-aiming epic will also edit:** `player_ship.gd` (`_handle_rotation`,
and it **deletes `_ready()`'s `rotation = 0.0`**), `player_ship.tscn` (adds a `ShipTurnController`
node), `project.godot` (no input changes), plus a new `SettingsState` autoload and the pause
menus. Its plan explicitly records that "the two epics must not be implemented in the same
window". The functions are independent, so the conflict is textual — but both add an `@export`
block and a child node to the same scene, and `player_ship.tscn` is the file most likely to
produce a real merge problem.

---

## Risks, edge cases, testing requirements

**Risks**

1. **The `max_speed` clamp swallows the burst.** `_handle_thrust()` ends with an unconditional
   `if velocity.length() > max_speed: velocity = normalized() * max_speed`. Any boost above 420
   px/s is erased on the same frame unless it bypasses that clamp — which is why
   `EngineBoostModule` sets `engine_boost_active`. Decide the exit rule too: snap back to 420, or
   decay to it (see `2-research.md`, finding 5).
2. **Two systems claiming the same `velocity`.** Core boost, `EngineBoostModule`,
   `PlayerBase.apply_knockback_motion()` and `_handle_thrust()` can all write it. Today's
   precedence is "module wins, everything else returns early". State the new precedence
   explicitly rather than discovering it.
3. **The idea's premise about health is wrong, and the plan should say so.** It asks for a meter
   "improved through collectibles/upgrades, similar to the existing health and shield upgrades".
   **There is no health upgrade.** `max_health = 50` is authored on the ship scene and nothing
   raises it; `HealthTankPickup` and `ArmorAndHealthPickup` only *heal* 40. The one real
   precedent is `ShipProgressionState.permanent_shield_count`.
4. **"Move the existing thrust/braking behavior into the boost system"** is the riskiest line in
   the idea, and is ambiguous. Read strictly it means W/S stop accelerating the ship and boost
   becomes the only propulsion — which would make the ship unflyable whenever the meter is empty,
   and would change how the player reaches every planet in the hub. Read loosely it means
   "momentum manipulation should be the primary verb". The plan must pick one, say which, and
   note that the strict reading needs a **non-empty floor** on the meter or a free low-power
   thrust, or the player can strand themselves.
5. **`MissionTrigger` gates on speed.** A planet only opens its menu while the player is **below
   `_MAX_APPROACH_SPEED = 150 px/s`** (`mission_select_hub.gd`). A faster, boost-oriented hub
   makes docking harder, and a boost aimed at a planet is a guaranteed missed approach. This is
   the one place the feature can break *progression*, not just feel.
6. **Art budget.** A boost-up pickup wants a sprite. PixelLab allowance is capped monthly and
   generation is irreversible; the `pixel-art-generation` skill is mandatory and enforces strict
   top-down for `open_space/`. Consider a recoloured/reused existing sprite for the first pass.
7. **The bar has nowhere obvious to live.** The open-space HUD (`hud.tscn`) has **no** overheat
   element — the overheat meter is a world-space `OverheatBar` under the ship. "Next to the
   overheat meter" therefore means *under the ship at roughly `(0, 26)`*, not "in the HUD".
   Putting it in the HUD instead would satisfy the words and break the intent.

**Edge cases the tests must cover**

- Boost pressed with an empty meter → nothing happens, and nothing is spent.
- Boost pressed with a partial meter → does it fire at reduced strength, or refuse? (Design
  choice; whichever, pin it.)
- Boost while `engine_boost_active` (module boost in flight) → must not double-write `velocity`.
- Boost while a `MissionSelectMenu` is open. `MissionTrigger._open_menu()`
  (`mission_select_hub.gd:155-156, :170`) calls `player.set_physics_process(false)`,
  `player.set_process_input(false)` and then `get_tree().paused = true`. So a boost read from
  `_physics_process` or `_input` is **already** covered; one read from `_unhandled_input` would
  **not** be, and would fly the ship out of the planet's `Area2D` mid-menu. Pin whichever is
  chosen. `DialogPlayer.is_active` is a separate gate — `AssaultPlayer._input` checks it,
  `OpenSpacePlayerShip._input` does not, so open space already lets you fire an ability mid-dialog.
- Meter refill must not tick while the boost is still active (the `Overheat._no_shoot_timer`
  pattern), or a held key trickle-charges.
- Redirect at exactly the threshold angle / speed, and at 0 velocity (`Vector2.ZERO.angle()` is
  `0.0` — the same singularity the sibling epic's finding 6 documents).
- An upgrade collected **mid-session** must raise the live meter, not just the saved number —
  `Shield._on_progression_changed` is the pattern.
- A corrupt/out-of-range saved value must clamp, not be trusted (`ship_progression_state.gd:52`).
- The cap: `add_*()` returns `false` and emits nothing when already maxed.

**Testing requirements**

- `Input` cannot be driven meaningfully in a headless GUT run, so — exactly as the sibling epic
  concluded for the mouse — **the boost model must be a pure step function over injected inputs**
  (`boost_pressed: bool`, `facing`, `velocity`, `delta`), with `Input` read in exactly one place
  in `player_ship.gd`. A design that reads `Input` inside the meter/boost component is untestable
  by this project's gate.
- A **wiring test** is mandatory. The sibling epic's review caught "the feature ships inert" as a
  live hole in its first draft; the same hole is available here (meter implemented, never
  connected).
- If a new upgradeable stat lands, it wants a **placement invariant test** in the same family as
  `test_module_unlock_sources.gd` / `test_weapon_unlock_sources.gd`: the hub must contain a
  source for it. One of those tests' cases also *collects a real pickup against the live
  autoload*, because every placement test passes on a pickup whose `_collect()` is empty — copy
  that.
- `tests/integration/test_project_load_integrity.gd` loads every scene and fails on **any** engine
  warning, so a new `.tscn` with a dangling reference reds the gate. `test_suite_integrity.gd`
  and `test_signal_emit_arity.gd` will also see the new files.
- Nothing headless can judge whether the boost *feels* like Jet Lancer. Every tuning number
  should be an `@export` on a scene node so the fly-test is an inspector change.

---

## Open questions for the plan

1. **What is the boost's velocity rule?** Three candidates, in rising order of ambition:
   (a) impulse — add `facing * impulse` and let the existing damping bleed it off, raising the
   cap only while a timer runs; (b) `EngineBoostModule`'s locked-direction ease-out at smaller
   numbers; (c) a two-branch rule — a *redirect* (kill and re-aim, today's `_trigger_flip_boost`)
   when the angle between `velocity` and `facing` exceeds some threshold, and a *burst* otherwise.
   (c) is closest to the idea as written; it is also two behaviours behind one key, which needs a
   clear tell so the player knows which one they got.
2. **Does the redirect branch keep an angle threshold at all,** or does every boost simply set
   `velocity = facing * speed` (which *is* a redirect whenever the angle is large)? The simpler
   rule has no threshold to tune and no ambiguity — and `_trigger_flip_boost` already proves it
   reads well. What it loses is the ability to boost *and* keep existing speed when flying
   straight.
3. **Meter shape: continuous bar, or discrete charges?** The idea says "meter". Continuous matches
   `Overheat`; discrete matches `Shield`'s `permanent_shield_count` and makes the upgrade
   trivially legible ("+1 boost"). See `2-research.md`, findings 2 and 4.
4. **What does the upgrade actually raise** — capacity, refill rate, or burst strength? Capacity
   is the one the shield precedent supports directly and the only one a player can see on the bar.
5. **Where does the boost stat live?** `ShipProgressionState` (a second key, matching shields) or
   a new autoload. A second key is strictly less machinery; a new autoload is only justified if
   the stat set grows.
6. **Which input action?** New `boost` on Shift (three actions on one key), or reuse `dash`
   (couples to infiltration's name), or new `boost` on a free key with Shift as a second event.
7. **How literally is "move the existing thrust/braking behavior into the boost system" meant?**
   Risk 4 above. This is the single decision that most changes the size of the epic, and if the
   strict reading is chosen, the epic gets materially larger and needs its own escape-hatch
   design for an empty meter.
8. **Sequencing against the mouse-aiming epic.** That epic is `status: review` — approved by its
   reviewer, awaiting the user — with six `todo` implementation tasks in the same file and scene.
   The plan should state which lands first and what the second one has to re-read.
9. **Does the core boost grant i-frames?** `EngineBoostModule` does, and that is a large part of
   what makes it worth a module slot. A free, metered, i-frame-granting boost would make the
   module redundant on its strongest axis.
