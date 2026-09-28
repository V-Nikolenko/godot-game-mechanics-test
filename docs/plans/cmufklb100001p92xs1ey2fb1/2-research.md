# Research: Enemy rework, phase 1 (mode-neutral enemy AI architecture)

Epic `cmufklb100001p92xs1ey2fb1`, research task `cmufklb3q0007p92xgnjiyyr2`, researched 2026-09-24.
Companion to `1-context.md`, which holds the codebase facts, the requirement list (R1–R14 are Phase 1, L1–L21
are later phases), conventions, blast radius and open questions. This file covers:

1. **Proposed improvements to the owner's ideas.** The owner asked for these at the top of the plan, so the
   plan stage should lift this section verbatim into `3-plan.md`.
2. How shipped games and engines solve the same problems (findings table with tradeoffs and sources).
3. Candidate approaches for each Phase 1 contract, with a recommendation.
4. A draft roadmap splitting the rest of the ideas into follow-up epics.

Labels used below:
- **[source]**: backed by a URL in §2 that was actually read.
- **[code]**: backed by a `file:line` in `1-context.md`.
- **[judgement]**: my own design call, with no citable source.

---

## 1. Proposed improvements to the ideas (to go at the top of `3-plan.md`)

Each item is a change to `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`, with the reason for it.

### I-1. Rename the movement contract. `MovementController` is taken [code]

`class_name MovementController` is the player's input/double-press handler
(`assault/scenes/player/movement_controller.gd:1`). It is also a node name in both player scenes and a type in
four player states. Reusing the name is a hard compile collision.

**Proposal:** call it `EnemyMover`. It is short and says what it owns.

### I-2. Extend the existing `AttackController`. Don't add a second one [code]

`global/components/attack_controller.gd` already *is* the contract IDEAS §3.1 describes: a pattern plus a pool
on a timer. Light assault ship, interceptor and ally fighter already use it.

**Proposal:**
- Add three things to the existing controller: an optional aim source (TargetInfo), an `enabled`/`hold_fire`
  switch the brain drives, and a manual `fire_now()` for telegraphed shots.
- Migrate the gunship's hand-rolled Timer onto it in its own later phase.

### I-3. Profiles can't be nested in `ShipConfig` as IDEAS §30 draws them [code]

`test_config_instance_isolation.gd` rejects Object/Array/Dictionary fields on any config (209–227). It also
allows only one `*config*.tres` per entity directory (line 107). The *intent* of §30, config you can read at a
glance, is kept like this:

- **Tuning numbers** stay **flat** on the enemy's `ShipConfig` subclass. Group them with `@export_group("Movement")`
  / `@export_group("Attack")` / `@export_group("Defense")` / `@export_group("Tactics")`. This gives the same
  readability in the inspector, stays a complete shallow copy, and passes the gate unchanged.
- **Behaviour choices**, such as the damage types accepted, are data on a component node in the scene, never
  mutable state inside a shared resource.

### I-4. Keep `DefenseProfile` stateless, and let state live on the node [code] [judgement]

The ram ship's armour *changes at runtime*: mask 33, then 97 on the first hit (`ram_ship.gd:21,45`). A profile
`Resource` that gets mutated would leak that change across every ram ship. That is exactly the shared-object
trap `privatise()` exists to stop.

**Proposal:**
- `DefenseProfile` is a component node that owns the hurtbox mask. It uses named constants and computes the mask
  from a small set of "accepts" flags: player bullets, player rockets, environment, hazard contact.
- It can hold an ordered list of *states*, for example ram `ARMOURED → STRIPPED`. The entity advances the list,
  and the profile rewrites the mask and `accepted_damage_types`.
- The default profile reproduces today's `1121` exactly, so no current enemy changes behaviour.

### I-5. Take the mask *and* the damage-type filter away from the base class, but keep armour as a damage rule [code]

The project has already ruled that "armour is a damage rule on a full-size hurtbox, never an absent hurtbox".
It is gated in `test_enemy_hurtbox_geometry.gd`.

