# Enemy rework, phase 4: Bomber, Sniper and Ram Corvette — completion report

Epic `cmufs7ele0015nm2xvag3vrwc`. Plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (**Revision 2**), review history in
`4-review.md`, tasks in `tasks.json` (23 tasks: t1–t23). The decision log's **"Phase 4 - as built"** section in
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` is the index of every deviation; this report is the narrative. Where this
report and the per-task "built in tX" notes differ, "as built" wins.

## What was built

### Primitives (t1–t6, one commit each)

| Task | What shipped | Commit |
|---|---|---|
| t1 pin | `test_level1_specialist_spawns.gd` pins all 50 sniper / ram / bomber rows (26 / 22 / 2) of level 1 by section, trigger, offset and delay, with the legacy peak constants `_LEGACY_PEAK_SPECIALISTS` frozen. | `62089d5` |
| t2 break contact + LOS | `Steering.break_contact`, `EnemyMover.break_contact`, `LineOfSight` (`global/enemy_ai/line_of_sight.gd`, opt-in blockers, ≤ 4 recasts), a real `TargetInfo.line_of_sight()`; `test_line_of_sight.gd`. | `f5b154e` |
| t3 persist pool | `BulletPool.persist_after_owner_death` with `_hand_over_active()` (disconnect the recycle callable, connect `expired -> queue_free`, drop from `_active`); `tests/unit/test_bullet_pool.gd`. | `e4fcc0e` |
| t4 armour query | `ArmorQuery` (`deflects_hit(hit_box)` first, else `is_armored()`), `ArmorPlate` with one idempotent `_resolve`, `Bullet.is_high_impact()`, `homing_point` for homing rockets; `test_armor_query.gd`. | `eb7af66` |
| t5 ARMOR contact | `ContactProfile.Mode.ARMOR` (value 4) with `shove_speed`; `OpenSpacePlayerShip.apply_knockback()`. | `048849a` |
| t6 ordnance | `EnemyOrdnance` (gravity bomb, mine, pursuit bomb) in `projectiles/enemy_ordnance/`, `EnemyOrdnanceScenes`; per-kind lifetime rows; `test_enemy_ordnance.gd`. | `26a2bec` |

### Renames (t7, t8)

`ram_ship/` -> `ram_corvette/` (`RamCorvette`, `RamCorvetteConfig`) and `sniper_enemy/` -> `sniper/` (`Sniper`, a new
`SniperConfig`), by `git mv` so `.uid` sidecars moved; every gate roster, the station's reinforcement table, `WaveBuilder`
(`ram()`, `sniper()`, alias `sniper_enemy()` kept) and docs updated; no behaviour change (the t1 pin stayed green). Commits
`ca1254a` (t7), `d3582a5` (t8).

### The Bomber (t9–t11)

- **t9** (`1f150aa`): `bomber.tscn` rebuilt as an AI scene — `BomberBrain`, flat `BomberConfig`, a 96 × 44 body shared by body,
  hurtbox and contact box, three `persist_after_owner_death` pools (4 / 10 / 4), `Bomber.drop()`. Rail fallback: a gravity bomb
  DOWN every 1.2 s. Assault DISENGAGE. `bomb.gd` / `bomb.tscn` deleted.
- **t10** (`d2fccdd`, task plan `cmuyk2qpr0089oa2xlih7xvmg`, three revisions, six attempts): the bombing runs. The line is
  predicted (mine wall undamped on the bomber's timeline, gravity / pursuit damped), a Dubins lead-in arrives on it, RUN drops
  3–5 mines in a bowed arc (or one gravity or pursuit bomb), ESCAPE turns away. The run is clamped to the corridor in Assault.
- **t11** (`fd8d476`): `bomber.png`, 104 × 56, dark hull, pale-blue edge light, hatched bomb bays, red spine stripe.

### The Sniper (t12–t15)

- **t12** (`047abd0`): `SniperBrain` shell, `SniperTelegraph`, `rail_round.tscn`, `SniperConfig`, rail fallback, Assault exit;
  `FLY_IN_TIME` and `enemy_sniper_bullet.tscn` deleted.
- **t13** (`1e7c9e0`, task plan `cmuyk2qq0008loa2xqwco8raj`): the relocation cycle — firing-point choice in the player's frame
  with tiers A/B/C, SETTLE, stationary AIM and LOCK, LOS refusal on two lines, FIRE with a `RailTrail`, BREAK_CONTACT, RELOCATE,
  corridor-safe Assault break.
- **t14** (`0a2b3a8`): the decoy (DECOY phase, `decoy_telegraph` flag, dim orange line 25–35° off, CHARGING never COMMIT).
- **t15** (`5505090`): `sniper.png` (48 × 64) and a separate `sniper_barrel.png` (8 × 42) that unfolds during AIM / LOCK.

### The Ram Corvette (t16–t18)

- **t16** (`35472db`, task plan `cmuyk2qq8008xoa2xxoq1frgn`): three `ArmorPlate`s under `Plates`, the hull's `is_armored()` /
  `deflects_hit()`, deferred exposure, `homing_point`, ARMOR contact; the `ram_ships` group and layer immunity retired.
- **t17** (`5d7fde7`, task plan `cmuyk2qqb0091oa2xy7yn9sxa`): `RamCorvetteBrain` — APPROACH, LINE_UP (≤ 0.5 s, brakes and turns onto
  the predicted point), WIND_UP (0.65 s crawl, plates glow, aim freezes), CHARGE (220 px overshoot, ≤ 1.45 s), WIDE_TURN,
  STAGGER, and the faster exposed hull.
- **t18** (`421d76f`): `ram_corvette.png` (84 × 84), `ram_plate_front.png`, `ram_plate_side.png`; old Ram Ship PNGs deleted.

### Hub and level 1 (t19–t22)

- **t19** (`47ac678`): hub idle (`IDLE`, `NOTICING`, `RETURNING` via `AnchorIdle`) for all three brains; the `start_engaged` seam.
- **t20** (`e075d33`): `SectorHub._spawn_patrol()` adds a Sniper (135°), a Bomber (45°) and a Ram Corvette (225°) on a 1700 px
  ring; clearance rows in `test_sector_hub_patrol.gd`.
- **t21** (`03d4976`, task plan `cmuyk2qqm009hoa2xyvw88ama`): the 35 specialist lines of deep_space and planet_approach lose
  `.move()` / `.free_after()` / `.shoot_at_player()`; `specialist_exit_probe.gd` measures the real DISENGAGE; the count gate
  (≤ 2.5× the frozen peaks).
- **t22** (`e2adf88`, task plan `cmuyk2qqp009loa2xb1k3py8o`): the 15 specialist lines of cloud_descent likewise; deadline rows per
  sniper and ram; `corridor_starts()`; `test_level1_specialist_exit.gd`; both ram levers.

### Docs (t23)

The three `ENEMY.md` files, `docs/enemy-roster.md`, `assault.md`, `global.md`, `PROJECT.md`, `BULLET_POOL.md`, `CLAUDE.md`, this
dossier and `DECISIONS.md`'s as-built section describe the code as built. `assault/DEVELOPMENT_PLAN.md` and
`docs/enemy-rework/current-enemies.md` carry a "historical" banner.

## How it was verified

- **The gate** (`bash /agent/verify.sh`: import, boot, GUT) ended green at **1593 tests, GUT time 256.8 s** after t22, and
  `scripts/check-test-leaks.sh` printed `LEAK CHECK PASS`.
- **New or extended test files:** `test_level1_specialist_spawns.gd`, `test_level1_specialist_exit.gd`, `test_engagement_deadline.gd`
  (sniper and ram rows, Bomber boundary), `test_sniper.gd`, `test_ram_corvette.gd`, `test_bomber.gd`, `test_enemy_ordnance.gd`,
  `test_armor_query.gd`, `test_line_of_sight.gd`, `tests/unit/test_bullet_pool.gd`, `test_steering.gd`, `test_enemy_mover.gd`,
  `test_target_info.gd`, the ARMOR rows of `test_contact_profile.gd`, `test_open_space_flight_feel.gd`, `test_sector_hub_patrol.gd`,
  `test_enemy_bullet_lifetime.gd` (rail round and per-kind ordnance rows), `test_player_bullet_lifetime.gd`, and the rosters of the
  contact-damage, contact-geometry and hurtbox-geometry gates.
- **Named behaviours with a real physics proof:** plate-by-plate vulnerability with real bullets, rockets, warhead and homing
  volleys, a real Sniper Shot, the beam and engine boost; a live-player mine-wall outcome (a straight 220 px/s stub takes a
  blast, the same stub turning 90° at RUN entry takes none, in both modes; 440 px/s takes one in Open Space); the sniper
  stationary through AIM and LOCK, a ≥ 45° bearing change each cycle, the LOS refusal (fixtures), the post-shot break-away.
- **Attack-in-budget rows** per specialist from every level-1 spawn class through a real `WaveManager`.
- **The integrity gates named in the acceptance criteria** (contact damage, contact geometry, hurtbox geometry, config
  isolation, single-writer with an empty allowlist, signal arity, sprite transparency, UID, project-load) are inside that suite
  and stayed green.
- **What the gate cannot see:** the look and feel of anything — see Known gaps. `ArmorPlate` glow, the barrel unfold and the plate
  fall-away were checked as numbers and still images only.

## Decisions and course changes

- **Plan review.** Round 1 returned CHANGES_REQUESTED (15 findings) and the plan became Revision 2. Round 2 returned
  CHANGES_REQUESTED again (B1, B2, N1–N10) and the owner started the epic without a re-plan, so the findings were applied by the
  tasks that own them. B1 changed three numbers: `mine_warning` 0.5 -> **0.25 s**, `gravity_release_lead` 80 -> **120 px** (task-level
  review), and the mine-wall lead gained a `(trigger_radius + arc_depth) / |v|` term; its fifth point (the boosting example) was
  recorded and not honoured. B2 produced the idempotent `ArmorPlate._resolve`.
- **Task-level plan rejections.** t10 (Bomber runs) was CHANGES_REQUESTED in two rounds before APPROVED (Revision 3); t13, t16,
  t17 and t22 were CHANGES_REQUESTED at least once; t21 was approved first time. t22's round-1 blocker was that the ram's exit was measured
  only from on-screen starts; it added `corridor_starts()`, and the 73.2 s ram row then needed both pre-approved levers to pass at a measured 9.60 s.
- **Nothing was dropped.** Every one of the 22 build tasks shipped; `persist_after_owner_death` moved forward from Ph5 as planned.
- **The gate's wall-clock cap.** t10's attempts 2–5 each ended exactly at the harness's ~300 s verification limit; the real-physics
  rows now run on an 8× clock with the physics step held at 1/60 game-second.
- Every deviation, with its reason, is the 28-row table in DECISIONS' "Phase 4 - as built".

## Numbers

| Value | Where it came from |
|---|---|
| Bomber: HP 150, contact 35, score 80, `max_speed` 240, `run_speed` 170, `engage_seconds` 8.0, `mine_warning` 0.25, `gravity_release_lead` 120, `approach_angle` 35°, `lead_factor` 0.6, `mine_speed_min..max` 150–440 | research F9 (damped lead) and the shipped code; warning and release lead set by plan review B1 and the t10 review. |
| Ordnance: gravity bomb 16 s / 1800 px, pursuit bomb 10 s / 2400 px, mine 10 s (life 8 s), pools 4 / 10 / 4 | judgement, then derived rows in `test_enemy_bullet_lifetime.gd`. |
| Sniper: HP 60, contact 20, score 50, `engage_seconds` 9.0, AIM 1.3 s, **LOCK 0.5 s**, `rail_speed` 2200, damage 28 (fallback 1400 / 25), range Open Space 900 ± 100 / Assault 680 ± 80, `min_bearing_change` 45°, `break_min` 1.0 s, decoy 0.6 s at 25–35° | LOCK from reaction-time research F4 (30 frames); the rest judgement tuned by the cycle's tests. |
| Ram Corvette: hull HP 120, three plates 50 each, contact 50 armoured (260 px/s shove) / 60 exposed, `cruise_speed` 280 (exposed 340), `charge_speed` 620 (exposed 700), wind-up 0.65 s, `overshoot` 220, `charge_max_time` 1.45, `wide_turn_rate` 1.4, `exit_speed` 560, `engage_seconds` 4.0 | plate HP and speeds judgement; `exit_speed` and `engage_seconds` set by the Cloud Descent deadline row (10.82 -> 10.10 -> 9.60 s). |
| Hub: ring 1700 px; bearings 135° / 45° / 225°; radii Sniper 700 / 1300, Bomber 650 / 1700, Ram 600 / 1300 | the plan's start values; each `lose_radius` is above the distance its own cycle opens, by an asserted inequality. |
| Level-1 density: ≤ 2.5× the frozen `_LEGACY_PEAK_SPECIALISTS`; measured peaks 6 / 6 / 6 against limits 12.5 / 7.5 / 10 | the plan's bound; no density lever was applied. |
| Measured exits (disengage): sniper 5.40 s, bomber 7.98 s, ram curved 6.35 s on the view grid and 5.77 s at 560 on the corridor set | `tests/helpers/specialist_exit_probe.gd` over the Ph3 404-start grid and t22's `corridor_starts()`. |
| Clearance: Sniper +144.6 px, Bomber +252.8 px, Ram +308.7 px | measured by `test_sector_hub_patrol.gd`. |

## Known gaps

- **Never play-tested.** A headless gate cannot tell whether the Sniper's 0.5 s lock is a fair window at Assault speed, whether the
  decoy reads as a bluff and never a lock, whether the mine wall is dodgeable by feel across 150–440 px/s, whether the ram's glow,
  plate break and charge read, or whether the barrel unfolding and the plate fall-away look right in motion. The Sniper's barrel
  covers the hull's red spine panel; the Bomber's red stripe was painted by hand because the generator left it out.
- **The 73.2 s ram passes Cloud Descent's deadline by 0.40 s** (9.60 s of 10). Any ram retune re-runs
  `test_engagement_deadline.gd`; the formula is pessimistic (a realisable split computes 8.55 s, printed not asserted).
- **The crowding count gate uses view-grid exits**, so it under-reports a ram's life by ~1.7 s. Every section still has room, and
  planet_approach has a one-ship margin.
- **A boosting player is never walled in with mines**; they get a pursuit bomb (B1e). The owner decides in Ph16 whether that is OK.
- **The Sniper can aim from a point a boosting player has left far behind**; nothing checks the range before AIM.
- **A `RailTrail` sits in the `EnemyContainer`**, so it can hold an `ENEMIES_CLEARED` section open for up to 0.4 s; Cloud Descent has
  6 s of margin against it.
- **Line of sight has one shipped blocker kind** (asteroids), and the hub has no bodies at all, so the refusal is proven by
  fixtures; no shipped scene hides a sniper behind cover yet.
- **The space station has no `homing_point`**, so rockets deflected by its armoured core still park there (Ph11).
- **The Heavy Shell still has no consumer** (Ph10).
- **Two unrelated mine concepts exist** (the race-mode mine and enemy-ordnance mines); not reconciled (Ph7).
- **A warhead-friendly Assault ram was not built**: a frontal warhead volley strips one plate, one homing volley strips all three.
- **`DefenseProfile.apply_alternate()` has no shipped user** (Ph17 may delete it), `light_assault_ship.png` from phase 3 is still
  unreferenced.
- **A sprite generated at the wrong angle cannot be fixed in code.** The Bomber and Sniper came out nose-up and the scenes were
  set to match (`sprite_forward_angle`, a π rotation on the Bomber's `Sprite2D`); a future redraw must keep that or change both.

## Links

- Epic plan directory: `docs/plans/cmufs7ele0015nm2xvag3vrwc/` (`1-context.md`, `2-research.md`, `3-plan.md`, `4-review.md`,
  `tasks.json`).
- Task plans: `cmuyk2qpr0089oa2xlih7xvmg` (t10), `cmuyk2qq0008loa2xqwco8raj` (t13), `cmuyk2qq8008xoa2xxoq1frgn` (t16),
  `cmuyk2qqb0091oa2xy7yn9sxa` (t17), `cmuyk2qqm009hoa2xyvw88ama` (t21), `cmuyk2qqp009loa2xb1k3py8o` (t22), all under `docs/plans/`.
- Decision log: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` -> "Phase 4 - as built (2026-10-14)".
- Earlier phases: `docs/epics-done/cmufklb100001p92xs1ey2fb1/` (Ph1), `cmufs7ek60001nm2x6d0bt2et/` (Ph2),
  `cmufs7ekv000lnm2x7nbswijy/` (Ph3).
- Commits: listed per task above, `62089d5` … `e2adf88`.
