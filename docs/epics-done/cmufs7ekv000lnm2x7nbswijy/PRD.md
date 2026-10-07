# Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family — PRD

## The ask

> Enemy rework, phase 3 of 20. This phase delivers the two gun-armed Tier 1/2 enemies. They replace the Light Assault
> Ship and the Interceptor, which fly on paths today, with pilots that fly attack runs. The Fighter makes passes with
> acceleration and a turn radius: approach, pass beside the player, burst, wide turn, reposition, second pass. It
> chooses between an aimed predicted burst of 3–5 shots and a forward burst of 5–7 shots based on distance, not on a
> spawn property. The Gatling Interceptor becomes a suppression unit. It keeps side-on range and swings through the
> player's flank, firing pressure windows (spin-up, an 8–12 round stream, cooldown, reposition) instead of a constant
> 11 shots/s. That settles the documented ambiguity over whether it fires forward or at the player. Paired
> interceptors can use convergence fire. The phase-2 SquadController gains the fighter roles (pincer flanks plus a
> frontal pass). WaveBuilder formations (V, W, wedge, line, diagonal, cluster) become spawn layouts that hand off to
> squad roles when the enemies activate. The enemy bullet family (Pulse Round, Scatter Round, Gatling Stream, Heavy
> Shell) is built on the pooled EnemyBullet with ProjectileLifetime, so later enemies can pick a round instead of
> retuning one bullet. Level-1 spawns of the Light Assault Ship and the Interceptor move to the new enemies under the
> corridor constraint with timing preserved, and both enemies join the hub's ambient spawn in Open Space. New strict
> top-down 56–72 px sprites follow the readability rules. Tests in both harnesses cover pass geometry, weapon-mode
> switching by distance, fire cadence and pressure-window rhythm, role reassignment and formation-to-role handoff.
>
> **Scope of this phase:** ENEMIES_OPEN_SPACE_REWORK_IDEAS.md: §5.3 Fighter (all of it); §5.4 Gatling Interceptor (all
> of it, including convergence fire); §11.1 bullet family (Pulse, Scatter, Gatling Stream, Heavy Shell); §17 and §35
> formations as spawn layouts plus fighter role assignment and dynamic regrouping (extending the phase-2
> SquadController); §21–23 readability and sprites for these two enemies; §40 combat tests (fire cadence, weapon
> selection) for them in both modes; §41 Phase 2 items 3–4. Also: level-1 Light Assault Ship and Interceptor spawns
> migrated to spawn layout + corridor constraint, and both added to the SectorHub ambient spawn.

### Original idea

> Analyze the files with ideas, add improvements to it if you have any great ideas, research and create a plan to
> implement ALL those ideas. Be sure, to add in the review all changes you proposed at the top of the document, if you
> have any. ENEMIES_OPEN_SPACE_REWORK_IDEAS.md - file with all ideas proposed. ENEMIES.md - current implementation.

