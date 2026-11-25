# Research — Enemy rework, phase 12: Dreadnought hunting boss

Research stage, task `cmug256th003pm52whp1pyy8c`, epic `cmug256tc003lm52wbdoxucrr`, 2026-11-25. Code read at `cf2562a`. What exists and the conventions that
constrain the design are in `1-context.md` (with the requirement list R1–R20 from `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`).
This file has the scope check, the web findings, the candidate approaches per subsystem with their tradeoffs, starting numbers, and the questions the plan must close.

## 1. Scope check (re-validated against the code, DECISIONS.md and the Ph10 / Ph11 as-built reports)

The phase scope was written before Phases 10 and 11 ran. Against what they actually built:

| # | Scope item | What the code / as-built says | Effect on this phase |
|---|---|---|---|
| S1 | "built on phase 10's module framework and on phase 11's boss-reinforcement mechanism and phase rules" | `EnemyModule`, `ModularHull`, `TurretMountBuilder` (Ph10) and `global/boss/` (`BossPhase`, `BossPhaseDriver`, `ReinforcementBay`, `BossReinforcements`, `EscortContainer`, `ShieldSector`, `BossDeathSequence`; Ph11) exist, are boss-agnostic and name Ph12 as their next consumer | **Reuse, do not rebuild.** The fortress root (`space_fortress.gd`) is the template for the Dreadnought root. |
| S2 | "The player chooses what to disable first (weapons, engines, shields or core)" + one-engine / two-engine phase shifts + critical ram (§9, §25) | `BossPhaseDriver` is **one ordered ladder**: `evaluate()` enters only `_index + 1`; "a later phase never jumps its predecessor" (`boss_phase_driver.gd:52-59`). The fortress also **locks** its generators and core until earlier phases (`starts_vulnerable` false) | **A shared-machinery change is in scope**: the Dreadnought cannot express a free order on one linear ladder, and it must not lock its core or shields (R7). See §3.1. The fortress stays bit-identical. |
| S3 | §10: "launches interceptors when a weapon module is destroyed" — *from that module* | A bay whose own part is destroyed is **killed in the same call** (`boss_reinforcements.gd:372-379`); Ph11 convention: "reinforcements always come out of a bay on a live part … and stop when that part is destroyed" | **A deliberate change to a Ph11 convention is in scope** (a new appended bay trigger, §3.4). The plan and DECISIONS must say so explicitly. |
| S4 | Attacks: broadside cannon sweep, missile fan, energy torpedo, engine wake, critical ram | Broadside: Heavy Gunship BROADSIDE and the Carrier's 150° side batteries exist. Missile fan: `RocketBatteryMount` fires a *sequence* along one barrel (no spread). Torpedo: **nothing** in the rocket, ordnance or round families. Wake: **nothing**, but `HazardField` / `ReactorField` (timed, drawn, stress damage) cover it. Ram: `RamCorvetteBrain`'s cycle exists; `ContactProfile` deals one `collision_damage` in every mode | Small additions (a rocket fan export, a torpedo scene, a wake field scene) and one decision on ram damage (§3.6). No new damage path is needed. |
| S5 | "Losing one engine makes its movement visibly lopsided" | `CarrierBrain` already scales turn / speed by engines alive and **lists** — but the list sags the **facing** only (`carrier_brain.gd:378-397`); DECISIONS Ph2: `max_turn_rate` turns the sprite, only brain-side `Steering.turn_toward` bends a path ("Dreadnought arcs must use this") | The Dreadnought must change the **path** (asymmetric turn rates + yaw bias + drift), measured on the path in tests, not on the sprite. Reuse the engine-count idea, not the facing sag. |
| S6 | "silhouette that changes as modules detach and wreckage states" | Ph10/Ph11 rule: destroyed = **wreckage that stays** (IDEAS §23 "destroyed modules visibly remain as wreckage"); LOS-blocking / physical capital wreckage is **Ph19** | Reconcile both: the part stays as a wreck *stump* (smaller wreck texture, so the outline shrinks) and a chunk **detaches** as a `DebrisFragment` (Ph6; a collision hazard that is not cover, so nothing of Ph19 is pulled in). |
| S7 | "an Assault adaptation within the corridor constraint" | The fortress has an Assault mode (ENTER / HOLD / bob, no budget, no exit). Level 1's boss slot (`station_assault`) is the fortress; Phase 15 owns Assault level migration | **The scope does not name a level placement.** Default recommended: Assault behaviour built and tested in the Assault harness plus `WaveBuilder.dreadnought()`, **no level-1 placement** — owner choice (§6 Q7). |
| S8 | "an Open Space placement for testing and hub use" | Hub draws 1–21, appended; the fortress is draw 21 in its own zone; `test_sector_hub_patrol.gd` sweeps every patrol's footprint | **Hub draw 22**, with a hunting leash (a hunter's footprint is its leash). |
| S9 | §40 boss tests in both harnesses | Every fortress suite runs `use_parameters(MODES)` with `tests/helpers/enemy_ai_harness.gd` | Same pattern; the epic names three must-have rows (engine loss changes movement, module death disables its attack, critical ram). |
| S10 | §25 rules for the Dreadnought "including the final-ram phase" | `test_boss_phase_rules.gd` already collects **every** `BossPhaseDriver` in an instantiated boss (`_drivers_of()`), and asserts the fortress is found | Gate-compatible with two drivers; the sweep must also assert the Dreadnought is found. |
| S11 | Gate time (not in the scope text, a project constraint) | GUT ≈ 225.2 s after Ph11 t11 against the 240 s ceiling; Ph11 escalated past a 237 s two-run mean | ≈ 12 s of headroom. Either a **gate-room task first** (Ph10 t1 freed 32.6 s by moving paced files from 8× to 16×) or a total allotment ≤ 10 s. Recommended: gate-room first, the Dreadnought's suites are the size of the fortress's (Ph11 spent +18.1 s). |
| S12 | Stays deferred (unchanged) | Enemy beams/rings vs parts (Ph18/19), capital wreck on death and LOS wrecks (Ph19), Carrier/Gunship onto the boss machinery (Ph18), encounter compositions and escort leash in Open Space (Ph13/14), per-part HUD / score / audio (Ph17), difficulty tiers (Ph16) | Out of scope here; the Dreadnought's death leaves no capital wreck (`wreck_chance` 0, the fortress rule). |

