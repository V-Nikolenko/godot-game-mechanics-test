# Research — Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship

Epic `cmufs7elw001pnm2xr3b6fteb`, research task `cmufs7em1001tnm2xsfqqybxp`, 2026-10-14.

`1-context.md` (next to this file) is the code inventory: requirements `R5.x`, files, reusable pieces, conventions and
risks `C1`–`C18`. This file holds what the plan decides from:
- §0 the scope check against the code and the earlier phases' as-built records;
- §1 outside findings, with their tradeoffs and typical values;
- §2 candidate approaches per part, each with a recommendation (§2.12 answers `1-context.md`'s open questions);
- §3 starting values and hub placement;
- §4 Assault placement and the `ENEMIES_CLEARED` / density arithmetic;
- §5 the testing requirements, mapped to gates;
- §6 sizing and ordering notes for the plan stage.

Facts were read at `59f4abe` on `agent/auto-dev`. Anything not read directly, or a judgement with no citable source, is
labelled **(judgement)**.

---

## 0. Scope check

The scope text was written before Phases 1–4 ran. Checked against `DECISIONS.md` (Phase 1–4 *as built*), the Phase 4
`REPORT.md` and the code, it changes as follows. Each item is an explicit adjustment the plan must carry.

| Id | Scope item | Finding | Adjustment |
|---|---|---|---|
| S1 | §12 `persist_after_owner_death` "as pool policy" (Ph1 roadmap row for Ph5) | **Already built in Ph4** (`BulletPool._hand_over_active()`, `bullet_pool.gd:136-161`), pulled forward for the Bomber's mines (Ph4 deviation 25). | Nothing to build. Rocket pools set the flag; "Ph5 builds rockets **on** this flag, it does not create its own" (DECISIONS Ph4). |
| S2 | §12 `max_distance_from_owner` (Ph1 F8 → "owner distance → Phase 5") | `ProjectileLifetime` has no owner rule (`projectile_lifetime.gd:101-104` documents the gap). With `persist_after_owner_death` the owner is often **dead** when the rule would apply; every rocket kind is already bounded by fuel time and range from its origin (§2.2). No consumer needs it. | **Recommend not building it** and logging why: the origin-distance + time rules bound every rocket; an owner-distance rule is meaningless for a projectile that outlives its owner. Hand it to Ph13 with `max_distance_from_player` if encounter ownership ever needs it. This is a recorded decision being revisited, so the plan must say so in `DECISIONS.md`. |
| S3 | `BulletPool` injectable container (deferred Ph2 → Ph5, twice) | Every pool in this phase can be a direct root child (corvette rocket pools). The one case a pool cannot serve is a **cluster rocket splitting after its corvette died** (the corvette's pools are gone). Unpooled children that free themselves (`expired → queue_free`, spawned into the parent rocket's container, the `ContactBlast.spawn` shape) keep the one-owner rule with no container injection. | **Not needed; recommend deferring again** to the first nested launcher (Ph10 Carrier hangars / Ph18). State it in `DECISIONS.md`. |
| S4 | §13.2 shields + "the DamageReaction-versus-BaseEnemy decision phase 1 deferred" (P-15) | `DamageReaction` is used **only by race ships** (`race_ship.gd:24` + five racer scenes). It routes `received_damage(damage)` → `Shield.consume_one()` → `Health`; it has no direction, no hit, a tween flash (BaseEnemy uses an `AnimationPlayer`), and death = `get_parent().queue_free()` (the station overrides death to linger; the Ram overrides damage to deflect). `Shield` is discrete charges with a fixed 5 s `Timer` regen, progression binding and a hacked flag — a player resource. | **Decide now: BaseEnemy keeps its own flow; `DamageReaction` is not adopted and stays a racer component.** Enemy shields are a new component with a hit-aware hook (§2.4). Reasons in §2.4. Log the decision (it closes P-15). |
| S5 | "All of this sits on the collision layer that phase 1 named for rockets" | Bit 32 is named **`player_rockets`** (`project.godot:177`, `CollisionLayers.PLAYER_ROCKETS`, 20 references). At runtime **every** `BaseEnemy` hurtbox accepts it (default `DefenseProfile` mask 1121 overwrites every scene mask), enemy-ordnance hurtboxes and `ArmorPlate`s mask 96 (32 \| 64), the big asteroid's hurtbox masks 32. The player and ally hurtboxes (mask 1281) do **not**. | A HitBox on 32 reaches enemies, ordnance, plates and asteroids for free — exactly the "made to hit other enemies and the environment" counterplay — but the rocket must **also** sit on 256 to hit the player, and C1/C2/C3 follow (§2.3). Renaming the layer `rockets` (name only, value unchanged) is optional (§2.3). |
| S6 | "Rockets can be … made to hit other enemies" | DECISIONS Ph2: "Enemy friendly fire (blasts, beams): undecided (Ph8 at the earliest)"; `ContactBlast` is layer 256 / mask 0 and no enemy hurtbox masks 256, so a blast never hurts an enemy. | **This phase must decide enemy friendly fire for rockets**, explicitly and only for rockets. Recommendation (§2.3): the rocket's **impact** hits enemies; the **blast** stays player-only. Beams and other blasts stay undecided (Ph8). |
| S7 | §6.1 "warning audio" | No enemy SFX pipeline exists (Ph2/Ph3 deferred enemy audio to Ph17). | Out of scope → Ph17. The telegraph is visual: `StateLight` CHARGING, a launch flash/tube light, the rocket's own trail and blink. |
| S8 | §6.1 "possible flare/decoy reaction" | The player kit has **no countermeasure** (grep for decoy/flare/chaff finds only the Sniper's decoy telegraph). Findings 13 (Ace Combat, Starsector flares) show it is a player-side system. | Out of scope: no consumer exists, and building a rocket "decoy reaction" without a decoy is building ahead. If a later phase adds a player countermeasure, rockets retarget through the same aim-point hook (§2.2). |
| S9 | §6.1 "bait it into a carrier escort" | The Carrier is Ph10/Ph18. | Covered generically by impact friendly fire (S6): any enemy in a rocket's path takes the hit. |
| S10 | §11.2 Hijack Pulse | Ph9 (scope). | Out. Nothing here may make player missiles retargetable. |
| S11 | §13.2 "directional, local-module, regenerating, projected bubble" | Only the Support Ship projects shields in this phase. Modules are Ph10. | Build **one** shield component whose arc width (≤ 360° = bubble), capacity, regeneration and lifetime are fields, attachable to any enemy hurtbox owner. Shipped consumer: the Support Ship's projection (directional arc). "Local module" and "bubble" are proven by fixtures (a shield on a part's hurtbox; arc 360°) and get their shipped consumers in Ph10/Ph11. Say so in the coverage table. |
| S12 | §6.2 "repairs allies" | No heal path for enemies exists; `BaseEnemy._on_health_changed` plays the hit flash and hit burst on **every** change (`base_enemy.gd:183-192`), and `Health.increase()` always emits. | In scope: a heal path that never flashes (a small `BaseEnemy` change, §2.5). |
| S13 | §6.2 "pulls the target away" | The ward's `EnemyMover` is the single writer of its motion (gated). | The support may not move the ward; the "pull" is a **tow request** on the ward's mover (`add_nudge`, a request, not a write) plus the support interposing itself (§2.7). |
| S14 | §6.2 Assault "cannot hide permanently above the camera" | `AssaultCorridorConstraint.inner_rect()` is the whole pan range (1480 × 1480); the camera shows 1280 × 720 of it, so a ship can sit ~380 px above the current view with zero pressure. No provider returns the current view (`EnemyWorld.cull_rect()` ignores the camera `offset`, Ph2). | Needs a view-relative clamp: a new `EnemyWorld` query backed by `ArenaCamera` (§2.8). |
| S15 | §37 Support + Ram "made possible" | An Assault Ram lives one charge (`engage_seconds` 4.0, DECISIONS Ph4 t22), so "multiple attack attempts" can only happen in Open Space. A Ram's plates are separate `ArmorPlate`s; while armoured its hull refuses all damage. | Make the pairing work mechanically (a Ram is an eligible ward; repair heals the hull, never plates; a projected arc protects the hull side facing the player) and place a Support with the hub Ram (shared anchor, §3.3). In Assault the pairing appears only where a level wave already has rams (§4). |
| S16 | Both enemies "added to existing Assault waves" | Missile Corvette rockets persist → they hold an `ENEMIES_CLEARED` section open (`level_director.gd:170` counts container children). cloud_descent's ram row passes by **0.40 s**; station_assault is the boss fight. | Both enemies only in **DURATION** sections (deep_space, planet_approach), with an `ENEMIES_CLEARED` boundary row for the corvette (the Bomber/Gatling precedent) (§4). |
| S17 | Level-1 density gates | They divide by frozen per-kind legacy constants; a **new** kind has no legacy rail baseline. planet_approach's specialist peak is 6 against a limit of 7.5 (1-ship margin). | Count both new kinds as specialists in `test_level1_specialist_spawns.gd`'s existing gate (same frozen constant, same 2.5×), and place them outside the planet_approach 65.7 s peak window (§4). |
| S18 | §21–23 sprites, "unfolding projector state" | Sizes today: bomber 104×56, ram 84×84, sniper 48×64. `StateLight` has no cyan state (IDEAS §21.1 "cyan/blue = shield"). The Sniper barrel (`SniperBrain._tick_barrel`, `scale.y` lerp + ease-out) is the unfold precedent. | Corvette ≈ 96×96, Support ≈ 88×88 (both inside 72–112), a separate projector child sprite that unfolds (Sniper precedent); the shield arc and the tether are cyan; repair pulses a pale green/white (judgement). |
| S19 | "tests in both harnesses" | Gate wall clock ~257 s of a ~300 s cap. | Prefer hand-ticked `_tick()` specs; any real-physics row runs on the 8× clock (Ph4 convention). Budget for it in sizing (§6). |
| S20 | Station reinforcements, `level_2_waves.gd` | Rail-driven; neither enemy is placed there. | Untouched. Each new enemy still gets a minimal rail fallback (Ph3 rule) so a future `.move()` is not silent (§2.9, §2.10). |

**Everything else in the scope stands as written.** No earlier phase built any part of either enemy, the rocket family,
enemy shields or repair. The reusable machinery is listed in `1-context.md` → *Existing code to reuse*.

---

## 1. Findings from shipped games and engine docs

A research subagent did the web searches; URLs were fetched and read unless marked *snippet only*. Pages that 403'd
were retried through `scripts/fetch-page.sh`. Unreachable sources are listed after the table. Ids `F1`–`F13` are used in
§2–§3.

| # | Finding | Tradeoff for this phase | Typical values | Source |
|---|---|---|---|---|
| F1 | Homing comes in two dodgeable kinds: **fast with a low turn rate** (threatens a forward cone; counter = cut across at a sharp angle, "it will take a long time for them to reorient… and they may time out") and **slow with a high turn rate** (cannot be out-turned; counter = distance until it despawns). Dodge perpendicular to a projectile's path, never along it. | A rocket must be *either* fast/wide-turning *or* slow/tight-turning; fast **and** tight is undodgeable. A finite homing time is what makes the slow kind fair. Maps to Pursuit (fast, capped turn, finite window) vs Delayed Warhead (slow, proximity). | — | https://shmups.wiki/library/Help:Dodging_strategy (read) |
| F2 | Starsector **Harpoon MRM**: launch speed 100 accelerating to 300, **turn 30°/s**, flight time 12.5 s, against a 150-speed frigate. A missile past its flight time ("flameout") loses its engine and **can hit friendly ships**. | A 2:1 speed ratio is still dodgeable when the turn radius is large (300 / 0.52 rad/s ≈ 573 units, arithmetic ours). Flameout = free friendly-fire counterplay: an unguided rocket is just a hazard to everyone. | 2:1 speed, 30°/s, 12.5 s | https://starsector.wiki.gg/wiki/Harpoon_MRM , /wiki/Wolf , /wiki/Missile (read) |
| F3 | **Proportional navigation**: lateral acceleration = N × closing speed × line-of-sight rate; N 3–5 (3 typical). It snaps onto the collision course at launch, then only small corrections. | Uncapped PN is near-perfect against a straight-flying target; the player can only escape by turning or outlasting it. Unfair for an arcade enemy; a low gain plus a hard turn cap (or lead pursuit) is readable and beatable (judgement). | N = 3 (range 3–5) | https://www.moddb.com/features/flint-lead-pursuit-guidance-principles (read via fetch script) |
| F4 | Reynolds **pursuit** steers at a predicted position with look-ahead `T = D·c`; `c = 0` is plain seek. **Offset pursuit** aims a radius off the predicted position; **leader following** = arrive at a point behind the leader + separation, stepping aside from the leader's near-future path; **evasion** is often deliberately non-optimal; **hide** = seek the far side of an obstacle. Steering is clamped by `max_force`. | The look-ahead constant is the difficulty knob (`c = 0` tail chase the player always wins; large `c` intercepts). Leader following / offset pursuit are ready-made building blocks for "stay behind the ward" and the escort. | `T = D·c`, clamped force | https://www.red3d.com/cwr/steer/gdc99/ , https://www.red3d.com/cwr/steer/LeaderFollow.html (read) |
| F5 | Godot homing recipe: seek steering with a clamped steer force so the missile does not "turn on a dime"; a lifetime timer explodes it. | Force-clamped steering gives a speed-dependent turn radius; a °/s cap gives a fixed angular rate. Either works if applied per physics tick (F6). We already have `Steering.turn_toward` (rate cap). | speed 350, steer_force 50 | https://kidscancode.org/godot_recipes/3.x/ai/homing_missile/ (read) |
| F6 | **Descent**'s homers became undodgeable at high frame rates ("over 80 fps, there's no way you'll ever get away from a homer"); D2X-XL fixed turning independent of frame rate. Players dodged by circling, or by boosting sideways at the last moment. | The turn cap must be rate × `delta` in `_physics_process`. The last-moment sideways boost is the classic counter, so our 700 px/s boost must beat a rocket's final turn — a test row. | fixed tick | https://descentbb.net/viewtopic.php?t=9962 (read; forum, anecdotal) |
| F7 | Doom's **Revenant** missiles are hard to outrun; counters: strafe then step forward just before impact so it cannot come round, or put a wall/cover between. | A rocket that orbits and re-attacks forever feels unfair without terrain. In open space the *guidance window* must end (then it coasts), and other enemies/asteroids play the wall's role. | — | https://doomwiki.org/wiki/Revenant (**snippet only**; blocked directly and via the fetch script) |
| F8 | Starsector **Hurricane MIRV** "splits into multiple warheads on closing with the target"; parent speed 250, 10°/s turn; **destroying the parent destroys every submunition**; submunition count went 9 → 11 → 9 → **7** with accuracy raised as the count fell; warheads are "aim then unguided burn". | Split by **distance to the target**, not a timer. Fewer, more accurate submunitions read better than a spray. Unguided children are dodgeable once released; killing the parent before the split is a skill reward. | 7 children, 10°/s parent turn | https://starsector.wiki.gg/wiki/Hurricane_MIRV_Launcher (read) |
| F9 | Proximity triggers: Deep Rock Galactic's mine arms after 3 s and shows its trigger range; a Second Life grenade triggers at **½ its blast radius**; blink faster as the fuse runs down. | Trigger radius below blast radius gives a near-miss zone; a visible arming delay and ring make it readable. Matches the Ph4 mine rule `(trigger + blast) / warning ≥ max player speed`. | arm 3 s; trigger ≈ 0.5 × blast | search snippets only (DRG wiki 402) — weak evidence |
| F10 | **Halo shields**: regen starts **5 s** after the last hit and refills in **4 s** (CE); Halo 2 **4.25 s / 1.75 s**; Halo 3 **5 s / 2 s**. Feedback: flare on hit, low-shield tone, a visible recharge wave. Jackal gauntlet shields stop most fire but leave them open to flanking and grenades; Halo 2's shield notches let rounds through. | A long delay + fast refill punishes half-commitment (switching targets resets it), so focus fire wins; a short delay makes it a second HP bar. Frontal shields push flanking — natural in Open Space, nearly impossible in the vertical Assault mode if the arc always faces the player (judgement). | delay 4.25–5 s; refill 1.75–4 s | https://www.halopedia.org/Energy_shielding (read); Kig-Yar gauntlet pages (snippet) |
| F11 | Shield-granters show the link: Warframe **Shield Osprey** — allies within **10 m** get +100 +35 % shields, shown by a **blue tether**, fires its own weak laser only when no ally needs it; Destiny 2 Servitors make tethered Fallen **immune** (snippet); Halo ODST **Engineers** overshield allies, drift to a safe distance when shot, and "kill them first". | A visible tether answers "who is shielded / who to kill" at a glance. **Immunity forces killing the support first; a partial bonus only suggests it.** Immunity in a time-boxed Assault section would stall a wave. Evasive-but-unarmoured makes a chase without a stall. | 10 m link; +35 % | https://wiki.warframe.com/w/Shield_Osprey , https://www.halopedia.org/Huragok (read); destinypedia Servitor (snippet) |
| F12 | Healers need rate limits: Warframe **Ancient Healer** pulses every **15 s** for **20 %** within 10 m; its old **90 % damage-reduction aura** was reworked twice (to overguard, then a separate unit). Risk of Rain 2 **Mending** elites heal only *non-Mending* allies and drop a healing core on death. | Pulsed, capped healing keeps fights moving; a constant strong aura stalls them. **Healers must not heal each other** (mutual-heal stalemate). | pulse 15 s / 20 %; 10 m | https://wiki.warframe.com/w/Deimos_Ancient_Healer (read); https://riskofrain2.fandom.com/wiki/His_Reassurance (read via fetch script, item text only) |
| F13 | Countermeasures and shield breaks: Ace Combat 7 flares are rationed (2–6 a sortie) and decoy missiles; Starsector flares draw missiles only by chance and destroy missiles that touch them. Doom Eternal's shield soldier: plasma overloads the shield into an explosion that hurts nearby enemies; explosive splash reaches the soldier behind it. | A rationed countermeasure is the fair answer to a well-tracking missile — but it is a player system (S8). A shield break that *does* something (flash, a burst) turns "break the shield" into a satisfying event. | flares 2–6 / sortie | https://acecombat.wiki.gg/wiki/Flares , https://starsector.wiki.gg/wiki/Flare_Launcher (read); Doom Eternal (snippet) |

**Sources tried and unreachable:** doomwiki.org (Revenant, Doom Eternal plasma) — 403 directly and via the fetch script;
doom.fandom.com Shield Soldier — 402 / empty; riskofrain2.wiki.gg Elites — truncated before Mending; deeprockgalactic.fandom
Proximity Mine — 402 (snippet only); gameaipro.com ch. 26 "Tactical Position Selection" — downloaded but **unread** (no PDF
text tool in the container); Buckland's "Interpose" behaviour (Programming Game AI by Example ch. 3) — no free text found;
no numbers found for Ace Combat / Elite Dangerous / Everspace / Enter the Gungeon / Nuclear Throne homing. **No Game AI Pro
chapter on escort/bodyguard AI exists** (table of contents checked). Where §2 uses "interpose" it is our own judgement, not a
cited behaviour.

---

## 2. Candidate approaches

### 2.1 Rocket guidance (R5.5, R5.6, R5.11, C6)

| Option | Behaviour | Verdict |
|---|---|---|
| A. Pure pursuit (seek the live player) | Tail chase; always behind the player | Rejected: contradicts R5.5 ("prefer the player's future path"); trivially outrun |
| B. Proportional navigation (F3) | Near-optimal collision course | Rejected: unfair without a cap; harder to read and test |
| **C. Lead pursuit with a turn-rate cap and a finite guidance window** | Each tick: aim point = `TargetInfo.intercept(rocket_pos, rocket_speed)` (fallback `predicted_position(clamped_lead_time(d, speed, 0, lead_max))` when `intercept` fails); heading = `Steering.turn_toward(heading, aim − pos, turn_rate, delta)`; after `guidance_seconds` the heading freezes and the rocket coasts | **Recommended.** It is exactly the shipped pursuit-bomb model (`enemy_ordnance.gd:183-195`) with `intercept()` instead of a linear lead. `lead_max` is Reynolds' `c` (F4) — the difficulty knob for Ph16. |

- **Launch and acceleration phase (R5.6):** every rocket leaves at `launch_speed`, flies straight for `boost_seconds`
  (no steering — the "visible launch"), then accelerates at `accel` to `cruise_speed`. Damage arms after
  `arm_distance` from the launch point (C1).
- **Dodgeability (F1, F2, F6) — pinned as test rows, not prose:** (a) a player running straight away at Open Space max
  speed (420 px/s) is not caught by a Pursuit rocket launched ≥ 300 px behind before its guidance ends; (b) a player
  boosting perpendicular (700 px/s) when the rocket is 150 px away is missed; (c) a stationary player is hit; (d) turn
  radius `cruise_speed / turn_rate` ≥ a config-asserted minimum. The Open Space ship's own sustained turn radius at
  420 px/s is ≈ v² / thrust = 420² / 380 ≈ 464 px, so a rocket turning tighter than that cannot be *out-turned* in a
  sustained turn — the escape is the **late break / boost** and the **finite window** (F1, F6). That is the design.
- **Coast after guidance (F2 flameout):** the coasting rocket keeps its impact rule, so it remains a hazard to enemies and
  asteroids it crosses.

### 2.2 The rocket family: class shape (R5.10–R5.13, open question 4)

| Option | Pros | Cons |
|---|---|---|
| A. Four new `Kind`s on `EnemyOrdnance` | One script, one contract | The script is bomb-shaped: no `rotation` (a `RocketTrail` needs a nose), proximity-only trigger, `max_travel` gravity cap, eject/fizzle, `pool_size_for` keyed on `BomberConfig`, `_draw()` primitives; rockets add an impact HitBox, owner exclusion, arming distance, splitting, a second layer. Every `match kind` grows, and Ph7's Mine Layer also extends this script. |
| **B. A sibling `EnemyRocket` (one script, `Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }`) in `assault/scenes/projectiles/enemy_rockets/`, with the same contract** | Keeps bomb code clean; reuses `ContactBlast`, `ProjectileLifetime`, HurtBox + Health defuse, the `_RESET_PROPS` capture and `_mark_done()` latch *by shape*; `EnemyRocketScenes.scene_for/pool_size_for(kind, cfg)` keyed on the corvette's config | Some duplicated structure (~60 lines of contract) |
| C. Extract a shared base (`EnemyProjectileBase`) and re-parent `EnemyOrdnance` onto it | No duplication | Churn on a Ph4 system with a 53 s test file for no player-visible gain; risk to the Bomber's measured rows |

**Recommend B.** Contract (mirrors `EnemyOrdnance`): `signal expired`, `reset()`, `launch(dir, speed, aim_point)`, a
`HurtBox` + `Health` 1 (any player hit defuses: pop, **no blast**), `ProjectileLifetime` (`max_time`, `max_distance`,
`use_world_rect` in Assault), never in `enemies`, never scored, detonation through `ContactBlast.spawn`. Additions: a
node `rotation` set by the rocket itself (it is not an `EnemyMover` actor, so the single-writer gate does not apply — the
gate sweeps brains, `global/enemy_ai/` and mover-driven enemy roots; `EnemyOrdnance` already writes its own
`global_position`), a `RocketTrail`, an impact `HitBox` (§2.3), `arm_distance`, `launcher` exclusion.

Per kind (numbers in §3.1):
- **Dumb** — no steering; aimed at launch at the intercept point. Fast and predictable (R5.10).
- **Pursuit** — §2.1 option C for `guidance_seconds`, then coast (R5.11).
- **Cluster** — mild steering; **splits by distance** to the player (F8), with a `split_time` cap: frees itself (no
  blast) and spawns `cluster_count` (3–5, R5.12) **unpooled** `SUBMUNITION` rockets into its own parent (the container)
  in a fan of `cluster_fan_deg` centred on the predicted point; children are unguided (F8 "aim then unguided burn"),
  short-lived and own themselves (`expired → queue_free`). **Shooting the parent before the split kills all of it** (F8).
  Children never hit each other or their parent (C2).
- **Delayed Warhead** — slow, mild steering, proximity trigger on the player hurtbox once armed, a blinking warning, then
  a large blast (R5.13). Trigger < blast (F9) and the Ph4 mine inequality `(trigger + blast) / warning ≥ 420 px/s`
  (Open Space max speed) so a player crossing at cruise speed is caught, while a 700 px/s boost escapes (counterplay).
  Also detonates on impact.

Pools: one per kind on the corvette, direct root children, `persist_after_owner_death = true`, sized by formula
(`max_salvo × ceil(rocket_max_time / min_salvo_period)`), pinned in the corvette's test like the Bomber's.

### 2.3 Collision layers and enemy friendly fire (R5.7, R5.15, S5, S6, C1–C4, open question 3)

Facts (1-context): every enemy hurtbox masks 32 at runtime; ordnance hurtboxes and Ram plates mask 96 (= 32 \| 64) and
plates **break on `ROCKET`**; asteroid hurtboxes mask 32; player and ally hurtboxes mask 1281 (no 32, has 256);
`ContactBlast` is 256 / mask 0.

| Option | How | Verdict |
|---|---|---|
| **A. Impact HitBox on 32 \| 256, `damage_type = ROCKET`** | The HitBox's layers reach the player (256) and every enemy / ordnance / plate / asteroid hurtbox (32). The rocket monitors (mask 128 \| 512) to detonate on contact. Its own shoot-down HurtBox is 512 with mask **64 only** (player bullets; not 32, or rockets would shoot each other down — C2). Its HitBox is **not monitorable until armed** (`arm_distance` from launch, C1), and its contact handler ignores its launcher and any `EnemyRocket` / `EnemyOrdnance` area (siblings sit on 512 too). | **Recommended.** It is literally "on the collision layer phase 1 named for rockets" and gives the counterplay for free: an enemy crossing the path, an asteroid, a mine, or a Ram's plate takes the hit. |
| B. HitBox on 256 only; enemies damaged by a direct `received_damage.emit()` from the rocket's sensor (the nova/dash idiom) | Bypasses type filters and plates; deviates from the scope's layer sentence; a second damage path for one projectile | Rejected |
| C. Rockets never hit enemies | Fails R5.7 | Rejected |

Consequences the plan must accept or reject explicitly:
- **Enemy rockets can strip a Ram's plate** (plates break on `ROCKET`, mask 96). This is emergent counterplay ("bait
  the rocket into the Ram") and the Ph4 Ram Corvette rocket interaction IDEAS §5.7 describes — **recommend accepting it**
  and pinning it with a test. The armoured Ram *hull* refuses the hit via `_on_received_damage` (no `ArmorQuery` on the
  enemy side, so the rocket detonates on the hull rather than passing through — acceptable; judgement).
- **Blast:** `ContactBlast` stays player-only (judgement). An enemy-damaging blast would be a second `ContactBlast` on
  layer 32 and would chain mines and plates; the impact rule already delivers R5.7. Logged as "enemy friendly fire:
  rocket **impacts** only; blasts and beams still undecided (Ph8)".
- **Layer name:** renaming `player_rockets` → `rockets` (value unchanged) makes the semantics honest; it touches
  `project.godot`, `CollisionLayers.PLAYER_ROCKETS` and ~20 references (`defense_profile.gd`'s `accepts_player_rockets`
  exports included, whose rename would touch every scene that authors them — none today). **Optional; recommend
  renaming only the layer name and the constant, keeping the `DefenseProfile` export names** (judgement). Either way
  `test_collision_layer_names.gd` must stay green.
- **Player rockets vs enemy rockets:** the enemy rocket's hurtbox masks 64 only, so player missiles (32) pass through
  enemy rockets; player bullets shoot them down. Rockets stay out of group `enemies`, so player homing never targets them.

### 2.4 Enemy shields and the DamageReaction decision (R5.21, R5.29–R5.32, S4, S11, C8, C9, open questions 1–2)

**Decision P-15 (recommended): do not adopt `DamageReaction` in `BaseEnemy`.**
1. It has no notion of a hit's direction or type (it listens to `received_damage(damage)`), so it cannot express a
   directional or projected shield — the only shields this phase needs.
2. Its `Shield` is a player resource: discrete charges, a fixed 5 s `Timer` regen (brains use accumulated clocks),
   progression binding, a hacked flag.
3. Swapping BaseEnemy's flow for it is churn across ~12 enemies with different needs (AnimationPlayer flash vs tween,
   the station's lingering death, the Ram's deflect override) — the same reason Ph1 deferred it, still true.