**Proposal:**
- The DefenseProfile should prefer `HurtBox.accepted_damage_types`, which already exists and goes unused by
  enemies, plus the `is_armored()` deflection query over mask exclusion.
- For the ram ship, a mask-excluded bullet passes *through* silently, while a deflected bullet flashes and
  reports. The rework should consider moving it to deflection in Phase 3's Ram Corvette.
- Phase 1 keeps the ram at 33 → 97. That is characterization, and `test_ram_ship.gd` pins it.

### I-6. Name layer 5 as well. The audit missed it [code]

All 12 pickups sit on bit 16 (layer 5), which has no name. So "name every used layer" means five fixes:

| Layer | Fix |
|---|---|
| 3 | fix the typo: `environemnt_player` → `environment_player` |
| 5 | name it `pickups` |
| 6 | name it `player_rockets` |
| 11 | name it `hazard_contact` (asteroid contact today; tomorrow's mines and debris) |
| 12 | reserve and name `area_control` for L1/L6. Leave it unused until a hazard needs it |

Keep every numeric value unchanged, which answers the epic's open question. Renaming a layer is display-only in
Godot: masks are stored as ints.

Add a `CollisionLayers` constants script (in `global/`) so code says `CollisionLayers.PLAYER_ROCKETS`, not
`32`. Add an invariant test that:
- every bit set in any `.tscn`, and every constant in `CollisionLayers`, has a `[layer_names]` entry
- the constants agree with the names

IDEAS §15's table has two small errors: it lists 4096 for bosses, and gives 2048 a meaning while 1024 is
already asteroid contact. Do not allocate bosses a layer. Boss modules are ordinary enemy hurtboxes, as the
station's turrets already prove.

### I-7. The Assault constraint should filter *velocity*, and must let enemies enter from off-screen [source] [judgement]

IDEAS §34 draws the chain `EnemyBrain → DesiredVelocity → AssaultMovementConstraint → MovementController`.
I'd make two refinements:

- **(a) Where the filter sits.** The constraint is a velocity filter between the mover's desired velocity and
  the single `move_and_slide()`. This is the same shape as Godot's `NavigationAgent2D.set_velocity →
  velocity_computed` hook [source], so there is one final writer.
- **(b) Two bands, not one.** Every Assault spawn starts *above* the visible screen (`wave_manager.gd:175`).
  A hard clamp would teleport the enemy. So the corridor has two bands:
  - a *soft* band: edge pressure that grows with depth
  - a *hard* outer band: the §34 "max 450 px outside the visible region"

  An enemy that starts outside the hard band may only move inward until it has entered. This mirrors Nova
  Drift's fix of making fresh enemies head for the screen centre until they are visible [source].

The corridor rectangle is *derived* from `ArenaCamera` constants, not copied: pinned `global_position`, plus or
minus half the viewport, plus or minus `H_LIMIT`/`V_LIMIT`.

### I-8. Phase 1 needs one real consumer. Port the Drone Interceptor, not a fixture alone [code] [judgement]

Contracts with no real user drift into the wrong shape. The Drone Interceptor:
- is self-driven in all its level-1 spawns (`level_1_director.gd:290-291`, no `.move()`)
- already uses world pixels
- has the only prediction code in the project

The proposal is to port its ENTER/ORBIT/DASH onto brain + `EnemyMover.orbit()/intercept()` + TargetInfo:
- **Keep** its tuning values and its identity. That is requirement R9.
- **Run** its behaviour spec in both modes. That is requirement R12.

Its Phase 2 redesign into the Razor Drone (feint, pulse, idle) builds on the port rather than replacing it.
A test fixture enemy under `tests/fixtures/` still covers the contract edges.

### I-9. Brains tick on physics, through one owner, with no `Timer` nodes [source] [code]

`StateMachine` ticks in `_process` (`state_machine.gd:16-18`). That is why the path mover must disable it by
magic node name. GUT's `simulate()` does not fire Timers [source].

**Proposal:**
- `EnemyBrain` is ticked explicitly from the entity's `_physics_process` by `tick(delta)`. This copies the
  race-mode `RacerStateMachine.tick` precedent [code].
- All brain and lifetime clocks are accumulated `delta` floats.
- Randomness comes from an injectable, seedable `RandomNumberGenerator`.

This makes every behaviour test a plain `simulate(node, N, 1/60)`.

### I-10. Suspend by contract, not by node name [code]

Replace `EnemyPathMover`'s `get_node_or_null("AIStateMachine")` lookup (63–65) with a duck-typed call,
`_actor.suspend_ai()` if present, falling back to the old name lookup so the light assault ship keeps working.
`BaseEnemy` implements `suspend_ai()` by pausing its brain, mover and constraint.

While a path is attached, the path mover stays the only position writer. That keeps all 264 path-driven spawns
identical, which is requirement R10.

### I-11. TargetInfo returns a *validity flag* and never throws [source] [code]

The intercept quadratic has no solution when the target outruns the projectile [source]. The target may also be
freed on the frame the player dies [code].

**Proposal:**
- `TargetInfo` is a stateless value/helper. It gets `has_target`; `predicted_position(t)` (the Reynolds pursuit
  `T = D·c` form); and `intercept_point(shot_speed)`, which returns `{ok, point, time}`.
- It falls back to the current position when there is no solution.
- It adds an `accuracy` parameter from 0 to 1 that blends intercept aim with direct aim [source].

`accuracy` is the hook that later difficulty tiers (L18) turn, so tiers need no new system. It also answers
"better prediction on Hard" (IDEAS §29) with a single number. Assault defaults to `accuracy = 0`, meaning aim at
the current position. That is today's behaviour, and it is learnable, as shmup design wants [source].

### I-12. Projectile lifetime: a component that *emits* the owner's expiry path [code] [source]

`ProjectileLifetime` is a small node. It is evaluated in `_physics_process` from accumulated time and distance.
When a rule trips, it emits `expired` on the host, and never calls `queue_free` itself. So:
- a pooled bullet recycles
- an unpooled one (the sniper shot) frees through its existing `expired → queue_free` connection

That keeps the one-owner rule. Default rules:
- `max_time`
- `max_distance_from_origin`
- an optional `world_rect`, which Assault fills from `ArenaCamera`. That preserves today's bounds exactly, and
  race mode is unchanged.

Screen-visibility culling is deliberately *not* a rule. `VisibleOnScreenNotifier2D` is camera-bound and reports
`false` for the first frame [source].

`persist_after_owner_death` belongs to the pool: `cancel_active()` on `_exit_tree`. It is a Phase 3 concern
(missiles and mines), so Phase 1 documents it and doesn't build it.

### I-13. Put the three unphased idea blocks into the roadmap [judgement]

IDEAS §41 has no slot for three blocks:
- the battlefield structures (§6.3–6.10: turrets, jammers, gravity wells, mines, twin-laser drones, wrecks,
  hacker frigate)
- hazard perception (§3.2.5)
- the art pass (§21–23)

The roadmap in §4 below gives each one a phase. Without a slot they would silently fall out of scope.

### I-14. Fix the conventions debt BaseEnemy carries while it is open [code]

These are small, and they belong in Phase 1 because R1 touches exactly these lines:
- Verbose-gate the death `print` (`base_enemy.gd:82`). It violates the logging convention.
- Replace `_rotate_sprite()`'s unconditional 180° flip with an exported `sprite_forward_angle`, defaulting to the
  current flip so art is unchanged.
- Settle one facing rule. Today there are three: nose-down in the path mover, nose-up in the interceptor, and
  the 180° flip. The rule is `rotation = heading.angle() + sprite_forward_angle`.

### I-15. Answer on `DamageReaction` versus BaseEnemy's inline flow: not in Phase 1 [code] [judgement]

`DamageReaction` offers Shield support, but the two flows differ:
- BaseEnemy flashes through an `AnimationPlayer`; DamageReaction uses a tween.
- The space station overrides both `_on_received_damage` (armour) and `_on_health_changed` (delayed death).

Swapping them now is churn with a regression surface across 10 enemies and the boss. Phase 1 turns those two
methods into documented virtual hooks instead. Adopting `DamageReaction` with Shield is reconsidered when
shields arrive (Support Ship, Phase 3).

### I-16. PatrolDrone: characterise now, replace in Phase 2 [code]

Its HurtBox mask is `64` only, so the player's rockets pass straight through it in Open Space. Its body sits on
layer 256 (`enemy_hitbox`). Phase 1 pins both as characterization. Phase 2's Swarm Drone replaces it; IDEAS §2
already scraps it. One exception: if the owner wants it fixed now, it is a one-line mask change that the new
DefenseProfile default gives for free.

### I-17. Tighten the test strategy: a behaviour spec runs in two harnesses [judgement]

IDEAS §40 says "the same behaviour specification should be used in both tests". The concrete form is:
- a shared test helper with an `open_space()` harness (no constraint) and an `assault()` harness
  (corridor from `ArenaCamera`)
- behaviour tests parameterised over both harnesses with GUT's `use_parameters`
- the assertions stated relative to the constraint: "the orbit radius holds within tolerance, *unless* clamped
  by the corridor, in which case the enemy stays inside the soft band"

---

## 2. Findings: how others solve it

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| **Arrive** caps speed at `max_speed` outside a slowing radius and ramps it down to 0 inside. `max_force`/`max_speed` are enforced with `truncate`. **Wander** perturbs the previous value on a circle ahead of the ship instead of drawing a fresh random force each frame. | The ramp is simple, but a slowing radius too short for the ship's max accel still overshoots and oscillates *[judgement, not in paper]*. So our `arrive()` needs a radius derived from `v²/(2·accel)`, not a free number. | The paper names the parameters without numbers. Derive the radius from speed and acceleration. | https://www.red3d.com/cwr/steer/gdc99/ |
| **Pursuit** predicts `T = D·c`: lookahead scales with distance. | Cheap and good enough for *movement*. It does **not** solve projectile travel time, so aiming needs the quadratic instead. The drone interceptor's fixed `t=0.2` is a special case of this. | `c` is tuned per enemy; the existing `dash_prediction_time` is 0.2 s [code]. | https://www.red3d.com/cwr/steer/gdc99/ |
| **Combining behaviours**: weighted sum or priority order. Fray: when chase and avoid conflict, "the most intelligent merge algorithm in the world will still fail", because each behaviour returns one context-free vector. This is hidden in big flocks and "very visible" with few entities. | We have few, individually visible enemies, so weighted sums will show cancellation (stalls at corridor edges or hazards). Priority order is simpler; context maps are more robust but cost more. | — | https://andrewfray.wordpress.com/2013/02/20/steering-behaviours-are-doing-it-wrong/ |
| **Context steering**: behaviours write *interest* and *danger* into per-heading slots. Mask out the dangerous slots, pick the highest interest, and use interest strength as speed. Stateless behaviours are unit-testable one at a time. | Too few slots give "juddery" motion; more slots cost CPU. It fits L1 hazards and the corridor edge naturally (the edge becomes a danger mask). It is overkill for Phase 1's primitives. | 8 slots in the example, which the author calls too few for smooth motion. | https://andrewfray.wordpress.com/2013/03/26/context-behaviours-know-how-to-share/ |
| **Lead-target intercept** is a closed-form quadratic in `t` over relative position and velocity. A negative discriminant (or no positive root) means no solution. | Exact and cheap, but it needs an explicit failure branch, and it assumes constant target velocity. The Open Space player boosts (700 px/s exit speed [code]), which will break predictions, and that is desirable counterplay. | Reference code returns `-1` on failure. | https://www.gamedeveloper.com/programming/shooting-a-moving-target ; https://itch.io/devlog/34576/predictive-aim-for-assisted-and-ai-targeting.amp |
| **Fairness**: "A 100% accurate AI is not any fun at all". Blend intercept and direct aim with a 0–1 accuracy, home in slowly over time, or add a random offset. askagamedev describes random rotational offsets so misses are "close but probably won't hit". | Perfect lead feels unfair, while obvious misses read as a broken AI. One `accuracy` scalar is the difficulty knob (I-11). | accuracy 0–1 | https://github.com/townofdon/predictive-aim ; https://www.tumblr.com/askagamedev/119049347621/how-exactly-do-developers-go-about-making-ai |
| **Intent/locomotion split is native to Godot**: `NavigationAgent2D.set_velocity(intent)` emits `velocity_computed(safe_velocity)`, and the callback does `velocity = safe_velocity; move_and_slide()`. Gotcha: without a `target_position`, `safe_velocity` is always zero. | One extra hop, but the final velocity has a single owner and a replaceable filter. That is exactly the slot the Assault corridor filter needs (I-7). | — | https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html |
| **Pooling vs `queue_free`**: pool only above roughly 20 spawn/free per second sustained. A pooled object "is never fresh" (velocity, timers, tweens, signals and `monitoring` persist), so it needs a mandatory `reset()`. `VisibleOnScreenNotifier2D` reports `false` on the first frame and depends on the camera. | Pools give stable frame time but need permanent reset discipline. Enemy bullets are above the threshold, so keep them pooled. ProjectileLifetime must reset its accumulators in `reset()`. Screen culling is unfit as a sole despawn rule. | ~20/s threshold; 1-frame notifier delay | https://saltmire.github.io/godot-4-object-pooling-vs-instantiate.html ; https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html |
| **Deterministic tests**: GUT `simulate(obj, times, delta)` calls `_process`/`_physics_process` with a fixed delta, but "timers … will not fire". Chained `wait_physics_frames` has a reported off-by-one (GUT #860, search snippet only). A seeded `RandomNumberGenerator` gives a reproducible sequence per instance. Layers can be named in Project Settings and set with `set_collision_mask_value`. | `simulate` is deterministic but blind to `Timer` nodes, so brain and lifetime clocks must be delta accumulators (I-9). Real-frame waits are only needed for true physics overlap tests. | — | https://gut.readthedocs.io/en/v9.5.0/Simulate.html ; https://gut.readthedocs.io/en/latest/Awaiting.html ; https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html ; https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html |
| **Free-roam enemies need on-screen pressure and self-preservation.** Nova Drift: "Bulwarks now do a better job of staying on-screen while not charging"; players complain about enemies circling just off-screen. Galak-Z (Jake Kazdal): enemies "prioritise not dying", disengage to recharge shields, call backup. Shmup guidance: a dead zone at the top so enemies can't be killed before they are seen, and chunked, learnable patterns. | Pure pursuit AI in open space loiters off-screen, so leash and re-entry rules are needed (L2, and the I-7 hard band). Shmups need predictable patterns, which argues for `accuracy=0` and authored spawn layouts in Assault. | — | https://pixeljam.itch.io/nova-drift/devlog/432409/enemies-20-part-2 ; https://steamcommunity.com/app/858210/discussions/0/3193616250031397466/ ; https://blog.playstation.com/archive/2013/06/11/galak-z-reinvents-the-16-bit-space-shooter-on-ps4/ ; https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101 |

**Tried and unreachable or unusable:**
- Game AI Pro 2 ch.18, "Context Steering" (PDF), and Game AI Pro 3 ch.33, "Using Your Combat AI Accuracy to
  Balance Difficulty" (PDF): binary only, `fetch-page.sh` returned 0 bytes, and no PDF tooling is available in
  the container. Fray's blog posts above stand in for the first.
- The Galak-Z AI talk from glenndoren.com (expired TLS certificate; the proxy returned 422).
- GDC Vault Galak-Z talks: found, not opened, and not about AI.
- No Everspace or Luftrausers developer statement on despawning was found.

**No numeric steering tuning** (slowing radius, max_force) was found in any source that was read. Starting
values must come from the existing configs (drone interceptor, the Open Space player's `max_speed=420`,
`thrust_acceleration=380`) and be labelled as judgement.

---

## 3. Candidate approaches per Phase 1 contract

### 3.1 Brain

| Option | For | Against |
|---|---|---|
| A. Reuse `global/statemachine/StateMachine` | Existing, tested, one `State` per file | Ticks in `_process`; suspended only by the magic node name; `simulate` does run `_process`, but mixing clocks with physics movement is a bug source |
| **B. `EnemyBrain` node with explicit `tick(delta) -> intent`, ticked by the entity in `_physics_process` (race precedent)** | One clock; testable by calling `tick` directly; the brain can internally use enum phases (simple enemies) or `State` children (complex ones), matching CLAUDE.md's two styles | New class |
| C. Behaviour trees / utility AI | Scales to bosses | No precedent in the project; heavyweight for 3–5 states per enemy (IDEAS §4 says as much) |

**Recommend B.** The intent is a small value object: desired move primitive + target + fire request.

### 3.2 Movement (`EnemyMover`)

| Option | For | Against |
|---|---|---|
| **A. Stateless primitive functions returning a desired velocity (`seek`, `arrive`, `orbit`, `intercept`, `evade`, `strafe`, `hold`, `drift`, `boost`, `retreat_from`), then accel / turn-rate / max-speed limits, then the constraint filter, then a single `move_and_slide()`** | Reynolds model [source]; each primitive is unit-testable in isolation; the corridor slots in as a filter | Weighted combinations show cancellation with few entities [source]. Mitigation: the brain picks **one** primary primitive plus an optional additive avoidance ("offered, brain opts in", as `LateralMover` does) |
| B. Context steering maps | Robust avoidance [source] | Premature before hazards (L1) exist; revisit then |
| C. Keep `EnemyPathMover` as the movement system | Zero risk | Defeats R2/R3; screen-space only |

**Recommend A for Phase 1, and keep B on the roadmap with L1 hazard perception.** Phase 1 builds the primitives
Phase 2 needs: `seek`, `arrive`, `orbit`, `intercept`, `evade`/`retreat_from`, `strafe`, `hold_position`,
`drift`, `boost`. Defer `formation_slot`/`regroup` to L12, `break_contact` to Phase 3 (sniper), and
`spiral`/`corkscrew` to Phase 2 (swarm). Each can be listed in the plan's coverage table against the phase that
needs it.

### 3.3 Assault constraint

| Option | For | Against |
|---|---|---|
| **A. Velocity filter with soft and hard bands (I-7)** | One writer; the enemy can enter from off-screen; same shape as Godot's nav avoidance [source] | Needs the "has entered" flag |
| B. Position clamp after `move_and_slide` | Trivial | Teleports spawns and leaves velocity inconsistent with position |
| C. Transform AI into camera space | Reuses design-unit authoring | Brings back exactly the camera coupling the epic removes |

**Recommend A.** Its null object, "no constraint", is the Open Space mode.

### 3.4 Projectile lifetime

| Option | For | Against |
|---|---|---|
| **A. `ProjectileLifetime` child node emitting the host's `expired` (I-12)** | Keeps the one-owner rule; composable; Assault `world_rect` reproduces today's bounds exactly | One extra node per bullet scene (pool pre-warm cost is negligible) |
| B. Rules inline in `enemy_bullet.gd` | Fewer files | Not reusable by bomb, sniper shot or future rockets |
| C. `VisibleOnScreenNotifier2D` | Built-in | Camera-bound; first-frame false [source]; wrong for Open Space |

**Recommend A.** The race weapon keeps working because the Assault/race `world_rect` defaults to the same numbers.

### 3.5 DefenseProfile and layers

Covered by I-4, I-5 and I-6. The acceptance test is: every roster enemy's post-`_ready()` mask is
byte-identical to today's (1121; ram 33 → 97).

### 3.6 TargetInfo

A static helper (`class_name TargetInfo extends RefCounted`) built from a `Node2D` target:
- `has_target`, `position`, `velocity`, `facing`, `distance_from(p)`, `relative_angle_from(p)`
- `predicted_position(t)`, `intercept(from, shot_speed) -> {ok, point, time}`
- `line_of_sight` as a stub returning `true` (a real raycast lands with L17)
- one `TargetInfo.player(tree)` resolver that replaces the scattered `get_nodes_in_group("player")[0]`

It is consumed first by the aimed/gatling attack patterns (behind `accuracy`, defaulting to today's aim) and by
the ported drone interceptor.

---

## 4. Draft roadmap for the follow-up epics (for the plan to finalise)

| Epic | Scope (idea §§) | Depends on |
|---|---|---|
| **1. Architecture (this epic)** | R1–R14 and I-1…I-17; Drone Interceptor port as the proof consumer | — |
| 2. Foundational enemies | Swarm Drone (replaces Kamikaze and PatrolDrone), Razor Drone (evolves the ported interceptor: feint, pulse, reversal, idle orbit), Fighter, Gatling Interceptor; contact-damage profiles (§16); `spiral`/`corkscrew`; first squad roles (lead/flank); Bonus Drone kept as an Assault reward | 1 |
| 3. Specialists | Bomber (3 ordnance types), Sniper (relocate/stationary/disengage, rail shot, `break_contact`, LOS), Ram Corvette (plates, charge), Missile Corvette + rocket family, Support/Shield ship (+ Shield on enemies, `DamageReaction` decision), `persist_after_owner_death` | 2 |
| 4. Hazard perception and battlefield structures | HazardInfo + context steering (§3.2.5, §18.6), turret, jammer, gravity well / anomaly, mines/minefield, wreck/debris, Mine Layer, twin-laser drones / laser wall, Hacker Frigate (needs the player's seeking weapons to expose retargeting) | 3 (rockets and mines) |
| 5. Heavy enemies and modular damage | Heavy Gunship (side batteries, overheat phase, no despawn retreat), Carrier; a generic module framework generalised from the station's turrets (§14, §26) | 3 |
| 6. Bosses | Space Fortress 2.0 (station rework, 360°), Dreadnought; reinforcement philosophy; phase rules (§8–10, §24–25) | 5 |
| 7. Open Space encounters | EncounterDirector, semantic spawns, leash/persistence lifecycle, idle profiles, squad messages, Salvage Drone event (§3.3, §18, §18.5, §19, §32–33) | 2 (it can start after 2 and grow) |
| 8. Assault migration | Formations become spawn layouts plus corridor-constrained AI; retire `EnemyPathMover` as the default (§20, §34–35) | 2, 3, 5 |
| Cross-cutting: art readability | Silhouette + accent + gameplay-light pass and size language (§21–23), done per roster epic under the `pixel-art-generation` skill; strict top-down | runs with 2–6 |
| Cross-cutting: difficulty | Behaviour-based tiers via `accuracy`, telegraph time, cooldown and decision latency (§29) | 1 (hook), tuned in 7 |

Note on the ordering. IDEAS §41 places the encounter director (6) before the Assault migration (7). This
roadmap moves hazards and structures, which §41 never phased, in before heavies, because the Mine Layer and
Bomber mines need the hazard layer. The plan stage may reorder; the table exists so nothing is dropped.

---

## 5. Suggested Phase 1 starting defaults

All of these are [judgement] unless marked otherwise.

- Drone Interceptor port: keep every config value [code]. Orbit 130 px, 1.8 rad/s, approach 200, correct 160,
  dash 480, prediction 0.2 s.
- Assault corridor: visible rect = `ArenaCamera` pinned centre ± (640, 360) ± (`H_LIMIT` 100, `V_LIMIT` 380)
  [code]. Soft band 0–120 px outside it; hard band 450 px outside it (IDEAS §34's own number).
- Projectile lifetime:
  - Assault `world_rect` = today's `EnemyBullet` box (x −164…1444, y −444…1164) [code]
  - default `max_time` 6 s
  - `max_distance_from_origin` 2000 px, i.e. about 1.5 screen widths at the player's 420 px/s cruise
- `accuracy` default 0.0 in Assault patterns, so today's aim is unchanged.