Nothing in this phase's scope was already built by an earlier phase except the machinery it builds on (S1). Two Ph11 conventions change (S2 single ladder per boss,
S3 bays die with their part) — both only for hosts that opt in, so the fortress is untouched.

## 2. Findings from shipped games and developer writeups

Web research done by a subagent and merged here; the Dark Souls 3 quote and the Starsector Conquest quote were re-checked by me against the pages. Rows marked
*(judgement)* in the values column are derived, not quoted.

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| F1 | **A broadside capital is built for a circling fight and survives its slow turning with a short burst-turn.** Starsector's Conquest "is designed to fire from a broadside position; facing perpendicular to its opponent", its ship system *Maneuvering Jets* is a short burst of speed and turn; the Onslaught's side guns "cannot reach a target directly in front" and its rear is "very vulnerable". | A low turn rate is what makes the ship feel huge, and is exactly what lets a fast player camp its blind arc. The fix is a timed burst-turn plus rear coverage, not a permanently higher turn rate. | Conquest speed 55 / turn 6°/s, Onslaught 25 / 4°/s, Wolf frigate 150 / 60°/s: capital ≈ 0.17–0.37× the fighter's speed, ≈ 0.07–0.1× its turn rate. *(judgement)* With our player at 420 px/s circling at 600 px (≈ 40°/s), a Dreadnought turning 15–25°/s can be out-circled; add a jets burst ≈ 2–3× turn for ≈ 1.5 s on a cooldown. | https://starsector.wiki.gg/wiki/Conquest, https://starsector.wiki.gg/wiki/Onslaught, https://starsector.wiki.gg/wiki/Wolf |
| F2 | **Broadside AI fails at the side switch and when avoidance overrides intent.** Starsector's developer: avoidance "took over without regard for what the ship was trying to do" and left ships on the wrong side of a broadside; the fix fed the preferred direction (away when too close, closer when too far) into avoidance. A Godot naval devlog aiming at bearing + 90° saw the ship turn 180° one way and then flip. | Range-keeping as a preference gives long arcs but must go through the same steering blend as hazards. Aiming at "bearing ± 90°" without remembering the side thrashes at the wrap-around. | *(judgement)* Keep the chosen broadside side; switch only when the player is > 30° past the bow or stern for ≥ 1 s. Range band ≈ 500–800 px through the existing context-avoidance stage, never an override. | https://web.archive.org/web/2020/https://fractalsoftworks.com/tag/ship-ai/, https://sandrot.itch.io/starboard/devlog/181386/adding-ai-part-1 |
| F3 | **Engine loss should show as movement, in the world.** Starsector: engines are "disabled individually, gradually reducing ship maneuverability and speed"; a disabled engine "can also cause the ship's facing to drift in one direction or another, depending on the location of the disabled engine"; the cue is animation and sound on the battlefield, not a status panel. Permanent loss was rejected there as a snowball. | For a boss, the snowball is the reward — but a crippled boss that is stationary *and* harmless is an anticlimax. The Dreadnought's extreme-weapons phase answers that. | *(judgement)* One engine: top speed ≈ 60–70 %, a constant yaw bias toward the dead side and a sideways drift so the track visibly curves; dead plume on that side only. | https://web.archive.org/web/2016/http://fractalsoftworks.com/2011/09/17/new-feature-damageable-modules/ |
| F4 | **Telegraph length.** Dark Souls 3 frame analysis: "Attack Signal and Attack together need to have a guaranteed duration of at least 340ms"; recovery length "is determined by the strength of the attack". Death's Gambit's co-designer: the wait should be proportional to the opening it gives, and one cue must always mean one outcome. | 340 ms is a melee number. A 400 px hull ramming from range needs longer, which makes it easy to dodge — pay for it with a big lane and a long recovery (the punish window). | *(judgement, derived)* clearing half a 200 px-beam lane + the player radius ≈ 130 px at 420 px/s ≈ 0.31 s; for a 400 px lane ≈ 232 px ≈ 0.55 s; + 0.25 s reaction → **telegraph ≥ 0.8 s, recommend 1.0–1.2 s, line frozen at telegraph start, 1.5–2.5 s recovery**. | https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3, https://www.gamedeveloper.com/game-platforms/designing-for-difficulty-readability-in-arpgs |
| F5 | **Trail hazards decay, and the designer chooses whether the chase lane is safe.** Battlesnake's Snail Mode tail hazards decay one stack per turn, and moving directly behind a tail suppresses them; Enter the Gungeon's Wallmonger fire trail is a safe space for fire-immune / flying players. | A wake is the natural punishment for camping the blind stern (F1), but invisible or lingering damage reads as unfair and clutters the arena. | *(judgement)* life ≈ 2–4 s; damage only while drawn above an alpha threshold; width ≈ the plume (60–100 px), never the hull; per-tick damage below a bullet hit; spawned behind **working** engines only, so a lost engine thins the wake (supports F3). | https://docs.battlesnake.com/maps/snail-mode, https://enterthegungeon.wiki.gg/wiki/Wallmonger |
| F6 | **A free destruction order collapses to one best order unless every choice has a cost.** Squadrons guides converge on "shields first, then targeting"; Everspace 2's destroyer turrets "can be destroyed to prevent the Destroyer from shooting. However, they are repaired after a short period of time"; Monster Hunter parts each change something different. | If one part removes the most danger, players learn that order and the choice is fake. Repair stops "disarm everything" at the cost of busywork. | *(judgement)* each target class needs a gain **and** a cost (table in §3.2); check no class is best for every player. | https://everspace.fandom.com/wiki/Outlaw_Destroyer; Squadrons / Monster Hunter claims from search summaries only (https://www.ginx.tv/en/how-to-destroy-squadrons-capital-ships-system-locations-weak-spots-strategies-and-tips-and-tricks, https://game8.co/games/Monster-Hunter-World/archives/311549) |
| F7 | **Reinforcements on part loss punish progress.** Horizon Zero Dawn does the opposite: knocking components off can remove special attacks or the ability "to call for reinforcements". | Interceptors launched when a module dies push players to leave weapons for last (a new dominant order) and spike difficulty when two modules die close together. | *(judgement)* make each launch a trade (the guns go silent, 2–3 weak interceptors take over), cap live escorts (4–6), and space launches so two quick kills cannot double the swarm. | https://www.digitaltrends.com/gaming/horizon-zero-dawn-beginners-guide/ |