Attached documents, preserved verbatim in the repo: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`
and `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES.md`. The epic's approved plan
(`docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md`, **Revision 2**) reflects them. See phase 1's PRD for how the idea was
split into 20 phases.

### The epic's tasks (titles verbatim; full descriptions and acceptance criteria are in `docs/plans/cmufs7ekv000lnm2x7nbswijy/tasks.json`)

| Key | Task |
|---|---|
| t1-pin | Level 1's fighter and interceptor spawns, their legacy density and the station's rail reinforcements firing are pinned before anything changes |
| t2-rounds | Enemy rounds read differently: a red-pink Pulse bolt, a short-range Scatter pellet, a thin Gatling streak and a big slow Heavy Shell exist as pooled rounds any enemy can pick |
| t3-burst-patterns | Enemy bursts fire an exact number of shots, and 'fire forward' goes out of the nose whichever way a sprite was drawn |
| t4-convergence-field | A squad can share one convergence aim point that disappears the moment its leader changes |
| t5-w-formation | Level authors can lay out a W formation as well as V, wedge, line, diagonal and cluster |
| t6-rename-fighter | The Light Assault Ship is renamed the Fighter everywhere with no change in how it plays |
| t7-rename-gatling | The Interceptor is renamed the Gatling Interceptor everywhere with no change in how it plays |
| t8a-fighter-shell | The Fighter is rebuilt as an AI enemy that still behaves exactly as before on rails, and in Assault leaves the corridor cleanly when its time is up |
| t8b-fighter-run | The Fighter flies attack runs: it passes a set distance beside the player, bursts, makes a visible wide turn and comes back, choosing an aimed or a close-range burst by distance |
| t9-fighter-squad | Three fighters close as a pincer while a fourth comes head-on, extra fighters wait their turn, and a fallen fighter's place is taken at once *(the "fourth" is a deviation, see below)* |
| t10-gatling-windows | The Gatling Interceptor holds side-on range and fires readable pressure windows — yellow spin-up, one 8–12 round stream, a pause, then a swing to the other flank — and still fires on rails |
| t11-gatling-convergence | Two Gatling Interceptors charge together and cross their streams at the player's likely next position from the same side, leaving the other side open |
| t12-shooter-idle | In Open Space, fighters and Gatlings drift calmly around their patrol point until the player comes close, then turn to fight, and drift home when the player leaves |
| t13-hub-patrol | The Open Space hub has a fighter pair and a Gatling pair on patrol, well clear of the planets, pickups and the spawn point |
| t14-art-fighter | The Fighter has its own readable top-down sprite: dark hull, cool edge light, red stripe, clearly a fighter |
| t15-art-gatling | The Gatling Interceptor has its own readable top-down sprite with a visible rotary cannon, unmistakable from the Fighter |
| t16-level1-duration | In level 1's deep-space and planet-approach sections, fighters and the Gatling pair arrive at the same moments and places as before, then fight as squads inside the corridor and leave |
| t17-level1-cloud | In level 1's cloud-descent section the fighters fight off rails too, and the section still clears in time for the level to move on |
| t18-docs | Project docs, the enemy roster and the decision log describe the Fighter, the Gatling Interceptor and the bullet family as actually built |

### Human feedback (plan review of Revision 1, verbatim intent)

Preserved in full in `docs/plans/cmufs7ekv000lnm2x7nbswijy/4-review.md`. **Round 1 — `CHANGES_REQUESTED`.** The reviewer
confirmed the structure (reuse of `SquadController`, `EngagementBudget`, `AnchorIdle`, `StateLight`, `turn_toward`; a pin
before migrating; the rail fallback shipped with the scene swap) and blocked on six points, four of which were geometry or
timing specs that were internally inconsistent — "the Razor t10 notes show this exact failure mode: geometry mis-specified
on paper, found live":

- **B1** the fighter's pass geometry flew it ≈ 67 px from the player (a near-ram) because both the start point and the pass
  point were offset along the same perpendicular;
- **B2** Gatling convergence was mis-sequenced (the two lights could be 0.5–1.5 s apart, the FLANK often streamed after the
  window closed, so convergence silently never happened);
- **B3** the Assault Gatling's "opposite half of the corridor" side rule contradicted the REPOSITION flip;
- **B4** the cloud_descent deadline arithmetic was wrong (`waves_complete` fires on the 76.0 s trigger, not 76.8 s) and the
  formula was missing the burst-deferral term;
- **B5** t2 could not meet its own acceptance criteria (the config fields it must read did not exist yet) and collided with
  t6/t7;
- **B6** the legacy density baselines were computed from rail data that t16 deletes.

Ten should-fix points followed (pool sizing ignored the rail cadence; "bit-identical" claims were false by 2π for the upper-left
quadrant; pool placement under an `AttackController` would carry bullets with the ship; art tasks missed `_rotate_sprite`;
the fighter window had no close rule; role side vs the no-cross-over test; §1 overstated the pincer; `WFormation` needed a
class; t8 was too big; t7 was mis-sized). **Round 2 — `APPROVED`**, with implementer notes N1–N12 (measure a moving player
against `P̂`; migrate the two existing `sprite_forward_angle` readers; the FLANK takes the LEAD's *intended* side; one
`min_burst_period` field; a config-derived deadline boundary; the legacy Gatling's shots/s is `min(1/interval, pool/lifetime)`;
and six minor points), all applied in Revision 2.

## Player-facing goal

Today (before the phase): the Light Assault Ship flies a fixed rail, fires one shot at a time, and is a target that never
changes; the Interceptor rides a rail and holds down a constant 11-shot-a-second hose. After this phase: a **Fighter**
sweeps in on a pass at a set distance beside you, fires a short readable burst (a yellow light shows 0.3 s first), swings
wide, comes back, and — if you let it get close enough with its nose on you — sprays a short-range forward burst instead;
three fighters in a squad come as a pincer plus a head-on pass, extra fighters wait their turn, and a killed fighter's slot
is filled at once. A **Gatling Interceptor** holds a flank, shows a yellow light, lays one aimed stream where you are
*going*, goes quiet, and swings round to your other side; two of them cross their streams from the same side, leaving the
other open. Their rounds are visibly different (a red-pink Pulse bolt, a short pink Scatter pellet, a thin Gatling streak,
a heavy slow Shell that no enemy fires yet). In Open Space the hub now has a fighter pair and a Gatling pair idling on
patrol, clear of the spawn, planets and pickups — fly close and they turn to fight, fly away and they drift home. In
Assault level 1 the same ships arrive at the same moments and places, now fight inside the corridor and leave in time for
the level to move on.

## Scope

**In scope:** the four-round enemy bullet family and `EnemyRounds`; `BurstClock`; the nose-correct "fire forward" and
`sprite_forward_angle_of`; `SquadController`'s convergence fields; `WFormation`; the Light Assault Ship → Fighter and
Interceptor → Gatling Interceptor renames; the Fighter brain (attack runs, weapons, squads, idle, rail fallback, Assault
exit) and the Gatling brain (windows, convergence, idle, rail fallback, Assault exit); new 64×64 sprites for both; the hub
patrols; level 1's 64 fighter / Gatling spawns off rails; the invariant and measured gates around all of it.

**Explicitly out of scope (deferred to named later phases):** every other enemy (the Gunship, Bomber, Sniper and Ram keep
the legacy `enemy_bullet.tscn`) — Ph4/5/10; taking the station's reinforcements off rails (Ph15); `BulletPool` container
injection and owner-bound projectile lifetime (Ph5); cross-squad arbitration and idle profiles for other families (Ph14);
the `EncounterDirector` and leash (Ph13); difficulty tiers (Ph16); muzzle flashes, spin-up particles, enemy SFX and recolouring
the legacy bullets (Ph17); level 2.

## Constraints

- **View rule:** `assault/` and `open_space/` are strict top-down orthographic; both sprites were specified under the
  `pixel-art-generation` skill (`view: "high top-down"`, `isometric: false`) and keep their node type and name so
  `_rotate_sprite`, the hit-flash track and the flip-list test stay valid.
- **Coordinate space:** level-1 waves stay in 640×360 design units; nothing pre-multiplies `ArenaCamera.WORLD_SCALE`.
- **Single-writer rule:** all motion goes through `EnemyMover` plus `Steering.turn_toward`; `SquadController`, `DubinsPath`,
  `BurstClock` and `AnchorIdle` move nothing.
- **Config:** flat `*_config.tres` copied per instance (`ShipConfig.privatise()`); every shooter's `rail_*` fields are config,
  so the round-lifetime sweep reads them.
- **Pools:** a pool is a direct child of the enemy root; sized for the AI burst and the rail cadence.
- **Gate:** every existing invariant test stays green; `bash /agent/verify.sh` and `scripts/check-test-leaks.sh` must be clean.
- **Process:** a large task starts only on an approved plan. Five tasks (t8b, t9, t10, t16, t17) were planned and reviewed
  on their own; t9 and t16 first ended a run **escalated, nothing built**.

## Open questions at the time, and how each was resolved

| Question | Resolution |
|---|---|
| Does the Gatling fire forward or at the player? | At the player — every round is aimed at a *predicted* point. The shipped code already did (`aim_at_player` defaults to `true`); only two docs claimed otherwise, and they are corrected. What keeps it side-on is the movement. |
| Is a four-attacker pincer + frontal pass readable? | No (research finding 1: everything firing at once reads as noise). **At most three fighters attack** (LEAD frontal + two flank lanes); a fourth and later are dry REARs. Recorded as a deviation from IDEAS §5.3. |
| How does a fighter fly a pass that is *actually* `pass_offset` beside the player? | B1's rewrite: bearing `b`, run direction `u = −b`, lane `l ⟂ u`, the start point *on* the pass line. Building it needed a turn-radius-limited lead-in that arrives pointing along the run, which the plan did not have: `DubinsPath`. |
| How do two Gatlings cross streams without the second one firing at nothing? | B2's rewrite: the window opens at the LEAD's SWING_IN, both hold in SPIN_UP until both are *ready* (own spin-up elapsed) or `sync_wait_max`, the point refreshes every tick, and the window closes on the later COOLDOWN. |
| Can the level-1 shots/s gate be a formula? | No. The analytic figure failed 1.86× / 1.90× with no pre-approved lever able to fix it, while the real run is far quieter. **Owner decision (option A): measure it.** |
| Does the fighter's exit fit the cloud_descent timeout? | Only with the *curved*-exit bound (5.37 s, gated on the real scene) — the Razor-shaped straight line under-reported by 2.5 s. Margin 0.53 s analytic / 0.93 s measured. |
| Can a fighter squad keep its members apart? | For the first window and a full two-pass cycle in 168 layouts, yes, with brain-local give-way rules. After a death, and for V6, not always. Left open; see the report. |
| Does a Gatling REAR hold back and never fire? | Specified in §2.6.1, **not built**; nothing places three in a squad yet. |
| Does the Heavy Shell need a consumer now? | No. It ships tested by a fixture shooter; its first consumer is Ph4 or Ph10. |
