# Enemy rework, phase 4: Bomber, Sniper and Ram Corvette — PRD

## The ask

> Enemy rework, phase 4 of 20. This phase delivers the first three specialists. Each adds one new battlefield mechanic:
> persistent ordnance, a precision shot from a relocated firing position, and breakable armour. The Bomber approaches at an
> angle, sets up a bombing line on the player's predicted path, not their current position, and escapes on an arc. It chooses
> between a gravity bomb, a mine cluster laid in an arc and a pursuit bomb. All of them can be shot down, and in Assault their
> placement is clamped to the corridor. The Sniper's core behaviour becomes a native relocation loop that replaces the
> path-authored retreat and the FLY_IN_TIME coupling. It creates distance (break_contact), picks a varied firing offset relative
> to the player's velocity and facing, and holds still during the telegraph and lock, which is the player's window. It then
> fires a rail shot with a residual trail and disengages rather than returning. It does not fire when line of sight is blocked,
> which needs a real can_see_player() raycast in place of the phase-1 stub. The Ram Corvette gets three independently breakable
> armour plates. The armour is a deflection rule on a full-size hurtbox, which respects the hurtbox-geometry gate and the
> is_armored() convention, not the old layer-based bullet immunity. The Corvette also gets a telegraphed predicted-intercept
> charge with an overshoot and wide turn, a vulnerable faster hull once the plates are gone, and the Armor collision contact
> profile. Enemy projectiles gain persist_after_owner_death, so mines and bombs outlive their owner without breaking the
> one-owner rule. Level-1 spawns of the old Bomber, Sniper and Ram Ship are migrated, and the three new enemies join the hub's
> ambient spawn. Their sprites show the required visual states: the sniper's weapon unfolds, and the Ram Corvette's plates glow
> and then disappear. Tests in both harnesses cover mine/bomb placement against the predicted path, a new firing position every
> cycle, stationarity during the telegraph, post-shot disengage, the LOS refusal, plate-by-plate vulnerability and charge
> direction.
>
> **Scope of this phase:** ENEMIES_OPEN_SPACE_REWORK_IDEAS.md: §5.5 Bomber (all three ordnance types, smart bombing, Assault
> adaptation); §5.6 Sniper (all of it, including the decoy telegraph behind a difficulty flag); §5.7 Ram Corvette (all of it);
> §3.2 break_contact primitive; §12 persist_after_owner_death; §13.1 Armor; §16 Armor collision profile; §28 line of sight (real
> can_see_player()); §31 removing the sniper FLY_IN_TIME/path coupling; §38 scrapping the fixed-screen bomber movement and the
> path-authored sniper retreat; §23 visual states and §21–23 sprites for these three; §40 behaviour tests (the sniper chooses a
> new firing location, the ram changes vulnerability after armour destruction; mines) in both modes; §41 Phase 3 items 1–3.
> Also: level-1 spawns of these enemies migrated and SectorHub ambient spawn extended.

### Original idea

> Analyze the files with ideas, add improvements to it if you have any great ideas, research and create a plan to implement ALL
> those ideas. Be sure, to add in the review all changes you proposed at the top of the document, if you have any.
> ENEMIES_OPEN_SPACE_REWORK_IDEAS.md - file with all ideas proposed. ENEMIES.md - current implementation.