**Unreachable or thin:** fractalsoftworks.com live (402 / Cloudflare; read through web.archive.org); no Starsector source on *how* its AI picks a broadside side; Game Developer's
Nex Machina and Mike Stout telegraph articles have no numbers; Sea of Thieves AI article says nothing on broadsides; no developer source for AC IV / Pirates! broadsides, Furi /
Gungeon / Cuphead / Hollow Knight telegraph seconds, Cosmoteer / Space Engineers thrust imbalance, FreeSpace 2 subsystems, or any exhaust / wake hazard writeup. The wake
numbers (F5) are therefore mostly judgement.

## 3. Candidate approaches per subsystem

### 3.1 Phase structure for a free destruction order (S2, R7–R11)

| Option | How | For | Against |
|---|---|---|---|
| A. One linear ladder (hunting → listing → crippled → critical) | four `BossPhase`s on `PhaseDriver` | zero machinery change | **Violates R7**: core-first play never reaches `critical` (and its ram) until both engines die; any fixed order is a hidden prescribed order. Reject. |
| **B. Two drivers on one host** (recommended) | `PhaseDriver` = the **hull track** (`hunting` START → `critical` at core ≤ ratio, HEALTH_AT_OR_BELOW on the core part); `EngineDriver` = the **engine track** (`twin_engines` START → `listing` 1 of {engine_port, engine_starboard} → `crippled` 2 of them). Both are ordinary ordered ladders | no change to `BossPhaseDriver`; the §25 gate already sweeps every driver; each track is genuinely ordered (one engine always precedes two); the four target classes stay free because weapons and shields are not phase gates at all | `BossReinforcements` binds **one** driver (`ON_PHASE`, `active_from_phase`): pass the hull track, or extend it to a list (small, default bit-identical). `phase_snapshot()` must cover both tracks; `critical` on a crippled hull cannot ram, so `critical` needs ≥ 2 changes on both paths (Ph11 rule: a path where a declared change cannot happen gets its own ≥ 2 row). Path count: engine/core orders interleave (E1 E2 C, E1 C E2, C E1 E2) — three §25 rows. |
| C. Unordered driver mode | `BossPhaseDriver.ordered := false` enters any phase whose rule holds | one driver, data-only | changes the driver's core invariant ("never jumps its predecessor"), which the §25 meaning (change vs the previous phase) relies on; `current_index()` becomes ambiguous; every fortress row must prove bit-identity. More risk than B for no gain. |
| D. Engines outside the ladder (Carrier precedent) | engine consequences in the brain, a hull ladder only | simplest | the scope names "one-engine and two-engine phase shifts" under §25 — they would escape the §25 gate. Reject. |

