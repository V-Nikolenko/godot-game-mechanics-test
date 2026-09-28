# Research — Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles

Epic `cmufs7ek60001nm2x6d0bt2et`, research task `cmufs7ekg0005nm2xzufhgq10`, 2026-09-27. The code facts behind
everything here are in `1-context.md`, next to this file. Its requirement ids `R2.x` and risk ids `C1`–`C7` are
reused below. Tuning values marked **[judgement]** have no citable source. They are starting defaults, not findings.

---

## 0. Scope check (re-validated against the code, `DECISIONS.md` and the Phase 1 as-built)

The phase scope was written after the Phase 1 roadmap (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §7). It does
not match that roadmap everywhere, and the code adds constraints neither document saw. The epic's scope text wins
where the two disagree, because it is the later and more specific instruction. Each difference below is stated so
the plan and `DECISIONS.md` can record it.

| # | What changed | Phase 1 roadmap / decision | Now | Consequence |
|---|---|---|---|---|
| S1 | **Explosive collision** is in this phase | L11: None/Collision/Ramming in Ph2, Armour in Ph4, **Explosive in Ph7** | The scope names None, Collision, Ramming **and** Explosive. Armour stays with the Ram Corvette (Ph4) | This phase must build Explosive and give it a real user. Candidate: the Swarm Drone's ram impact, the kamikaze lineage. Ph7 (mines) then reuses it instead of building it |
| S2 | **Razor idle + generic anchor-idle→combat handover** is in this phase | §18.5 idle profiles → Ph14 | The Razor idle and the *generic* handover are here. Idle profiles for other families stay in Ph14 | Ph14 builds on a handover contract made here, so it has to be generic (in `global/enemy_ai/`) and not Razor-only |
| S3 | **Level-1 Kamikaze + Drone Interceptor spawns migrate** to spawn layout + corridor | Assault migration → Ph15 (the path mover stays the default until then) | Only these two enemies' level-1 spawns move now. Everything else in level 1 stays on rails until Ph15 | This is the first time a *swarm* of AI enemies runs in the corridor. The corridor was designed but has never been played (REPORT *Known gaps*). See risks C1–C3; this is the biggest item in the phase |
| S4 | **Bonus Drone kept** is in this phase | §38 Bonus Drone → Ph4 | It is here, but "kept exactly as it is" is a do-nothing requirement | Deliverable: a regression guard (its existing pins stay green, and it is never touched by the drone rework). No code change |
| S5 | **Sprites for these two enemies** are in this phase | §21–23 → Ph17 as an audit; art "in each roster phase" | Same as Ph1's intent | One art task per enemy, under the `pixel-art-generation` skill |
| S6 | **Station reinforcements use the Kamikaze Drone** (the scope does not mention this) | not recorded | `station_reinforcements.gd` BOTTOM squad = 2 × `b.drone()` on rails | "Retire the Kamikaze Drone" cannot delete `kamikaze_drone/` unless these two spawns move too. Cheapest option: point `WaveBuilder.DRONE` at the Swarm Drone scene. A path mover suspends the brain, so a Swarm Drone *on a rail* flies exactly the old straight line. Its contact profile must still deal damage while suspended (see §3.4). The station tests' spawn counts are unaffected |
| S7 | **`BulletPool` injectable container** (P-18) | Moved to Ph2 because "Ph2 first fires enemy weapons in Open Space" | Every real parent chain already satisfies pool → ship → container: SectorHub's `EnemyContainer` is one level under the root, and so are both harness roots | Downgrade from required to "a one-line guard". Either an optional `container` export with the grandparent fallback, or just a test proving the Razor's pulse lands in `EnemyContainer` in the hub. Either way it stays small. The plan decides; this phase does not need the churn |
| S8 | **Drone Interceptor has no telegraph and never culls outside DASH** | P-8 kept it 1:1 | The Razor Drone does *not* die after a dash (overshoot + return), so the only cull it has goes away | The Razor needs its own Assault exit rule (the same as the Swarm's, C1), and its telegraph is new work, not a tweak |
| S9 | **Drone Interceptor → corridor on** | DECISIONS: "Ph2 turns the corridor on and must re-pin" | Unchanged | `test_drone_interceptor.gd`'s "1:1 with pre-port" pins become Razor pins (rewritten), not kept |
| S10 | **Kamikaze Drone collision_damage dead field** (AUDIT) | — | Retired with the enemy | The Swarm config's `collision_damage` must reach the hitbox. `test_enemy_contact_damage.gd` enforces this once the Swarm is in its roster |
| S11 | **The Assault player is also a valid Open Space target** | — | `TargetInfo.player()` works in both modes (Phase 1) | No work needed |

Nothing in scope turned out to be already done. `spiral`, `corkscrew`, `formation_slot`, separation, cohesion and
alignment do not exist anywhere in `Steering`. There is no squad code outside `StationReinforcements`, which is a
spawn table, not an AI construct (`1-context.md` → "Existing code").

---

## 1. Findings from shipped games and practitioner sources

Web research was done by a subagent and merged here. Where a page was only available through a fetch summary, the
quote comes from that summary, as marked in the Sources section.

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| 1 | **Flocking: keep the neighbourhood small and stop side-flip flicker.** Reynolds defines a neighbour by distance plus a field-of-view angle. The search may be exhaustive or use spatial partitioning. An RTS postmortem moved to a spatial grid to avoid "costly O(n²)" comparisons. It also found avoidance "would flicker between two neighbours either side of the agent's forward vector", and fixed it by **latching the side**. | Brute force is O(n²), but n is squad-sized here: 3–6 per squad, and the largest level-1 drone group is 7, loose spawns in a single wave at lines 460–466. A grid only pays off at dozens of agents. More separation means less clumping but more jitter. Neither source publishes weights; tuning is iterative. | Sample neighbour `range = 50` (units unspecified). **[judgement]** Weights separation : alignment : cohesion ≈ 1.5 : 1 : 1. Separation radius ≈ 1.5–2 × hull radius (≈ 25–35 px for a 32 px drone). Neighbours = squad members only, so O(k²) with k ≤ 7. | https://www.red3d.com/cwr/steer/gdc99/ ; https://www.jdxdev.com/blog/2021/03/19/boids-for-rts/ ; https://arnauld-alex.com/scaling-boids-for-multiplayer-games-fast-flocking-with-spatial-grids-and-zero-copy-optimization |
| 2 | **Attack tokens and roles, not a free-for-all.** *Kingdoms of Amalur* (Game AI Pro ch. 28): a grid of 8 slots around the player, a per-creature weight, an attack capacity, and an outer "approach circle" versus an inner "attack circle". *DOOM* (2016): a demon must "request a token… then release the token back"; tokens can be **stolen** so the closest demons stay threatening. *The Last of Us* (Game AI Pro 2 ch. 34): only "one NPC … shooting the player at any given time", and the rest get roles (Flanker, Approacher…). | A cap reads as fair and choreographed, but the waiting enemies look passive. Giving them roles (flank, orbit) and allowing token stealing hides this. The cap is also the natural difficulty knob, and both games scale it. | 1 active shooter (TLoU); 8 slots, weights 4/8 (Amalur). **[judgement]** Drones: 1 lead attacker (the token), 2 flankers, the rest on rear orbit. This matches IDEAS §5.1 exactly, so the owner's design is a known-good pattern. | http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter28_Beyond_the_Kung-Fu_Circle_A_Flexible_System_for_Managing_NPC_Attacks.pdf ; https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016- ; https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter34_Human_Enemy_AI_in_The_Last_of_Us.pdf |
| 3 | **Telegraph length comes from reaction time.** GDKeys: anticipation = reaction time + the player's ability trigger time + a difficulty buffer, with reaction time ≈ 0.25 s. Hornet's fastest wind-up is 15 frames (0.5 s). A *Dark Souls 3* analysis says signal plus attack need "at least 340 ms". Recovery is a lever too: a short recovery denies a counter, while a long one (≈ 1 s) is a deliberate opening. | Shorter feels sharper but is harder. Longer is fairer but slower. The window after a missed attack is where the player gets to punish. | 0.34 s floor, 0.5 s for a fast attack, 0.25 s reaction. **[judgement]** Swarm ram wind-up 0.35–0.45 s; Razor real dash 0.5–0.6 s. | https://gdkeys.com/keys-to-combat-design-1-anatomy-of-an-attack/ ; https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3 ; https://note.com/darkangels_417/n/nb520b22d60f7?hl=en |
| 4 | **A feint is a longer version of a real telegraph. Keep one cue only the real attack has.** A feint is "Telegraph A looped for longer time" followed by something else, and variants reuse a telegraph with a small colour or scale change. Stout: unfairness is damage the player *could not respond to*; combine animation, SFX and VFX. | A feint identical to the real attack is cheap to make but teaches the player to ignore telegraphs. A cue exclusive to the real attack keeps the feint as a *delay*, never a lie. This is exactly IDEAS §5.2's "the actual dash gets a stronger cue than the fake". | No numbers in the sources. **[judgement]** Fake: yellow "charging" light only, held 1.5–2 × a normal wind-up, then a brake. Real: the same yellow wind-up, then a 0.1–0.15 s white "commit" flash (+ SFX) that the fake never shows. | https://note.com/darkangels_417/n/nb520b22d60f7?hl=en ; https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing |
| 5 | **Bound the prediction.** Reynolds: pursuit's prediction time T should scale with distance, and drop "to zero" when the pursuer is already aligned in front of its target. The predictive-aim article asks how perfect prediction needs to be, suggests perturbation, and notes that intercepts often have **no solution** (negative discriminant or negative time). | Unbounded lead is unfair against steady movement and overshoots badly when the target jinks. A clamped lead can be beaten by changing direction, which is the behaviour the ram should reward. | T ∝ distance. IDEAS fixes 0.4–0.8 s for the Swarm. **[judgement]** T = clamp(distance / burst_speed, 0.4, 0.8). If there is no intercept, aim at the current position (`TargetInfo.intercept()` already returns `ok = false`). | https://www.red3d.com/cwr/steer/gdc99/ ; https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting |
| 6 | **Orbit = tangent plus a radial correction; reversal is the anti-pattern breaker.** The standard trick is "direction to target + 90°". Pure tangent motion spirals outward, so a radial term (distance − radius) holds the ring. No source covers reversal. | Frequent reversals make the enemy hard to hit but look twitchy. Rare ones fail IDEAS §5.2's "prevents players from learning it always attacks clockwise". | `Steering.orbit` already has the radial correction (anchor walk, `clamp(dist·4, 60, max)`). **[judgement]** Reversal chance 30–40% per orbit window before a dash, so it is never on a fixed timer. Brake through zero angular speed over ≈ 0.25 s rather than flipping instantly, so the reversal is visible. | https://discussions.unity.com/t/enemy-ai-orbit-strafe-around-player/575271 |
| 7 | **Wander, leash and hysteresis for idle→combat.** Reynolds' wander keeps a target on a circle ahead of the agent and adds small random displacement each frame ("change wanderAngle just a bit" to avoid jitter). A Godot project uses leash > aggro as hysteresis (300 / 450, marked as a guess in the source). *TLoU* uses a 1–2 s perception build-up and keeps combat ≥ 10 s after losing the player. | Without hysteresis the enemy flip-flops at the perception boundary. A wide gap makes it cling. A notice delay is fair but can look sluggish. | Leash ≈ 1.5 × aggro. **[judgement]** Razor perception 450 px, lose at 700 px, a 0.3–0.5 s "noticed" beat before ENTER. The handover blends from the idle orbit into APPROACH through the mover's `acceleration` rather than with a separate blend timer. | https://www.red3d.com/cwr/steer/gdc99/ ; https://code.tutsplus.com/understanding-steering-behaviors-wander--gamedev-1624t ; https://github.com/Saitamadupauvre/brotatomato/pull/33 ; TLoU PDF above |
| 8 | **Contact damage: always on, or only while attacking, needs a visible rule.** *Enter the Gungeon*: the dodge roll is invulnerable for its first half (≈ 0.7 s total), and the player "will take contact damage if they are still touching the enemy during the second part", so there contact is always on and dodging it is about timing. The rationale pages for "damage on touch" were unreachable. | Always-on contact is simple and fits "keep moving" games, but punishes accidental grazes, especially from small fast drones. Damage only during an attack is fairer, but needs a clear visual state or it reads as random. IDEAS §16 picks the second for rammers, which matches finding 9's "one gameplay light per state". | Player i-frames here: `PlayerBase.invincibility_sec = 0.5`. **[judgement]** Swarm/Razor at rest: 0 or a token graze. Ramming: full damage only while the red "armed" light is on. | https://enterthegungeon.wiki.gg/wiki/Dodge_Roll_(Move) |
| 9 | **Small-sprite readability: shape first, colour second.** SLYNYRD's shmup sprite guide: enemies share a faction look but are "distinguished in shape and color", with a wide spread of sizes; projectiles should stay the most vivid thing on screen. | A strong faction palette (dark hull + red) is consistent but vanishes on a dark background (AUDIT). Brightening whole sprites breaks the faction. IDEAS §21.2's answer is a thin cool edge highlight plus a *single* bright state light. The light must stay dimmer than bullets, or drones read as projectiles. | IDEAS §21/§22: Swarm 24–36 px (author 32×32), Razor 40–56 px (author 48×48). State colours: red armed, yellow charging, white locked or committed. | https://www.slynyrd.com/blog/2020/12/14/pixelblog-31-shmup-sprite-design |

**What the research changes in the design:**
- Findings 2 and 3 confirm the owner's role model and numbers rather than replacing them.
- Finding 4 gives the concrete rule behind R2.11: the white commit flash belongs only to the real dash.
- Finding 5 turns "0.4–0.8 s" into a distance-scaled clamp with a no-solution fallback.
- Finding 8 decides how the Ramming profile reads on screen.
- Finding 1's side latch is the same idea as "choose an unoccupied side and keep it". Once a side is chosen it must not flip mid-approach, or the flank reads as jitter.

---

## 2. What the code allows. The constraints that shape every approach

- **Motion goes only through `EnemyMover` requests** (single-writer gate). A squad cannot move members. It can only
  assign *roles and slots* that each member's brain turns into its own request.
- **One clock per enemy.** `BaseEnemy._physics_process` calls `brain.tick` then `mover.step`. There are no Timers,
  and randomness comes from `brain.rng`.
- **The corridor forces re-entry and holds no exit concept** (C1). Every Assault AI enemy therefore needs a way to
  leave, or it lives until killed. The Interceptor avoided this only because DASH ends in a cull.
- **Requests are per step**, so a brain that stops requesting brakes to zero. The fake dash's "brake and slide"
  therefore needs the mover's `braking` to be non-zero; the Interceptor runs everything at 0, i.e. instantly.
- **`boost()` is filtered by the corridor.** In Assault a ram toward the edge gets pressure, not a hard wall; a
  burst never lands outside the hard band.
- **The corridor is 1480×1480 world px against a 1280×720 screen.** A drone that is "inside" can still be off-camera
  (up to 380 px above or below). "Cross above/below the player inside the available space" (R2.6) is therefore
  literally available, but a drone orbiting at the corridor's top edge is invisible.
- **The level spawn line is 60 px above the corridor top** (design y −400 gives world y −440). The not-yet-entered
  rule pulls drones in at ≥ 60 px/s on that axis. Entry is guaranteed but slow, unless the brain's own APPROACH
  already points inward (it will, since the player is below).

---

## 3. Candidate approaches and tradeoffs

### 3.1 Squad layer (R2.5, R2.15)

| | S-A: squad = a node that owns the members and moves them | **S-B: squad = a passive role board, members read it** | S-C: no squad object, emergent from local rules only |
|---|---|---|---|
| Shape | `SquadController` node parents or steers drones | `SquadController` (`global/enemy_ai/squad_controller.gd`, a `Node` or `RefCounted`) holds the member list, assigns `Role {LEAD, FLANK_LEFT, FLANK_RIGHT, REAR}` and the squad's shared state (anchor, mean velocity, the one attack token). Each brain calls `squad.role_of(self)` / `squad.request_token(self)` in its own `tick` | Each drone decides from its neighbours (Reynolds only) |
| Single-writer gate | **Fails**: the squad would write motion | Passes: the squad only hands out data | Passes |
| Reassignment when the lead dies | trivial | Members disconnect on `tree_exiting`; the board reassigns on the next query or on `died`, giving LEAD to the member closest to the player (DOOM's "steal" finding). Deterministic and testable without physics | Not guaranteed. R2.5 "another takes its place" is not testable |
| Clock | its own `_physics_process`, i.e. a second clock | **Lazy.** Recompute at most once per physics frame, guarded by `Engine.get_physics_frames()`, on the first member query. No new clock, and it works under the dual harness's manual `_tick()` as long as the frame guard is injectable in tests | none |
| Mixed squads later (Ph3 fighters, Ph14 messages) | rigid | the natural place for Ph14's messages | none |
| Verdict | rejected | **recommended** | rejected: cannot satisfy R2.5 or its tests |

Membership comes from the spawner:
- **Assault:** one `FormationResource` expansion = one squad. Loose `b.drone()` lines in the same `b.wave()` form
  one squad per wave.
- **Open Space:** `SectorHub` builds one squad explicitly.

An opt-in `WaveBuilder` `.squad(&"id")` hint is a cheap escape hatch **[judgement]**. `WaveManager` must thread
the squad id through `_expand_formation()`, which today discards the grouping. The squad frees itself when its last
member leaves. It holds members weakly (via `is_instance_valid`) because members `queue_free` on contact
mid-frame (C6).

**Rear-orbit phase offsets (R2.3):** each member takes a phase offset from `brain.rng` at `_ready()`, plus a
slot-index spacing so that REAR members spread around the ring. "Ten drones do not trace identical curves" is then
testable as *pairwise-distinct positions after N ticks from identical spawns*.

### 3.2 Swarm movement (R2.2, R2.3, R2.7)

| | Weighted blend of all five terms every tick | **Primary request per state + bounded flocking nudge** | Context steering |
|---|---|---|---|
| Description | seek + separation + alignment + cohesion + avoidance summed | The state picks **one** primary request (`orbit` for REAR, `formation_slot` for FLANK, a burst for LEAD). The three flocking terms are pure `Steering` functions over squad-mate positions, summed into one `mover.add_nudge()` capped at ≈ 30–40% of `max_speed` **[judgement]** | Ph6 |
| Phase 1 decision | **Rejected in Phase 1** (§2.4: cancellation shows as stalls with few, visible enemies) | Matches Phase 1's "one primary request + offered nudge" design exactly | Deferred to Ph6 by DECISIONS |
| Verdict | rejected | **recommended** | out of scope |

- **`spiral(center, radius, angle, shrink_rate)`:** orbit whose radius changes with time. It is the approach used
  from the rear orbit to the burst start.
- **`corkscrew(pos, forward_dir, amplitude, phase)`:** forward motion plus a perpendicular sinusoid. It gives
  entering drones a non-straight path. It is also the in-AI replacement for today's `sine()` rails, which keeps the
  level-1 "feel" readable.
- **`formation_slot(anchor, heading, slot_offset)`:** `arrive` at `anchor + slot_offset.rotated(heading)`.

All three are pure functions, unit-testable like Phase 1's nine primitives. "Player avoidance until attack
commitment" is `evade` from the player with a small radius, applied only outside the committed states.

### 3.3 Coordinated ram (R2.4) and the Razor dash / fake dash (R2.8–R2.12)

A shared commit sequence, not shared code. Two brains, one vocabulary.

**Swarm:** `ORBIT(REAR) → [token] → WINDUP(yellow, ~0.4 s) → BURST(red, boost toward clamp-predicted point on the chosen side) → OVERSHOOT(brake, capped turn) → second pass once → REJOIN(REAR)`.
- **Side choice:** the player's velocity gives a left/right half-plane. Pick the side with no other member's reserved
  side, and latch it (finding 1).
- **Stationary player:** use the player's `facing` instead of the velocity.

**Razor:** keeps `ENTER → ORBIT` and adds:
- **Reversal:** negate the angular speed, with a visible brake.
- **FEINT:** yellow wind-up held ≈ 1.5 × longer, then brake and slide past with `braking` > 0, then re-orbit to the
  opposite side.
- **DASH:** the same yellow wind-up, then a white commit flash, then `boost()`.
- **OVERSHOOT → RETURN** to orbit.
- **Pulse:** after a dash that ended *without* a contact hit, one `AimedAttackPattern` shot via
  `AttackController.fire_now()`.

**Fake versus real choice** comes from `rng` with a probability export. A test must be able to force either, the
same seam style as `_begin_dash()`.

"Missed" needs a definition that a test can pin: **the dash ended (burst duration elapsed) and the contact hitbox
registered no hit during it.** Do not use a distance threshold, which is fragile with `move_and_slide`.

### 3.4 Contact profiles (R2.14)

| | Enum + `match` inside `BaseEnemy` | **`ContactProfile` node, mirroring `DefenseProfile`** | Per-enemy script code (today) |
|---|---|---|---|
| Shape | new export on `BaseEnemy` | `global/components/contact_profile.gd` child node: `mode {NONE, COLLISION, RAMMING, EXPLOSIVE}`, `damage` (copied from `config.collision_damage`), `ram_damage`, `self_destruct_on_hit`, `blast_radius`, `blast_damage`. The brain calls `arm(bool)` for RAMMING. The node owns the `ContactHitBox`'s `monitorable`/damage and the blast. `BaseEnemy` resolves or creates it the way it does `DefenseProfile` | kamikaze/interceptor each connect `area_entered → set_health(0)` |
| Covers S1 Explosive | yes | yes: a short-lived blast `HitBox` (shape r = `blast_radius`, layer 256, mask 128) enabled for one physics frame via an accumulated-delta counter, **not** `create_timer` (brain rule, leak trap) | ad hoc |
| Future (Ph4 Armour) | grows the base class | adds a mode | copy-paste |
| Gates | `test_enemy_contact_damage` still reads the `ContactHitBox.damage` | same, and the gate's rule can be "damage == config.collision_damage **for the mode's resting damage**", with RAMMING's `ram_damage` from config | same |
| Verdict | acceptable | **recommended** (the precedent already exists) | rejected (R2.14 wants an explicit profile) |

The profile is **data plus one toggle**. It must never write motion, since `BaseEnemy` is an ancestor swept by the
single-writer gate.

Proposed defaults **[judgement]**:

| Enemy | Resting mode | Armed mode | On hit |
|---|---|---|---|
| Legacy enemies | COLLISION (today's behaviour) | none | unchanged |
| Bonus Drone | NONE (it already has no `ContactHitBox`) | none | none |
| Swarm Drone | RAMMING | armed only in BURST (and in the second pass) | self-destruct, EXPLOSIVE on impact with a small radius (the kamikaze lineage and S1's consumer) |
| Razor Drone | RAMMING | armed only in DASH | no self-destruct: the overshoot and pulse need it alive |

**Rails (S6):** when AI is suspended, `suspend_ai()` should arm the profile permanently. A rail-driven Swarm Drone
(station reinforcements, and any not-yet-migrated `.move()` user) then damages on contact exactly as the Kamikaze
does today.

**Engine caveat (C5):**
- An Area2D that becomes `monitorable` while already overlapping is reported on the next physics step, so a burst
  that starts on top of the player still hits. This is engine behaviour to *pin with a test*, not to assume.
- Toggling from inside an `area_entered` callback must use `set_deferred`.

### 3.5 Anchor-idle → combat handover (R2.16, R2.17)

- **Contract:** a small `global/enemy_ai/` helper, `IdleAnchor` or brain-side helpers. It holds `anchor: Vector2`,
  `perceive_radius` and `lose_radius` (hysteresis, finding 7), and a cheap `perceives(target) -> bool` check.
  "Cheap" means no prediction and no squad queries while idle.
- **Razor idle states** (all around the anchor): IDLE_ORBIT (irregular radius and angular speed from `rng`),
  IDLE_BRAKE (short stop), IDLE_REVERSE.
- **Handover:** on perception, go to a NOTICED beat of 0.3–0.5 s (the light turns on). Then ENTER **from the
  current velocity**. The mover's `acceleration` does the blending, so there is no snap.
- **"Instead of instantly snapping" becomes testable:** the velocity change per tick across the handover is bounded
  by `acceleration × delta`.
- The Swarm reuses the same contract: a squad idles as a loose orbit around the anchor.
- **Assault skips idle entirely.** Spawns start in APPROACH, because the level has already decided the fight is on.

### 3.6 Assault migration (R2.23): the exit problem (C1–C3)

The facts:
- A rail kamikaze is visible for ≈ **3.4–3.6 s**. It spawns at world y −440 and is culled at y ≈ 800. `straight(180)`
  is 360 px/s and `sine(170)` is 340 px/s.
- Level 1 has 119 drone lines.
- An AI drone with no exit lives until killed.

| | A: stay until killed | **B: engagement budget, then disengage and exit** | C: keep rails for the Kamikaze replacement |
|---|---|---|---|
| Player-facing | 2–3× the concurrent drones (C3), drones leak into the enemy-free asteroid belt (C2), cloud_descent waits on them | Close to today's density. Each drone gets one ram (+ the second pass if time allows) and then leaves through the nearest side or bottom. "Wave timing preserved" is honoured | Unchanged, but it fails R2.23 outright |
| Mechanism | nothing | brain `engage_budget` (s), **derived** rather than tuned: ≈ legacy on-screen time + one ram cycle, **[judgement]** ≈ 5–6 s. Then a DISENGAGE state requests `retreat_from(player)` biased down or sideways. The mover needs a way to **release** the corridor: a `MovementConstraint.release()`/`releasing` flag on the corridor that stops pressure and lets outward motion through, **or** the brain swapping `mover.constraint = null`. After release, the provider's `enemy_cull_rect()` frees it. Scoring: a disengaged drone is `was_killed = false`, i.e. the escape penalty, exactly as a kamikaze leaving the bottom today | — |
| Section flow | breaks | cloud_descent survivors still hit the existing 10 s fallback; budgets ≤ 6 s mean most leave on their own | — |
| Verdict | rejected | **recommended** | rejected |

**Where the exit rule lives:** the brain decides; the constraint only gets a released state. Swapping
`mover.constraint` from a brain is a field write on the mover, not a motion write. This was checked against the
gate: `test_enemy_mover_single_writer.gd`'s patterns (`_PROPS`/`_CALLS`) match only `velocity`/`rotation` writes
and `set_velocity`/`set_rotation`/`look_at`/`rotate`/`move_and_*`, so `mover.constraint = …` passes. The Razor needs the
same budget, because it lost its dash-cull (S8).

**Spawn layout kept (R2.23):** only `.move(...)` is dropped. `.at()`, `.formation()` and `.delay()` stay, so offsets
and wave timings are untouched. The *path shapes* (sine amplitude, straight angle) disappear. Their intent can be
carried as a per-spawn entry heading or `corkscrew` amplitude via `initial_props` **[judgement]**. That is optional:
the scope says layouts and timing, not paths.

**From-below and side entries** (`at(x, 400)`, `at(±500, 150)`) spawn *outside* the corridor on other edges. The
not-entered rule handles every edge per axis, so they enter correctly. A test should cover one below-spawn.

**Balance risk that cannot be tested headless:** the swarm will feel different. The gate can pin *budgets,
concurrency caps and exit*, but not fun. Flag this for a hand playtest (REPORT *Known gaps* already says the
corridor is unplayed).

### 3.7 Razor Drone: evolve in place, or new directory (open question 1)

- **R-A (recommended):** `git mv drone_interceptor/ → razor_drone/`, rename the classes (`RazorDrone`,
  `RazorDroneBrain`, `RazorDroneConfig`), keep the `.uid` sidecars, and repoint `WaveBuilder.DRONE_INTERCEPTOR`
  (rename it to `RAZOR_DRONE`). The station guard `test_no_squad_uses_a_self_managed_ai_enemy` follows the renamed
  constant. This keeps history and satisfies DECISIONS P-8's "evolve the port".
- **R-B:** new directory plus delete. Cleaner diff for review, but it loses `git log --follow` and duplicates UID
  handling.
- **R-A risk:** every hand roster and doc path changes in one commit. The hurtbox gate's completeness guard catches
  a miss; the two hand-written rosters do not (§1-context "Gates"). Add guards to them first.

### 3.8 Open Space hub (R2.22, C4)

- The player spawns at the origin. Today's drones spawn 300–600 px from there, and planets sit 650–740 px out.
- **Option H1:** keep the "same anchor" (the origin) but put the idle orbit radius and perception so that the squad
  idles **outside** perception at start: anchor ring ≥ 700 px, perceive ≈ 450 px. The player engages by flying
  toward them.
- **Option H2:** move the anchor off to one side (for example, away from the mission planets).
- The scope says "around the same anchor", so **H1** is the literal reading. H2 contradicts the text, so it is an
  owner question if H1 plays badly.
- **Determinism:** `SectorHub` should seed spawn angles from an exported seed or a `RandomNumberGenerator`, not the
  global `randf()`, so a hub test can pin positions.
- **Existing hub tests** that add `sector_hub.tscn` to the tree will now contain live AI. They must stay green:
  nothing in them should be in perception range at frame 0, which H1 guarantees.

---

## 4. Risks and mitigations

| Id | Risk | Mitigation |
|---|---|---|
| C1 | AI drones never leave the Assault corridor | Engagement budget → DISENGAGE → constraint release → cull rect (§3.6). Tested in the assault harness: a drone spawned with budget B is freed within B + exit time and is never freed earlier |
| C2 | Survivors cross DURATION sections / stall ENEMIES_CLEARED | Budget ≤ legacy lifetime + one ram. Test: the section-length constraint is satisfied by the derived budget (e.g. budget + exit < `enemies_cleared_timeout` 10 s) |
| C3 | Difficulty spike from concurrency | Squad token (1 attacker per squad), budget, and a per-squad role cap. Characterize level 1's peak concurrent drones before and after as a number in the plan, computed from the spawn list rather than guessed. The rest needs a hand playtest |
| C4 | Hub ambush at spawn | H1 geometry + a test that no member perceives the player at frame 0 in `sector_hub.tscn` |
| C5 | Ramming hitbox enable/disable timing | Pin with an integration test: burst starts overlapping the player → damage exactly once; disarm from a callback is deferred |
| C6 | Squad dangling references / empty squad | Weak membership, `tree_exiting` cleanup, and the squad frees itself when empty. Tests: lead freed mid-burst, squad of 1, all members freed |
| C7 | Nondeterminism | All choices on `brain.rng` / a squad RNG seeded from the spawner. The dual-mode tests set `rng_seed` |
| C8 | Deleting two scenes breaks load/UID gates or docs links | `test_project_load_integrity`, `test_resource_uid_integrity` and the hand rosters: add the completeness guards *before* the deletions |
| C9 | The corridor was designed but never played; the band numbers are judgement | The Razor re-pins edge behaviour (S9); keep the band values, and change them only with a test that shows why |
| C10 | Swarm on rails (station, S6) must still hurt on contact | `suspend_ai()` arms the contact profile; test on the real station reinforcement spawn |
| C11 | Art budget (PixelLab monthly cap) | Two sprites, 32×32 and 48×48, one attempt each plus a fix pass with `strip-sprite-bg.sh`. State lights are separate small `Sprite2D`/`PointLight`-free modulate children, so states need no extra generations **[judgement]** |

---

## 5. Testing requirements (R2.20, R2.24)

**Unit (pure, in `tests/unit/`):**
- `Steering.spiral` / `corkscrew` / `formation_slot` / `separation` / `alignment` / `cohesion`: each with a
  zero-vector case and a boundary case (radius 0, no neighbours, a coincident neighbour).
- Prediction clamp: T is clamped at 0.4 and at 0.8; the no-intercept fallback returns the current position.
- `ContactProfile`: mode matrix; `arm()` toggles; Explosive blast is active for exactly one tick; RAMMING damage
  equals config.
- `SquadController`: roles for 1/2/3/6/7 members; lead freed → the closest member becomes lead within one query;
  both flank sides occupied → REAR; token single-holder; the last member freed → the squad frees itself.

**Dual-mode spec** (`test_enemy_dual_mode.gd` or a sibling). Parameterize on a **string label**, never on built
harnesses. The same assertions, relative to the constraint:
- Swarm: orbit radius held; ram target within [0.4, 0.8] s prediction of the player; side = the unoccupied one;
  overshoot → exactly one second pass → rejoin; role reassignment after the lead dies; formation recovery (members
  return to their slots within N s after a scatter); distinct phase offsets.
- Razor: orbit radius; reversal happens, with a forced seed; fake dash never arms the RAMMING profile and never shows
  the commit light; the real dash does both; dash direction = locked prediction; a missed dash fires exactly one
  pulse; a dash that hit fires none; idle → combat velocity continuity bounded by `acceleration·delta`; hysteresis
  (no flip at the boundary).

**Assault-only:**
- Engagement budget → exit → freed; never freed before the budget.
- A below-spawn enters.
- Burst near an edge stays inside the hard band.
- Level-1 migration invariant: every `WaveBuilder.DRONE` / `RAZOR_DRONE` spawn in `level_1_director.gd` has **no**
  `movement`, and the wave triggers and offsets equal the pre-migration list. Pin the list before migrating
  (characterization first).

**Open Space:**
- `SectorHub` spawns 1 squad (N Swarm) + 1 Razor on the anchor.
- No PatrolDrone references remain.
- Nobody perceives the player at frame 0.
- The Razor's pulse bullet lands in `EnemyContainer` (the BulletPool depth check, S7).

**Gates:**
- The new scenes are in the contact-damage and contact-geometry rosters; completeness guards are added to both.
- `kamikaze_drone` / `drone_interceptor` are removed from the rosters.
- The floors still hold.
- Transparency covers the new PNGs.
- Single-writer covers both brains and the squad.
- Bonus Drone pins unchanged (S4).

**Leak check:** run `scripts/check-test-leaks.sh` after anything that awaits or creates nodes in `use_parameters`
tests (DECISIONS t12 trap).

---

## 6. Recommended decomposition, as input to the plan (not a plan)

The ordering is by dependency; the plan owns the final list. Roughly:
1. Characterization pins: the level-1 drone spawn list, the station BOTTOM squad, the hub spawn. Add completeness
   guards to the two hand rosters.
2. `Steering` additions: spiral, corkscrew, formation_slot, the flocking terms, the prediction clamp.
3. `ContactProfile`, wired into `BaseEnemy`, with legacy = COLLISION and no behaviour change.
4. `SquadController` + the `WaveManager`/`WaveBuilder` squad-id threading.
5. The corridor release plus the Assault engagement-budget/exit contract.
6. The generic anchor-idle contract.
7. Swarm Drone: scene, brain, config.
8. Razor Drone: rename the Interceptor, then reversal / feint / dash telegraph / pulse / idle; re-pin.
9. Two art tasks.
10. Level-1 migration + station BOTTOM squad + `WaveBuilder` constants; delete `kamikaze_drone/`.
11. SectorHub squad + Razor; delete PatrolDrone.
12. Docs + DECISIONS as-built.

Steps 7, 8, 10 and 11 are the large ones.

---

## Sources

Read by the research subagent. "(summary)" means the text came through a fetch summary and not a full read.

| Source | What it contributed | Status |
|---|---|---|
| https://www.red3d.com/cwr/steer/gdc99/ | Neighbourhood definition, pursuit prediction T ∝ distance, wander | read |
| https://www.jdxdev.com/blog/2021/03/19/boids-for-rts/ | Spatial grid versus O(n²); side-latch fix for avoidance flicker | read |
| https://arnauld-alex.com/scaling-boids-for-multiplayer-games-fast-flocking-with-spatial-grids-and-zero-copy-optimization | Grid scaling for large flocks (why not needed at squad size) | read |
| http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter28_Beyond_the_Kung-Fu_Circle_A_Flexible_System_for_Managing_NPC_Attacks.pdf | Amalur slot grid, attack capacity, approach and attack circles | read via r.jina.ai (the raw PDF was undecodable) |
| https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016- | DOOM attack tokens, token stealing | read (summary) |
| https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter34_Human_Enemy_AI_in_The_Last_of_Us.pdf | One active shooter, roles, perception delay, combat persistence | read via r.jina.ai |
| https://gdkeys.com/keys-to-combat-design-1-anatomy-of-an-attack/ | Anticipation formula, 0.25 s reaction, recovery as the opening | read |
| https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3 | ≥ 340 ms signal + attack | read (summary) |
| https://note.com/darkangels_417/n/nb520b22d60f7?hl=en | Feint = longer telegraph; reaction thresholds | read (summary) |
| https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing | Fairness = the ability to respond; combine animation, SFX and VFX | read (summary) |
| https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting | Imperfect prediction, no-solution intercepts | read (summary) |
| https://discussions.unity.com/t/enemy-ai-orbit-strafe-around-player/575271 | Tangent orbit (direction + 90°) | read |
| https://code.tutsplus.com/understanding-steering-behaviors-wander--gamedev-1624t | Wander angle smoothing | read |
| https://github.com/Saitamadupauvre/brotatomato/pull/33 | Aggro/leash hysteresis 300/450 (a guess in the source) | read |
| https://enterthegungeon.wiki.gg/wiki/Dodge_Roll_(Move) | Always-on contact damage, avoided by i-frame timing | read |
| https://www.slynyrd.com/blog/2020/12/14/pixelblog-31-shmup-sprite-design | Shape and colour distinction, size spread | read |
| tvtropes.org/pmwiki/pmwiki.php/Main/CollisionDamage | Contact-damage rationale | **unreachable** (403 direct and through the proxy) |
| neogaf.com/threads/damage-on-touch-good-or-bad.1149018 | Contact-damage debate | **unreachable** (403) |

No source was found for three things, so they are marked **[judgement]** above:
- orbit reversal frequency;
- charge overshoot numbers from named games (Nuclear Throne, Hades, Gungeon);
- per-agent phase offsets.