4. Nothing a player sees improves.

**Where the hit-aware decision is made.** `HurtBox.received_damage` carries no `HitBox` (C8), and Godot orders
`area_entered` callbacks undefined (C9, the Ph4 plate lesson).

| Option | How | Verdict |
|---|---|---|
| **A. A `HurtBox` absorb hook** | `HurtBox._on_area_entered` asks an optional duck-typed absorber (`absorber.absorbs_hit(hit_box) -> bool`, set by the shield when it attaches, cleared when it detaches) **before** emitting `received_damage`; if absorbed it emits a new `hit_absorbed(hit_box: HitBox)` instead. One decision point per hit, inside the hurtbox that owns the hit, so callback order is irrelevant. A hurtbox with no absorber is byte-identical (the player's included). | **Recommended.** Smallest shared change; every existing `received_damage` consumer and override (Ram, station) is untouched. |
| B. Projectile-side (`ArmorQuery` gains `absorbs_hit`) | The bullet would know, but the damage still lands through the hurtbox; the hull still needs the hit to refuse it | Rejected: does not remove the need for A |
| C. A separate `ShieldArc` `Area2D` part (plate-like) in front of the hull, plus a hull rule | Shots stop visibly at the arc radius | Rejected for now: the hull must still decide per hit (needs A anyway), and a moving arc part on another enemy is a second hurtbox the hurtbox-geometry gate and the parts rule have to reason about. Revisit for Ph10 module shields if needed. |

**Absorbed shots are consumed.** `bullet.gd` stops on a hit unless `ArmorQuery` reports a deflection; the shielded hull
answers neither `deflects_hit` nor `is_armored`, so the bullet expires on the shield — the "shield eats bullets" reading
(F10, F11) — and the hull takes nothing. Direct emitters (nova, dash, shield overload, EMP) bypass the hook exactly as
they bypass plates; the beam calls `received_damage` directly too (C8) — the plan decides whether a shielded ward answers
`is_laser_blocking()` for beams from the arc side (judgement: yes, so the beam reads consistently).

**The shield component** (name it something other than `Shield`, which is taken — e.g. `EnemyShield`): a `Node2D` that
attaches to a host's `HurtBox`, with
- `arc_deg` (360 = bubble), `facing` (a world direction it turns toward the threat at a capped `turn_rate`), `capacity`
  (points), `regen_delay`, `regen_seconds` (empty → full), `reboot_seconds` after a break, an optional `lifetime` /
  heartbeat (`sustain(seconds)`) so a projected shield fades when its projector stops feeding it;
- the rule: a hit whose source lies inside the arc (bearing from the host to the hit box's position, measured against
  `facing`) is absorbed while points remain; **the breaking hit is absorbed whole** (judgement — one hit, one outcome, no
  bleed-through bookkeeping; F10's bleed-through is a player-shield nicety);
- signals `absorbed(hit_box: HitBox, remaining: int)`, `broken()`, `restored()`;
- drawing: a cyan arc hugging the hull (radius = hull + ~6 px) drawn with angles in `_draw()` (no `rotation` writes),
  flaring on absorb, a break burst (F13), a visible refill (F10).

"Temporary resource, not a second HP bar" (R5.29) is met by: small capacity, a regen delay that punishes switching
targets (F10), a break + reboot, **and** a direction (it covers ~110°, not the whole hull), and for the projected kind a
hard dependency on the projector. Shipped consumer: the Support's projection. "Local module" (on a part's hurtbox) and
"bubble" (360°) are fixture-proven (S11).

**Assault (F10's caveat):** an arc that always faces the player is unflankable in a vertical lane. Mitigation: the arc
turns toward the player's bearing at a capped rate (e.g. 90°/s) so lateral movement gets shots around it, and the arc is
narrower in Assault (judgement; config field). The plan should state this as an accepted limitation if it keeps one
width.

### 2.5 Repair (R5.20, S12, C7)

- **Heal path:** `BaseEnemy` gains `repair(amount: int) -> int` (applies `health.increase`, returns HP actually
  restored) and `_on_health_changed` plays the hit flash / burst **only when health went down** (track the previous
  value). Today health never goes up, so no shipped behaviour changes; the station's override calls `super` for
  `current > 0` and is unaffected. Pin: a repair on a damaged enemy flashes nothing; a repair at full HP restores 0.
- **Rate (F12):** small and capped — a continuous `repair_per_second` accumulated into whole HP, **or** a pulse every
  `repair_period` of a fraction of max HP. Recommend the **pulse** (reads as discrete events, cheap to test, F12), with a
  per-support `repair_budget` (total HP it can restore in a life) so a support cannot stall a fight indefinitely
  (judgement, F12 "pulsed, capped").
- **What is repairable:** the ward's hull `Health` only. Never `ArmorPlate`s (plates "physically disappear", IDEAS §23),
  never another Support (F12's no-mutual-heal rule), never the space station, never ordnance.
- **Range and LOS:** repair only within `beam_range`; the beam is a `Line2D` tether drawn support → ward. LOS
  (`TargetInfo.line_of_sight`-style ray) is optional; recommend checking it with the existing `LineOfSight` so asteroids
  break the tether (IDEAS §28 lists the support as an LOS user) — judgement.

### 2.6 Ward selection — "stays behind the highest-threat enemy" (R5.19, R5.24, C10, C11, open question 6)

- **Candidates:** nodes in group `enemies` that are `BaseEnemy`s with a `Health`, alive, not queued for deletion, not
  another Support, not the space station / bosses, within `ward_search_radius` (Open Space) or the view clamp (Assault).
  The only existing ally scan is `FighterBrain._mates()` (`fighter_brain.gd:1531-1541`); reuse its filters.
- **Threat score (judgement):** `score_value` (already on every config: fighter 25, ram 35, sniper 50, bomber 80) as the
  kind weight × a proximity term (closer to the player = more threatening) × a damaged bonus (low HP fraction ranks
  higher, F12's "lowest-HP-fraction" rule folded in). Alternatives: a new flat `ShipConfig.threat` field (touches the
  base config of every enemy; clearer intent) or a duck-typed `support_priority()` (per-enemy code). Recommend the
  derived score now and a config field only if tuning needs it.
- **Stability:** keep the current ward for at least `min_ward_seconds` and switch only when a candidate beats it by a
  margin (×1.3) — no flicker (F12 "keep the choice briefly").
- **Retarget on death (R5.24):** the ward's `tree_exiting` (or `died`) triggers an immediate reselection on the next
  tick; also reselect when the ward is suspended on a rail, starts DISENGAGE (Assault), or leaves range. Ward references
  are validity-checked every tick (`is_instance_valid`). No ward → hold a safe distance near the nearest ally (Open
  Space) or, in Assault, wait `no_ward_grace` then DISENGAGE.
- **Positioning ("behind", soft anchor):** the anchor is `ward + (ward − player).normalized() × follow_distance` plus a
  small lateral offset, sought with `arrive` (Reynolds leader-following, F4), with separation from the ward and an
  `evade`/`break_contact` nudge when the player closes inside `evade_radius` ("high evasiveness", R5.23). The support
  never pursues the player.

### 2.7 Emergency escort (R5.22, S13, C12, open question 7)

- **Trigger:** ward HP fraction ≤ `escort_hp_ratio` (0.35; the legacy Gunship retreated at 0.3, `gunship.gd:21`) while the
  ward has an `EnemyMover` and is not boosting (a charging Ram or dashing Razor ignores nudges anyway).
- **"Pulls the target away":** each tick the support calls `ward_mover.add_nudge(away_from_player × tow_speed)`, capped at a
  fraction of the ward's `max_speed` — a **request** on the ward's own mover (the Ph2 flocking-nudge idiom), never a write
  of its `velocity`, so the single-writer gate stays green. The tether turns into a visible tow beam.
- **"Becomes the closer target itself":** the support's anchor switches from behind the ward to the **interpose point**
  on the ward→player line (judgement; Buckland's "interpose", unsourced), at `interpose_distance` in front of the ward.
- **End:** ward HP back above `escort_release_ratio` (hysteresis, e.g. 0.5 — repair continues during the escort), ward
  dead, ward-player distance beyond `escort_safe_distance`, or `escort_max_seconds`; then a per-ward `escort_cooldown`.
- **Assault:** the tow is clamped by the corridor anyway; escort still triggers (testable in both harnesses).

### 2.8 The Assault view clamp (R5.25, S14, C13, open question 8)

| Option | How | Verdict |
|---|---|---|
| **A. `EnemyWorld.view_rect(tree)`** backed by a new `ArenaCamera.enemy_view_rect()` = `global_position + offset ± viewport / 2` | Correct (includes the camera's offset pan); tests inject the rect like the other provider queries; nothing under `global/` names `ArenaCamera` | **Recommended** |
| B. Player-relative band (stay within N px above the player) | No new provider | Approximates the camera's dead-zone follow; drifts from what is on screen |

Use: the support's anchor is clamped into `view_rect().grow(−margin)`, and it **supports only while inside**
`view_rect().grow(band)` — so hiding above the camera turns its beam and projection off. A test puts the ward above the
view and asserts the support stays visible and stops supporting.

### 2.9 Missile Corvette behaviour (R5.1–R5.9, open question 4)

- **Movement (R5.3):** hold `preferred_range` on **broad arcs**: an `orbit` about the player at a slow angular speed with
  occasional direction reversals (the Razor's reversal idiom) and a slow range drift; never closes inside `min_range`
  (then `break_contact`). A curve is a brain-side `turn_toward` request (Ph2); `turn_rate × speed ≤ acceleration` is
  pinned.
- **Launch cone ("get behind it", R5.1):** rockets leave forward tubes; a salvo starts only with the player inside
  `launch_cone_deg` of the nose, and the nose turns at a capped rate — so a player who circles behind gets a real
  window (judgement; this is what makes the IDEAS verb true).
- **Predicted salvo (R5.4, R5.5):** telegraph (`StateLight` CHARGING + a tube light, `salvo_telegraph`), then a
  `BurstClock` salvo of `salvo_count` rockets at `salvo_gap`. Dumb salvos aim at successive points on the player's
  predicted path (lead times spaced by `salvo_lead_step`) so the salvo covers where the player *will be* and "forces
  turns" (R5.9). Pursuit / cluster / warhead salvos aim at the intercept point.
- **Kind choice (judgement):** by distance and player speed, the Bomber `choose_kind` precedent: far or a fleeing player →
  Pursuit; mid → Dumb salvo on the path; a fast crossing player at range → Cluster; close (< `warhead_range`) → a Delayed
  Warhead pair laid across the predicted path (area denial), then reposition outward. A seeded `rng` jitter avoids a fixed
  rotation.
- **`StateLight`:** CHARGING during the telegraph, ARMED while the salvo fires, OFF otherwise; **never COMMIT** (Ph2/Ph3:
  shooters do not use it).
- **Assault:** one or two salvos per life (`engage_seconds` ≈ 7 s); the budget defers to a started salvo (bounded by
  `salvo_telegraph + (salvo_count − 1) × salvo_gap`), a salvo starts only with that much budget left; DISENGAGE as the
  Bomber; an **attack-in-budget row** (first salvo before expiry from every placed spawn).
- **Rail fallback (Ph3 rule):** a Dumb rocket DOWN every `rail_rocket_interval` while suspended (nothing places it on a
  rail; this keeps a future `.move()` from being silent).
- **Hub idle:** `AnchorIdle` IDLE / NOTICING / RETURNING appended, `start_engaged` seam; RETURNING never interrupts a
  telegraph or salvo; `lose_radius` above the largest distance its own cycle opens (asserted).

### 2.10 Support Ship behaviour (R5.17–R5.27)

- **Phases (sketch):** `SEEK_WARD` (no ward: hold near allies), `FOLLOW` (soft anchor behind the ward; repair pulses;
  projector unfolding then projecting), `ESCORT` (§2.7), `EVADE` (player inside `evade_radius`: break contact laterally,
  keep supporting if in range), `DISENGAGE` (Assault), then `IDLE / NOTICING / RETURNING`.
- **No weapon, contact profile `NONE` (IDEAS §16, R5.26)**: `test_base_enemy.gd`'s `_AUTHORED_CONTACT_MODES` gains
  `support_ship → NONE`; `test_enemy_contact_damage.gd` needs a `NONE`/0 row (the Bonus Drone has a `no_hitbox`
  exception; a NONE profile is the cleaner shape).
- **Low HP, high evasiveness (R5.23):** HP ≈ the sniper's, high acceleration, jinks (rng lateral nudges) while following,
  `break_contact` on approach.
- **Projection:** the support attaches an `EnemyShield` to the ward's hurtbox and keeps it alive with `sustain()` each
  tick while in range / in view / not stunned. An EMP-stunned support (process disabled) stops feeding, so the ward's
  shield fades (C14) — counterplay, and the shield never outlives its projector.
- **Rail fallback:** none needed (not a shooter or area-denier); on `on_suspended()` it drops its ward and turns visuals
  off. State it in the plan.
- **Hub idle:** `AnchorIdle` around the hub Ram's anchor (§3.3); hands over to combat when its ward engages.

### 2.11 Visual states and art (R5.33–R5.36, S18)

- **Corvette (~96 × 96):** wide hull with two visible forward launch tubes; tube lights glow in the telegraph (a child
  `Sprite2D` modulate, the `ArmorPlate.set_glow` idiom). Rockets reuse `rocket.png` (36 × 17, used by the player's
  missiles) recoloured for the faction **or** a new small enemy rocket sprite + `RocketTrail`; the cluster parent is
  fatter, children tiny; the warhead blinks faster as it arms (F9).
- **Support (~88 × 88):** distinct silhouette (a ring or dish projector), a **projector child sprite that unfolds**
  (`scale` lerp with ease-out, the Sniper barrel precedent) while it supports; a cyan tether / shield arc; repair pulses
  pale green or white (judgement — IDEAS §21.1 names cyan for shields only).
- **`StateLight`:** optional new `SHIELD` (cyan) state, or leave the support's state to the projector + tether. Recommend
  the projector + tether (one gameplay signal per state, and COMMIT exclusivity is untouched); the corvette uses the
  existing CHARGING / ARMED.
- Art via PixelLab under the `pixel-art-generation` skill, strict top-down (`view: "high top-down"`), ≤ 90 % opaque
  with a transparent margin; keep sprite node types/names once tests reference them.

### 2.12 Recommended answers to `1-context.md`'s open questions

| # | Question | Recommendation |
|---|---|---|
| 1 | DamageReaction (P-15) | Not adopted; BaseEnemy keeps its flow; enemy shields are a new component (§2.4). Log it. |
| 2 | Where the shield decision is made | A `HurtBox` absorb hook (duck-typed absorber, `hit_absorbed(hit_box)` signal); byte-identical without an absorber (§2.4 A). |
| 3 | Rocket layers / friendly fire | Impact HitBox on 32 \| 256 (ROCKET), hurtbox 512 / mask 64, armed after `arm_distance`, launcher and sibling ordnance ignored; blast player-only; rockets may strip Ram plates (§2.3). |
| 4 | Rocket class | Sibling `EnemyRocket` with the `EnemyOrdnance` contract (§2.2 B). |
| 5 | Owner-distance lifetime | Not built; logged with the reason (S2). |
| 6 | Threat score | Derived: `score_value` × proximity × damaged bonus, with hysteresis and a minimum hold (§2.6). |
| 7 | Escort pull | `add_nudge` tow on the ward's mover + the support interposing (§2.7). |
| 8 | Assault clamp | `EnemyWorld.view_rect()` / `ArenaCamera.enemy_view_rect()` (§2.8 A). |
| 9 | Level-1 placement | DURATION sections only; both counted in the specialist gate; outside planet_approach's peak (§4). |
| 10 | Hub placement | Corvette at 315° on a 1900 px ring; Support shares the hub Ram's anchor and wards it (§3.3). |
| 11 | Visual state | Projector unfold + cyan tether/arc; corvette tube glow + `StateLight` CHARGING/ARMED (§2.11). |

---

## 3. Starting values (judgement unless a finding is cited)

Player reference: Open Space max 420 px/s, boost 700 px/s, thrust 380 px/s² (sustained turn radius ≈ 464 px at max
speed); Assault 360–400 px/s with direct control.

### 3.1 Rockets

| Kind | Launch → cruise (px/s) | Boost (s) | Turn | Guidance | Trigger | Blast r / dmg | Impact dmg | Life / range | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Dumb | 140 → 520 | 0.25 | — | none (aimed at launch) | impact | 36 / 18 | 18 | 3.5 s / 1800 px | fast, straight (F1) |
| Pursuit | 120 → 440 | 0.35 | 1.6 rad/s (~92°/s; radius ≈ 275 px) | 3.0 s, `lead_max` 0.8 s, then coast | impact | 40 / 20 | 20 | 6.0 s / 2400 px | F1/F2/F6 band: 1.05× player cruise, under the boost |
| Cluster (parent) | 120 → 380 | 0.35 | 0.7 rad/s | until split | split at ≤ 260 px from the player or 2.0 s | — (no blast on split) | 20 | 4.0 s / 1800 px | F8: split by distance; shot down pre-split = all gone |
| Submunition | 520 | 0 | — | none | impact | 22 / 10 | 10 | 1.0 s / 600 px | `cluster_count` 4 (3–5), fan 36° total |
| Delayed Warhead | 100 → 200 | 0.35 | 0.6 rad/s | 4.0 s | proximity 70 px once armed (0.6 s), warning 0.4 s blink | 110 / 35 | 35 | 7.0 s / 1600 px | (70 + 110) / 0.4 = 450 ≥ 420 (Ph4 mine rule); a 700 px/s boost escapes |

Common: `arm_distance` = launcher hull radius + 12 px; hurtbox r ≈ 8 px, Health 1. Lifetime rows in
`test_enemy_bullet_lifetime.gd` per kind (two-speed travel bound like the pursuit bomb's), speeds read from the
corvette's config. Rocket speeds never enter `_every_shipped_enemy_bullet_speed()` (round family only).

### 3.2 Missile Corvette and Support Ship

| Field | Missile Corvette | Support Ship |
|---|---|---|
| Size | ≈ 96 × 96 | ≈ 88 × 88 |
| HP / contact / score | 160 / 30 / 70 | 55 / 0 (`NONE`) / 60 |
| `max_speed` / `acceleration` | 210 / 240 | 270 / 700 |
| Range | `preferred_range` 620 (Assault 460), `min_range` 380 | `follow_distance` 150, `beam_range` 380, `evade_radius` 300 |
| Arc / cadence | orbit 0.22 rad/s, reversal every 4–7 s, range drift ±80 px | repair pulse every 1.5 s for 6 % of the ward's max HP (min 1), `repair_budget` 150 HP per life |
| Attack | `launch_cone_deg` 45, telegraph 0.7 s, `salvo_count` 3, `salvo_gap` 0.22 s, `salvo_period` 4.0–5.0 s, `salvo_lead_step` 0.25 s, `warhead_range` 420 | shield `arc_deg` 110 (Assault 90), `capacity` 40, `regen_delay` 3.0 s, `regen_seconds` 1.5, `reboot_seconds` 4.0, arc `turn_rate` 1.6 rad/s, `sustain` heartbeat 0.3 s |
| Escort | — | `escort_hp_ratio` 0.35, release 0.5, `tow_speed` 0.5 × ward `max_speed`, `interpose_distance` 90, `escort_max_seconds` 4.0, `escort_safe_distance` 700, `escort_cooldown` 6.0 |
| Ward choice | — | `ward_search_radius` 900, `min_ward_seconds` 2.0, switch margin ×1.3, `no_ward_grace` 1.5 s |
| Assault | `engage_seconds` 7.0, `exit_speed` 280 | `engage_seconds` 9.0 (or leaves with its ward) |
| Hub | `perceive_radius` 720, `lose_radius` ≥ preferred + drift + a margin (≈ 1500, asserted) | perceive 600 / lose 1300 (the Ram's, since it follows the Ram) |

Shield numbers are F10's band compressed for short fights (delay 3 s rather than 5; refill 1.5 s); a fighter (60 HP)
behind a 40-point arc survives roughly one extra Pulse burst from the front (judgement). Repair: a 120 HP exposed Ram
hull regains ≈ 7 HP per pulse; the 150 HP budget caps one support at about one extra fighter's worth of HP per life
(F12, judgement).

### 3.3 Hub placement

Existing anchors: Swarm (0, 1300), Razor (0, −1300), Fighter (−1500, 0), Gatling (1500, 0), Sniper (−1202, 1202), Bomber
(1202, 1202), Ram (−1202, −1202). Nearest interactable (every `MissionTrigger` / `PickupBase` + player spawn, computed
from `sector_hub.tscn`):

| Candidate anchor | Position | Nearest interactable | Clearance at idle 150 + perceive 720 |
|---|---|---|---|
| 315° on 1700 (the free diagonal) | (1202, −1202) | 1097 px (`ShipBoostUpPickup`) | **+227 px** |
| **315° on 1900** | (1344, −1344) | 1287 px | **+417 px** |
| 315° on 2100 | (1485, −1485) | 1480 px | +610 px |

- **Missile Corvette: 315° on a new 1900 px ring** (recommended): +417 px clearance, 1345 px from the Razor anchor and
  1353 px from the Gatling anchor (> 1000, the existing apart rule). The 1700 ring's 315° works too (+227) but sits
  closest to the pickup bench, which is why Ph4 left it free.
- **Support Ship: shares the Ram Corvette's anchor (−1202, −1202) and wards the Ram** (R5.27 "made possible"): no new
  bearing, the Ram's clearance (+308.7 px) holds if the support's `idle_radius` / `perceive_radius` do not exceed the
  Ram's. `test_sector_hub_patrol.gd`'s "seven anchors > 1000 px apart" becomes eight groups with one shared anchor (or
  the test counts distinct anchors) — the plan states which.
- Both draw their seeds **after** the existing 12 draws.

---

## 4. Assault placement, deadlines and density

**Sections:** deep_space DURATION 30 s, asteroid_belt DURATION 30 s (no enemies), station_assault ENEMIES_CLEARED 180 s
(boss), planet_approach DURATION 110 s, cloud_descent ENEMIES_CLEARED 10 s (default timeout).

- **Missile Corvette → DURATION only.** Its rockets persist after it leaves (`persist_after_owner_death`), and a section
  ends only when the container is empty. Deadline formula if it were in cloud_descent: `rel + engage 7.0 + salvo
  deferral (0.7 + 2 × 0.22 = 1.14) + measured exit (~6–8 s, Bomber-like curved) + rocket max life (≤ 7 s) + 0.5` ≫ 10 s. So:
  a boundary row "a corvette in any ENEMIES_CLEARED last wave misses the timeout" plus "no ENEMIES_CLEARED section contains
  one" (the Bomber rows, `test_engagement_deadline.gd:753`).
- **Support → DURATION only (recommended)**, beside existing rams/snipers. It has no ordnance, so a cloud_descent placement
  is arithmetically possible. But cloud_descent's ram row already passes by only 0.40 s, and the support would add its
  own deadline row (budget + measured exit) to a section with no slack to spare. Not worth the risk in this phase
  (judgement).
- **Density:** `_LEGACY_PEAK_SPECIALISTS` (frozen) with the 2.5× gate; measured peaks deep_space 6 / limit 12.5,
  planet_approach 6 / 7.5 (peak at ≈ 65.7 s), cloud_descent 6 / 10. **Room is in deep_space** (≈ 6 more alive at the
  peak) and in planet_approach away from 65.7 s. Lifetimes are measured exits (Ph4 convention: never a straight line for
  a curved exiter); the corvette's exit gets a `SpecialistExitProbe` measurement.
- **Candidate placements (for the plan to measure, judgement):** deep_space — one corvette ≈ 12 s and a support with the
  26.0 s ram pair; planet_approach — corvettes ≈ 40 s and ≈ 85 s (clear of the 65.7 s peak window, re-measured), a support
  with the 28 s ram triple. Each placement is a new pin row; triggers and offsets of existing rows stay untouched.
- **Attack-in-budget rows:** corvette — first salvo starts before `engage_seconds` from every placed spawn; support —
  first repair pulse or projection on its ward before its budget from every placed spawn (the "proves it acts" analogue).
- Late spawns may live into the next section (DURATION → DURATION, as Ph4 accepted); deep_space's corvette rockets
  spilling into asteroid_belt can hit asteroids (intended, R5.7).

---

## 5. Testing requirements → gates

| Requirement | Test (new unless stated) | Harness |
|---|---|---|
| Rocket steers toward the predicted point (R5.39) | `test_enemy_rockets.gd`: the Pursuit heading converges on `intercept()`'s point for a constant-velocity target; turn per tick ≤ `turn_rate × delta`; heading frozen after `guidance_seconds` | both |
| Dodgeable (C6, F1/F6) | straight-away player at 420 not caught; perpendicular 700 boost at 150 px missed; stationary hit; turn-radius config inequality | both |
| Cluster splitting (R5.39) | splits at ≤ `split_distance` (and at `split_time` when the player is far); exactly `cluster_count` children in the fan; children unpooled, freed on expiry; parent shot pre-split → no children; children never hit each other or the parent; split after the corvette died still works | both |
| Proximity detonation (R5.39) | warhead does not trigger before arming; triggers inside `trigger_radius`; blast after `warning`; Ph4 inequality asserted from config; boost escapes, cruise does not | both |
| Shoot-down | a player bullet defuses any kind (no blast); a player rocket passes through | open_space |
| Friendly fire (S6) | impact damages an enemy crossing the path; blast does not; launcher not hit at launch (C1); siblings not hit (C2); a rocket strips a Ram plate (C3); asteroid hit | both / fixture |
| Lifetime | per-kind rows in `test_enemy_bullet_lifetime.gd` (two-speed bounds), speeds from config; `persist_after_owner_death` hand-over for rocket pools | — |
| Repair (R5.39) | heals a damaged ward by the pulse amount at the period; capped at max; no flash (`_on_health_changed` decrease-only); budget exhausts; out of range / out of view stops | both |
| Shield application (R5.39) | absorbs a hit from inside the arc (bullet consumed, hull HP unchanged); a hit from behind lands; capacity → break → reboot → regen delay/refill; fades without `sustain`; bubble (360°) and part-hurtbox fixtures; `HurtBox` without an absorber is unchanged (unit) | both / unit |
| Retarget on ally death (R5.24, R5.39) | free the ward → new ward selected next tick; ward suspended / disengaging → reselect; no candidates → grace then DISENGAGE (Assault); never wards another support | both |
| Escort trigger (R5.39) | at ≤ `escort_hp_ratio` the ward's mover receives a tow nudge away from the player and the support moves to the interpose point; ends on release ratio / timeout; single-writer gate green | both |
| Assault view clamp (R5.25) | ward above the view → support stays inside `view_rect`, stops supporting while outside; provider injected | assault |
| Corvette range / arcs / cone | holds `preferred_range` ± tolerance on an arc; never inside `min_range` for long; no salvo with the player behind the cone; salvo = `salvo_count` rockets at `salvo_gap` after the telegraph; StateLight CHARGING → ARMED, never COMMIT | both |
| Attack-in-budget (Ph4 convention) | both enemies, every placed level-1 spawn, real `WaveManager`, 8× clock | assault |
| Deadline / placement | corvette boundary + "no ENEMIES_CLEARED section contains one"; pin rows for the new placements; specialist count gate includes both kinds | — |
| Hub | clearance rows (corvette at 315°/1900; support at the Ram's anchor), seed order unchanged, frame-0 IDLE list, a corvette rocket lands in `EnemyContainer`, the hub support wards the Ram | open_space |
| Rosters | contact damage (support `NONE` 0, corvette 30), contact geometry, hurtbox geometry, `_AUTHORED_CONTACT_MODES`; config isolation / sprite transparency / single writer pick them up automatically | — |
| Collision names | `test_collision_layer_names.gd` green after any rename | — |

**Gate time:** hand-ticked specs (`_tick()`) for steering, splitting, shields, repair and escort; awaited physics only
for the attack-in-budget rows and the hub, on the 8× clock. Measure with `time bash /agent/verify.sh` after each heavy
task (~257 s of ~300 s today).

---

## 6. Notes for the plan stage (sizing, ordering)

- **Foundations first, each independently testable:** (1) `HurtBox` absorb hook + `EnemyShield` (fixtures: arc, bubble,
  part); (2) `BaseEnemy.repair()` + decrease-only flash; (3) `EnemyWorld.view_rect()` / `ArenaCamera.enemy_view_rect()`;
  (4) the `EnemyRocket` family (one task per guidance kind is likely too small; Dumb + Pursuit together, Cluster, Warhead —
  plus the lifetime rows); (5) the layer rename, if taken, as its own small chore before rockets land.
- **Missile Corvette:** shell (scene, config, pools, rail fallback) → behaviour (arcs, cone, predicted salvos, kind
  choice) → art → hub idle. **Support Ship:** shell → ward selection + follow + repair → projection → escort → art → hub
  idle. Repair, projection and escort are separate tasks; each is a verifiable outcome.
- **Placement:** hub (both groups, one task) → level 1 (both enemies, pins, deadline boundary, density, attack-in-budget
  rows) → docs (roster, module docs, CLAUDE.md gate paragraph, DECISIONS as-built).
- **Likely large (own plan + review):** the shield hook + component (shared component change; ordering and consumption
  semantics), the corvette's behaviour task (salvo prediction and kind choice), the support's ward/escort task, and the
  level-1 placement task (density and deadline arithmetic) — the Ph4 pattern, where the behaviour and placement tasks
  each needed their own plan.
- **Decisions to log in `DECISIONS.md` at the plan stage:** P-15 closed (no DamageReaction), owner-distance lifetime not
  built (S2), container injection deferred again (S3), enemy friendly fire = rocket impacts only (S6), the layer rename
  (if taken), the view-rect provider, ward-selection and escort rules.
- **Owner questions worth surfacing in the plan summary:** accept rockets stripping Ram plates? A single shield arc width
  in both modes, or narrower in Assault? Repair budget per support (stall guard) — yes/no?