### 3.2 Hull rule and the four target classes (R3, R7, F6)

Ph10 requires one hull rule per boss. **Recommended: the armoured hull** (Carrier / fortress): the root refuses damage (`deflects_hit` / `is_armored` true), shots cross it to
the parts, the core part's death is the boss's (`health.set_health(0)`). The vulnerable-hull alternative (Heavy Gunship: the root `Health` is a shared bar, flush-edge parts)
makes "core first" meaningless (every hit feeds one bar) and the flush-edge rule awkward on a long ship outline.

**No locks** (R7): every part `starts_vulnerable` true, unlike the fortress. "When intended" (§40) is satisfied by *shielding*, not locking. A design matrix that keeps every
choice a trade (F6, F7) — *judgement*, to be play-tested:

| Target class | Parts | Gain | Cost |
|---|---|---|---|
| Weapons | port broadside, starboard broadside, missile rack, torpedo tube | that attack angle goes silent (mount UNPOWERED, §26) | its bay launches interceptors (R10) |
| Engines | engine port, engine starboard (stern) | one: lopsided, exploitable slow-turn side, wake thins; two: no movement, no wake, **no final ram** | attacking the stern means crossing the wake; two dead → `crippled` extreme-weapons phase |
| Shields | one shield generator (WEAK_POINT) | the `ShieldSector` bubble drops for good on what it protects (recommended: the core and the engines) | the generator sits where the broadsides overlap / it is small; nothing else |
| Core | core (CORE) amidships | the kill; ≤ ratio → `critical` | under both broadsides; regenerating bubble while the generator lives makes it slow |

