# Research — Enemy rework, phase 8: energy weapons, defense turrets and Twin-Laser Drones

Epic `cmug23ona0015m52w4t1m73bc`, research task `cmug23onf0019m52wp7po891o`, 2026-10-27, against `agent/auto-dev` at
`cd1b0b5`. Companion: `1-context.md` (requirements R8.1–R8.25, files, reuse table, conventions, risks, open questions
Q1–Q13). This file holds the **scope check** (§0), the external findings (§1), the candidate approaches with their
tradeoffs and a recommendation each (§2, answers to Q1–Q13 in §2.12), starting values (§3), placement (§4), the gates
the testing requirements turn into (§5) and sizing notes for the plan stage (§6).

Labels: **[source]** = from a finding in §1; **[code]** = read in this repo; **[judgement]** = mine, no citable source,
to be play-tested. Numbers in §3 are *starting values* unless a source is cited.

---

## 0. Scope check

This phase's scope was written before Phases 2–7 ran. Checked against the code, `DECISIONS.md` and the as-built
reports, the following changes or clarifications apply. The plan should carry each one into its coverage table.

| # | Finding | Effect on scope |
|---|---|---|
| **S1** | **The only beam, `LaserRay`, cannot be the family's base.** It is a one-hit kill (`received_damage.emit(9999)`), its phases advance on sprite `animation_finished` (length fixed by frame counts, not hand-tickable), it re-damages with a 0.1 s `Timer` (the brain rule forbids `Timer`s), it is never blocked, and it is not in the `Hazards` registry **[code]** `laser_ray.gd:73,88,118-122,245-264`. It is also load-bearing in three pinned places: the race gauntlet (`race_hazard` contract), level 1's columns and `LaserWallWave`, and the station laser phase (`test_laser_ray_hit_mask.gd`, `test_station_laser_phase.gd`). | Build a **new** beam component beside it (§2.1). `LaserRay`, `StationLaserPhase` and the station stay byte-identical; **the station's migration onto the family is Ph11's** (Space Fortress 2.0), as Ph4 kept the station byte-identical for `homing_point`. The epic's "generalises what the station's laser phase and rotating hull already do" is met by the family *covering* those behaviours (a beam rotated by its host = the hull sweep; a timed volley = the laser phase), not by rewriting the station. |
| **S2** | **Friendly fire for beams is no longer open: the epic decides it** — "every beam damages anything crossing its line, other enemies included" (R8.7). DECISIONS left "blasts and beams" to Ph8 (Ph5 deferred table, Ph6 and Ph7 changes). | Ph8 records the decision for **all energy weapons** (beam, sweep, lance, twin-beam, wall, *and* the Pulse Ring, §2.6) and leaves the rocket and mine blast rules exactly as Ph5/Ph7 decided. The open detail is the **owner set** a beam never hurts (Q4, §2.7). |
| **S3** | **Level 1 already has "temporary laser barriers"** — 11 scheduled `LaserRay` column volleys (warn 3.0 s, active 4.0 s) and a static 12-ray `LaserWallWave` **[code]** `level_1_director.gd:62-87,172-186`, `level_1.tscn:46`. Their mask includes 512, so **they kill AI enemies**, and since Ph2 the AI enemies move freely in the corridor and nothing avoids them. **No test replays them** (level-1 replays drive `WaveManager` only). Whether AI enemies actually die in columns in play is unmeasured. | In scope as a *check*, not a rewrite: measure it (a level-1 replay with the column schedule), then decide (§2.10, Q12). The new laser-wall structure (R8.20) is built on the new family. |
| **S4** | **`HazardInfo` geometry is circles only** (`contains`, `falloff`, `penalty_at`, `Hazards.around`, `Steering.context_avoid` all use centre distance) **[code]** `hazard_info.gd:48-86`, `steering.gd:236-299`. DECISIONS Ph6 promised walls would "join the same registry with no change to the AI" — true for the *registry*, not for the *geometry*: a 400 px wall is not a circle. | A small, gated extension of `HazardInfo` + `context_avoid` for segments (§2.9), keeping Ph6's pass-through and circle results bit-identical. State it in DECISIONS as a change to the Ph6 promise. |
| **S5** | **Enemy beams are direct emitters**, like every beam in the project (global.md: beam, nova, dash, laser ray bypass `EnemyShield` and `ArmorPlate`). Consequences: an enemy beam passes another enemy's projected shield; a plated Ram refuses it in its own `_on_received_damage` (hull rule) and its plates ignore it; the player's own shield charge *does* absorb it (the player's `Shield` lives in `PlayerBase._apply_damage`, not in the absorber slot) **[code]** `player_base.gd:126-140`, `ram_corvette.gd:128-133`. And the **player's** mining beam bypasses the shield generator's bubbles. | Keep the convention (no new damage path). The generator's bubble therefore stops bullets and rockets, not the player's beam — record it as accepted counterplay (an owner option is listed in §2.5). |
| **S6** | **No stationary AI enemy exists** except the bespoke station. A brain-only `BaseEnemy` already works: `_physics_process` ticks the brain and steps a mover only if one exists **[code]** `base_enemy.gd:115-120`; `is_ai_driven()` is false without a mover, so it refuses tows. Static things in Assault drift down at 60 px/s (Wreck, Minefield). | Turrets and structures are brain-only (or brainless) `BaseEnemy`s with **no `EnemyMover`**; the Assault drift is owned by the structure root (the Wreck precedent), which the single-writer gate permits for a moverless root (§2.5). |
| **S7** | **`BulletPool` resolves its container as the grandparent** (`bullet_pool.gd:63`). If turrets were children of a group node, a turret's rounds and rockets would be re-parented under the group (and drift with it in Assault). Container injection has been deferred three times "to the first nested launcher" (Ph2 → Ph5 → Ph10). | Avoid becoming that launcher: the turret group is a **coordinator, not a parent** — members are spawned as direct children of the enemy container (§2.8). Injection stays with Ph10 (Carrier hangars). |
| **S8** | **Out of this phase by the scope line and the roadmap:** mounting turrets on large ships / stations / bosses (Ph10, Ph11), jammer-linked groups (Ph9 jammers, Ph20 linking), `disables_abilities` (Ph9), placed Assault encounter geometry (Ph15), difficulty variants (Ph16), audio (Ph17). | Design the **mount** (§2.5) and the **group link** (§2.8) so those phases plug in without changing them; build none of it. |
| **S9** | **The Ph1 roadmap expected Ph8 to build telegraphs on `AttackController.fire_now`.** A beam is not a pattern + pool: it has its own TELEGRAPH → ACTIVE timeline and its geometry changes every tick. | The beam component owns its telegraph; `AttackController` stays the bullet/rocket driver (burst cannon). No change to `AttackController`. |
| **S10** | **`class_name PulseRing` is taken** by Ph7's visual-only pulse-mine shockwave **[code]** `enemy_ordnance/mines/pulse_ring.gd:5`. | The §11.3 weapon needs another class name (proposal: `EnergyRing`, §2.6). |
| **S11** | **Attack B needs a "controller ship" that is in no roster table** (IDEAS §2 lists none; §1.1's "Controller / Turret" verb is generic). The Carrier (Ph10) and the fortress (Ph11) will also launch drones. | A scope addition the owner should confirm (Q9, §2.4): recommended is a small dedicated launcher ship whose launch API Ph10/Ph11 reuse. |
| **S12** | **Heavy Shell** still has no consumer; Ph4 handed its first use to Ph10 (Heavy Gunship). | The burst cannon fires Pulse rounds; Heavy Shell stays Ph10's unless the plan takes it explicitly for the heavy emplacement and says so in DECISIONS. |
| **S13** | **The player's beam stops at the first layer-1 body and skips that body as a target** **[code]** `beam_behavior.gd:56-91` — a structure whose root sits on layer 1 would block the mining laser and be immune to it (why the station root is on layer 0). | Every new structure root answers `is_laser_blocking() == false` (the ray then treats it as a target) or sits on layer 0; a row pins it. (The same skip seems to apply to every layer-1 enemy root today; that is outside this phase — listed as a follow-up in the run report.) |
| **S14** | **Gate time**: Ph7 closed at GUT 218.44 s of 240 s (2344 tests); `tests/README.md` says Ph8 "should recover time first if it plans more than that". Ph7 added ~16 s net after recovering 13.8 s. | Phase 8 is the largest content phase so far (three enemies, three structures, a weapon family). A gate-room task first, with a hard floor (§6). |
| **S15** | **Every new enemy must join group `enemies` in its own `_ready()`** (placed mines, `pulse_damage` and now beams find victims through it), and **pooled hazards register on `launch()`** (DECISIONS Ph7 gap table). | Applies to the turret, the structures, the drones and the controller; the moving wall registers while it is lit. |
| **S16** | **"Assault waves"** for turrets: no level section today hosts static structures except asteroids/wrecks; DURATION sections only (persistent fire or ordnance must not hold an `ENEMIES_CLEARED` section, the Bomber/Mine Layer rule). | Placement limited to DURATION sections (deep_space, asteroid_belt, planet_approach); guard rows in `test_engagement_deadline.gd` (§4.2). |

---

## 1. Findings from shipped games, tools and engine docs

Gathered by a research subagent (WebSearch / WebFetch, `scripts/fetch-page.sh` for blocked pages) and merged here.
Sources marked *unreachable* in the last paragraph were not used for any number.

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| F1 | **Telegraph = a thin, harmless line on the exact path, then the full beam; the hit zone is narrower and shorter than the art.** Danmakufu's straight laser spawns "a laser with no hitbox … with a smaller width to show where the laser will spawn"; warning lines under ~18–20 px "often" go unseen; tips carry no hitbox (10 % each end) to avoid "cheapshots"; render width ≈ hitbox width causes "accidental deaths". Moon Lord's beam does no damage for its first 0.33 s; Stone Titan shows a targeting laser for its 3 s charge. | Longer warnings are fairer but empty the lane (the player simply leaves); shorter ones threaten more but feel arbitrary. A hitbox the size of the art punishes visually-safe grazes. | Warning 1.0 s (60 f) for a 512 × 24 laser active 0.33 s (lance-like) or 5 s; 2.0 s / 2.0 s for a big beam; boss charge 3 s; damage grace 0.33 s; tips 10 % harmless. | https://sparen.github.io/ph3tutorials/ph3u1l9.html ; https://terraria.wiki.gg/wiki/Moon_Lord ; https://riskofrain2.wiki.gg/wiki/Stone_Titan |
| F2 | **Sweeping beams sweep a bounded arc, start off-target and sweep toward the player, slowly enough that a direction change beats them**; the escapes are crossing during i-frames or moving toward the pivot. Tip speed grows with radius. | A fast sweep forces a *crossing* (costs a hit or needs i-frames/boost); a slow one lets the player outrun the tip. A long beam is much harder at its tip than near the pivot. | Moon Lord 120° over 3 s (40°/s) starting 60° off target; Danmakufu rotating ring 60°/s; Beholster "can't keep up if the player changes direction". Derived: at 420 px/s the tip is outrunnable only within r = v/ω (≈ 600 px at 40°/s, ≈ 400 px at 60°/s). | https://terraria.wiki.gg/wiki/Moon_Lord ; https://sparen.github.io/ph3tutorials/ph3u1l9.html ; https://enterthegungeon.wiki.gg/wiki/Beholster |
| F3 | **Continuous beams either tick small damage or hit once per contact, capped by post-hit i-frames.** | Ticks scale with exposure and can shred if mis-tuned; one hit + i-frames is readable and capped but flattens beam identity. An i-frame window longer than the active time turns any beam into one hit. | Stone Titan 24 ticks × 12.5 % over 3 s (0.125 s/tick); Terraria player i-frames 0.67 s; this project's player 0.5 s **[code]** `player_base.gd:32`. | https://riskofrain2.wiki.gg/wiki/Stone_Titan ; https://terraria.wiki.gg/wiki/Invincibility_frames |
| F4 | **Expanding rings are passed, not outrun**: long obvious wind-up; the ring travels faster than the player, who crosses it through a gap or with a dash/jump. A ring with a (rotating) gap steers the player. | A solid ring with no pass mechanic is unavoidable damage. Gaps turn it into a positioning puzzle. Rings combined with other attacks tax the dodge. | Mithrix: ~1 s crouch, slam at 3 s, ring of 12 waves at 60 m/s for 3 s. "A single gap that rotates over time." No source gives thickness. | https://riskofrain2.wiki.gg/wiki/Mithrix ; https://www.powerpyx.com/returnal-boss-guide-all-bosses/ ; https://itch.io/jam/bullet-hell-v/topic/3751351/bullet-hell-tips |
| F5 | **"Generator powers this turret group; shield tower protects it" ships in real games; a single power point is a known, exploitable weakness.** Desert Pirates: "Every turret or group of turrets are tied to an ENERGY GENERATOR"; destroying it removes them permanently; shield towers must fall first. StarCraft II: a destroyed Pylon powers structures down; Blizzard advises several Pylons for redundancy. Helldivers 2 bunker turret: two slow shots then ~5 s cooldown. | One source per group = a clear, high-value objective, but trivialises the group once found; redundancy/overlapping shields are robust but less readable. Accurate lead is lethal to an evader and needs a cadence limit or deliberate error. | Groups tied to one generator; shields gate the generator; up to 4 shield generators per outpost (Halo Wars 2); turret cadence 2 shots / 5 s (Helldivers). | https://www.gamedeveloper.com/design/enemy-settlements-mechanics-for-car-games ; https://strategywiki.org/wiki/StarCraft_II:_Wings_of_Liberty/Protoss_structures ; https://news.blizzard.com/en-us/article/5963105/game-guide-protoss-photon-cannons ; https://helldivers.wiki.gg/wiki/Bunker_Turret ; https://halopedia.org/Banished_shield_generator |
| F6 | **A beam is tied to its emitter: kill the emitter, the beam ends** (Moon Lord's beam "vanishes if the head eye is killed"; Gungeon lasers are cancelled at "the origin point"). Linked-enemy designs exist in indie shmups. **No shipped twin-drone `\|---\|` fence was documented.** | Collapse-on-death rewards focus fire but makes fragile ends trivial; a beam surviving one end is confusing. A rigid pair reads; a stretching beam changes its threat zone unpredictably. | Rule only; fixed separation, own warning phase and "pair slower than the player crosses it" are **[judgement]**. | https://terraria.wiki.gg/wiki/Moon_Lord ; https://enterthegungeon.wiki.gg/wiki/Blasphemy ; https://kasoof.itch.io/owww-outer-world-wide-web |
| F7 | **Godot 4: `area_entered` fires once per overlap start and overlap lists refresh once per physics step; `RayCast2D` reports only the closest hit; `ShapeCast2D` / `intersect_shape` report many (default 32) at higher cost; space queries are safe only in `_physics_process`.** GDQuest's laser = `RayCast2D` + `Line2D`, width tween 0.2 s in / 0.1 s out; anti-aliased `Line2D` is not batched. | Area2D beams are cheap but go silent on a target that stays inside (needs polling); a ray gives the cut-off point (cover) but one target; a shape cast gives width and many targets at more cost — and none of them is hand-tickable outside a physics step. | `max_results` 32; GDQuest `max_length` 1400, cast 7000 px/s. | https://docs.godotengine.org/en/stable/classes/class_area2d.html ; https://docs.godotengine.org/en/stable/classes/class_raycast2d.html ; https://docs.godotengine.org/en/stable/classes/class_shapecast2d.html ; https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html ; https://www.gdquest.com/library/laser_2d/ ; https://docs.godotengine.org/en/stable/classes/class_line2d.html |
| F8 | **Enemy friendly fire needs rules to stay controlled.** Doom infighting comes from attackers that don't hold fire plus retaliation; it is limited by same-species immunity to projectiles ("but not hitscan") and a target threshold; Heretic/Hexen exempt bosses. | Baiting and ammo-saving emerge, but enemies can kill each other faster than the encounter intends (pacing, `ENEMIES_CLEARED` emptied early, a group stripping its own protection). | Species immunity; threshold 100 decrementing per step. | https://doomwiki.org/wiki/Monster_infighting (read via a Wayback snapshot) |

**Unreachable** (WebFetch and `fetch-page.sh` both failed; nothing taken from them): doomwiki.org direct (read via
Wayback instead), doom/starcraft/everspace fandom wikis, zdoom.org, liquipedia (Pylon, Shield Battery), the Construct 3
turret manual, giantbomb, zeldawiki, the StrategyWiki Pylon page, the Mindustry power-node page. Kain Shin's predictive-aim
article and the GDC 2017 "Predictable Projectiles" talk were seen only as search snippets; **no number here comes from
them**.

What the findings change, in one line each:
- F1 → every beam kind has a harmless warning line ≥ 3 px drawn (≥ 20 px in Touhou's 384 px field ≈ a clearly visible
  line at our scale), a hit half-width < the drawn half-width, harmless tips, and a short damage grace after ignition.
- F2 → a sweep starts off-target and turns *toward* the player; a gate inequality caps tip speed (`ω · length`) against the
  player's cruise speed per mode.
- F3 + this project's 0.5 s i-frames → one hit per target per `rehit_interval` (≥ 0.5 s) for both sides; the lance hits once.
- F4 → the Pulse Ring is short-range with gaps (we have no jump; boost is the dash).
- F5 → one power source per group (clear objective) **plus** a shield generator that also covers the power source, so the
  source is not a free win; no redundancy in this phase (Ph20's jammer link is the natural redundancy lever).
- F6 → collapse on either endpoint's death; fixed length with a tolerance; a separate warning phase.
- F7 → a geometric hit scan, hand-tickable, plus an optional physics ray for cover (real-physics rows only).
- F8 → an owner set the beam never hurts (emitter, its pair, its own structure group); no retaliation AI.

---

## 2. Candidate approaches

### 2.1 The beam component (R8.1–R8.3, R8.5–R8.7; Q1, Q2)

**Q1 — new component or convert `LaserRay`?**

| Option | For | Against |
|---|---|---|
| A. Convert `LaserRay` | One beam in the project | Its 9999 kill, animation-clocked phases, `Timer`, race contract and three pinned users all have to change or be kept behind flags; the station and race tests become this phase's blast radius. |
| **B. New `EnemyBeam` beside it (recommended)** | Hand-tickable from the owner's `tick()`, damage per kind, geometry free per tick (sweep, twin endpoints, wall), registry and cover built in; `LaserRay` untouched. | Two beam implementations until Ph11 migrates the station (and Ph15 possibly the level columns). |

**Shape of B** (names are proposals for the plan):
- `assault/scenes/projectiles/enemy_beams/` (the rockets / ordnance precedent), `EnemyBeam extends Node2D`,
  `enum Kind { BEAM, SWEEP, LANCE, TWIN }` (append-only), `enum Phase { OFF, TELEGRAPH, ACTIVE, FADE }`.
- **Two geometry sources:** *emitter* beams (origin = the node's global position, direction = its global rotation or a
  set direction, `length`), and *endpoint* beams (`set_endpoints(a, b)` every tick — twin drones, wall posts). The station
  hull sweep is the emitter case with a rotating parent.
- **Owner-driven clock:** `start(telegraph_s, active_s)`, `tick(delta)` called by the owner's brain (no `Timer`, no
  `_process` clock; a self-ticking fallback for scene-placed walls, the Minefield/PulseRing precedent), `cancel()`
  (TELEGRAPH → OFF at once; ACTIVE → FADE), signals `phase_changed(phase: int)`, `target_hit(target: Node2D, damage: int)`.
- **Tuning in the scene's exports** (the Ph5/Ph7 rule): `damage`, `rehit_interval`, `hit_half_width`, `draw_half_width`,
  `tip_grace` (fraction), `ignite_grace` (s), `telegraph_seconds`, `active_seconds`, `fade_seconds`, `length`,
  `blocked_by_cover`; one scene per kind (`beam.tscn`, `sweep_beam.tscn`, `lance.tscn`, `twin_beam.tscn`), and an
  `EnemyBeamScenes.scene_for(kind)` / `export_of()` helper so gates read numbers from scenes, never typed.
- **Drawing:** `Line2D` core + glow (the `PiercingBeam` / `RailTrail` / `MineWake` precedent), a thin telegraph line during
  TELEGRAPH, width tween at ignite/fade (F7: 0.2 s in / 0.1 s out). Not anti-aliased (F7, batching).

**Q2 — hit detection.**

| Option | For | Against |
|---|---|---|
| Area2D + re-emit loop (LaserRay) | Exact shapes | `area_entered` once; overlap lists only refresh on a physics step (F7) → stale on hand-ticked tests and on a beam moved this tick; a moving segment means rebuilding the shape transform every tick. |
| Physics shape cast / `intersect_shape` | Exact shapes, many hits | Physics-step only (F7) → every beam row must run real physics; more cost per beam per tick. |
| **Geometric scan (recommended)** — segment (swept, see below) vs each candidate's hurtbox shape over groups `player` + `enemies` (+ `asteroids`, Q4) | Deterministic and hand-tickable (the dual-harness rows stay hand-ticked); the exact precedent of `BeamBehavior` (group scan, perpendicular distance) and `Hazards.pulse_damage` (group scan, both sides); cost = O(group size) per active beam per tick, tiny at our counts. | Must read each hurtbox's own shape (circle / rect / capsule × scale) to be exact — a centre-distance test like `pulse_damage` would miss the Bomber's 96 × 44 wings. A ray is still needed for **cover** (§2.10), which only runs on real physics. |

**Tunnelling** (1-context risk): test the **swept area** between the previous and the current segment (the quad
`a0 b0 b1 a1`) as well as the current segment, so a target inside the quad was crossed this tick. A twin wall at
500 px/s moves 8.3 px per 60 Hz tick and a 560 px sweep at 0.7 rad/s moves its tip 6.5 px — both below the smallest hurtbox
radius (~12 px), but a fast boost or a long boss beam would not be. **[judgement]**

**Damage** (F3, Q5): direct emit `HurtBox.received_damage.emit(damage)` (S5), at most once per target per
`rehit_interval` (a per-beam dictionary keyed by instance id, cleared at FADE). With `rehit_interval ≥ 0.5 s` the player's
i-frames and an enemy's lack of them see the same cadence — the same beam is equally dangerous to both sides. The Lance has
`rehit_interval = INF` (one hit per activation).

**Recommendation:** B + geometric swept scan + per-target re-hit; physics only for the cover clip.

### 2.2 Telegraph timing and fairness (R8.1–R8.3, R8.24)

- TELEGRAPH draws the exact line (F1) and lights the emitter's `StateLight` CHARGING (yellow); the Lance's last 0.5 s is
  COMMIT (white, "locked shot", IDEAS §21.1); ACTIVE is ARMED (red). Off-state is OFF. This reuses `StateLight` unchanged.
- `ignite_grace` (F1, Moon Lord 0.33 s; ours 0.1 s **[judgement]**, since our warning is the line itself): ACTIVE but not yet
  lethal while the width tweens in.
- **A gate-asserted fairness inequality per kind, read from scene exports** (the Ph7 mine warning-rule precedent):
  - *Static beams:* `telegraph_seconds ≥ reaction (0.25 s) + (hit_half_width + player_radius) / cruise_speed` — the player can
    leave the lane it is standing in. At Assault cruise 360 px/s, half-width 14 + player ~20 → ≥ 0.35 s; the starting value
    (0.9 s) passes with a wide margin; the inequality exists to stop a later tier (Ph16) dropping below it.
  - *Sweep:* `sweep_rate · length ≤ cruise_speed` of the slower mode (Assault 360 px/s) — the tip never outruns cruise (F2).
    Station precedent for contrast: 0.5 rad/s × 1536 px = 768 px/s — a boss beam, deliberately out of this rule (Ph11).
  - *Lance:* `telegraph_seconds − commit_seconds ≥ 0` and `commit_seconds ≥ 0.5` — the Ph4 "reactable floor" (`lock_seconds`).
  - *Twin / wall:* `advance_speed < cruise_speed` per mode, and `length/2 / cruise_speed + reaction ≤ telegraph_seconds +
    (approach distance / advance_speed)` — the player can reach an end before the wall arrives (F6, "slower than the player").
- Tests assert the **timeline** (not lethal at TELEGRAPH end − ε, lethal at ACTIVE + `ignite_grace` + ε, not lethal after
  FADE) in both harnesses — R8.24 "beam activation and telegraph timing".

### 2.3 Sweeping Beam and Lance (R8.2, R8.3)

- **Sweep:** an emitter beam whose owner rotates its mount by a signed `sweep_rate` for `active_seconds` over `sweep_arc`;
  the start bearing is `aim ± sweep_arc/2`, on the side the player is moving *from*, so the sweep travels **toward and
  through** the player (F2). The mount, not the beam, rotates (a turret's `Mount`; Ph10/Ph11 host the same scene on a
  module or a hull, which is the station's "rotating hull" case).
- **Lance:** aim → lock (mount frozen on `TargetInfo.intercept` at lock, the Sniper rule) → ACTIVE ≤ 0.25 s, one hit, high
  damage. The Sniper's rail round stays the Sniper's; the lance is the turret/emitter equivalent and needs no projectile
  (no lifetime row).

### 2.4 Twin-Beam pair, Attacks A and B, the controller (R8.5, R8.6, R8.14–R8.18; Q9)

**Rig, not two free movers (F6).** A `TwinLaserPair` coordinator (RefCounted, the `SquadController` precedent) holds the
two drones, the rig length `L`, and a frame (centre `C`, axis `u`, normal `n`). Each drone's brain requests its slot
`C ± u·L/2` (feed-forward frame velocity + a spring on the slot error). During a **committed advance** both drones run
**identical `mover.boost(n, advance_speed, duration)`** calls on the same tick: separation is then exact by construction
(drift aside), and DECISIONS Ph6 already names "the Ph8 twin-laser sweep" as a `boost()` user that skips avoidance.

**Length stability (R8.15, R8.24):** the beam is lethal only while both drones are alive, not suspended, and
`| |A − B| − L | ≤ length_tolerance`; outside it the beam *strains* (flicker) and after `strain_seconds` collapses to
FADE. This makes the counterplay emergent rather than scripted:
- kill a drone → collapse at once (F6);
- a gravity well's drift (it still applies during `boost()`) pulls one end → strain → collapse, or the pair is dragged
  in (R8.17 "bait … into a gravity well");
- a wreck body stops one drone (`move_and_slide`) → strain → collapse ("terrain"); a wreck between the ends clips the beam
  (§2.10);
- the beam hits other enemies on its line (R8.17 "use the beam to damage the enemy formation").

**Beam ownership:** the `EnemyBeam` (TWIN) is a child of drone **A** (top-level drawing), fed `set_endpoints(A, B)` each
tick by A's brain; if A dies the beam goes with it, if B dies A's brain sees the partner invalid and cancels. One owner
at every instant.

**Attack A — closing laser:** set the frame across the player's position offset by `standoff` on the drones' side
(`C = P + n·standoff`, `u ⟂ n`), move to the slots (APPROACH/ALIGN), TELEGRAPH the line, then ADVANCE through `P` along `−n`
for `standoff + overshoot`, then BREAK (separate, re-form). In Assault the rig is horizontal above the player and advances
down (or vertical beside and advances across), clamped to the corridor's inner rect where the constraint is identity
(R8.18).

**Attack B — V-launch → moving wall:** the controller launches both drones on diverging boosts (the V) toward `Q± = P̂ ±
u·L/2`, where `P̂` = the player's predicted position at `lead_time` along its velocity (a standing player: along its
facing), `u ⟂` the player's heading — i.e. the wall is placed **across the escape route** (IDEAS: "cuts off escape routes
rather than simply aiming at the current player location"); on arrival (or a timeout) ALIGN to `|---|`, TELEGRAPH, then
ADVANCE toward the player as one rig. Prediction horizon: the undamped wall lead the Bomber's mine wall and the Mine Layer
use for persistent walls (DECISIONS Ph4: "a persistent wall is not an aimed shot"), capped.

**Q9 — the controller ship.**

| Option | For | Against |
|---|---|---|
| **Dedicated small launcher ("Laser Tender", ~96 px) (recommended)** | One clean verb ("kill it before it relaunches"); keeps every Ph2–Ph7 ship's identity; its `launch_pair(points)` API is what Ph10's Carrier hangars and Ph11's fortress reuse. | A new roster entry the IDEAS table does not name — owner confirmation (S11). |
| Missile Corvette variant (tubes launch drones) | No new ship | Muddles a finished specialist's identity and tested salvo logic. |
| A structure ("drone bay") | Fits the structure theme | Static; Attack B wants "toward predicted points around the player's path", which a static bay reaches poorly in Open Space. |
| Defer Attack B | Smaller phase | Drops an in-scope requirement (R8.16). |

The tender holds medium range (the Missile Corvette's HOLD_ARC idea, not its code), carries one docked pair (visible on
the hull — its §23 state change), launches only when it has no live pair, re-arms after `rearm_seconds`, and has no gun.
Pairs can also be spawned **without** a tender (waves / hub) and then only run Attack A.

**Drone body:** a small `BaseEnemy` (28–32 px art, body r ≈ 13), `ContactProfile.COLLISION`, low HP (one or two
Standard shots — the "destroy one drone" counterplay must be cheap enough to matter), `hazard_resistance` low (they are
the well-bait), `accepts_tow()` false in ALIGN/TELEGRAPH/ADVANCE.

### 2.5 Stationary Defense Turret (R8.8–R8.13; Q10)

- **Root:** `DefenseTurret extends BaseEnemy`, **no `EnemyMover`** (S6), body circle on layer 1 so ships bump it, root
  answers `is_laser_blocking() == false` (S13), `ContactProfile.NONE` (a base does not ram; `collision_damage` 0, exempt
  from the contact-damage roster as `no_hitbox`, the Bonus Drone precedent — or a 0-damage box; the plan picks one).
- **Mount (the Ph10 seam):** a child `TurretMount` (Node2D) that owns aim (turn-rate-limited rotation of itself only),
  muzzles, the weapon node and its telegraph. The brain asks the mount to aim/fire; the mount never reads its host's
  type. Ph10 mounts the same scene on a ship module; Ph11 on the fortress. The single-writer gate is satisfied because
  only a child's rotation is written.
- **Variants (R8.10)** — `enum Variant { BURST_CANNON, SWEEP_BEAM, ROCKET_BATTERY, PULSE_RING, LANCE }` (append-only), one
  mount scene per variant (`TurretMountScenes.scene_for(variant)`):

  | Variant | Weapon (reused) | Cycle |
  |---|---|---|
  | Burst cannon | `AttackController` + Pulse rounds pool (Ph3), `BurstClock` | TRACK → CHARGING 0.4 s → burst → cooldown |
  | Sweeping beam | `EnemyBeam` SWEEP | TRACK → TELEGRAPH (line at start bearing) → ACTIVE sweep → cooldown |
  | Rocket battery | `EnemyRocket` DUMB/PURSUIT pools, `persist_after_owner_death` (Ph5; `launch_velocity()` = zero, `rocket_clear_radius()` = body) | TRACK → tube glow → salvo of 2 → cooldown |
  | Pulse ring | `EnergyRing` (§2.6) | idle until the player is inside `trigger_range` → charge → ring → cooldown |
  | Lance | `EnemyBeam` LANCE | TRACK → lock (COMMIT) → strike → cooldown |

- **Predictive aim (R8.9, F5):** aim point = `lerp(P, TargetInfo.intercept(muzzle, shot_speed).point, lead_blend)`
  (partial lead, `lead_blend` 0.6), mount `turn_rate` capped, fire only inside `fire_cone`; beams aim at the intercept at
  their *telegraph* start, never re-aim during ACTIVE (except the sweep's own rotation). Line of sight via
  `EnemyBrain.can_see_player()`; a blocked turret holds fire (§28 precedent), except the rocket battery (rockets curve —
  the Missile Corvette rule).
- **Idle (IDEAS §18.5 "turret scanning arcs"):** with no player inside `perceive_radius`, the mount scans a slow arc;
  NOTICING → TRACK on perception (no `AnchorIdle` needed — nothing moves). Phase enum proposal:
  `{ SCAN, TRACK, TELEGRAPH, FIRE, COOLDOWN, UNPOWERED }`. `accepts_tow()` is moot (no mover → `is_ai_driven()` false).
- **Heavy emplacement (R8.8, 128–192 px):** the same script with a larger body, more HP and **two mounts** (e.g. sweep +
  burst), as its own scene/dir. **[judgement]** IDEAS says "can act as"; the plan may defer it to Ph10 if the phase is
  too large — say so in the coverage table.
- **Q10 — Assault:** "static hazards in the scrolling corridor" = the Wreck/Minefield rule: the root drifts down at
  60 px/s (owned by the root, moverless) and frees itself below the projectile world rect; no engagement budget (it leaves
  by drifting). Fire limited to inside `view_rect()` (the Support Ship's view-clamp precedent) so a turret never shoots
  from off-screen.

### 2.6 Pulse Ring (R8.4; S10)

- `EnergyRing` (Node2D, class name chosen to avoid Ph7's `PulseRing`): an annulus expanding from the emitter at
  `ring_speed` to `max_radius`, thickness `band`, with `gap_count` gaps of `gap_deg` (optionally rotating, F4); a target is
  hit **once per ring** when `| d − r | ≤ band/2 + target_radius` and its bearing is not in a gap. Owner-ticked, drawn with
  arcs, tuning in scene exports.
- **Telegraph:** a charge glow on the emitter plus a faint circle at `max_radius` for `telegraph_seconds` (F4: "long, obvious
  wind-up").
- **Counterplay without a jump:** stay outside `max_radius` (it is short-range — "forces movement around the enemy"), slip
  through a gap, or boost across the band (band 24 px at ring 360 + boost 700 px/s is crossed in ~0.02 s — still one hit if
  overlapped on a scan tick; gaps are the clean pass). **[judgement]**
- **Friendly fire:** same owner-set rule as beams (Q4) — the ring is an energy weapon, not a Ph5 blast.

### 2.7 Friendly fire and the owner set (R8.7; Q4, Q8)

| Option | For | Against |
|---|---|---|
| (a) Hit everything except the emitter | Literal reading of R8.7 | A sweeping turret beheads its own power source and generator; a turret ring kills its neighbour (F8: uncontrolled). |
| **(b) Hit everything except the *owner set* (recommended)** = the emitter, its twin partner and its controller, and its own structure group's members | R8.7 holds for every *other* enemy (formations, escorts, patrols, the drones' victims); Doom's species immunity analogue (F8); group placement stays authorable | One rule more; a player cannot bait a group into destroying itself (they bait *other* enemies into it instead). |
| (c) Player only | Simplest, LaserRay-station precedent | Contradicts R8.7. |

- Victims: groups `player` and `enemies`; **asteroids** (group `asteroids`) also take beam damage **[judgement]**, matching
  the player's beam and rocket impacts; enemy ordnance (mines, rockets) is not in `enemies` and is not hit (no shoot-down of
  ordnance by beams in this phase — owner option).
- Armour: a plated Ram refuses (hull rule), its plates ignore it; the station refuses while armoured (unchanged).
- **Q8 — scoring:** a kill by an enemy beam sets `was_killed` and scores like any kill; rocket-impact kills already do (Ph5)
  and level-1 column kills do. Keep it: no kill-attribution system exists, and building one is out of scope. Record it.

### 2.8 Turret groups, shield generator, power source (R8.11, R8.12, R8.19; Q3, Q11)

**Q11 — group shape.** A `TurretGroup` scene (Node2D) authored with `Marker2D` slots (member kind + facing); in `_ready()`
it spawns its members **as siblings in its own parent (the enemy container)** at the slot positions, deferred, and then
only coordinates: membership via `tree_exiting`, power and shield state, fire staggering. Members are direct container
children, so `BulletPool`'s grandparent rule, `enemies`, `ScoreTracker` and every roster gate see ordinary enemies (S7). A
group frees itself when its last member leaves (the Minefield precedent). In Assault the group node drifts with its
members (or simply stops mattering once they leave). Rejected: members as children (S7, the nested launcher); a pure
static registry (no authoring surface).

**Q3 — structures as `BaseEnemy`s.** The shield generator and the power source are **`BaseEnemy`s with no brain** (or a
trivial one): they are targets the player is meant to prioritise, they must be scored, be in `enemies` (beams, placed
mines, `pulse_damage`), and get every roster gate for free. Rejected: `Wreck`-like structures (not in `enemies`, no score,
no `died`). Each needs `ContactProfile.NONE`, `is_laser_blocking() == false`, a hurtbox covering its body, and the
generic lethal-flow row in `test_base_enemy.gd`.

**Power (R8.12):** the power source *powers* the group: on its `died`, the group calls `set_powered(false)` on every live
member in the same tick (turrets → UNPOWERED: cancel a telegraph, fade an active beam, stop bursts, lights OFF, mount
droops — a §23 visual state; in-flight rockets and rounds persist under their pools' existing rules). Unpowered turrets
stay **dark, harmless and destructible** (they still score and still count toward clears); they never restart. A group
with no power source is always powered. **[judgement]** Option for the owner: Desert Pirates-style destruction instead of
dark (F5).

**Shield generator:** sustains a 360° `EnemyShield` bubble (`sustain_mode`) on each powered member **including the power
source** (so the source is not a free win — F5's single-point weakness), through the Support Ship's
`ProjectedShield` path (`attach` before `add_child`, `sustain()` every tick, lapse after `heartbeat` when the generator dies
or loses power). It does not shield itself. Visible cyan tethers generator → member (Support tether precedent), amber power
lines source → member (F5 readability, **[judgement]**). Bubbles stop bullets and rockets (absorbed hits consume bullets),
not beams (S5).

**Overlapping fire lanes (R8.11):** slots on a ring around the group anchor with mounts' rest bearings outward, and a
coverage rule tested geometrically: for every bearing around the group anchor at the turrets' engagement range, at least
**two** turrets have range and line of sight (no single safe direction). Fire staggering: group members do not start a
telegraph on the same tick (offsets of `stagger` 0.3 s) **[judgement]** so overlapping fire stays readable.

**Ph9 / Ph20 seam:** `set_powered(on)` and the group's "power providers" list are the only coupling; a jammer joins as a
second provider in Ph20 (redundancy, F5's StarCraft lever) without changing turrets.

### 2.9 Segment hazards (R8.20, R8.21; S4, Q7)

| Option | For | Against |
|---|---|---|
| **`HazardInfo` gains segment geometry (recommended)**: `segment_half: Vector2` (ZERO = circle); `contains`, `Hazards.around` use distance to the segment; `context_avoid` adds, for a segment info only, danger over the bearing span between the inflated endpoints (plus the closest-point cone). | One entry per wall; a moving / rotating wall updates two vectors; circles untouched (branch on `segment_half != ZERO`), so Ph6's pass-through and avoidance rows stay bit-identical. | Touches `Steering.context_avoid` — the code every mover-driven enemy runs; needs new unit rows. |
| Bead chain (N circles of radius ≈ band + pad spaced ≤ radius) | No change to `Steering` / `HazardInfo` | N registry entries per wall updated every tick for the moving wall; gaps if spaced wrong; claims meaningless. |

Registration: `kind = &"laser_wall"`, while TELEGRAPH or ACTIVE (a temporary barrier unregisters when OFF; the
twin-drone wall registers while lit, with `velocity` = rig velocity so the avoidance stage leads it — the Ph7
`carry_velocity` lesson). The drones themselves skip their own wall (the Ph6 "own claimed blocker" skip, generalised to
`HazardInfo.source` in the owner set). `avoid_weight` 1.0 for static walls, lower for the moving wall **[judgement]**, so
enemies mostly avoid barriers but a formation can still be caught by a twin sweep (R8.17).

### 2.10 Laser walls, temporary barriers and cover (R8.20; Q6, Q12)

- **`LaserWall` structure:** two `LaserEmitter` posts (`BaseEnemy`, destructible, high HP — shoot a post, the wall drops:
  the same F6 rule as the twin drones) and one `EnemyBeam` (TWIN geometry) between them. `mode = STATIC` (always lit after
  its first telegraph) or `CYCLE` (temporary barrier: OFF → TELEGRAPH → ACTIVE → FADE with `on_seconds` / `off_seconds` —
  IDEAS §6.6's "pulsed … movement windows" idea applied to walls). A wall can be a `TurretGroup` member, so a power source
  drops it (R8.12 + R8.20 combined in the hub site, §4.1). Orphan art `laser_wall.png` (92×84) is a candidate post sprite
  after a transparency check.
- **Q6 — cover:** beams stop at line-of-sight blockers (`LineOfSight`'s opt-in rule: group `asteroids`, or
  `blocks_line_of_sight()` — wrecks) via a physics ray from each end, so a twin or wall beam split by a wreck leaves a
  shadow behind it. This matches Ph6's "two-sided cover" (enemy rounds stop on wrecks) and the player's beam. Real-physics
  rows only (F7); the plain-geometry rows stay hand-ticked with no blockers in the world.
- **Q12 — level 1's existing LaserRay columns:** first *measure* whether AI enemies die in them (a level-1 replay with the
  column schedule, 8× clock). If they do: give `LaserRay` an opt-in `registers_hazard` export (default false; race and
  station unaffected) that registers a `&"laser_wall"` segment while warning/active, and turn it on for level 1's columns
  and `LaserWallWave`. If they do not (columns and enemy lanes rarely cross), leave level 1 alone and hand it to Ph15.
  Either way the level-1 density and deadline gates must stay green.

### 2.11 Art (R8.22)

Strict top-down, faction palette (dark hull, cool edge light, red/maroon accents), state shown only by lights and moving
parts (§21.1, §23). Proposed set (sizes from IDEAS §21.3 / §22):
- Turret **base** 64–72 px + one **head** sprite per variant (≈ 40–56 px; rotates separately — the station turret is one
  64×64 sprite, but a rotating head on a fixed base reads aim direction at a glance). Destroyed/unpowered states: dark head,
  lights off (no extra generation needed if done by `modulate` on the head only — the faction hull keeps its colour).
- Heavy emplacement 144 px base + two heads.
- Shield generator ~72 px (cyan emitter dish — the Support Ship's colour language), power source ~80 px (reactor core with
  an amber glow that dies on destruction).
- Laser emitter post ~40 px (candidate: orphan `laser_wall.png`).
- Twin drone 32 px (emitter lens lit red when the beam is up — its §23 state), Laser Tender ~96 px with two visible docking
  cradles (empty after launch — its §23 state).
- Beams, rings, telegraph lines and tethers are code-drawn (`Line2D` / `draw_arc`), not generated.

### 2.12 Recommended answers to `1-context.md`'s open questions

| Q | Recommendation | Where |
|---|---|---|
| Q1 | New `EnemyBeam` family beside `LaserRay`; station migration is Ph11's. | §2.1, S1 |
| Q2 | Geometric swept segment scan over `player` / `enemies` / `asteroids`, exact hurtbox shapes; physics ray only for the cover clip. | §2.1 |
| Q3 | Shield generator, power source and laser-wall posts are brainless `BaseEnemy`s in `enemies`. | §2.8 |
| Q4 | Hit everything except the owner set (emitter, twin partner, controller, own structure group); asteroids yes, ordnance no; Pulse Ring follows the same rule. | §2.7 |
| Q5 | One hit per target per `rehit_interval` ≥ 0.5 s for both sides; Lance one hit; numbers in §3. | §2.1, §3 |
| Q6 | Yes — beams stop at LOS blockers (wrecks, asteroids). | §2.10 |
| Q7 | Segment geometry on `HazardInfo` + a segment branch in `context_avoid`; circles bit-identical. | §2.9 |
| Q8 | Beam kills score like any kill; record it. | §2.7 |
| Q9 | A small dedicated Laser Tender (owner to confirm); pairs also spawn standalone for Attack A. | §2.4 |
| Q10 | Drift 60 px/s with the corridor (Wreck rule), fire only inside `view_rect()`, DURATION sections only. | §2.5, §4.2 |
| Q11 | `TurretGroup` coordinator that spawns members as container siblings; not a parent. | §2.8 |
| Q12 | Measure level 1's columns first; opt-in `registers_hazard` on `LaserRay` if AI enemies die in them; else Ph15. | §2.10 |
| Q13 | Rosters in §5; gate-room task first with a ≥ 15 s floor. | §5, §6 |

---

## 3. Starting values (judgement unless a finding is cited)

Player reference: HP 50, 0.5 s i-frames, cruise 420 px/s (Open Space) / 360 px/s (Assault), boost ≈ 700 px/s.
Damage references **[code]**: Pulse round 8, Gatling round 4, Heavy Shell 20, rail round 28, Dumb rocket blast 16,
mine blast 30.

### 3.1 Beam kinds

| Kind | Telegraph | Active | Hit / draw half-width | Length | Damage / rehit | Notes |
|---|---|---|---|---|---|---|
| Beam | 0.9 s (F1: 1.0 s) | 1.2 s | 12 / 16 px | 700 px | 10 / 0.5 s | `ignite_grace` 0.1 s, tips 10 % harmless (F1) |
| Sweep | 0.9 s at the start bearing | 2.0 s over 100° (0.87 rad/s) | 10 / 14 px | 400 px | 10 / 0.5 s | tip 349 px/s ≤ Assault cruise 360 (F2 rule); starts 50° off target, sweeps toward the player |
| Lance | 1.0 s (aim 0.5 + lock/COMMIT 0.5) | 0.2 s | 8 / 10 px | 1100 px | 24 / once | Ph4 reactable floor; F1's 0.33 s active lance |
| Twin / wall | 0.8 s (ALIGN complete) | ≤ 3.0 s advance | 10 / 14 px | rig L 420 px (tolerance 16 px, strain 0.15 s) | 12 / 0.5 s | advance 240 px/s (< 360), standoff 260 px, overshoot 200 px |

### 3.2 Pulse Ring
Charge 0.8 s + max-radius circle; `ring_speed` 360 px/s; `max_radius` 280 px (0.78 s); band 24 px; 2 gaps × 45°, rotating
30°/s; damage 12 once per ring; turret trigger range 300 px; cooldown 3.5 s.

### 3.3 Turrets (standard ≈ 64 px; heavy ≈ 144 px)
HP 90 (heavy 260); `perceive_radius` 900 px Open Space; mount turn rate 2.0 rad/s (heavy 1.2); `lead_blend` 0.6; `fire_cone`
8°; scan arc 90° at 0.4 rad/s. Burst cannon: 4 Pulse rounds at 0.12 s gap, 300 px/s, CHARGING 0.4 s, cooldown 2.2 s
(F5's slow cadence spirit). Rocket battery: salvo 2 (DUMB, 1-in-3 PURSUIT), cooldown 5.5 s. Lance: cooldown 4.0 s, range
1100 px. Sweep: cooldown 3.5 s, range 400 px. Pulse ring: §3.2. Assault drift 60 px/s.

### 3.4 Structures
Shield generator HP 120, bubble capacity 50 / regen delay 3 s / regen 2 s / reboot 5 s (Ph5 projected shield: 40 /
3 / 1.5 / 4), radius = member body + 8. Power source HP 150. Laser emitter post HP 140. Group: 2–4 turrets, stagger 0.3 s,
coverage rule ≥ 2 turrets per bearing.

### 3.5 Twin drones and the Laser Tender
Drone HP 30 (**[code]** `assault/scenes/player/weapons/modes/*.tres`: Standard 50, Sniper 40, Spread 25, Gatling 14 per
round — so one Standard or Sniper shot, two Spread pellets or three Gatling rounds: the "destroy one drone" counterplay
costs one or two hits as intended), body r 13,
`max_speed` 300, acceleration 900, `hazard_resistance` 0.1, `hazard_avoidance` 0.6. Tender HP 160, `preferred_range` 650,
`max_speed` 200, `rearm_seconds` 7.0, launch boost 520 px/s over ≤ 1.4 s, `lead_time` ≤ 1.5 s, one live pair. Hub radii
(perceive / lose) sized by the Ph4 inequality (the cycle's farthest actor–player distance + margin).

---

## 4. Placement

### 4.1 Open Space hub (R8.23)
- **A defense site** guarding the `TacticalSpace` derelict structures (station module (2457, 1203), cargo platform
  (2495, 1033), satellite (2588, 887)) **[code]** `sector_hub.tscn`: one `TurretGroup` of 3 turrets (burst cannon, sweeping
  beam, rocket battery) + a shield generator + a power source, plus one **temporary laser barrier** between two structures
  as a group member — so the hub shows every Ph8 structure rule once, and the player can lure patrols into the barrier and
  the site's fire (R8.17, R8.21). Exact position is a plan decision; `test_sector_hub_patrol.gd`'s sweep needs
  `_element_radius()` cases for `TurretGroup` (max member engagement range) and `LaserWall` (half length + band), and the
  site must clear the player spawn, pickups and `MissionTrigger`s by the existing margins.
- **A Laser Tender** as draw 16 and **a standalone twin pair** as draw 17 on a ring (appending after draw 15 keeps every
  earlier seed); their idle uses `AnchorIdle` (the drones idle as a docked pair beside the tender, or as a slow rig orbit
  when standalone).

### 4.2 Assault, level 1 (R8.23)
- DURATION sections only (S16), inside existing waves (the Ph5/Ph7 rule that no other wave's effective trigger moves).
  Candidates: a 2-turret group (burst + lance) in **asteroid_belt** (30 s, no AI enemy waves to crowd **[verify in the
  plan]**), a standalone twin pair in deep_space, a Laser Tender in planet_approach.
- Rows: turrets/drones/tender counted in the frozen specialist density gate (2.5×) or a separate structure row; an
  attack-in-budget row for the pair and the tender (one attack per life); drift-exit row for turrets (they leave the
  corridor by drifting, within a computed time); "no `ENEMIES_CLEARED` section holds a turret, a tender or a pair" guard
  rows in `test_engagement_deadline.gd`.

---

## 5. Testing requirements → gates

| Requirement | Gate (new or extended) | Harness |
|---|---|---|
| Beam activation and telegraph timing (R8.24) | `test_enemy_beams.gd`: not lethal through TELEGRAPH, lethal after `ignite_grace`, harmless tips, FADE ends damage; `rehit_interval` cadence; swept-area hit (a target the segment jumped over); fairness inequalities read from scene exports per kind | hand-ticked, both harnesses |
| Beam damage to allies (R8.7, R8.24) | same file: a fixture ally on the line takes damage; the owner set does not; a plated Ram refuses; a shielded ally is not protected (S5); asteroids hit; ordnance not | both |
| Beam cover | `test_enemy_beams.gd` cover rows: a wreck clips the beam and shadows a target | real physics, 8× clock |
| Pulse Ring | `test_energy_ring.gd`: once per ring, gaps pass, band edges, max radius, fairness | both |
| Power-source shutdown (R8.24) | `test_turret_group.gd`: source death → every live member UNPOWERED the same tick (telegraph cancelled, beam fading, no new rounds), never restarts; members killed earlier stay dead; generator bubbles lapse; coverage rule (≥ 2 turrets per bearing) | both |
| Turret behaviour | `test_defense_turret.gd`: per variant cycle, partial lead, turn-rate cap, `fire_cone`, LOS hold (except rockets), scan idle, Assault drift and view-only fire, `is_laser_blocking()` false | both (LOS rows real physics) |
| Moving wall keeps its length (R8.24) | `test_twin_laser_drones.gd`: `|A−B| ∈ L ± tol` on every ACTIVE tick for Attack A and B, with and without a well's drift; kill one → collapse; strain → collapse; Assault rig clamped | both |
| Attack B / tender | `test_laser_tender.gd`: V-launch toward predicted points across the player's path, one live pair, rearm, launch telegraph | both |
| Segment hazards (S4) | `tests/unit/test_hazards.gd`, `test_context_avoidance.gd`: segment `contains`/`around`, avoidance of a wall from every bearing, moving wall led by `velocity`; **circle rows and pass-through unchanged** | unit |
| Roster gates | add each new scene to the hand rosters of `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd` (or `no_hitbox`), `test_wreck.gd` `_SHIP_SCENES`; automatic: `test_config_instance_isolation.gd`, `test_base_enemy.gd` (mask 1121, lethal flow), `test_entity_sprite_transparency.gd`, `test_enemy_mover_single_writer.gd`, `test_signal_emit_arity.gd` | — |
| Dual-mode spec | `test_enemy_dual_mode.gd` cases for the turret, the pair, the tender (label-parameterised harness) | both |
| Hub | `test_sector_hub_patrol.gd`: new draws, `_element_radius()` cases, site clearance | — |
| Level 1 | `test_level1_specialist_spawns.gd` (`EXPECTED_PH8`, density), `test_engagement_deadline.gd` (guard rows), attack-in-budget rows; Q12 measurement replay | 8×/16× slice replays |
| Lifetimes | any new projectile kind gets a row in `test_enemy_bullet_lifetime.gd` (beams and rings are not projectiles: none expected) | — |

## 6. Notes for the plan stage (sizing, ordering)

- **t1 gate room**, a dependency of everything: recover **≥ 15 s** (a hard floor, Ph7's t1 precedent) with only the
  `tests/README.md` rules — `test_fighter_squad.gd` (63.7 s) and `test_level1_fighter_fire_density.gd` (32.3 s) are the
  obvious candidates. Per-task allotments should total ≤ the recovered time + the 21.6 s headroom − a 5 s margin.
- **Foundations before consumers:** `EnemyBeam` (+ scan, scenes, fairness rows) → `EnergyRing` → segment hazards → turret
  shell + mount → variants → group / generator / power source → laser wall → twin pair (Attack A) → Laser Tender (Attack
  B) → art → hub → level 1 → docs. Art can run in parallel after each shell exists.
- **Large tasks** (own task plan + review): `EnemyBeam` (geometry, scan, cadence, cover), segment avoidance (touches
  `Steering`), the twin rig (coordinated boosts, strain/collapse), the turret group (cross-entity state).
- **Owner decisions to surface in the plan:** Q9 (the Laser Tender as a new roster entry), Q4's owner set (vs literal
  "everything"), unpowered turrets dark vs destroyed, the heavy emplacement in or deferred, and Q12's outcome.
- **DECISIONS.md entries the plan must write:** the beam friendly-fire rule and owner set; direct-emitter damage for enemy
  beams (shields bypassed, hull armour refuses); `EnemyBeam` / `EnergyRing` names and the "tuning in scene exports" rule;
  segment `HazardInfo` (a change to Ph6's "no change to the AI" promise); `TurretGroup` as a non-parent coordinator and
  `set_powered()` as the Ph9/Ph20 seam; the `TurretMount` as the Ph10 seam; the Laser Tender's `launch_pair()` as the
  Ph10/Ph11 seam; Heavy Shell left to Ph10.