Attached documents, preserved verbatim in the repo: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`
and `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES.md`. The epic's approved plan
(`docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md`, **Revision 2**) reflects them. See phase 1's PRD for how the idea was split
into 20 phases.

### The owner's notes (plan review)

The AI plan review's second round returned CHANGES_REQUESTED (B1, B2, N1–N10). The owner started the epic without a re-plan, so
the findings were handed to the tasks that own them as corrections that win over the plan text:

- **B1 (blocking)** the mine wall could not hurt a player who holds course, and the live-player test could not see it. Applied in
  t6 (the mine polls its overlap from launch) and t9/t10 (`mine_warning` 0.25 s with an asserted inequality, the wall-margin
  term, the live-player outcome test, and the rejected "boosting right -> mine chain" example recorded rather than honoured).
- **B2 (blocking)** `ArmorPlate.deflects_hit` depended on the order of physics callbacks. Applied in t4 (one idempotent
  `_resolve(hit_box)` called from both paths) and t16.
- **N1–N10** (task ordering, replay start time, sniper spawn classes, the ram's attack floor, the centred-ram side tie-break, one more legacy test, the Assault live-player set-up, stale DECISIONS wording, a shared attack-in-budget helper, the warhead geometry constraint) were applied, or declined with a reason, by the task each concerns; each task's plan or final report says which (for example t22 applied N2 by replaying Cloud Descent from 0.0 s, and t17 applied N4 and N5).

### The epic's tasks (titles verbatim; full descriptions and acceptance criteria are in `docs/plans/cmufs7ele0015nm2xvag3vrwc/tasks.json`)

| Key | Task |
|---|---|
| t1-pin | Level 1's sniper, ram and bomber spawns and their legacy density are pinned before anything about them changes |
| t2-break-contact-los | Enemies can deliberately break contact with the player, and can tell whether a rock blocks their line of sight |
| t3-persist-pool | A pool can let its projectiles outlive the ship that fired them, with exactly one owner at every moment |
| t4-armor-query | Armour can deflect bullets while letting rockets break it, and homing rockets steer at the armour plate instead of parking inside a hull |
| t5-contact-armor | An armoured enemy can hurt the player on touch at all times without ever exploding or dying from the contact |
| t6-ordnance | Enemies can drop gravity bombs, proximity mines and pursuit bombs that blink before they go off and can be shot down |
| t7-rename-ram | The Ram Ship is renamed the Ram Corvette everywhere with no change in how it plays |
| t8-rename-sniper | The Sniper Enemy is renamed the Sniper everywhere with no change in how it plays |
| t9-bomber-shell | The Bomber is rebuilt as an AI enemy whose bombs outlive it, still dropping today's bombs on rails and leaving Assault cleanly when its time is up |
| t10-bomber-runs | The Bomber angles in, lays mines, bombs or a pursuit bomb across where the player is heading, then escapes on an arc |
| t11-art-bomber | The Bomber has its own wide, readable top-down sprite: dark hull, cool edge light, red stripe, visible bomb bays |
| t12-sniper-shell | The Sniper is rebuilt as an AI enemy with a rail shot and its own telegraph, still firing like today on rails, with no fly-in timing constant left |
| t13-sniper-cycle | The Sniper backs off, slides to a fresh firing angle, holds dead still while it aims and locks, fires a rail shot with a fading trail, then breaks away - and holds fire if a rock is in the way |
| t14-sniper-decoy | On a higher-difficulty flag the Sniper can flash a fake orange aim line before its real one, never looking like a lock |
| t15-art-sniper | The Sniper has a narrow top-down hull sprite and a separate barrel that visibly unfolds when it aims |
| t16-ram-armour | The Ram Corvette wears three armour plates: bullets glance off with a flash, each rocket knocks off the plate it hits, and only then does the hull take damage |
| t17-ram-charge | The Ram Corvette lines up on where the player will be, glows while it charges, rams through and past that point, swings wide - and turns faster and jinkier once its plates are gone |
| t18-art-ram | The Ram Corvette has its own hull sprite and separate armour-plate sprites that can glow and fall away |
| t19-specialist-idle | In Open Space the Bomber, Sniper and Ram Corvette drift calmly around their patrol point until the player comes close, then attack |
| t20-hub | The Open Space hub has a Sniper, a Bomber and a Ram Corvette on patrol, well clear of the planets, pickups and the spawn point |
| t21-level1-duration | In level 1's deep-space and planet-approach sections, snipers, rams and bombers arrive at the same moments and places as before, then fight on their own and leave |
| t22-level1-cloud | In level 1's cloud-descent section the snipers and rams fight off rails too, and the section still clears in time for the level to move on |
| t23-docs | Project docs, the enemy roster and the decision log describe the Bomber, Sniper, Ram Corvette and enemy ordnance as actually built |

## Player-facing goal

Three enemies that each ask for a different answer:

- **The Bomber** is a wide, slow target that angles in and leaves what it dropped on the line you are flying along — a mine
  wall, a gravity bomb, a pursuit bomb. It rewards turning, stopping or reversing, and every piece of ordnance can be shot
  down. Killing the Bomber does not clear its mines.
- **The Sniper** backs away, slides to a fresh angle, then holds dead still while a red line tracks you and turns white on
  lock. That stillness is your window, and the shot is followed by a break-away, never a camp. A rock in the way means no
  shot. On a higher-difficulty flag a dim orange fake line precedes the real one.
- **The Ram Corvette** is a battering ram you have to open: bullets glance off, each rocket knocks off one of three plates, and
  then the hull is a faster, jinkier, vulnerable target. It lines up on where you will be, glows through a wind-up (your
  window), rams through the point and swings wide.

All three patrol the Open Space hub until you come close, and level 1 spawns them off rails at the same moments and places as
before.

## Scope

**In scope:** the three enemies with their brains, configs and art; `break_contact`, real line of sight, `persist_after_owner_death`,
the armour query and `ArmorPlate`, the ARMOR contact profile, enemy ordnance; level-1 migration of all 50 sniper / ram / bomber
lines; the hub patrol; the gates in `CLAUDE.md`.

**Explicitly out of scope** (deferred, with owners in `DECISIONS.md`'s "Handed to later phases"): owner-distance lifetime and
enemy rockets (Ph5), mine variants and the Mine Layer (Ph7), LOS blockers in shipped content (Ph6 / Ph19), modular damage beyond
three plates (Ph10), a station `homing_point` (Ph11), squad messages (Ph14), difficulty tiers (Ph16), and taking
`level_2_waves.gd` and the station's reinforcements off rails (Ph15).

**Where the epic was split:** 23 tasks in a chain — primitives first (t1–t6), renames (t7–t8), then one shell / behaviour / art
trio per enemy (Bomber t9–t11, Sniper t12–t15, Ram t16–t18), hub (t19–t20), level 1 in two steps (t21–t22), docs (t23).

## Constraints

- **View rule:** `assault/` and `open_space/` are strict top-down orthographic; all art through PixelLab with the
  `high top-down` view and a visual check (the plates were drawn by script).
- **Design-unit coordinates** for level spawns (640×360, scaled by `WORLD_SCALE`).
- **One owner per projectile** — hence the pool hand-over instead of a re-parent to the level.
- **Hurtbox-geometry gate** — armour is a deflection rule on a full-size hurtbox, never a narrowed one.
- **Single writer of motion** — brains request, `EnemyMover` writes; the empty allowlist holds.
- **Config isolation, signal arity, sprite transparency, UID integrity, project-load integrity** stay green.
- **Level 1 timing preserved** — every trigger, offset and delay pinned; the Cloud Descent `ENEMIES_CLEARED` timeout (10 s) is a hard
  deadline the AI enemies' budgets must fit.
- **The gate's wall clock** (~300 s) — real-physics tests run on a scaled clock.

## Open questions at the time

| Question | How it was resolved |
|---|---|
| Names | `Bomber` kept; `ram_ship/` -> `ram_corvette/`, `sniper_enemy/` -> `sniper/` (`WaveBuilder.ram()`, `sniper()`, alias `sniper_enemy()` kept). |
| Armour query | Plate child parts plus an additive `deflects_hit(hit_box)` with `is_armored()` as the fallback (`ArmorQuery`). |
| Ordnance pooling and the flag | `BulletPool.persist_after_owner_death`, ordnance pooled; built in Ph4 rather than Ph5. |
| Bombers in `ENEMIES_CLEARED` | Barred by a deadline boundary row; no level-1 `ENEMIES_CLEARED` section contains one. |
| What breaks plates | Rockets, and any projectile answering `is_high_impact()` (the player's Sniper Shot). The beam and modules are deflected while armoured. The `ram_ships` rule is retired. |
| Assault Ram budget | One charge per life; `engage_seconds` 4.0 after the pre-approved levers (4.5 was the research's start value). |
| Sniper range | Open Space 900 ± 100; Assault 680 ± 80, firing point inside `inner_rect().grow(−fire_margin)`. |
| Decoy flag | `SniperConfig.decoy_telegraph` default `false`; a CHARGING-only line, never COMMIT. |
| Rail shot | An inherited pooled `rail_round.tscn` plus a code-built `RailTrail`; the old scene deleted. |
| Hub placement | Three lone patrols on the free diagonals of a 1700 px ring, appended to the seeded draw order. |
| Does killing the Bomber clear its mines? | No: persistence is the point (scope). Recorded as a design choice from the shmup "bullet cancel" convention. |
| Can a boosting player be walled in by mines? | No. Recorded, not honoured (review B1e); a boosting player gets a pursuit bomb. Owner question for Ph16. |