### 3.3 Weapons (R5, R6, R12)

- **Broadside cannon sweep.** (a) Tracking cannon mounts per side with a ~150° traverse (Carrier) — the player crossing an arc is the only "sweep"; (b) **narrow-traverse
  side batteries** (`traverse_deg` ≈ 30–40, an existing export) that fire roughly abeam while the hull's own arc turn walks the lanes across the player — the §24 "weapon from the
  geometry" reading, and the Carrier's "a dead battery leaves its side safe" for free; (c) a new walking-barrage pattern (shots laid along an arc in time) — new code for little
  gain. Recommended (b), several mounts per broadside part fired as one volley through a brain gate (`telegraph_gate`), the battery lights as telegraph. Fairness as the Ph11
  beam rule: the lane's tip speed at its reach, `hull turn rate × reach` ≤ 0.8 × player speed (0.35 rad/s × 900 px = 315 ≤ 336 px/s).
- **Missile fan.** (a) `RocketBatteryMount` gains `fan_count` / `fan_spread_deg` (1 / 0 = bit-identical; the `BurstCannonMount.pellets` precedent, Ph11 t3): one salvo
  leaves as a spread at once; (b) a salvo of `CLUSTER` rockets (each splits into a 36° fan of 4) — needs a kind choice on the mount anyway and fans late, not at launch.
  Recommended (a); pools sized by the existing `pool_size_for` stand-in × `fan_count`; `persist` pools make the Dreadnought a **persistent-ordnance** host (relevant only if a
  level places it in an `ENEMIES_CLEARED` section — S7).
- **Energy torpedo.** (a) a new `EnemyRocket.Kind` (appended) — rockets are shot down by **one** bullet and steer briefly; a torpedo wants several hits and a slow, long
  approach: new code in the rocket's shoot-down path; (b) **an `EnemyOrdnance` PURSUIT_BOMB-kind scene** (`energy_torpedo.tscn`): ordnance already has a multi-hit `Health`,
  a proximity trigger, `steer_window` / `turn_rate` / `steer_lead` / `final_speed`, `ContactBlast`, `ProjectileLifetime`, hazard bending — likely **no new ordnance code**, only
  a scene with its own exports and art; the launcher is the gap (no ordnance-firing `TurretMount` exists: a new `Variant.TORPEDO_TUBE` mount, or the brain firing from a
  root `BulletPool` the Bomber way); (c) a slow, large `EnemyBullet` round — no counterplay beyond dodging. Recommended (b) + a small tube mount (bow, narrow traverse,
  the ram's line) so module death disables it through the standard UNPOWERED path.
- **Engine wake.** (a) **timed puffs**: a `HazardField` scene (the `ReactorField` precedent: stress-only, ring drawn at the full radius, fade, `duration`) spawned
  deferred into `Hazards.container()` every `wake_spacing` px of travel behind each **live** engine; damage through the existing `Hazards.pulse_damage` (centre distance);
  (b) one trail node per engine with a polyline: `Hazards` registers one `HazardInfo` per node, so a polyline needs one node per segment anyway — no saving. Recommended (a).
  Costs: one registered hazard per puff (2 engines × life / interval, e.g. 2 × 3 s / 0.25 s = 24), each enemy mover queries `Hazards.around()` every step — measure in the
  gate-time row; the boss's own escorts and other ships are hit by centre distance (friendly fire — owner choice; `exempt_group` exempts only *avoidance*); `damage_radius`
  must equal the drawn radius and damage must stop before the fade ends (F5).
- **Critical ram.** The `RamCorvetteBrain` cycle on a boss: LINE_UP → WIND_UP (lane drawn, engines glowing; aim tracks for a fraction then **freezes**) → CHARGE
  (`mover.boost` through the predicted point plus `overshoot`, ≤ `charge_max_time`; boost skips hazard avoidance — the Ph6 committed-run rule) → long WIDE_TURN (the punish
  window) → repeat on a cooldown. Only in `critical` with ≥ 1 engine (a one-engine ram curves — the lopsided rule applies to the charge line too, or the charge is straight and
  the turn lopsided: plan decision). Assault: diagonal across the corridor (the Ram Corvette's Assault rule); the corridor filter still applies during a boost.

### 3.4 Interceptors from a destroyed weapon module (S3, R10, F7)

| Option | How | For | Against |
|---|---|---|---|
| **A. New appended trigger `ReinforcementBay.Trigger.ON_OWN_DESTROYED`** (recommended) | `BossReinforcements._on_module_destroyed`: for this trigger the bay is not killed; it queues one launch, runs its door cycle on the wreck (a short "breach" telegraph, sparks / CHARGING light on the wreck), launches, then dies | literal §10 ("from that module"); keeps caps, `assault_launch_limit`, `config_overrides`, scuttle, `boss_escort_spawned` scoring; every other trigger bit-identical | changes a Ph11 convention for opt-in bays; must define what happens on the boss's death mid-breach (scuttle and drop) and while EMP'd (`tick(…, false)` holds) |
| B. `ON_SECTOR_LOSS` bays on a live part (core / hull) watching each weapon | no machinery change | the mouth is not the wreck (fails "from that module"); a bay on the core dies with the boss anyway |
| C. Brain-side spawn | none | bypasses caps, scoring, the escort container and scuttle — a regression of Ph11's rules |

Payload: "interceptors" — the Gatling Interceptor (the IDEAS lineage of "Interceptor") pair is the natural default, Razor Drone the alternative; per-module payloads possible.
`config_overrides` makes them fire within the Ph11 3 s escort rule. F7: cap (Open Space 6 / Assault 4, the fortress numbers) and `count` 2 so two quick kills cannot double
the swarm past the cap.

### 3.5 Movement: hunting on long arcs (R2, R4, R8, R9, F1–F3)

- **Ship model, not orbit anchor.** `Steering.orbit` walks an anchor round a circle and corrects toward it — the velocity can point anywhere, so a 400 px hull would
  slide sideways. A **heading model** reads as a ship: velocity along the nose, the heading turned with `Steering.turn_toward` at `turn_rate` toward a desired heading from a
  guidance law (tangent to a loiter circle of radius ≈ 600–800 px about the player's predicted position, on the side that brings the chosen broadside to bear — an orbiting
  ship has the target abeam, so **the arc and the broadside are the same geometry**). `DubinsPath` plans a set-up turn when the side must change (F2 hysteresis).
- **Out-circling is the counterplay** (F1): Dreadnought angular rate about the player `v / R` = 120 / 700 ≈ 0.17 rad/s against the player's 420 / 700 = 0.6 rad/s. A
  **jets burst-turn** (×2–3 turn for ≈ 1.5 s on a cooldown) stops the stern from being a permanent safe spot — with the wake (F5) covering the stern too.
- **One engine (`listing`):** speed × ≈ 0.65, turn rate toward the dead side × 1.0 and toward the live side × ≈ 0.35, a constant yaw bias toward the dead side and a sideways
  drift → the arc tightens one way and widens the other; it prefers to circle with its dead side inward. Readable (F3) and exploitable (stay on its slow-turn side). Tested on
  the **path**: turn radius left vs right, net heading drift with a straight request.
- **Two engines (`crippled`):** translation 0 (a request of zero velocity; drift from hazards still applies through the mover — §18.6 resistance high), rotation only by
  manoeuvring thrusters at a slow rate (else a player in a dead arc is safe forever), extreme weapons: cooldown factor and attack-gate cap raised **inside** the measured
  density ceiling (`pool_period_factor` authored to match).
- **Open Space leash:** hunts inside a zone round `patrol_anchor` (a hunter that follows the player to the spawn or the mission triggers breaks the hub) → RETURNING past
  `lose_radius`, `AnchorIdle` for the hub idle; `start_engaged` skips it (Carrier rule).
- **Assault:** same brain inside the 1480 × 1480 corridor (a 400 px hull is ~27 % of its width): enters from above (`world_anchored_x`), then wide side-to-side sweeps in the
  upper band with the broadside toward the player at the ends, no budget, no exit (fortress rule). The corridor filter acts on velocity; the heading model must request
  velocities the filter rarely has to bend (pick arc centres inside the band) or the hull will skid.

### 3.6 Ram damage and contact (R5, contact-damage gate)

`ContactProfile` deals `config.collision_damage` in every mode (`test_enemy_contact_damage.gd`'s single rule). Options: (a) one number — hull contact ARMOR (always on, shove)
at a moderate `collision_damage`, the ram is "a touch at speed" with the same damage; (b) **a separate bow `RamHitBox`** (`HitBox`, CONTACT type, `damage = config.ram_damage`,
armed only during CHARGE, deferred toggles) beside the ARMOR `ContactHitBox` — a new row in the contact-damage gate. Player HP is 50; the Ram Corvette's 50 one-shots an
unshielded player, so a boss ram ≈ 30–35 (*judgement*). Recommended (b) if the plan wants the ram to hurt more than a touch; (a) is simpler.

### 3.7 Detachment and art (R13, R14, S6)

Each part: intact, damaged sparks (`EnemyModule` `damaged_ratio`), and a **wreck stump** texture smaller than the intact one so the outline visibly shrinks; on destruction a
`DebrisFragment` chunk (`ram_fragment.tscn` precedent, `source` = the boss so it never hits it) is flung outward and drifts as a hazard (not cover). Engines: plume
(`CarrierEnginePlume` precedent, the part's `Light` child so it dies with the engine) + wake. Lights per §21. Hull: one large texture (≈ 448 × 224 for a 448 px ship;
`create_map_object` paints a background above 40 000 px — strip it, the Ph11 t9 route) + parts hand-drawn through `pixelart_workbench` at their exact hurtbox sizes.

## 4. Starting numbers (to be confirmed in the plan)

| Value | Start | Source |
|---|---|---|
| Hull length × beam | ≈ 448 × 224 px (R1 320–480) | IDEAS §9; *judgement* on the beam |
| Cruise speed / turn rate | 120 px/s / 0.35 rad/s (≈ 20°/s) → turn radius ≈ 340 px | F1 ratios scaled to player 420 px/s |
| Loiter radius about the player | 600–800 px | F2 band; broadside reach |
| Jets burst-turn | × 2.5 for 1.5 s, cooldown 8 s | F1 *judgement* |
| One engine | speed × 0.65, toward-live turn × 0.35, yaw bias ≈ 0.08 rad/s | F3 *judgement*; Carrier `one_engine_*` exist as precedent |
| Ram telegraph / speed / overshoot / recovery | 1.1 s / 560 px/s / 300 px / 2.0 s | F4 derived; Ram Corvette 0.65 s / 620 / 220 scaled to the body |
| Ram damage | 30–35 | player HP 50; Ram Corvette 50 |
| Wake puff | radius 40 px, life 3.0 s, every 0.25 s per live engine, 5 damage per 0.5 s stress tick, no damage in the last 0.5 s fade | F5 *judgement*; `ReactorField` |
| Torpedo | 160 px/s steering 3.0 s at 0.6 rad/s, then 320 px/s; 3 HP; blast 64 px / 25 | pursuit bomb 1.5 s / 1.2 rad/s / 380 px/s, scaled slower and bigger (*judgement*) |
| Broadside fairness | lane tip speed ≤ 0.8 × player speed at reach | Ph11 beam rule |
| Density ceilings | mean ≤ 13.3 rounds/s, peak ≤ 30 per half-open 2 s window, ≤ 2 committed attacks (3 in `critical` / `crippled`) | Ph11 convention ("later bosses measure the same way") |
| Escort caps / per launch | 6 Open Space / 4 Assault; 2 per weapon death | Ph11 fortress numbers; F7 |
| Critical | core ≤ 35 % | Ph11 fortress 40 % *(judgement)* |
| EMP | `emp_factor` 0.4 | Ph11 owner choice 6 |

## 5. Testing requirements (both harnesses unless noted)

1. **Engine loss changes movement** (epic must-have): hand-ticked with a fixed request — two engines symmetric turn radii; one engine left ≠ right radius by the configured
   ratio and a net drift toward the dead side; two engines → translation speed 0 and rotation only at the thruster rate. Measured on positions, never the sprite.
2. **Module death disables its attack** (must-have): each weapon part destroyed → its mounts UNPOWERED, no further round / rocket / torpedo from that mount over N s while the
   other weapons still fire; the broadside side goes safe.
3. **Critical ram** (must-have): `critical` with ≥ 1 engine → WIND_UP ≥ its fairness bound, line frozen after the track fraction, boost through + overshoot, the ram box armed
   only in CHARGE, damage = config; boundary: `critical` with both engines dead → no ram ever.
4. **§25** for both tracks on every reachable order (E1 E2 C, E1 C E2, C E1 E2), snapshot from phase-driven state only, a boundary that one engine short of `crippled`
   changes no key of it; `test_boss_phase_rules.gd` finds the Dreadnought.
5. **Interceptors**: launched from the destroyed module's mouth, count / cap / Assault limit, none from a bay killed during the death sequence, scuttled on death, scored via
   `boss_escort_spawned`; the new trigger's rows in `test_boss_reinforcements.gd` and every existing row unchanged.
6. **Free order**: every part is damageable from spawn; shields bubble the protected parts until the generator dies.
7. **Wake**: spawned only behind live engines, damage radius = drawn radius, no damage after the fade threshold, never damages the boss itself; a test container is required.
8. **Torpedo, fan**: lifetime rows (`test_enemy_bullet_lifetime.gd` family), fan spread bit-identical at 1 / 0, pools sized with `pool_period_factor`.
9. **Density** per phase (`hunting`, `listing`, `crippled`, `critical`) in Assault, the Ph11 method.
10. **Roster gates** listed in `1-context.md` → *Dependencies*; hub sweep (draw 22); art sizes and transparency.

## 6. Questions the plan must close (owner choices where marked)

1. Phase structure: two drivers (recommended §3.1 B) — and whether `BossReinforcements` learns a list of drivers.
2. Shields: what the generator protects (recommended: core + engines) and whether more than one generator.
3. **Owner:** interceptor payload (Gatling Interceptor pair default, Razor alternative, or per module).
4. **Owner:** the change to the Ph11 convention "reinforcements stop when their part is destroyed" for opt-in `ON_OWN_DESTROYED` bays.
5. Ram: separate `RamHitBox` + `ram_damage`, or one `collision_damage`.
6. **Owner:** does the wake hurt other enemies (bait-able, IDEAS §18.6) or exempt the boss's owner group?
7. **Owner:** level placement — none (default; Assault harness + `WaveBuilder.dreadnought()` only), level 1 after the fortress, or a later phase (Ph15).
8. Gate time: a gate-room task first (recommended) and per-task allotments; the escalation line stays 237 s.
9. Hub: draw 22 ring and bearing, leash radius, and its pre-approved levers (the fortress is at 4200 / −45°; 135° on 4200 is the mirror and must clear the Heavy Gunship at
   157.5° on 2600 and every trigger / pickup by the sweep).
