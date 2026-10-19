# Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship

Epic `cmufs7elw001pnm2xr3b6fteb`, plan task `cmufs7em4001xnm2xwo26fzlf`, 2026-10-14, **Revision 2** (answers the round-1 plan
review in `4-review.md`; §9 lists each finding and what changed). Built on `1-context.md` (code inventory, requirement ids
`R5.x`, risks `C1`–`C18`) and `2-research.md` (scope check `S1`–`S20`, findings `F1`–`F13`, starting values) in this
directory. Facts were read at `7916662` on `agent/auto-dev`; gate timings were measured on that commit (§4.3).

## Summary for the owner

- **For the player:** a **Missile Corvette** keeps its distance on wide arcs and fires telegraphed rocket salvos aimed where
  you are going: fast straight rockets, mildly guided ones, clusters that split into four near you, and slow warheads that
  stop, blink and blow up when you come close. Every rocket can be outrun, out-turned, shot down (by your bullets or your
  own missiles) or lured into other enemies and asteroids. A rocket hurts you once, by its explosion, hit or near miss.
  A **Support Ship** has no gun: it shadows the most dangerous nearby enemy, repairs it in pulses, projects a cyan shield
  arc on its side facing you, and drags a badly hurt ally away inside a full shield bubble while putting itself in your
  line of fire — never during that ally's telegraphed attack. It is fragile and dodgy; kill it first.
- **Where:** the Open Space hub patrol (the support guards the hub's Ram Corvette) and level 1's two timed sections only.
- **Built:** a reusable enemy shield, enemy repair and tow, a "what the camera shows" query, the rocket family, both enemies
  with art, tests in both modes.
- **Left out:** rocket audio, flare reactions (no player flares), the Hijack Pulse (phase 9), module shields in real content
  (phase 10; proven by a test fixture), encounter design (phase 13).
- **Risks:** the test gate already runs near its 5-minute cap, so the first task must free about 70 s of test time before
  anything else lands; rocket fairness (gated by escape and hit tests); a player-facing shield is hard to flank in Assault.
- **Questions [default taken]:** (1) May enemy rockets wear down Ram Corvette armour plates (about four rockets per plate)?
  [Yes.] (2) Narrower shield arc in Assault, 90° vs 110°? [Yes.] (3) Cap a Support Ship's repair at 150 HP per life? [Yes.]
  (4) May the gate's 5-minute cap be raised? [No: if the first task cannot free 70 s it stops and asks before any other.]

## For every task

**Shared rules (earlier phases, still binding).** A brain decides; `EnemyMover` is the single writer of an enemy's
`velocity` / `rotation` and its one `move_and_slide()` (gate `test_enemy_mover_single_writer.gd`, empty allowlist). Clocks
are accumulated `delta`; randomness only from `brain.rng`; the player only via `TargetInfo`. A curve is a brain-side
`Steering.turn_toward` request and `turn_rate × speed ≤ acceleration` is asserted for any config that curves. Configs are
flat `ShipConfig` subclasses with `@export_group`s; `.tres` values win; contact damage comes from `config.collision_damage`
via `ContactProfile`. Signals declare what they emit. Never hand-type a `uid://`. Art only via PixelLab under the
`pixel-art-generation` skill (strict top-down), ≤ 90 % opaque. One owner per projectile (a pool, or `expired → queue_free`);
pools are direct root children, `persist_after_owner_death = true` for anything that outlives its ship. Ordnance and rockets
are never in group `enemies`, never scored. A shooter has a rail fallback (`on_suspended()`). A telegraphed attack is never
cut off by the Assault budget (the budget defers, bounded), and **never moved by anyone but its own brain** (tow refusal).

**New names (use exactly these):**
- `HurtBox.set_absorber(obj) -> bool` / `clear_absorber(obj)` / `has_absorber()`, `signal hit_absorbed(hit_box: HitBox)`;
  absorber duck type `absorbs_hit(hit_box: HitBox) -> bool`. `EnemyShield` (`global/components/enemy_shield.gd`, `Node2D`):
  `arc_deg` (≥ 360 = bubble); it never absorbs while its host answers `is_armored() == true`.
- `BaseEnemy.repair(amount) -> int` (never flashes), `can_be_repaired() -> bool`, `is_ai_driven() -> bool` (brain and mover
  present, not suspended), `ai_mover_max_speed() -> float`, `accept_tow(v: Vector2) -> bool` (a nudge on its own mover;
  false unless `is_ai_driven()`, not boosting, and `brain.accepts_tow()`). `EnemyBrain.accepts_tow() -> bool` (default true;
  false in committed or telegraphed phases — Sniper DECOY/AIM/LOCK/FIRE, Ram WIND_UP/CHARGE, Bomber RUN, Fighter RUN_IN,
  Gatling SPIN_UP/STREAM, Razor WINDUP/DASH/FEINT_WINDUP/FEINT_LUNGE, Swarm WINDUP/BURST, Corvette TELEGRAPH/SALVO).
- `EnemyWorld.has_view_rect(tree)` / `view_rect(tree) -> Rect2`, backed by `ArenaCamera.enemy_view_rect()` = centre
  `global_position + offset`, size `viewport size / zoom` (never `get_screen_center_position()`).
- `EnemyRocket` (`assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd`, `extends Area2D`, `enum Kind { DUMB, PURSUIT,
  CLUSTER, WARHEAD, SUBMUNITION }`): `signal expired`, `reset()`, `launch(dir: Vector2, aim_point: Vector2, launcher: Node)`.
  A launcher answers duck-typed `launch_velocity() -> Vector2` (inherited along `dir`) and `rocket_clear_radius() -> float`.
  `EnemyRocketScenes.scene_for(kind)` / `pool_size_for(kind, cfg)`. **Tuning lives in each rocket scene's exports.**
  Art and `rotation` are **nose-up** (`rotation = heading.angle() + PI / 2`, the player missiles' convention).
- `MissileCorvette` / `MissileCorvetteBrain` / `MissileCorvetteConfig` (`assault/scenes/enemies/missile_corvette/`),
  `MissileCorvette.fire(kind, aim_point) -> EnemyRocket`, `WaveBuilder.missile_corvette()`, const `MISSILE_CORVETTE`.
- `SupportShip` / `SupportShipBrain` / `SupportShipConfig` (`assault/scenes/enemies/support_ship/`), contact `NONE`,
  `WaveBuilder.support_ship()`, const `SUPPORT_SHIP`.
- Phase enums (append-only): `MissileCorvetteBrain.Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING,
  RETURNING }`; `SupportShipBrain.Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }`.

**Rocket collision (no layer renamed):** impact `HitBox` on layer **32 only**, mask **128 | 512**, `ROCKET`, closed until the
rocket is clear of its launcher's *current* position; shoot-down `HurtBox` layer 512, mask **96**, resolved by the rocket's
own `area_entered` handler (never `received_damage`), ignoring any `EnemyRocket`'s HitBox. Blast = `ContactBlast` (256).
So: the **impact** hurts enemies, ordnance, Ram plates and asteroids; the **blast** is the only thing that hurts the player
or allies; a player bullet or player missile and a rocket destroy each other with no blast; rockets ignore each other; an
armoured hull lets a rocket through (`ArmorQuery`), as it does a player missile.

**Closed earlier questions:** `DamageReaction` is not adopted by `BaseEnemy` (Ph1 P-15); no owner-distance lifetime rule;
`BulletPool` container injection stays deferred; enemy friendly fire = rocket impacts only. Direct emitters (beam, nova,
dash, shield overload, engine boost) bypass enemy shields as they bypass armour plates.

**Tests:** dual-mode specs use `use_parameters(["open_space", "assault"])` on a bare label, build
`tests/helpers/enemy_ai_harness.gd` in the body, hand-tick `_tick()`. Real physics only where a real collision is the point,
always on the 8× clock (`Engine.time_scale`, `physics_ticks_per_second`, `max_physics_steps_per_frame` scaled together,
restored in `after_each`). Read `tests/README.md` first; run `scripts/check-test-leaks.sh` after anything that awaits. New
enemy directories join `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`
and `test_base_enemy.gd`'s `_AUTHORED_CONTACT_MODES`.
**Gate-time budget (§4.3):** every task runs `scripts/gate-time.sh` (from t1) before and after and reports both in its
final message; its new GUT time stays within its allotment — t1 0 (frees ≥ 70 s, to GUT ≤ 183 s) · t2 3 · t3 2 · t4 0.5 · t5 6 · t6 4 · t7 3 · t8 5 · t9 0.5 · t10 2 · t11 4 · t12 4 · t13 3 · t14 0.5 · t15 2 · t16 2 · t17 15 · t18 0 s (total 56.5); GUT ≤ 240 s after every task.
A task over its allotment converts rows to hand-ticked form or shares a replay before it asks; it never cuts an assertion.
**Phase log:** a deviation a later phase depends on is appended under this phase's section of
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` before the task finishes.

## 1. Problem

Every enemy the player meets today fires bullets or rams. Nothing makes the player read a slow, steering threat and decide
whether to run, turn, shoot it or use it; and nothing in a formation makes another enemy tougher, so every target is as
important as every other. IDEAS §6.1 and §6.2 ask for two enemies that change how a fight reads without adding another
bullet stream:

- **Missile Corvette** — "Can I survive the salvo and get behind it?" A mid-weight ship that holds medium range on broad
  arcs and fires predicted rocket salvos. Its rockets have a visible launch, accelerate, steer mildly toward the player's
  future path and explode with a radius. They can be outrun, out-turned, shot down, or made to hit other enemies and the
  environment.
- **Support / Shield Ship** — "Can I kill the support unit before the formation becomes overwhelming?" No gun. It stays
  behind the most threatening ally, repairs it, projects a directional shield onto it, and escorts it away when it is
  nearly dead, putting itself in the line of fire. Low HP, high evasiveness; it switches to another ally when its ward dies;
  in Assault it cannot hide above the camera.

Both appear in Open Space (hub patrol) and in Assault (level 1), run the same brain in both, and are tested in both.

## 2. Design

### 2.0 Scope check and changes to earlier decisions

The scope text predates Phases 1–4. Checked against `DECISIONS.md` (Phase 1–4 *as built*) and the code, it changes as
follows (from `2-research.md` §0; each line is a decision this plan takes):

| Id | Scope item | Decision |
|---|---|---|
| S1 | `persist_after_owner_death` | Already built in Ph4 (`BulletPool._hand_over_active()`). Rocket pools set the flag; nothing new. |
| S2 | Owner-distance lifetime (`max_distance_from_owner`, Ph1 → Ph5) | **Not built.** Every rocket is bounded by its own `max_time` and `max_distance` from its origin, and a projectile that outlives its owner has no owner to measure from. Handed to Ph13 with `max_distance_from_player` if encounter ownership ever needs it. **This revisits a recorded decision; logged in DECISIONS.** |
| S3 | `BulletPool` injectable container (deferred Ph2 → Ph5) | **Deferred again** to the first nested launcher (Ph10 Carrier hangars). Every pool here is a direct root child; cluster submunitions are unpooled and own themselves. |
| S4 | Adopt `DamageReaction` for enemies (Ph1 P-15) | **Not adopted.** It has no hit direction or type, its `Shield` is a player resource (discrete charges, `Timer` regen, progression binding), and swapping ~12 enemies' damage flows gains the player nothing. Enemy shields are the new `EnemyShield` on a `HurtBox` absorb hook (§2.3). `DamageReaction` stays a racer component. |
| S5 | "On the collision layer phase 1 named for rockets" | Bit 32, named `player_rockets`, constant `CollisionLayers.PLAYER_ROCKETS`. Enemy rockets' impact HitBox sits on it **alone** (Revision 2: not on 256 — the player is hurt only by the rocket's blast, so one rocket is one hit against the player's 0.5 s i-frames). **The layer is not renamed** (name-only churn over ~20 references, no player value); the constant's doc comment says enemy rockets use it too. |
| S6 | Rockets "made to hit other enemies" | Decided for rockets only: the **impact** hits enemies, ordnance, plates and asteroids; the **blast** is player-only and is the player's only damage from a rocket. Player bullets and player missiles shoot rockets down (both destroyed, no blast). Beams and other blasts: still undecided (Ph8). |
| S7 | "warning audio" | Out (no enemy SFX pipeline; Ph17). The telegraph is visual. |
| S8 | "flare/decoy reaction" | Out: the player has no countermeasure. A later countermeasure retargets rockets through `EnemyRocket`'s aim-point function. |
| S9 | "bait it into a carrier escort" | Covered generically by impact friendly fire (Carrier is Ph10). |
| S10 | Hijack Pulse | Out (Ph9). Nothing here makes player missiles retargetable. |
| S11 | Shield kinds: directional, local-module, regenerating, projected bubble | One `EnemyShield` whose arc (360° = bubble), capacity, regeneration and lifetime are fields. Shipped consumers: the Support Ship's projected directional arc, which **becomes a projected bubble (360°) during the emergency escort** (Revision 2, §2.14). Local-module is proven by a fixture; its shipped consumer is Ph10 modular damage. |
| S12 | Repair | A heal path that never flashes: `BaseEnemy.repair()` (§2.4). |
| S13 | Escort "pulls the target away" | A tow **request** on the ward's own mover through `BaseEnemy.accept_tow()`; never a write to the ward's motion; refused by the ward's own brain (`EnemyBrain.accepts_tow()`) in committed or telegraphed phases (§2.4, §2.14). |
| S14 | Assault "cannot hide above the camera" | New `EnemyWorld.view_rect()` (§2.5); the corridor rect is the whole 1480 × 1480 pan range and does not stop it. |
| S15 | §37 Support + Ram "made possible" | A Ram is an eligible ward; repair heals its hull only; the hub Support shares the hub Ram's anchor (§2.13, §2.17). |
| S16–S17 | Assault placement and density | DURATION sections only; both kinds count as specialists in the existing count gate (§2.18). |
| S18 | Sprites and the unfolding projector | Corvette ≈ 96 × 96, Support ≈ 88 × 88, a separate projector sprite that unfolds (§2.15). |
| S19 | Both harnesses, gate time | Hand-ticked specs; t1 frees ≥ 70 s first, sized by the per-task budget (§2.2, §4.3). |
| S20 | Station reinforcements, `level_2_waves.gd` | Untouched; the corvette still gets a rail fallback. |

### 2.1 Names and places

| Thing | Path | Kind |
|---|---|---|
| Enemy shield component | `global/components/enemy_shield.gd` (`class_name EnemyShield extends Node2D`) | new |
| Absorb hook | `global/components/hurtbox_component.gd` (`HurtBox.set_absorber`, `clear_absorber`, `hit_absorbed`) | changed |
| Repair and tow | `assault/scenes/enemies/base_enemy.gd` (`repair`, `can_be_repaired`, `is_ai_driven`, `accept_tow`, `ai_mover_max_speed`, decrease-only flash); `global/enemy_ai/enemy_brain.gd` (`accepts_tow`) and its overrides in the seven shipped brains | changed |
| View rect | `global/enemy_ai/enemy_world.gd` (`has_view_rect`, `view_rect`), `assault/scenes/systems/arena_camera.gd` (`enemy_view_rect`) | changed |
| Rocket family | `assault/scenes/projectiles/enemy_rockets/` — `enemy_rocket.gd` (`EnemyRocket`), `enemy_rocket_scenes.gd` (`EnemyRocketScenes`), five `.tscn`, art | new |
| Missile Corvette | `assault/scenes/enemies/missile_corvette/` — `missile_corvette.gd/.tscn`, `missile_corvette_brain.gd`, `missile_corvette_config.gd/.tres`, `ENEMY.md` | new |
| Support Ship | `assault/scenes/enemies/support_ship/` — `support_ship.gd/.tscn`, `support_ship_brain.gd`, `support_ship_config.gd/.tres`, `ENEMY.md` | new |
| Art | `assault/assets/sprites/enemies/missile_corvette.png`, `support_ship.png`, `support_projector.png`; `assault/assets/sprites/projectiles/enemy_rocket.png`, `enemy_cluster_rocket.png`, `enemy_warhead.png`, `enemy_submunition.png` | new |
| WaveBuilder | `assault/scenes/systems/wave_builder.gd` — `missile_corvette()`, `support_ship()`, consts `MISSILE_CORVETTE`, `SUPPORT_SHIP` | changed |
| Hub | `open_space/scenes/levels/sector_hub.gd` `_spawn_patrol()` | changed |
| Level 1 | `assault/scenes/levels/edelia/1/level_1_director.gd` | changed |
| Gate time | `scripts/gate-time.sh`; `tests/README.md` "Gate time" section; the 8× clock / shared-replay changes in the slow files of §2.2 | new / changed |
| Tests | `tests/helpers/rocket_launcher_fixture.gd`, `tests/unit/test_enemy_shield.gd`, `tests/integration/test_enemy_shield_hits.gd`, `tests/integration/test_enemy_rockets.gd`, `tests/integration/test_missile_corvette.gd`, `tests/integration/test_support_ship.gd`; rows in existing gates | new / changed |

### 2.2 Gate time headroom (t1)

**Why first.** The harness kills verification at ~300 s **wall clock** (import + boot + GUT; Ph4 t10 attempts 2–5 ended
exactly 5:00 after start, and Ph4's passing tasks took 4.4–4.7 min with GUT at ~244 s, i.e. up to ~38 s of harness, import
and boot overhead on that machine). Measured for this plan at `7916662` on the dev container: import 4.7 s (warm cache),
boot 1.0 s, **GUT 253.3 s** (1593 tests, 126 scripts) — already above the ~240 s GUT ceiling that leaves a margin for that
overhead. This epic's new tests are budgeted at **56.5 s** (§4.3). So t1 must bring GUT time to **≤ 183 s** (free **≥ 70 s**)
before any other task adds a test; every later task then keeps GUT ≤ 240 s.

**Where the time is (measured, seconds, `-gjunit_xml_file`):** `test_fighter_squad.gd` 64.7 (17 tests, hand-ticked, one
`_run` replayed per test), `test_level1_fighter_fire_density.gd` 60.7 (6 tests, real physics at 4×),
`test_level1_fighter_exit.gd` 25.6 (2 tests, real physics at **1×**), `test_ram_corvette.gd` 18.6 (56 tests, 55 awaits at
**1×**), `test_level1_specialist_exit.gd` 10.1 (8×), `test_level1_drone_exit.gd` 9.4 (**1×**), `test_bomber.gd` 8.7 (8×),
`test_enemy_ordnance.gd` 6.6 (8×), `test_engagement_deadline.gd` 5.7, `test_armor_query.gd` 5.3,
`test_station_laser_phase.gd` 4.9, `test_level1_specialist_spawns.gd` 4.3, `test_station_assault_section.gd` 4.1,
`test_swarm_drone.gd` 3.5; everything else ≤ 2.7 s.

**What t1 does.**
1. Add `scripts/gate-time.sh`: runs the three gate steps exactly as `/agent/verify.sh` does (import, `--quit` boot, GUT with
   `-gjunit_xml_file=<tmp>`), prints each step's wall time, GUT's own `Time`, the test count and the 15 slowest files. Every
   later task runs it before and after.
2. Record the before/after table in `tests/README.md` under a new "Gate time" heading, with the date, the ceiling (GUT ≤ 240
   s after every task), the epic budget (§4.3) and the rule "a test that awaits real physics scales the clock to 8×; a
   hand-ticked loop that replays the same scenario in several tests computes it once".
3. Cut GUT time to **≤ 183 s** **without removing or weakening any assertion**. Allowed means, in this order (the expected
   yield is from the measurements above):
   (a) put every file that awaits real physics at 1× on the 8× clock (`Engine.time_scale`, `physics_ticks_per_second` and
   `max_physics_steps_per_frame` scaled together, step kept at 1/60 game-second, restored in `after_each` — the Ph4
   pattern): `test_level1_fighter_exit.gd`, `test_ram_corvette.gd`, `test_level1_drone_exit.gd` (≈ 54 s at 1× → ≈ 7–10 s);
   (b) raise `test_level1_fighter_fire_density.gd` from 4× to 8× (≈ 61 → ≈ 31 s);
   (c) in `test_fighter_squad.gd`, compute each scenario that several tests replay identically once (in `before_all`, or a
   memoised helper keyed by its inputs) and assert on the shared log, leaving each test's assertions intact;
   (d) drop per-tick bookkeeping that no assertion reads.
   Never lower a tick count, a duration, a sample count or a start-grid size that an assertion depends on. Every assertion's
   outcome must be unchanged; where a scaled clock shifts a measured value (Ph4: one row moved by a spawn frame, 2.25 →
   2.33 s), the task shows the before/after value and that it is still inside its asserted bound — it never widens a bound.
4. If 70 s cannot be freed this way, stop with `Result: ESCALATE`, listing what was measured and freed; the owner decides
   between raising the harness cap (owner question 4) and trimming this epic's real-physics rows. No later task starts
   until t1 is done.

**Acceptance:** `scripts/gate-time.sh` shows GUT ≤ 183 s on the dev container (and ≥ 70 s below the "before" run on the same
machine); the test count is unchanged (1593) and every test passes; `scripts/check-test-leaks.sh` clean; `tests/README.md`
has the Gate time section with the before/after table. **Budget for t1's own new tests:** none (it adds none).

### 2.3 Enemy shields: the HurtBox absorb hook and `EnemyShield` (t2)

**Decision (closes Ph1 P-15):** `BaseEnemy` keeps its own damage flow; `DamageReaction` is not adopted and stays a racer
component. Reasons: `DamageReaction` listens to `HurtBox.received_damage(damage)`, which carries no hit, so it cannot
express a directional or projected shield; its `Shield` is a player resource (discrete charges, a fixed 5 s `Timer`
regen, progression binding, a hacked flag); replacing ~12 enemies' flows (AnimationPlayer flash, the station's lingering
death, the Ram's deflect override) changes nothing the player sees.

**Where the hit-aware decision is made.** `HurtBox.received_damage` has no `HitBox`, and Godot orders `area_entered`
callbacks undefined, so the decision must happen inside the hurtbox that owns the hit, once per hit. Change
`global/components/hurtbox_component.gd`:

```gdscript
signal hit_absorbed(hit_box: HitBox)
var _absorber: Object = null   # duck-typed: absorbs_hit(hit_box: HitBox) -> bool

func set_absorber(obj: Object) -> bool:   # false if another live absorber holds the slot
func clear_absorber(obj: Object) -> void: # no-op unless obj holds the slot
func has_absorber() -> bool

func _on_area_entered(area: Area2D) -> void:
	var hb := area as HitBox
	if not hb: return
	if not accepted_damage_types.is_empty() and hb.damage_type not in accepted_damage_types: return
	if _absorber != null and is_instance_valid(_absorber) and _absorber.absorbs_hit(hb):
		hit_absorbed.emit(hb)
		return
	received_damage.emit(hb.damage)
```

A hurtbox with no absorber behaves byte-identically (the player's, every plate's, every existing enemy's). One slot only:
a second `set_absorber` while a live absorber holds it returns false.

**What happens to the projectile.** `bullet.gd` stops on a hurtbox unless `ArmorQuery.deflects(area, hit_box)` reports a
deflection; a shielded enemy answers neither `deflects_hit` nor `is_armored` for the shield, so the bullet is **consumed**
by the shield and the hull takes nothing ("the shield eats bullets"). A pierce charge is spent on an absorbed hit (it is
not a deflection). The Sniper Shot (`unlimited_pierce`) passes on as it does through any target. Player rockets detonate
on it. **Direct emitters** (beam, plasma nova, dash, shield overload, engine boost, laser ray) call
`received_damage.emit()` and **bypass the shield**, exactly as they bypass `ArmorPlate`s; recorded as accepted.

**Armoured hosts (review finding 9).** While the host refuses the hit anyway, the shield must not spend points on it: an
armoured Ram's hull lets every projectile through to its plates (`ram_corvette.gd` `deflects_hit` returns `is_armored()`),
so a shield that absorbed first would drain and flare on shots that never touch the hull. **Rule:** `absorbs_hit(hb)`
returns false whenever the host (the `HurtBox`'s parent) has `is_armored()` and it returns true. The shield asks the
**hit-blind** `is_armored()` only, never `deflects_hit(hb)`: an `ArmorPlate`'s `deflects_hit` resolves and damages the plate
(`armor_plate.gd` `_resolve`), which a query must not do. A host with neither method is unarmoured.

**`EnemyShield` (`global/components/enemy_shield.gd`, `class_name EnemyShield extends Node2D`).** A child of the entity it
protects; attaches to a `HurtBox` with `attach(hurt_box: HurtBox) -> bool` (calls `set_absorber(self)`), detaches on
`_exit_tree()`. Exports (all `@export`, defaults = Open Space projected values):

| Field | Default | Meaning |
|---|---|---|
| `arc_deg` | 110.0 | Width of the protected arc; ≥ 360 = bubble (every direction). May be changed while attached (the escort widens it to 360, §2.14) |
| `capacity` | 40 | Points; an absorbed hit subtracts `hit_box.damage` |
| `regen_delay` | 3.0 | Seconds after the last absorbed hit before refilling starts |
| `regen_seconds` | 1.5 | Empty → full refill time (linear, accumulated clock) |
| `reboot_seconds` | 4.0 | After a break: absorbs nothing for this long, then regenerates from 0 |
| `turn_rate` | 1.6 | rad/s the arc's facing turns toward the threat point |
| `radius` | 40.0 | Drawn radius (owner sets hull radius + 6) |
| `sustain_mode` | `false` | When true the shield fades unless `sustain()` was called within `heartbeat` |
| `heartbeat` | 0.3 | Seconds of grace after the last `sustain()` |
| `fade_seconds` | 0.3 | Fade-out then `queue_free()` when a sustained shield lapses |

Methods: `set_threat_point(world: Vector2)` (the arc turns toward the bearing from the host to that point at
`turn_rate`), `sustain(threat_point: Vector2)` (refreshes the heartbeat and sets the threat point), `absorbs_hit(hit_box)`,
`points() -> int`, `is_up() -> bool`, `facing() -> Vector2` (world direction). Signals: `absorbed(hit_box: HitBox,
remaining: int)`, `broken()`, `restored()`, `lapsed()`.

**The absorb rule (one decision per hit; no state outside the call):** `absorbs_hit(hb)` returns true when the host is not
armoured (above), the shield is up (not rebooting, not lapsed, points > 0) **and** the bearing from the host's
`global_position` to `hb.global_position` lies within `arc_deg / 2` of `facing()` (always true when `arc_deg >= 360`). On
true: points −= `hb.damage` (floor 0); **the breaking hit is absorbed whole** (no bleed-through); at 0 emit `broken()` and
start `reboot_seconds`; after reboot, refill from 0 over `regen_seconds` and emit `restored()` when full. A hit from outside
the arc returns false and lands on the hull normally. The regen delay restarts on every absorbed hit (focus fire wins, F10).

**Drawing.** `_draw()` with world angles converted to local (`world_angle − global_rotation`); the shield never writes its
own or its host's `rotation`. Cyan (`Color(0.35, 0.9, 1.0)`) arc stroke at `radius`, alpha by points fraction; a brighter
flare for 0.12 s on absorb; a burst of short cyan strokes on break; the refill drawn as the arc growing back from the
centre. Bubble = full circle.

**"Temporary resource, not a second HP bar" (R5.29)** is met by small capacity, the regen delay, break + reboot, the
direction (110°, not the hull), and for the projected kind the hard dependency on its projector (`sustain_mode`).

**Tests (t2):**
- `tests/unit/test_hitbox_hurtbox.gd`: a hurtbox without absorber emits `received_damage` exactly as before; with an
  absorber answering true it emits `hit_absorbed(hb)` and not `received_damage`; answering false → `received_damage`;
  a freed absorber is ignored; second `set_absorber` returns false; `clear_absorber` by a non-holder is a no-op;
  the `accepted_damage_types` filter still runs first.
- `tests/unit/test_enemy_shield.gd` (hand-ticked, fake `HitBox`es placed around a host): a hit inside the arc is absorbed
  and points drop by its damage; with a 110° arc a hit 54° off the facing is absorbed and one 56° off lands; bubble (360°)
  absorbs from behind; changing `arc_deg` 110 → 360 while attached makes a rear hit absorbed on the next call; the breaking
  hit is absorbed whole and `broken` fires once; nothing absorbed during `reboot_seconds`; regen starts only `regen_delay`
  after the last hit and reaches full after `regen_seconds` (`restored` once); the facing turns at no more than
  `turn_rate × delta` per tick; `sustain_mode` lapses `heartbeat` after the last `sustain()`, then fades and frees (`lapsed`
  once); detaching on free clears the hurtbox slot; **armoured host**: a host answering `is_armored() == true` gets
  `absorbs_hit` false with points unchanged, and true again once it answers false; a host whose `deflects_hit` would have a
  side effect (a counting fake) is never asked it.
- `tests/integration/test_enemy_shield_hits.gd` (real projectiles, 8× clock): on `fixture_enemy.tscn` (`tests/helpers/`)
  with a 110° shield facing a shooter, a real player `Bullet` from the front is consumed and hull HP is unchanged; from
  behind it damages the hull; a real homing/warhead player rocket from the front detonates and does no hull damage; a beam
  (`received_damage.emit`) bypasses the shield; **local-module fixture**: a shield attached to a part's own hurtbox (an
  `ArmorPlate`-like child hurtbox) protects that part only; **bubble fixture**: 360° absorbs from four directions.
  Keep this file small (≤ 6 awaited cases; one scene build per case) — it is budgeted in §4.3.
- Boundary: capacity 40 against two 25-damage hits → first absorbed (15 left), second absorbed whole and breaks, third
  lands on the hull.

### 2.4 BaseEnemy and EnemyBrain support hooks: repair and tow (t3)

Changes to `assault/scenes/enemies/base_enemy.gd`, `global/enemy_ai/enemy_brain.gd` and a one-function override in each of
the seven shipped brains (plus tests):

- **Decrease-only feedback.** `_on_health_changed(current)` plays the hit flash and `_hit_effect.burst()` **only when
  `current` is lower than the previous value.** Track `_last_health` (−1 = unset): on each call, if unset take
  `health.max_health` as the previous value (enemies start full; subclasses write health from config without a signal),
  compare, then store `current`. Death at 0 is unchanged. Today health never goes up, so no shipped behaviour changes; the
  station's `_on_health_changed` override (`space_station.gd:197`) still calls `super` and is untouched.
- **`repair(amount: int) -> int`:** returns 0 if `amount <= 0`, health is 0, `is_queued_for_deletion()`, or
  `can_be_repaired()` is false; else `before = health.current_health; health.increase(amount)` and returns
  `health.current_health − before` (0 at full HP). Never flashes (rule above). `can_be_repaired() -> bool` defaults to
  `true`; `SpaceStation` overrides it to false in this task (the Support Ship does in t10).
- **`is_ai_driven() -> bool`:** `_brain != null and _mover != null and not _ai_suspended`. False for every legacy enemy
  (Gunship, Bonus Drone, Space Station have no brain) and for any enemy on a rail. The Support Ship's ward filter uses it
  (§2.12), so a ward can always in principle be towed.
- **`EnemyBrain.accepts_tow() -> bool`** (new virtual on `global/enemy_ai/enemy_brain.gd`, default `true`): "may an ally
  move me right now?". A brain answers **false in every committed or telegraphed phase**, because each of those promises
  the player that the warning they saw is the attack they get — the Sniper fires from its *current* muzzle toward
  `lock_point` (`sniper_brain.gd` `_fire()`), so a 0.5 s tow during LOCK at the ward's max speed would move the shot ~100 px
  off the line it showed. Overrides added in this task (one `match phase` each):

  | Brain | `accepts_tow()` false in |
  |---|---|
  | `SniperBrain` | DECOY, AIM, LOCK, FIRE |
  | `RamCorvetteBrain` | WIND_UP, CHARGE |
  | `BomberBrain` | RUN |
  | `FighterBrain` | RUN_IN |
  | `GatlingInterceptorBrain` | SPIN_UP, STREAM |
  | `RazorDroneBrain` | WINDUP, DASH, FEINT_WINDUP, FEINT_LUNGE |
  | `SwarmDroneBrain` | WINDUP, BURST |
  | `MissileCorvetteBrain` (t8 adds it) | TELEGRAPH, SALVO |

- **`accept_tow(v: Vector2) -> bool`:** returns false unless `is_ai_driven()`, `not _mover.is_boosting()` and
  `_brain.accepts_tow()`; else `_mover.add_nudge(v)` and true. The nudge is summed onto the brain's own primary request
  for one `mover.step()` and limited to the mover's `max_speed`; nothing else writes motion (the single-writer gate stays
  green). The brain check matters because `BaseEnemy._physics_process` returns before `mover.step()` without a brain
  (`base_enemy.gd:103-108`): a nudge accepted there would never be applied.
- **`ai_mover_max_speed() -> float`:** the mover's `max_speed`, or 0 without a mover (the escort sizes its tow from it).

**Tests (t3), in `tests/integration/test_base_enemy.gd` (hand-ticked; ≤ 2 s of GUT time in total, §4.3):**
- repair: a damaged fixture enemy repaired by 10 regains 10, the `HitFlashAnimationPlayer` is not playing and the hit
  burst did not fire; at full HP `repair` returns 0; repair of a dead or queued-for-deletion enemy returns 0; a hit after
  a repair still flashes; the station answers `can_be_repaired() == false` and `repair()` returns 0 on it.
- tow: `accept_tow` on a suspended enemy, on one with no brain and on one whose mover is boosting each returns false and
  leaves the mover's nudge empty; on a live one it returns true and the next step's velocity component along the nudge is
  > 0; `is_ai_driven()` is false for a real `gunship.tscn` and `bonus_drone.tscn`.
- **refusal per brain:** for each row of the table, the real scene's brain put into each listed phase via its
  `enter_phase()` answers `accepts_tow() == false`, and into one unlisted phase (e.g. APPROACH) answers true.
- **telegraph is not moved (boundary):** a real `sniper.tscn` driven into LOCK (hand-ticked, `start_engaged`), offered
  `accept_tow(Vector2(400, 0))` every tick through the whole LOCK, keeps its muzzle position within 1 px of where LOCK began,
  and the rail round leaves along the locked line; the same for a real `ram_corvette.tscn` through WIND_UP (position within
  1 px). A control run with the refusal bypassed (a fixture brain answering true) moves > 50 px — proof the row can fail.

### 2.5 Assault view rect (t4)

The Assault corridor rect (`AssaultCorridorConstraint.inner_rect()`, 1480 × 1480) is the camera's whole pan range; the
camera shows 1280 × 720 of it, so a ship can sit ~380 px above the visible screen with no pressure. "The support cannot
hide above the camera" needs the rect the camera actually shows now.

- `assault/scenes/systems/arena_camera.gd`: `func enemy_view_rect() -> Rect2` — centre **`global_position + offset`** (the
  project's own convention for "where the camera looks now": `ArenaCamera` pins `global_position` and pans only through
  `offset`, class doc lines 10-15; `level_1_director.gd:140` uses the same sum), size
  `get_viewport().get_visible_rect().size / zoom` (correct under the pause-menu zoom). **Not**
  `get_screen_center_position()`: that returns the centre cached at the camera's last scroll update, which runs only for
  the current camera in its own process step, so a test that sets `offset` and reads at once — and every hand-ticked
  dual-mode spec, whose harness camera is never processed (`tests/helpers/enemy_ai_harness.gd`) — would read a stale value.
- `global/enemy_ai/enemy_world.gd`: `static func has_view_rect(tree) -> bool` and `static func view_rect(tree) -> Rect2`,
  duck-typed on `enemy_view_rect`, following the existing `cull_rect` pair exactly (empty `Rect2()` with no provider).
  Nothing under `global/` names `ArenaCamera`.

**Tests (t4), `tests/unit/test_enemy_world.gd` (or the existing provider test file; hand-ticked, ≤ 1 s, §4.3):** no
provider → `has_view_rect` false and `Rect2()`; a fake provider in group `assault_arena` answering a rect → that rect; a
real `ArenaCamera` at `global_position` (640, 360) with `offset = (0, -300)` → read **in the same frame**, without awaiting
a process step, the rect's centre is (640, 60), its top is 300 px higher than with offset zero, and its size is 1280 × 720
at zoom 1 and 1600 × 900 at zoom 0.8.

### 2.6 Enemy rocket family: common contract, layers and friendly fire (t5, t6)

**Class shape.** `EnemyRocket` is a sibling of Ph4's `EnemyOrdnance`, not new kinds on it (the ordnance script is
bomb-shaped: no rotation, proximity-only trigger, `pool_size_for` keyed on `BomberConfig`; Ph7's Mine Layer extends it).
Path `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd`, `class_name EnemyRocket extends Area2D`,
`enum Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }`.

**Contract (mirrors `EnemyOrdnance`):** `signal expired`; `reset()` restores every export to the scene's own value
(the `_RESET_PROPS` capture at `_ready()`, as `EnemyOrdnance` does) and clears state; `launch(dir: Vector2, aim_point:
Vector2, launcher: Node)`; one `_mark_done()` latch so `expired` fires once and every hit is resolved once; accessors
`heading() -> Vector2`, `speed() -> float`, `is_armed() -> bool`, `is_guiding() -> bool`, `aim_point() -> Vector2`. Never
in group `enemies`, never registered with `ScoreTracker`. The rocket writes its own `global_position` and `rotation` (it is
not an `EnemyMover` actor; the single-writer gate sweeps brains, `global/enemy_ai/` and mover-driven enemy roots, not
projectiles).

**Scene shape (every kind):**

```
<Kind>Rocket (Area2D, enemy_rocket.gd; collision_layer 0, mask 0)
├── HitBox (HitBox) layer 32, mask 128|512 = 640, damage_type ROCKET, damage = impact_damage; closed until armed
│   └── CollisionShape2D (circle, r = body_radius)
├── HurtBox (HurtBox) layer 512, mask 96 (= 32 | 64)   # shoot-down; its received_damage is NOT connected
│   └── CollisionShape2D (circle, r = body_radius + 2)
├── ProjectileLifetime                              # max_time, max_distance from origin, use_world_rect in Assault
├── RocketTrail                                     # global/components/rocket_trail.gd: emits along local +Y
└── Sprite2D                                        # NOSE-UP art; rotation = heading.angle() + PI / 2
```

**Orientation (review finding 10).** Rocket art is drawn **nose-up** and the rocket sets `rotation = heading.angle() + PI /
2` — the player missiles' convention (`homing_missile.gd` `_fly_to_target`). `RocketTrail` emits along local +Y "for a
rocket whose nose points in local −Y" (`rocket_trail.gd`), so the exhaust leaves the tail with no extra rotation. (The
enemy ships stay nose-down with `sprite_forward_angle = PI / 2`; rockets are projectiles and follow the projectile
convention.)

Warheads add `ProximityArea` (Area2D, layer 0, mask 128, circle `trigger_radius`), polled with
`get_overlapping_areas()` (the Ph4 B1b rule: a player already inside at arm time still triggers it).

**Who hurts whom (review findings 1 and 2; S5, S6, C2, C3).** One damage source per target:

| Target | Takes | How |
|---|---|---|
| Player, allies (hurtbox layer 128, mask 1281) | **`blast_damage` only** | The impact HitBox is on 32, which their mask lacks, so they never take the impact. The HitBox's mask 128 still *sees* their hurtbox and detonates the rocket; the `ContactBlast` (layer 256) that follows is their only damage. A direct hit and a near miss inside `blast_radius` both cost `blast_damage` — one hit, one invincibility window (`PlayerBase._apply_damage` starts 0.5 s of i-frames after every hit, so a second source a frame later would be swallowed anyway, or with i-frames off would spend a second shield charge). |
| Any `BaseEnemy` (runtime hurtbox mask 1121 includes 32) | `impact_damage` | Its own hurtbox detects the HitBox. A shielded ward's arc can absorb it. |
| Armoured Ram hull | nothing; the rocket passes on | The rocket asks `ArmorQuery.deflects(area, hit_box)` exactly as the player's missiles do: the armoured hull answers true, so the rocket flies on through to a plate. |
| Ram `ArmorPlate` (mask 96, breaks on ROCKET) | `impact_damage` to the plate's HP | Plates have 50 HP (`ram_corvette_config.tres`): `ceil(50 / 16)` = 4 DUMB or `ceil(50 / 18)` = 3 PURSUIT rockets break one. Owner question 1. |
| Ph4 enemy ordnance (mask 96) | defused | Its hurtbox detects the HitBox. |
| Asteroids (hurtbox mask 32 / 96) | `impact_damage` | Their hurtbox detects the HitBox. |
| Another enemy rocket | nothing | The impact handler ignores an area whose owner is an `EnemyRocket`; the shoot-down handler ignores any `EnemyRocket`'s HitBox. |
| Player bullet / player homing or warhead missile | both destroyed, **no blast** | See *Shoot-down*. |

**No environment bit.** The HitBox mask has no bit 1: every solid thing a rocket can meet has a hurtbox on 512 or 128, and
bit 1 would also see every enemy *body* (`CharacterBody2D`s sit on default layer 1), so a rocket would detonate on an
armoured Ram's body before reaching its plates.

**Impact handler** (`HitBox.area_entered`, armed only): return if done; return if the area's owner is an `EnemyRocket`;
return if `ArmorQuery.deflects(area, hit_box)`; else detonate — `_mark_done()`, close the HitBox with `set_deferred`
(never free inside the callback), `ContactBlast.spawn(get_parent(), global_position, blast_radius, blast_damage,
blast_frames)`, pop, `expired`. The target's own hurtbox has already seen the impact in the same flush.

**Shoot-down (review finding 1).** The player's homing and warhead missiles have a HitBox on layer 32, mask 513
(`homing_missile.tscn`, `warhead_missile.tscn`): they *see* the rocket's hurtbox (512), find no armour answer and free
themselves. So the rocket must see them too: its `HurtBox` masks **96** (the Ph4 ordnance value). The rocket connects that
node's `area_entered` itself — never `received_damage`, which carries no hit — and resolves each area once (the
`ArmorPlate._resolve` shape): a `HitBox` whose owner is an `EnemyRocket` is ignored (sibling impact HitBoxes are on 32
too); any other `HitBox` defuses the rocket: small pop, **no blast**, `expired`. So a player bullet or player missile and an
enemy rocket destroy each other; the Sniper Shot (`unlimited_pierce`) passes on as through any target. No `Health` node.

**Launch, inheritance and arming (review finding 3; C1).** A rocket fired from a moving ship must never be overrun by it:
- **Inherited speed.** `launch()` reads `launcher.launch_velocity()` (duck-typed; `Vector2.ZERO` without it) and starts at
  `speed = launch_speed + max(0, launch_velocity.dot(dir))`, held through `boost_seconds`, then `move_toward(cruise_speed,
  accel × delta)`. The perpendicular component is dropped (it only increases separation). A ship on a rail has
  `velocity == 0` (`EnemyPathMover` writes position), so `MissileCorvette.launch_velocity()` returns `velocity` under AI and
  the observed position delta per frame while suspended (§2.9).
- **Arming by clearance from the launcher's current position.** The impact HitBox starts with `monitoring` and
  `monitorable` false and opens (deferred) on the first tick where
  `global_position.distance_to(launcher.global_position) >= launcher.rocket_clear_radius() + body_radius + arm_clearance`.
  `rocket_clear_radius()` is duck-typed on the launcher (the corvette answers its hull radius, 40; absent = 0);
  `arm_clearance` is a rocket export (default 8). **The rocket is the only owner of this rule** — the launcher passes
  nothing but `dir`, `aim_point` and itself. A freed launcher arms the rocket at once; a null launcher (a submunition)
  measures from its launch point with radius 0. The shoot-down HurtBox is live from launch.
- **Config inequalities (asserted in t5 for every kind a ship fires, t6 for the rest):** `cruise_speed >= 1.1 ×
  MissileCorvetteConfig.max_speed` (231 px/s), so a launcher can never catch its own coasting rocket; and `launch_speed >
  MissileCorvetteConfig.acceleration × boost_seconds` (the launcher cannot out-accelerate the boost). After arming the
  launcher is an ordinary target: a pursuit rocket the player baits back into its own corvette hits it — intended
  counterplay.

**Lifetime.** `ProjectileLifetime` with per-kind `max_time` / `max_distance` (from origin) and, in Assault,
`use_world_rect` (the corridor's projectile rect) — this is "limited by the corridor". Expiry by lifetime is a fizzle: pop,
no blast. No owner-distance rule (S2).

**Ownership.** Corvette pools (one per kind, direct root children, `persist_after_owner_death = true`) own pooled
rockets; submunitions are **unpooled** and own themselves (`expired → queue_free`), spawned into the parent rocket's own
parent (the container). `EnemyRocketScenes.pool_size_for(kind, cfg)` = `count × ceil(rocket.max_time /
cfg.salvo_period_min)` where `count` = `cfg.warhead_salvo_count` for WARHEAD and `cfg.salvo_count` otherwise (duck-typed on
those fields): DUMB 3, PURSUIT 6, CLUSTER 3, WARHEAD 4.

**Tuning lives in the rocket scenes' exports** (one source of truth per kind, whoever fires it — the Ph10 Carrier and
Ph11 fortress will fire the same rockets). This differs from Ph4, where the Bomber's config carries its ordnance numbers;
logged in DECISIONS with that reason. Ph16 difficulty tiers scale a rocket by setting exports before `launch()`.

**Common exports (`EnemyRocket`):** `kind`, `launch_speed`, `cruise_speed`, `boost_seconds` (straight, no steering: the
visible launch), `accel`, `turn_rate` (rad/s), `guidance_seconds`, `lead_max` (s), `impact_damage` (enemies),
`blast_radius`, `blast_damage` (the player-facing number), `blast_frames` (3), `arm_clearance` (8), `body_radius`,
`max_time`, `max_distance`.

**Shipped values (judgement, F1/F2/F6/F8/F9; `2-research.md` §3.1; re-tuned in Revision 2 so the blast is the player's
number and every cruise speed clears 231 px/s):**

| Kind | launch → cruise px/s | boost s | accel | turn rad/s | guidance s | impact (enemies) / blast (player) | blast r | life s / px |
|---|---|---|---|---|---|---|---|---|
| DUMB | 140 → 520 | 0.25 | 900 | 0 | 0 | 16 / 16 | 36 | 4.0 / 1800 |
| PURSUIT | 120 → 440 | 0.35 | 600 | 1.6 | 3.0 (`lead_max` 0.8) | 18 / 18 | 40 | 6.0 / 2400 |
| CLUSTER | 120 → 380 | 0.35 | 600 | 0.7 | until split | 16 / 16 | 36 | 4.0 / 1200 |
| SUBMUNITION | 520 → 520 | 0 | 0 | 0 | 0 | 8 / 8 | 22 | 1.2 / 600 |
| WARHEAD | 100 → 240 | 0.35 | 300 | 0.6 | 4.0 | 12 / 30 | 110 | 7.0 / 1300 |

`launch_speed > 240 × boost_seconds`: DUMB 140 > 60, PURSUIT / CLUSTER 120 > 84, WARHEAD 100 > 84.

**Lifetime rows (t5 for DUMB / PURSUIT, t6 for the rest)** in `tests/integration/test_enemy_bullet_lifetime.gd`, one per
kind, speeds read from the rocket scene's exports with zero inheritance (the slowest case), in the Ph4 pursuit-bomb form:
the straight-line time to cover `max_distance` — `boost_seconds` at `launch_speed`, then accelerating at `accel` to
`cruise_speed`, then the rest at `cruise_speed` — must fit `max_time` (so the distance cap, not the clock, ends a straight
rocket). Computed: DUMB 3.80 ≤ 4.0 s, PURSUIT 5.90 ≤ 6.0, CLUSTER 3.55 ≤ 4.0, SUBMUNITION 1.15 ≤ 1.2, WARHEAD 5.76 ≤ 7.0.
Rocket speeds never enter `_every_shipped_enemy_bullet_speed()` (round family only).

### 2.7 Dumb and Pursuit rockets (t5)

**Guidance law (lead pursuit with a turn cap and a finite window — `2-research.md` §2.1 option C):** each physics tick,
while `is_guiding()` (after `boost_seconds`, before `boost_seconds + guidance_seconds`):
`aim = _aim_point()`; `heading = Steering.turn_toward(heading, aim − global_position, turn_rate, delta)`. `_aim_point()` =
`TargetInfo.player(get_tree()).intercept(global_position, speed())`; if not `ok` or its `time > lead_max`, use
`predicted_position(lead_max)`. No player → keep heading. After the window the heading freezes and the rocket coasts at
`cruise_speed` — still armed, still a hazard to everything it crosses (F2 "flameout"). Speed: `launch_speed` (+ inherited
along-heading launcher speed, §2.6) during the boost, then `move_toward(cruise_speed, accel × delta)`. All per physics tick
with `delta` (F6: no frame-rate dependence). `rotation = heading.angle() + PI / 2` (nose-up art).

- **DUMB**: no guidance (`turn_rate` 0). The launcher aims it at an intercept point at launch; it flies straight.
- **PURSUIT**: the law above. Turn radius `cruise_speed / turn_rate` = 275 px, tighter than the Open Space ship's
  sustained turn (≈ 464 px at 420 px/s), so the counter is the **late break / boost** and the **finite window**, not a
  sustained turn — that is the design (F1, F6).

**t5 builds:** `enemy_rocket.gd` with the whole common contract of §2.6 (layers, impact and shoot-down handlers,
inheritance, clearance arming, blast, fizzle) and both guidance kinds, `dumb_rocket.tscn`, `pursuit_rocket.tscn`,
`enemy_rocket_scenes.gd`, the placeholder look (nose-up `_draw()` body + `RocketTrail`; t9 swaps in the sprite), the two
lifetime rows, and a test fixture launcher (`tests/helpers/rocket_launcher_fixture.gd`: a `CharacterBody2D` with a
`HurtBox` on 512 / mask 1121 and a `Health`, answering `launch_velocity()` (its `velocity`, settable) and
`rocket_clear_radius()` (40), that calls `launch()` on rockets taken from a `BulletPool` with
`persist_after_owner_death`).

**Tests (t5), `tests/integration/test_enemy_rockets.gd`, parameterised `["open_space", "assault"]` where marked; hand-ticked
unless marked "real physics" (those run on the 8× clock and share one scene build per case; budget in §4.3):**
- (both) a PURSUIT rocket's heading converges on `intercept()`'s point for a constant-velocity player stub: the angle
  between heading and `aim − pos` shrinks monotonically after the boost until < 3°; per tick the heading never turns more
  than `turn_rate × delta` (+1e-4); after `boost_seconds + guidance_seconds` the heading is constant to 1e-6.
- (both) dodgeability, hand-ticked against a scripted stub: (a) a stub running straight away at 420 px/s from 300 px
  ahead at launch is never touched before the rocket expires; (b) a stub flying at 220 px/s toward the rocket that boosts
  perpendicular at 700 px/s when the rocket is 150 px away is missed (closest approach > `body_radius` + the player hurtbox
  radius); (c) a stationary stub 600 px away is hit; (d) config inequality `cruise_speed / turn_rate >= 250` for PURSUIT.
- (both) a DUMB rocket keeps its launch heading to 1e-6 for its life; its speed reaches `cruise_speed` within
  `boost_seconds + (cruise − launch) / accel + 2 ticks`; `rotation == heading.angle() + PI / 2` every tick.
- config inequalities from §2.6 for DUMB and PURSUIT, read from the scenes and `missile_corvette_config.tres` once it
  exists (until t7, from the plan's numbers as constants marked `# until t7`): `cruise_speed >= 1.1 × 210` and
  `launch_speed > 240 × boost_seconds`.
- **(both) moving launcher (finding 3):** the fixture launcher moving at 210 px/s along the launch direction (hand-ticked
  position, `launch_velocity()` = that velocity) fires a DUMB and a PURSUIT rocket: the rocket's starting speed is
  `launch_speed + 210`; the launcher–rocket distance grows every tick after launch; `is_armed()` becomes true only once the
  distance ≥ 40 + `body_radius` + 8; a control with `launch_velocity()` returning zero shows the launcher overtaking the
  rocket (distance shrinks) — proof the row can fail.
- (open_space, real physics) **shoot-down:** a real player `Bullet` on the rocket → the rocket emits `expired` once, no
  `ContactBlast` child appears in the container, the bullet is consumed. **Player missile (finding 1):** a real
  `homing_missile.tscn` locked onto the fixture enemy and crossing the rocket → **both** expire (the missile freed, the
  rocket's `expired` once), no `ContactBlast` appears, the fixture enemy behind it is untouched.
- (open_space, real physics) **friendly fire:** an armed rocket crossing a fixture enemy damages it by exactly
  `impact_damage` and detonates (the blast that follows does not damage it); the launcher is not hit when the rocket
  leaves it (launcher HP unchanged after 0.5 s); two rockets launched 2 px apart on the same heading both survive 1 s;
  **Ram plate (finding 6):** a real `ram_corvette.tscn` with a DUMB rocket fired at a plate → the plate's HP drops by
  exactly `impact_damage` (50 → 34), `plate_broken` does not fire, the rocket is consumed and the hull HP is unchanged; a
  second rocket at a plate set to ≤ `impact_damage` HP breaks it (`plate_broken` once); a big asteroid on the path takes
  `impact_damage`.
- (both, real physics, **real player scenes — finding 2**) on `open_space/scenes/entities/player/player_ship.tscn` (Open
  Space) and `assault/scenes/player/player_fighter.tscn` (Assault), with the shield component emptied so health reads the
  hit: a direct hit costs exactly `blast_damage` (not `impact_damage + blast_damage`); a detonation on a fixture 30 px from
  the player also costs exactly `blast_damage`; one at `blast_radius + 20` costs 0. With a shield charge present, a direct
  hit spends exactly one charge.
- (assault) a rocket expires on leaving the projectile world rect; (both) lifetime expiry spawns no `ContactBlast`.
- Pool: `persist_after_owner_death` — freeing the fixture launcher leaves its in-flight rockets flying (and arms any still
  unarmed one on the next tick); each frees itself on expiry (`queue_free`, no leak — `scripts/check-test-leaks.sh`).

### 2.8 Cluster rocket and Delayed Warhead (t6)

Both build on the `EnemyRocket` contract t5 shipped (`assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd`): impact
HitBox on layer 32 / mask 640 closed until clear of the launcher, shoot-down HurtBox on 512 / mask 96 resolved by the
rocket itself, `ContactBlast` as the only player damage, nose-up art.

**CLUSTER** (`cluster_rocket.tscn`, `Kind.CLUSTER`): guided by the §2.7 law with `turn_rate` 0.7 until it splits. It
**splits by distance** (F8): when within `split_distance` (260 px) of the player, or after `split_time` (2.0 s from
launch) if never that close. On split it emits `expired` **without a blast** (it is gone, not exploded) and spawns
`cluster_count` (4; export range 3–5) `SUBMUNITION`s **unpooled** into its own parent (the container): positions = the
split point; headings fanned evenly across `cluster_fan_deg` (36° total) centred on the direction to the predicted point
`TargetInfo.predicted_position(distance / submunition cruise_speed)`; each connected `expired → queue_free`; each launched
with `launcher = null` (armed `arm_clearance` from the split point, §2.6) and the parent's inherited speed is not passed on
(submunitions launch at their own 520 px/s). Children are unguided (F8 "aim, then unguided burn") and never hit each other
or their parent (the sibling rule). **Shooting the parent before the split kills all of it** (no children). A split after
the launcher died works (children go to the container, not to a pool).

**WARHEAD** (`delayed_warhead.tscn`, `Kind.WARHEAD`): slow (100 → 240 px/s), mild steering (`turn_rate` 0.6,
`guidance_seconds` 4.0, aim = §2.7 law). Arms its proximity trigger `prox_arm_seconds` (0.6 s) after launch (independent of
the launcher clearance, which still gates the impact HitBox). Once armed it polls `ProximityArea.get_overlapping_areas()`
for the player hurtbox; on the first hit it **stops dead** (speed 0, steering off — it latches onto the spot like a Ph4
mine; review finding 12) and starts `warning_time` (0.4 s): the body blinks at 12 Hz and the `blast_radius` ring is drawn
faint, then it detonates (`ContactBlast`, radius 110, damage 30). It also detonates on impact like any rocket, and a direct
hit costs the player the same 30 as a proximity detonation (one damage source, §2.6). **Fairness inequality (the Ph4 mine
rule, exact because the blast centre does not move):** `(trigger_radius + blast_radius) / warning_time >= 420` (Open Space
max speed): (70 + 110) / 0.4 = 450 — a player crossing at cruise is caught, a 700 px/s boost escapes (700 × 0.4 = 280 >
180).

**Tests (t6), in `tests/integration/test_enemy_rockets.gd` (hand-ticked unless marked real physics, 8× clock; budget
§4.3):**
- (both) CLUSTER splits when the stub is within `split_distance` (not before: one tick earlier it is still whole); splits
  at `split_time` when the stub is 2000 px away; exactly `cluster_count` children, headings fanned across
  `cluster_fan_deg` (max − min angle within 0.5° of 36°, centred within 1° on the predicted direction); children are not in
  any pool, each frees itself on expiry; the parent emits `expired` once and spawns no `ContactBlast`.
- (open_space, real physics) a player bullet on the parent before the split → no children ever; children launched
  together survive 0.3 s (no sibling hits); a split after the launcher was freed still produces 4 children in the
  container.
- (both) WARHEAD does not trigger before `prox_arm_seconds` with the stub inside the radius from launch, then triggers on
  the first armed tick (B1b); from the trigger tick to detonation its position changes by < 0.5 px; detonates exactly
  `warning_time` after the trigger; the inequality above is asserted from the scene's exports; a stub crossing the trigger
  edge at 420 px/s is inside `blast_radius` at detonation; one boosting at 700 px/s away from the trigger point is outside
  it.
- §2.6 config inequalities for CLUSTER and WARHEAD (`cruise_speed >= 231`, `launch_speed > 240 × boost_seconds`).
- Lifetime rows for CLUSTER, SUBMUNITION and WARHEAD in `test_enemy_bullet_lifetime.gd` (§2.6 numbers: 3.55 ≤ 4.0,
  1.15 ≤ 1.2, 5.76 ≤ 7.0).

### 2.9 Missile Corvette: scene, config, pools, rail fallback (t7)

Follows the Ph4 specialist template (`bomber/`, `ram_corvette/`): root script adds to `enemies`, `_apply_config`, an actor
API, a rail fallback in `_process` while suspended, a brain with the `start_engaged` seam.

**Scene `assault/scenes/enemies/missile_corvette/missile_corvette.tscn`** (root `MissileCorvette extends BaseEnemy`):
body `CircleShape2D` r 40 shared (same `SubResource`, same scale) by the body, the root `HurtBox` and `ContactHitBox`
(contact-geometry and hurtbox-geometry gates); `Health`, `HitFlashAnimationPlayer`, `Sprite2D` (placeholder until t9),
`StateLight`, `Tubes/TubeL` and `Tubes/TubeR` (`Marker2D` at local (±18, 30), nose = local +y), `Tubes/TubeLightL` /
`TubeLightR` (small `Sprite2D`s, modulate driven by the telegraph, the `ArmorPlate.set_glow` idiom), `EnemyMover`,
`MissileCorvetteBrain` (node `Brain`), four pools `DumbPool`, `PursuitPool`, `ClusterPool`, `WarheadPool` (`BulletPool`,
direct root children, `persist_after_owner_death = true`, `pool_size` = `EnemyRocketScenes.pool_size_for(kind, config)` =
`count × ceil(rocket max_time / salvo_period_min)` with `count` = `warhead_salvo_count` for WARHEAD and `salvo_count`
otherwise: **Dumb 3, Pursuit 6, Cluster 3, Warhead 4** — pinned in the test). `sprite_forward_angle = PI / 2` (nose-down hull
art; the rockets themselves are nose-up, §2.6).

**`MissileCorvetteConfig extends ShipConfig`** (flat; `.tres` = these values; `2-research.md` §3.2):

| Group | Field = value |
|---|---|
| Base | `max_health` 160, `collision_damage` 30, `score_value` 70 |
| Movement | `max_speed` 210, `acceleration` 240, `max_turn_rate` 1.2 |
| Range | `preferred_range` 620, `assault_preferred_range` 460, `min_range` 380, `range_drift` 80, `range_tolerance` 120 |
| Arc | `orbit_angular_speed` 0.22, `reversal_min` 4.0, `reversal_max` 7.0 |
| Salvo | `launch_cone_deg` 45, `salvo_telegraph` 0.7, `salvo_count` 3, `warhead_salvo_count` 2, `salvo_gap` 0.22, `salvo_period_min` 4.0, `salvo_period_max` 5.0, `salvo_lead_step` 0.25, `warhead_offset` 90, `warhead_range` 420, `cluster_min_range` 700, `pursuit_flee_speed` 300 |
| Engagement | `engage_seconds` 7.0, `exit_speed` 280 |
| Rail | `rail_rocket_interval` 2.5 |

`max_speed` 210 and `acceleration` 240 are the numbers the rocket scenes' inequalities are checked against (§2.6:
every rocket's `cruise_speed >= 1.1 × max_speed`, `launch_speed > acceleration × boost_seconds`); t7 moves those t5/t6 rows
from constants to reading this `.tres`.

**Launcher API (the rocket reads it; review findings 3 and 15).**
- `MissileCorvette.fire(kind: EnemyRocket.Kind, aim_point: Vector2) -> EnemyRocket`: the one place a rocket is taken from
  a pool: alternates tubes, `acquire()`s from that kind's pool at the tube's global position, calls
  `launch((aim_point − tube).normalized(), aim_point, self)` and returns the rocket (null if the pool is exhausted, counted
  in `rockets_refused`). It sets **no** rocket field: arming, speeds and damage are the rocket's own (§2.6).
- `launch_velocity() -> Vector2`: `velocity` while the AI drives it; while suspended (on a rail, where `EnemyPathMover`
  writes `global_position` and `velocity` stays 0) the position change observed over the last frame divided by its delta,
  tracked in the root `_process` that runs the rail clock.
- `rocket_clear_radius() -> float`: 40.0 (the hull radius).

**Minimal brain (t7):** `Phase` enum as in *For every task*; t7 plays APPROACH (seek to `preferred_range` along the
line to the player) and the Assault `EngagementBudget(engage_seconds)` → DISENGAGE (the Bomber's exit: away from the
player toward the nearest corridor edge at `exit_speed`, freed on leaving the cull rect as the Bomber does). No salvos
yet.

**Rail fallback (`on_suspended()`):** a root `_process` clock fires a DUMB rocket straight DOWN (aim point 600 px below)
every `rail_rocket_interval`. Nothing places it on a rail; this keeps a future `.move()` from being silent (Ph3 rule).
Because the rail moves the ship down at ≥ 330 px/s while it fires down, the rocket starts at `launch_speed` + the observed
rail speed and arms only once clear of the hull — the railed row below proves the corvette never hits itself.

**Outside:** `WaveBuilder.missile_corvette()` + const `MISSILE_CORVETTE`; rows in `test_enemy_contact_damage.gd` (30),
`test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` rosters, `test_base_enemy.gd`
`_AUTHORED_CONTACT_MODES` (COLLISION); a `test_enemy_dual_mode.gd` case (spawns and moves in both harnesses with
`start_engaged`).

**Tests (t7), `tests/integration/test_missile_corvette.gd` (budget 3.0 s, §4.3):** pool sizes equal `pool_size_for` and
are 3/6/3/4; `fire()` alternates tubes, returns an unarmed rocket at the tube and changes none of its exports; config
isolation picks it up (directory sweep, nothing to add); rail fallback: `suspend_ai()` then 2.6 s of `_process` → one DUMB
rocket heading DOWN; **railed corvette (finding 3, real physics 8×):** a real corvette on a WaveBuilder `straight()` rail
moving down at 330 px/s fires its fallback for 3 s → corvette HP unchanged, every rocket's distance to the corvette grows
after launch and each arms; `launch_velocity()` reads ≈ (0, 330) ± 5 on the rail and equals `velocity` off it; budget
expiry → DISENGAGE (Assault); corvette freed with rockets in flight → rockets keep flying (persist); the §2.6 rocket
inequalities now read from this `.tres`.

### 2.10 Missile Corvette behaviour: broad arcs, launch cone, predicted salvos (t8)

Brain `MissileCorvetteBrain` (`assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd`). Phases `APPROACH,
HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE` (+ `IDLE, NOTICING, RETURNING` from t15). Range `R` = `preferred_range` (620) in Open
Space, `assault_preferred_range` (460) in Assault. Config fields are those of `MissileCorvetteConfig` (§2.9).

1. **APPROACH** → seek toward a point at range `R` on the line player→corvette; enter HOLD_ARC within `range_tolerance`.
2. **HOLD_ARC (broad arcs, R5.3):** `Steering.orbit` about the player at radius `R + drift` where `drift` wanders in
   ±`range_drift` (a slow rng-seeded sine, period 6–9 s), angular speed `orbit_angular_speed`, direction ±1; the direction
   reverses after an rng interval in [`reversal_min`, `reversal_max`] (the Razor idiom). Inside `min_range` it blends
   `Steering.break_contact` (side = orbit direction) until back outside. The **nose** turns toward the player through
   `mover.face_toward(player)` at the mover's `max_turn_rate` (1.2 rad/s), independent of travel direction. Never pursues
   closer than `min_range`. (Its radial escape speed against a closing threat is ≈ 134 px/s — `break_contact` doubles the
   lateral share, `steering.gd` — so a player who closes faster *can* get inside; that is the counterplay, and the tests
   below bound the chase in time instead of asserting it can never happen.)
3. **Launch cone (R5.1 "get behind it"):** a salvo may start only when the player lies within `launch_cone_deg / 2` (22.5°)
   of the nose and `salvo_period` (rng in [min, max]) has elapsed since the last salvo ended. A player who circles behind
   faster than 1.2 rad/s of nose turn has a real window.
4. **Kind choice** (`choose_kind(distance, player_speed)`, judgement, the Bomber `choose_kind` precedent; checked in
   order): `distance < warhead_range` → WARHEAD; player speed ≥ `pursuit_flee_speed` and moving away (radial velocity > 0)
   → PURSUIT; `distance >= cluster_min_range` and player crossing (|tangential| > |radial|) → CLUSTER; else DUMB. A seeded
   `rng` swaps a DUMB choice for PURSUIT one time in four, so the rotation is not fixed.
5. **Salvo size per kind (review finding 15):** `warhead_salvo_count` (2) WARHEADs, else `salvo_count` (3) rockets of the
   chosen kind. `salvo_size(kind)` is the one function both the brain and the tests read.
6. **TELEGRAPH** (`salvo_telegraph` 0.7 s): `StateLight` CHARGING; tube lights ramp 0→1; the corvette keeps orbiting at
   half angular speed; the nose keeps tracking. If the player leaves the cone by more than 2× during it, the salvo is
   cancelled (back to HOLD_ARC, light OFF) — not in Assault, where it always fires once started (deadline bound).
7. **SALVO:** `BurstClock` of `salvo_size(kind)` rockets at `salvo_gap`, `StateLight` ARMED, tube lights flash per launch,
   each through `MissileCorvette.fire(kind, aim_point)`. **Aim points (R5.4, R5.5):** DUMB rocket *i* aims at
   `predicted_position(t_i)` with `t_i = intercept(tube, dumb cruise).time + i × salvo_lead_step` (successive points along
   the player's predicted path, so the salvo covers where the player will be and forces a turn, R5.9); PURSUIT / CLUSTER
   aim at the intercept point (the rocket re-aims itself); WARHEAD rocket *i* (of 2) aims at the predicted point offset
   ±`warhead_offset` (90 px) perpendicular to the player's velocity (a pair across the path, 180 px apart). Then HOLD_ARC;
   `StateLight` OFF. **Never COMMIT** (Ph2/Ph3: shooters do not use it).
8. **Tow refusal:** `accepts_tow()` (the `EnemyBrain` virtual from t3) returns false in TELEGRAPH and SALVO, so a Support
   Ship's escort never moves the corvette while its tubes are glowing or firing.
9. **Assault:** one or two salvos per life. The budget defers to a started TELEGRAPH/SALVO (bound `salvo_telegraph +
   (salvo_count − 1) × salvo_gap` = 1.14 s, + 2 ticks); a TELEGRAPH starts only if `budget.remaining() >= 1.14 + 0.05`
   (the Ph4 attack-gate margin). The corridor constraint filters motion; the orbit centre is the player.

**Tests (t8), in `tests/integration/test_missile_corvette.gd`, dual-mode unless marked, all hand-ticked (budget 5.0 s,
§4.3):**
- **holds range (fixed, finding 8):** from 1200 px with a stationary stub: after 6 s the corvette–player distance stays
  within `R ± (range_drift + range_tolerance)` for the next 10 s, and its **cumulative** bearing change about the player
  (Σ|Δbearing| per tick) over those 10 s is ≥ 60° (it arcs, it does not park; reversals do not cancel it out).
- **bounded chase (fixed, finding 8):** with the corvette settled at `R`, a stub closes straight at it at 200 px/s for
  2.0 s and then stops: the corvette's closest approach is ≥ 0.6 × `min_range` (228 px) and it is back outside `min_range`
  within 3.0 s of the stub stopping. In Assault the scenario is placed so the corridor edge is ≥ 400 px behind the corvette.
- orbit direction reverses at least once in 15 s (Open Space).
- launch cone: a stub kept exactly behind the corvette (180° off the nose) by a scripted follower for 6 s → zero salvos;
  in front → first TELEGRAPH within `salvo_period_max + 1` s.
- salvo shape: after TELEGRAPH (exactly `salvo_telegraph` ± 1 tick) exactly `salvo_size(kind)` rockets leave at
  `salvo_gap` intervals — 3 for DUMB, PURSUIT and CLUSTER, 2 for WARHEAD; `StateLight` goes CHARGING → ARMED → OFF and
  never COMMIT.
- predicted path: for a stub at constant 250 px/s crossing, the three DUMB aim points lie on the stub's predicted line
  (within 1 px) at lead times spaced `salvo_lead_step`; a PURSUIT salvo is chosen for a stub fleeing at 350 px/s; a
  WARHEAD pair for a stub at 300 px; the two warhead aim points are 2 × `warhead_offset` = 180 px apart across the velocity.
- tow refusal: `accepts_tow()` is false throughout TELEGRAPH and SALVO and true in HOLD_ARC.
- Assault: a TELEGRAPH started with 1.2 s of budget left completes its salvo; none starts with 1.0 s left.
- turn inequality: the arc's centripetal demand `max_speed² / R ≤ acceleration` (210² / 460 = 95.9 ≤ 240) is asserted
  from the config for both ranges.

### 2.11 Support Ship: scene, config, shell (t10)

**Scene `assault/scenes/enemies/support_ship/support_ship.tscn`** (root `SupportShip extends BaseEnemy`): body
`CircleShape2D` r 34 shared by the body, root `HurtBox` and `ContactHitBox` (the hitbox exists so the geometry gates hold;
the contact profile is `NONE`, so it never deals damage); `Health`, `HitFlashAnimationPlayer`, `Sprite2D` (placeholder
until t14), `Projector` (`Sprite2D` child, `scale.y` 0 when folded — the Sniper barrel idiom; t14 swaps art), `Tether`
(`Line2D`, `top_level = true`, drawn in world space from the projector to the ward, hidden when idle), `EnemyMover`,
`SupportShipBrain` (node `Brain`). No pool, no weapon, no `StateLight` (its state is the projector and the tether, §2.15).
`sprite_forward_angle = PI / 2`.

**`SupportShipConfig extends ShipConfig`** (flat; `2-research.md` §3.2):

| Group | Field = value |
|---|---|
| Base | `max_health` 55, `collision_damage` 0, `score_value` 60 |
| Movement | `max_speed` 270, `acceleration` 700, `max_turn_rate` 4.0, `jink_strength` 60, `jink_period` 0.8 |
| Follow | `follow_distance` 150, `follow_lateral` 40, `evade_radius` 300, `evade_speed` 240 |
| Ward | `ward_min_score` 20, `ward_search_radius` 900, `ward_keep_radius` 1100, `min_ward_seconds` 2.0, `ward_switch_margin` 1.3, `no_ward_grace` 1.5 |
| Repair | `beam_range` 380, `repair_period` 1.5, `repair_fraction` 0.06, `repair_budget` 150 |
| Shield | `shield_arc_deg` 110, `assault_shield_arc_deg` 90, `shield_capacity` 40, `shield_regen_delay` 3.0, `shield_regen_seconds` 1.5, `shield_reboot_seconds` 4.0, `shield_turn_rate` 1.6, `projector_unfold_seconds` 0.4, `projector_fold_seconds` 0.25 |
| Escort | `escort_hp_ratio` 0.35, `escort_release_ratio` 0.5, `escort_tow_ratio` 1.25, `interpose_distance` 90, `escort_max_seconds` 4.0, `escort_safe_distance` 700, `escort_cooldown` 6.0 |
| Assault | `engage_seconds` 9.0, `exit_speed` 300, `view_margin` 48, `view_band` 24, `ward_view_band` 120 |

**Shell (t10):** `SupportShip` adds itself to `enemies`, applies config, sets `ContactProfile` mode `NONE`, overrides
`can_be_repaired()` → false (supports never repair each other, F12). Minimal brain: SEEK_WARD only as "hold position
near the nearest live `BaseEnemy` ally at `follow_distance`, or drift in place with none", the Assault budget →
DISENGAGE (the Bomber's exit). `on_suspended()`: drop any ward, fold the projector, hide the tether; no rail weapon
(it has none — stated, not a gap).

**Outside:** `WaveBuilder.support_ship()` + const `SUPPORT_SHIP`; `test_enemy_contact_damage.gd` gains a `NONE` / 0 row
(a `NONE` profile, not the Bonus Drone's `no_hitbox` exception); contact-geometry and hurtbox-geometry rosters;
`test_base_enemy.gd` `_AUTHORED_CONTACT_MODES` gains `support_ship → NONE`; a `test_enemy_dual_mode.gd` case.

**Tests (t10), `tests/integration/test_support_ship.gd`:** touching the player deals 0 in both harnesses; it holds near an
ally; budget expiry → DISENGAGE in Assault; `can_be_repaired()` is false; `suspend_ai()` folds the projector.

### 2.12 Support Ship: ward selection, follow, retarget, Assault clamp (t11)

Brain `SupportShipBrain` (`assault/scenes/enemies/support_ship/support_ship_brain.gd`); config fields are those of
`SupportShipConfig` (§2.11; its Ward group includes `ward_min_score` 20).

**Candidates** (scan of group `enemies`, the `FighterBrain._mates()` filter shape): a `BaseEnemy`, not self, not a
`SupportShip`, with `is_ai_driven()` true (§2.4: brain and mover present, not on a rail), `health.current_health > 0`, not
`is_queued_for_deletion()`, `counts_toward_wave_clear` true, `score_value >= ward_min_score`, within `ward_search_radius` of
the support; in Assault also inside `EnemyWorld.view_rect(tree).grow(ward_view_band)`; and **not claimed by another live
support** (claim = the ward's meta `&"support_claim"` holding the claiming support's instance id; a stale id —
`instance_from_id` null — counts as free).

**Why each filter (review finding 11).** The threat weight is the enemy's shipped `score_value` (`*_config.tres`); the full
table and what the filters do with it:

| Enemy | `score_value` | Ward? | Reason |
|---|---|---|---|
| Swarm Drone | 10 | no | below `ward_min_score` 20 — disposable, a support on it is wasted |
| Fighter | 25 | yes | |
| Ram Corvette | 35 | yes | §37 Support + Ram |
| Razor Drone | 40 | yes | |
| Sniper | 50 | yes | |
| Missile Corvette | 70 | yes | |
| Gatling Interceptor | 75 | yes | |
| Bomber | 80 | yes | |
| Gunship | 200 | no | legacy: no brain or mover, so `is_ai_driven()` is false — it could never be towed and would otherwise always win |
| Bonus Drone | 500 | no | **explicit:** `counts_toward_wave_clear` false (a reward target, not a combatant) — and it has no brain either |
| Space Station | 1000 | no | no brain; also `can_be_repaired()` false |
| Support Ship | 60 | no | never another support |

Because every candidate passes `is_ai_driven()`, **every ward is escort-capable**: an escort can only be refused
transiently (the ward is boosting or in a telegraphed phase, §2.4), never forever.

**Threat score (judgement):** `score_value × (1 / (1 + d_player / 600)) × (1 + (1 − hp_fraction))`, where `d_player` is the
candidate's distance to the player and `hp_fraction` its health fraction — kind weight, closeness to the player, and damage
taken.

**Stability:** keep the current ward at least `min_ward_seconds`; afterwards switch only to a candidate scoring ≥
`ward_switch_margin` × the current ward's score. Claim on select, release (remove the meta if it is ours) on switch, on
DISENGAGE and on `_exit_tree()`.

**Retarget (R5.24):** the support connects to the ward's `tree_exiting`; when it fires, or each tick when the ward is
invalid, dead, queued, no longer `is_ai_driven()` (a rail took it), beyond `ward_keep_radius`, or (Assault) outside
`view_rect().grow(ward_view_band)`, the ward is dropped and a new one is selected **on the next tick** (the minimum hold
does not apply to a lost ward). No candidate → SEEK_WARD (Open Space: hold `follow_distance` from the nearest ally or
drift; Assault: after `no_ward_grace` s with none → DISENGAGE).

**FOLLOW (soft anchor, R5.19):** anchor = `ward + (ward − player).normalized() × follow_distance + perp × follow_lateral
× side` (Reynolds leader-following, F4; `side` ±1 chosen at selection by rng), sought with `mover.arrive`; plus a jink
nudge (rng direction change every `jink_period`, magnitude `jink_strength`); plus, when the player is inside
`evade_radius`, `Steering.break_contact(pos, player, player_vel, side, evade_speed)` blended in (R5.23 "high
evasiveness"). The support never pursues the player. It faces the ward (`face_toward`), so the projector points at it.

**Assault view clamp (R5.25):** the anchor is clamped into `EnemyWorld.view_rect(tree).grow(−view_margin)`; the support
**supports** (repair, projection — t12) only while its own position is inside `view_rect().grow(view_band)`. So it cannot
hide above the camera: it is pulled into view to follow, and loses its effect if it is pushed out. (`view_rect` is the
camera's `global_position + offset` centred rect, §2.5.)

**Brain state for tests and later tasks:** `ward` (weak, validity-checked), `ward_score`, `ward_held_for`,
`wards_selected` (count), `anchor`, `is_supporting() -> bool` (ward valid, within `beam_range`, and in Assault the support
inside `view_rect().grow(view_band)` and the ward inside `view_rect().grow(ward_view_band)`), `signal
ward_changed(new_ward: Node)` (null when lost).

**Tests (t11), dual-mode, hand-ticked (budget 4.0 s, §4.3):**
- selection: with a fighter (25) and a bomber (80) at equal distance, it picks the bomber; a damaged fighter at 20 % HP
  close to the player beats an undamaged one far away; another support is never chosen; a rail-suspended enemy is never
  chosen; a ward claimed by another support is skipped; a swarm drone (10) alone → no ward; **a real `gunship.tscn` and a
  real `bonus_drone.tscn` next to a fighter → the fighter is chosen** (gunship: not AI-driven; bonus drone: not a
  combatant) — a boundary that fails if the filter falls back to raw `score_value`.
- stability: a candidate scoring 1.2× the ward does not take over; 1.4× does, but only after `min_ward_seconds`.
- **retarget on death (R5.39):** free the ward → `ward_changed` fires with a new ward on the next tick; kill it via
  `health` → same; `suspend_ai()` on the ward → same; with no other candidate → `ward == null` and SEEK_WARD (Open Space) /
  DISENGAGE after `no_ward_grace` (Assault).
- follow: after 4 s the support sits within 60 px of the anchor (behind the ward relative to the player) and never
  within `evade_radius` × 0.8 of a player stub that approaches at 200 px/s for 3 s (evasion works); it never moves toward
  the player by more than 50 px net over 5 s.
- (assault) view clamp: with the ward 300 px above the view top, the support stays inside `view_rect()` (+ `view_band`)
  every tick and `is_supporting()` is false while the ward is out of `ward_view_band`; when the view pans to include it
  (camera `offset` changed in the same frame — no process step needed, §2.5), support resumes. Provider: the harness's real
  `ArenaCamera`, or a fake `assault_arena` node answering `enemy_view_rect`.
- single-writer gate green (`test_enemy_mover_single_writer.gd`, automatically sweeps `support_ship_brain.gd`).

### 2.13 Support Ship: repair beam and shield projection (t12)

**Repair (R5.20):** while `is_supporting()` and the ward is within `beam_range`: every `repair_period` (accumulated clock)
call `ward.repair(max(1, round(ward.health.max_health × repair_fraction)))`; subtract the returned HP from the remaining
`repair_budget`; stop repairing when the budget is spent (projection continues). Only a ward whose `can_be_repaired()` is
true is repaired. **The Ram's plates are never repaired** — `repair()` heals the hull `Health` only; a broken plate stays
broken (IDEAS §23). Optional line of sight: if `LineOfSight.clear(space, support, ward)` is false (an asteroid between),
no pulse and the tether is drawn dim. Each pulse flashes the tether pale green for 0.15 s and emits `repaired(ward: Node,
amount: int)`.

**Projection (R5.21):** on FOLLOW entry (ward valid, in range), the projector unfolds over `projector_unfold_seconds`
(`scale.y` 0→1, ease-out — the Sniper barrel). When fully unfolded, the support creates an `EnemyShield` (§2.3 component:
`global/components/enemy_shield.gd`) **as a child of the ward** named `ProjectedShield`, with `sustain_mode = true`,
`arc_deg` = `shield_arc_deg` (Open Space) or `assault_shield_arc_deg` (Assault), capacity / regen / reboot / turn rate
from the config, `radius` = ward hull radius + 6, and calls `attach(ward.hurt_box)`; if `attach` returns false (another
absorber holds the slot) the projection is skipped and the shield freed. Every tick while `is_supporting()`, the support
calls `shield.sustain(player_position)`, so the arc turns toward the player at `shield_turn_rate`. The shield is owned by
the ward from then on: when the support stops feeding it (dead, stunned by EMP — `process_mode` DISABLED —, out of range,
out of view in Assault, switched ward), it lapses after `heartbeat` and frees itself. The projector folds when the support
is not supporting. The tether (`Line2D`) is cyan while projecting.

**Support + Ram (R5.27, made possible):** a Ram Corvette is an ordinary candidate (score 35). While armoured, its hull
lets every projectile through to its plates (`ram_corvette.gd` `deflects_hit` = `is_armored()`), and the projected shield
**does not absorb at all** — the `EnemyShield` rule refuses any hit while its host answers `is_armored() == true` (§2.3,
review finding 9), so it neither drains nor flares on shots meant for the plates and the plate fight plays exactly as
without a support. Repair heals hull HP only (plates never). Once the ram is exposed the arc absorbs the player's frontal
fire and pulses refill the hull, giving it more charges in Open Space (in Assault a ram lives one charge, so the pairing
shows only as a tougher exposed hull). The escort (t13) widens this same shield to a 360° bubble while it tows the ward.

**Tests (t12), dual-mode, hand-ticked unless marked (budget 4.0 s, §4.3):**
- repair: a ward at 50/100 HP within range regains `round(100 × 0.06)` = 6 per `repair_period` (± 1 tick), never above
  max; no hit flash on the ward; `repaired` fires per pulse; the budget stops repair after 150 HP total; out of
  `beam_range` → no pulse; a `SpaceStation`-like `can_be_repaired() == false` ward is never repaired.
- projection: after `projector_unfold_seconds` the ward has one `ProjectedShield` attached to its `HurtBox`
  (`has_absorber()`); its facing turns toward the player; in Assault its `arc_deg` is 90.
- (open_space, real physics, 8×) a real player `Bullet` from the player's side is consumed by the shield and the ward's HP
  is unchanged; from behind it lands.
- lapse: free the support → the ward's shield lapses within `heartbeat + fade_seconds` + 1 tick and the hurtbox slot is
  free; set the support's `process_mode` DISABLED (EMP) → same; switch ward → the old ward's shield lapses, the new one
  gets one.
- Ram pairing: a support wards a real `ram_corvette.tscn`; after its plates are broken and the hull damaged, pulses raise
  the hull HP and `live_plate_count()` stays 0.
- **armoured Ram (finding 9):** while the warded real `ram_corvette.tscn` still has plates, a fake player `HitBox` from the
  player's side reaching the hull hurtbox → `absorbs_hit` false, the shield's `points()` unchanged and no `absorbed`
  signal; the same hit after the last plate breaks → absorbed. (Hand-ticked: the hurtbox's `_on_area_entered` is called
  with the fake directly, so no physics frames are spent.)

### 2.14 Support Ship: emergency escort (t13)

Brain `SupportShipBrain` (`assault/scenes/enemies/support_ship/support_ship_brain.gd`), Phase `ESCORT`; Escort config group
of `SupportShipConfig` (§2.11): `escort_hp_ratio` 0.35, `escort_release_ratio` 0.5, `escort_tow_ratio` 1.25,
`interpose_distance` 90, `escort_max_seconds` 4.0, `escort_safe_distance` 700, `escort_cooldown` 6.0.

**Trigger (R5.22):** in FOLLOW, the ward's health fraction ≤ `escort_hp_ratio` and the per-ward cooldown
(`escort_cooldown`, keyed by ward instance id) has elapsed → ESCORT. Every ward is AI-driven (§2.12 filter), so an escort is
never started on a ward that can never be towed.

**In ESCORT, each tick:**
- **"pulls the target away":** `ward.accept_tow(away × escort_tow_ratio × ward.ai_mover_max_speed())` where `away` =
  (ward − player).normalized(). `BaseEnemy.accept_tow(v) -> bool` (t3) adds a nudge to the **ward's own mover**, summed onto
  the ward brain's own request and limited to its `max_speed`; with 1.25× the ward's max speed the net motion is away from
  the player even while the ward's brain seeks the player at full speed. It is a request, not a write (the single-writer
  gate stays green).
- **Refusal (review finding 4):** `accept_tow` returns false while the ward is boosting **or its brain's
  `accepts_tow()` is false** — Sniper DECOY/AIM/LOCK/FIRE, Ram WIND_UP/CHARGE, Bomber RUN, Fighter RUN_IN, Gatling
  SPIN_UP/STREAM, Razor WINDUP/DASH/FEINT_WINDUP/FEINT_LUNGE, Swarm WINDUP/BURST, Missile Corvette TELEGRAPH/SALVO — so a
  telegraphed attack always lands where its warning said. While refused, the escort **only interposes** (below) and keeps
  offering the tow each tick; the escort clock keeps running, so a ward that stays committed ends the escort by timeout.
- **"becomes the closer target itself":** the support's anchor switches to the interpose point `ward + (player −
  ward).normalized() × interpose_distance` (judgement; Buckland "interpose", unsourced), clamped into the view in Assault;
  its evade blend is suspended (it accepts fire).
- **Shield bubble (review finding 13; IDEAS §13.2 "shield bubble projected by support ships"):** on entering ESCORT the
  ward's `ProjectedShield` (`EnemyShield`, §2.13) is widened to `arc_deg = 360` (a full bubble around the fleeing ward —
  the player is no longer the only threat direction once the ward runs); on leaving ESCORT it returns to the mode's arc
  (110 Open Space / 90 Assault). Capacity, regen and the armoured-host rule are unchanged, so the bubble is still a small
  temporary resource. If the ward has no `ProjectedShield` (support out of range, slot taken), nothing is widened.
- The tether is drawn thicker as a tow beam; repair continues.

**End:** ward HP fraction ≥ `escort_release_ratio` (0.5, hysteresis), ward lost (→ retarget, §2.12), ward–player
distance ≥ `escort_safe_distance`, or `escort_max_seconds` elapsed → FOLLOW (shield arc restored), and the ward's cooldown
starts.

**Assault:** the corridor constraint clamps the tow; the escort still triggers and ends by the same rules; the support's
budget is not deferred by an escort.

**Tests (t13), dual-mode, hand-ticked (budget 3.0 s, §4.3):**
- trigger: ward at 36 % → no escort; at 34 % → ESCORT on the next tick; the ward's mover received a nudge pointing away
  from the player (angle < 5°) of magnitude `1.25 × max_speed`.
- effect: a ward whose fixture brain seeks the player at full speed **increases** its distance to the player over 1 s of
  escort (control run without a support: distance decreases).
- interpose: within 1.5 s the support lies within 40 px of the interpose point (Open Space; in Assault within 40 px of its
  view-clamped image).
- **telegraphs are not moved (finding 4):** a real `sniper.tscn` ward at 30 % HP driven into LOCK → ESCORT starts, the tow
  is refused every tick (`accept_tow` false, no nudge on its mover), the support still interposes, and the sniper's muzzle
  stays within 1 px through LOCK; the same for a real `ram_corvette.tscn` ward through WIND_UP. On the first tick after the
  sniper leaves FIRE, the tow is accepted again.
- **bubble (finding 13):** during ESCORT the ward's `ProjectedShield.arc_deg` is 360 and a fake hit from behind the ward
  is absorbed; after ESCORT ends it is back to 110 (Open Space) / 90 (Assault) and the same hit lands.
- end: repaired to 50 % → FOLLOW; ward–player 700 px → FOLLOW; 4 s → FOLLOW; re-trigger blocked for `escort_cooldown`.
- a boosting ward: `accept_tow` false, no nudge applied, ESCORT persists until it stops boosting or ends by timeout.
- single-writer gate green.

### 2.15 Art and visual states (t9, t14)

Both via PixelLab under the `pixel-art-generation` skill: strict top-down (`view: "high top-down"`, `isometric: false`),
saved only with `scripts/pixellab.sh`, each image opened and checked; ≤ 90 % opaque with a transparent margin
(`test_entity_sprite_transparency.gd`); faction palette (dark navy/black hull, red/maroon accents, cool edge highlight,
IDEAS §21); hulls are never recoloured by state — only gameplay lights change. Texture references UID-less. Keep node
names and types tests reference (`Sprite2D`, `Projector`, `Tether`, `Tubes/*`).

**Missile Corvette (t9):** `missile_corvette.png` ≈ 96 × 96, nose-down, a wide flat hull with two visible forward launch
tubes at the positions of `Tubes/TubeL` / `TubeR` (local (±18, 30)); tube lights are separate small sprites (red-orange
glow, modulate 0..1 driven by the brain's telegraph value). Rockets are drawn **nose-up** (the player missiles' convention: the rocket sets `rotation = heading.angle() + PI / 2`, and
`RocketTrail` emits along local +Y, i.e. out of the tail of nose-up art — review finding 10): `enemy_rocket.png` (≈ 10 × 20,
used by DUMB and PURSUIT), `enemy_cluster_rocket.png` (fatter, ≈ 14 × 24), `enemy_submunition.png` (≈ 6 × 10),
`enemy_warhead.png` (≈ 18 × 18, rounder, with a light the blink modulates) — each keeps its `RocketTrail`; replace the
placeholder `_draw()` bodies. A test row asserts, for each rocket scene, that the trail child sits behind the nose: the
trail's world position is on the opposite side of the rocket centre from `heading()`. Rockets are in `assault/scenes/projectiles/`, so the transparency gate covers them.

**Support Ship (t14):** `support_ship.png` ≈ 88 × 88, nose-down, a distinct silhouette (a ring or dish projector mount
amidships, slim hull — readable as "not a gunship"); `support_projector.png` (the dish/emitter, folded = `scale.y` 0,
unfolded = 1; anchored so it opens forward toward the ward). The tether stays a `Line2D` (cyan while projecting, pale green
pulse on repair, thicker during escort). The shield arc is `EnemyShield`'s own cyan drawing.

**Tests (budget 0.5 s each for t9 and t14, §4.3):** the transparency gate (automatic); the existing node-name references in
each enemy's test file still resolve; t9's trail-behind-the-nose row above.

### 2.16 Hub idle for both enemies (t15)

Both brains get the Ph3/Ph4 hub idle: `Phase` appends `IDLE, NOTICING, RETURNING` (corvette values 5–7, support 4–6 —
matching the enums in *For every task*), `patrol_anchor`, `anchor_idle` (`AnchorIdle`), `idle_phase_offset`, and the
`start_engaged` test seam (set before the first tick to skip the idle; Assault builds no `AnchorIdle` and starts in
combat). Each config gains an `Idle` group: `perceive_radius`, `lose_radius`, `notice_time` 0.35, `idle_radius` 150,
`idle_speed` 0.5, written to the `.tres` too.

- **Missile Corvette:** perceive 720, lose 1500. Asserted: `lose_radius > preferred_range + range_drift + range_tolerance`
  (620 + 80 + 120 = 820), the largest corvette–player distance its own cycle opens, with margin; RETURNING never interrupts TELEGRAPH or SALVO (the Ph4 "protected phases" rule; it is retried every tick).
- **Support Ship:** perceive 600, lose 1300 (the Ram's — it patrols with the hub Ram). Asserted: `lose_radius >
  escort_safe_distance + follow_distance + interpose_distance` (940). RETURNING interrupts nothing (no protected phase).
- Every existing test that spawns either enemy in the Open Space harness sets `start_engaged = true`.

**Tests (t15, budget 2.0 s, §4.3):** per enemy, the Ph4 `test_*_hub_idle` shape: idles on its ring with no player; NOTICING then combat when
the player enters `perceive_radius` (after `notice_time`); RETURNING when beyond `lose_radius`; the inequality from the
config; the protected-phase rule for the corvette (a TELEGRAPH in progress completes before RETURNING).

### 2.17 Open Space hub placement (t16)

`open_space/scenes/levels/sector_hub.gd` `_spawn_patrol()` appends, **after the existing 12 seeded rng draws**:

- **Missile Corvette** at bearing 315° on a new ring `missile_corvette_ring_radius` = **1900** (exports
  `missile_corvette_ring_radius`, `missile_corvette_anchor_bearing_deg`); draw 13 is its `rng_seed`. Anchor (1344, −1344):
  nearest interactable 1287 px (`ShipBoostUpPickup`) → clearance 1287 − 150 − 720 = **+417 px**; 1345 px from the Razor
  anchor, 1353 px from the Gatling anchor (> 1000).
- **Support Ship** at the **Ram Corvette's anchor** (−1202, −1202), sharing it; draw 14 is its `rng_seed`. Its idle and
  perceive radii (150 / 600) equal the Ram's, so the Ram's +308.7 px clearance holds. It wards the Ram once both engage
  (§37 Support + Ram made possible).

`tests/integration/test_sector_hub_patrol.gd` (budget 2.0 s, §4.3): two clearance rows (corvette, support); "the seven patrol anchors are well
apart" becomes **eight distinct anchors > 1000 px apart, and the support's anchor equals the ram's**; the existing 12
draws' seeds unchanged; the container count and the frame-0 IDLE list include both; a hub corvette's rocket lands in
`EnemyContainer` (`start_engaged`, 8× clock); a hub support engaged with the hub Ram selects the Ram as its ward
(hand-ticked, `start_engaged` on both; ward selection is the Support Ship brain's, §2.12: the Ram is AI-driven, scores 35 ≥
`ward_min_score` 20 and is the only candidate in range, so `ward_changed(ram)` fires and `is_supporting()` turns true once
in `beam_range`).

### 2.18 Level 1 placement (t17)

**Rule:** both enemies go only into **DURATION** sections (deep_space 30 s, planet_approach 110 s). A Missile Corvette's
rockets persist after it leaves and `LevelDirector._wait_enemies_cleared` waits until the container is empty, so a
corvette in an `ENEMIES_CLEARED` section would stall it: worst case `rel + engage 7.0 + salvo deferral 1.14 + measured exit
+ rocket max life 7.0 + 0.5` ≫ cloud_descent's 10 s. The support has no ordnance, but cloud_descent's ram row already passes
by 0.40 s; not worth the risk (judgement).

**Placements (candidates to measure; the task may shift a new row's trigger to satisfy the gates, never an existing row):**
- deep_space: one corvette at ≈ 12 s (offset (0, −400), off the top edge); one support with the deep_space ram line
  nearest 26 s (same trigger, offset 120 px behind it).
- planet_approach: corvettes at ≈ 40 s and ≈ 85 s (clear of the 65.7 s specialist peak window, re-measured); one support
  with the planet_approach ram triple nearest 28 s.
- New lines carry no `.move()`, `.free_after()` or `.shoot_*()`.

**Gates (`tests/integration/`):**
- `test_level1_specialist_spawns.gd`: a new pin `EXPECTED_PH5` for the new rows (trigger, offset, delay); the legacy
  50-row `EXPECTED` and its sanity counts stay (the migrated-sections line count becomes 50 + new rows, stated);
  **both kinds count as specialists** in the existing count gate (`peak ≤ 2.5 × _LEGACY_PEAK_SPECIALISTS`, frozen
  constants unchanged): limits deep_space 12.5, planet_approach 7.5 (peak today 6 — at most one more alive at its peak),
  cloud_descent 10. Lifetimes: corvette `engage 7.0 + 1.14 + 2 ticks + measured exit`; support `engage 9.0 + measured exit`;
  exits measured with `tests/helpers/specialist_exit_probe.gd` `worst_disengage()` over **`corridor_starts()`** (the
  corridor-wide set; the Ph4 ram lesson). A boundary row: an extra corvette at planet_approach's 65.7 s peak fails the gate.
- `test_engagement_deadline.gd`: "no `ENEMIES_CLEARED` section contains a Missile Corvette" and "… a Support Ship" rows;
  a boundary row: a corvette added to cloud_descent's last wave computes > 10 s with the rocket term alone (`rel + 7.0 +
  1.14 + 7.0 + 0.5`, no exit term needed).
- **Attack-in-budget rows** (the Ph4 convention), through a real `WaveManager` at the 8× clock, from every placed spawn
  class: the corvette reaches TELEGRAPH before its `engage_seconds` expires and fires at least one salvo per life; the
  support has a `ProjectedShield` attached to a ward (`is_supporting()` true — §2.12: ward valid, in `beam_range`, both
  inside the view bands) before its budget expires. Asserted in `test_missile_corvette.gd` / `test_support_ship.gd`.
  **Cost (budget 15.0 s for all of t17, §4.3):** one 8× WaveManager run per placed spawn class (≤ 5), each covering only
  `rel − 1 s .. rel + engage + 2 s` of its section (never a whole-section replay); the exit probes run once per kind in
  `before_all` and are shared by every row that reads them.
- Spill-over: a deep_space late spawn may live into asteroid_belt (DURATION, no enemies; its rockets may hit asteroids —
  intended, R5.7); nothing from planet_approach may still be alive at cloud_descent's last-wave trigger (asserted from the
  lifetimes).

If a gate cannot be met by moving a new row's trigger, the task stops with `Result: ESCALATE` — no lever on an existing
enemy's config is pre-approved in this phase.

### 2.19 Docs and phase close (t18)

Invoke the `updating-project-docs` skill. `ENEMY.md` beside each new enemy (role, config, phases, tests, §43 checklist
answers from §2.20 below); `docs/enemy-roster.md` (both enemies, the rocket family section next to "Enemy ordnance (Ph4)",
Quick Rules: rockets hit enemies by impact only, supports never repair supports, both DURATION-only);
`docs/architecture/modules/assault.md`, `global.md` (`EnemyShield`, the `HurtBox` absorb hook, `EnemyWorld.view_rect`,
`BaseEnemy.repair` / `accept_tow`), `open_space.md` (hub groups), `docs/architecture/PROJECT.md` conventions (enemy shields;
rocket layers and friendly fire), `docs/BULLET_POOL.md` (rocket pools), `CLAUDE.md` (the bullet paragraph gains "a shielded
enemy consumes the bullet"; the gate list gains the new rows and test files), `tests/README.md` (gate-time section from t1).
Then the phase close: `DECISIONS.md` `## Phase 5 - as built (<date>)` and the dossier `docs/epics-done/cmufs7elw001pnm2xr3b6fteb/`
(PRD / SOURCES / REPORT).

### 2.20 Mode compatibility and the §43 checklist (R5.40, R5.41)

Every new behaviour test is parameterised `["open_space", "assault"]` with the same assertion and only the constraint
changed, except rows that are physically mode-specific (view clamp: Assault; reversal and real-physics shoot-down rows:
Open Space). §43 answers, for the `ENEMY.md` files:

| Question | Missile Corvette | Support Ship |
|---|---|---|
| Silhouette | wide hull, two forward tubes | slim hull, dish projector |
| Preferred distance | 620 px (Assault 460) | 150 px behind its ward |
| Movement signature | slow broad arcs with reversals | shadowing, jinking, interposing |
| Attack | telegraphed predicted salvos, four rocket kinds | none: repair, shield, escort |
| Player behind it | cannot launch outside its 45° cone; nose turns 1.2 rad/s | evades (break contact) |
| Player boosts away | pursuit rockets; holds range | follows its ward, not the player |
| Off-screen | rockets need no LOS; Assault corridor-limited | Assault: clamped into view, no effect outside it |
| Retreat / reposition | break contact inside 380 px; Assault DISENGAGE | evade radius 300; DISENGAGE with no ward |
| Telegraph | CHARGING light + tube glow 0.7 s | projector unfold + cyan tether |
| Destroying it changes the encounter | no more rockets (in-flight ones persist) | shields lapse, repair stops |
| Armour / shields | none | none of its own; projects one |
| Alone / combined | alone: area denial; + fighters (§37) | alone: inert evader; + Ram (§37) |
| Deterministic tests | yes (seeded rng, hand-ticked) | yes |

## 3. Build sequence

Each step is one task in `tasks.json` under the same key.

1. **t1 gate-headroom** (§2.2, §4.3) — first; frees ≥ 70 s so GUT is ≤ 183 s; every other task depends on it.
2. **t2 enemy-shield** (§2.3) — the `HurtBox` hook and `EnemyShield` on fixtures.
3. **t3 support-hooks** (§2.4) — `repair`, decrease-only flash, `can_be_repaired`, `is_ai_driven`, `accept_tow`, and
   `EnemyBrain.accepts_tow()` with its overrides in the seven shipped brains.
4. **t4 view-rect** (§2.5).
5. **t5 rockets-dumb-pursuit** (§2.6, §2.7) — the common rocket contract, layers, friendly fire, two kinds.
6. **t6 rockets-cluster-warhead** (§2.6, §2.8).
7. **t7 corvette-shell** (§2.9).
8. **t8 corvette-salvos** (§2.10).
9. **t9 corvette-art** (§2.15) — art after behaviour on the same scene.
10. **t10 support-shell** (§2.11).
11. **t11 support-ward** (§2.12).
12. **t12 support-repair-shield** (§2.13).
13. **t13 support-escort** (§2.14).
14. **t14 support-art** (§2.15).
15. **t15 hub-idle** (§2.16).
16. **t16 hub-spawn** (§2.17).
17. **t17 level1** (§2.18).
18. **t18 docs** (§2.19, §2.20).

**Dependencies:** **t1 is the root of every other task** (review finding 5: t3 and t4 used to be independent roots and
could land in the middle of t1's before/after measurement). t2, t3, t4 and t5 need t1. t6 needs t5. t7 needs t6 (four
pools). t8 needs t7 and t3 (it overrides `accepts_tow()`). t9 needs t8. **t10 needs t7** and t3 (`can_be_repaired`); t7
and t10 both edit the contact-damage / geometry rosters, `test_base_enemy.gd` and `test_enemy_dual_mode.gd`, so they run
in series. t11 needs t10 and t4. t12 needs t11, t2 and t3. t13 needs t12 (same brain file) and t3. t14 needs t13. t15
needs t8 and t13 (both brains and both configs). t16 needs t15. t17 needs t15 (it may write the same `.tres` files) and
t8, t13. t18 needs t9, t14, t16 and t17. Critical path: t1 → t5 → t6 → t7 → t10 → t11 → t12 → t13 → t15 → t17 → t18.

## 4. Test plan

The test rows for each task are listed under its design section (§2.2–§2.18); this section holds the rules they share.

### 4.1 Shared test rules

- **Dual mode:** `use_parameters(["open_space", "assault"])` on a bare label; build `tests/helpers/enemy_ai_harness.gd` in
  the test body (never in a default argument — the GUT leak); drive brains with hand-ticked `_tick()`; Open Space spawns
  set `start_engaged = true` once t15 has landed (mark earlier ones `# pre-t15` so t15 can find them).
- **Real physics only where a real collision is the point** (shoot-down, shield consumption, friendly fire, attack-in-
  budget); those run on the 8× clock with the step kept at 1/60 game-second, restored in `after_each`.
- **Every gate must be able to fail:** each new invariant row has a boundary case that a deliberately wrong value trips
  (listed in §2.x rows: the 34 % / 36 % escort edge, the shield's 54° / 56° arc edge, the
  launcher-overtakes-its-rocket control, the refused tow on a locking Sniper, the gunship / bonus-drone ward filter, the split one tick early, the extra
  corvette at the 65.7 s peak, the corvette in cloud_descent).
- **Automatic sweeps that will see the new code without edits:** config isolation, sprite transparency, single writer,
  signal arity, UID integrity, project load, suite integrity. Do not add allowlist entries to any of them.
- **Gate time:** each task runs `scripts/gate-time.sh` (from t1) before and after, reports import, boot and GUT time and
  its delta, and stays within its allotment in §4.3 (GUT ≤ 240 s after every task). A task over its allotment converts
  rows to hand-ticked form, shares a replay or a scene build, before it asks; it never cuts an assertion.
- **Leaks:** run `scripts/check-test-leaks.sh` after any test that awaits.

### 4.2 Requirement → test map

| Requirement | Where (task) |
|---|---|
| Rocket steering toward the predicted point (R5.39) | §2.7 rows (t5), both modes |
| Dodgeable rockets (C6) | §2.7 rows (t5) |
| Splitting (R5.39) | §2.8 rows (t6) |
| Proximity detonation (R5.39) | §2.8 rows (t6) |
| Shoot-down, friendly fire, launcher, siblings, Ram plate, asteroid | §2.7 rows (t5), §2.8 (t6) |
| Repair application (R5.39) | §2.4 (t3), §2.13 (t12) |
| Shield application (R5.39) | §2.3 (t2), §2.13 (t12) |
| Retarget when the ally dies (R5.24, R5.39) | §2.12 (t11), both modes |
| Escort trigger (R5.39) | §2.14 (t13), both modes |
| Assault view clamp (R5.25) | §2.5 (t4), §2.12 (t11) |
| Corvette arcs, cone, salvos | §2.10 (t8) |
| Hub clearance, seeds, pairing | §2.17 (t16) |
| Level-1 pins, density, deadline guards, attack-in-budget | §2.18 (t17) |
| Rosters (contact damage, geometry) | §2.9 (t7), §2.11 (t10) |

### 4.3 Gate-time budget (review finding 5)

**Ceiling:** GUT time ≤ **240 s** after every task (the harness cap is ~300 s wall clock; import 4.7 s and boot 1.0 s on the
dev container, but up to ~38 s of total overhead was seen on the harness machine in Ph4). **t1 brings GUT to ≤ 183 s**, so
the epic can add the 56.5 s below and still end at ≤ 240 s. Each task measures with `scripts/gate-time.sh` before and after
and reports both numbers and its delta in its final message; the next task's "before" is the last task's "after".

**Allotments (new GUT seconds per task), estimated from measured Phase 4 analogues at `7916662`.** Rule of thumb from those
files: an 8× real-physics case costs ≈ 0.25–0.4 s (`test_enemy_ordnance.gd` 6.6 s / 27 cases, `test_bomber.gd` 8.7 s / 36);
a hand-ticked dual-mode case costs ≈ 0.02–0.06 s (`test_sniper.gd` 1.6 s / 53, `test_fighter.gd` 1.0 s / 71); a whole-section
WaveManager replay at 8× costs ≈ 5 s (`test_level1_specialist_exit.gd` 10.1 s / 2).

| Task | Allotment | What it pays for | Analogue |
|---|---|---|---|
| t1 | 0 (frees ≥ 70) | — | — |
| t2 shield | 3.0 | ≤ 6 real-physics cases + unit rows | `test_armor_query.gd` 5.3 s / 13 |
| t3 hooks | 2.0 | 7 brain scenes instantiated, 2 hand-ticked telegraph rows | `test_base_enemy.gd` |
| t4 view rect | 0.5 | unit rows | `test_enemy_world` rows |
| t5 rockets | 6.0 | ≈ 12 real-physics cases + hand-ticked guidance rows | `test_enemy_ordnance.gd` |
| t6 cluster/warhead | 4.0 | ≈ 6 real-physics cases + hand-ticked rows | `test_enemy_ordnance.gd` |
| t7 corvette shell | 3.0 | rail rows (`_process` 3 s at 8×), dual-mode case, rosters | `test_bomber.gd` shell rows |
| t8 corvette fight | 5.0 | hand-ticked 16 s simulations × 2 modes | `test_sniper.gd` / `test_bomber.gd` |
| t9 art | 0.5 | none new (import of 4–5 PNGs adds ≈ 1–2 s once to import, not GUT) | — |
| t10 support shell | 2.0 | dual-mode shell rows, rosters | — |
| t11 ward | 4.0 | hand-ticked dual-mode rows | `test_fighter.gd` |
| t12 repair/shield | 4.0 | hand-ticked rows + 1–2 real-physics bullet rows | — |
| t13 escort | 3.0 | hand-ticked dual-mode rows | — |
| t14 art | 0.5 | none new | — |
| t15 hub idle | 2.0 | hand-ticked idle rows × 2 enemies | Ph4 `test_*_hub_idle` rows |
| t16 hub | 2.0 | clearance rows + one 8× rocket-landing row | `test_sector_hub_patrol.gd` 0.2 s |
| t17 level 1 | 15.0 | 5 attack-in-budget WaveManager runs at 8×, 2 corridor-wide exit probes, pins | `test_level1_specialist_spawns.gd` 4.3 + `test_level1_specialist_exit.gd` 10.1 + `test_engagement_deadline.gd` 5.7 |
| t18 docs | 0 | — | — |
| **Total** | **56.5** | | |

**Over-allotment rule:** a task that measures over its allotment first converts rows to hand-ticked form, shares a replay
between tests, or runs one scene build for several assertions; it never cuts an assertion. If it is still over **and** the
gate is above 240 s, it stops with `Result: ESCALATE` and its measurements. Under-spend carries forward to later tasks.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Gate wall clock (measured GUT 253.3 s + import 4.7 s + boot 1.0 s at `7916662`, against a ~300 s cap with up to ~38 s of harness overhead seen in Ph4) | t1 frees ≥ 70 s (GUT ≤ 183 s) before anything else, or escalates; per-task allotments (§4.3, 56.5 s total); GUT ≤ 240 s after every task; hand-ticked specs; 8× clock for real physics. |
| The `HurtBox` hook touches every hurtbox in the project | No absorber = byte-identical path; unit rows pin it; the slot is set only by `EnemyShield`. |
| Rockets feel unfair (fast and tight-turning) | One kind is fast/wide or slow/tight, never both; finite guidance; dodge rows (straight run, late boost) are gates. |
| Enemy rockets wear Ram plates / kill allies — surprising | Owner question 1; pinned by a test either way; impact damage to enemies is small (8–18), 3–4 rockets per 50 HP plate. |
| A rocket hurts the player twice, or its own launcher | One player-facing source (the blast; the impact is on layer 32 only); inherited launch speed, arming by clearance from the launcher's current position and `cruise_speed ≥ 1.1 × launcher max_speed`, with moving-launcher and railed-corvette rows. |
| Player missiles silently eaten by enemy rockets | The rocket's shoot-down hurtbox masks 32 \| 64 and resolves the hit itself: both are destroyed, tested from the missile's side. |
| A shield that always faces the player is unflankable in the vertical Assault lane | Arc turns at a capped 1.6 rad/s and is 90° in Assault; capacity is small with a long regen delay; recorded as an accepted limitation. |
| Support stalls fights (repair + shield) | Pulsed 6 % repair, 150 HP budget per life, supports never repair each other, shield lapses without its projector. |
| Escort tow fights the ward's own brain, or moves a telegraphed attack | It is a nudge summed onto the brain's request through the mover; a boosting ward, or one whose brain answers `accepts_tow() == false` (every committed or telegraphed phase), refuses it; bounded by `escort_max_seconds`; locking-Sniper and winding-up-Ram rows. |
| planet_approach density margin is one ship | Corvettes placed outside the 65.7 s window; boundary row; escalate rather than retune existing enemies. |
| Persisting rockets stall a section | DURATION-only rule plus two guard rows and a boundary row. |
| Direct emitters (beam, nova) ignore shields | Same as plates; documented; revisit in Ph8 with energy weapons. |
| Not play-tested by the gate | Whether salvos read, whether the shield arc and tether read, whether the support is too evasive — listed for the owner in the dossier. |

## 6. Requirements coverage

| Req | Requirement | Delivered by |
|---|---|---|
| R5.1 | Missile Corvette role and verb ("survive the salvo, get behind it") | t7, t8 (launch cone) |
| R5.2 | Size 80–112 px | t9 (≈ 96 × 96) |
| R5.3 | Medium distance, broad arcs | t8 |
| R5.4 | Predicted salvos | t8 |
| R5.5 | Rockets prefer the future path | t5 (guidance), t8 (salvo aim points) |
| R5.6 | Visible launch, acceleration, mild steering, explosion radius; warning audio; flare/decoy reaction | t5/t6 (launch boost, accel, steering, blast); **audio out** (Ph17, no enemy SFX pipeline); **flare/decoy out** (no player countermeasure; hook noted) |
| R5.7 | Outrun, out-turn, shoot down, hit other enemies / environment; bait into carrier escort | t5, t6; carrier part generic (Ph10 Carrier) |
| R5.8 | Assault: rockets functional, corridor-limited | t5 (`use_world_rect`), t17 |
| R5.9 | Corvette + Fighter combination | made possible by t8 (path-covering salvo); encounters Ph13/Ph14 |
| R5.10–R5.13 | Dumb, Pursuit, Cluster, Delayed Warhead | t5, t6 |
| R5.14 | Hijack Pulse | out (Ph9) |
| R5.15 | Rocket collision layer | t5 (impact on bit 32, the layer Ph1 named for rockets; blast on 256) |
| R5.16 | World-space lifetime, persist after owner death | t5/t6 (lifetime rows), t7 (pools); owner-distance rule not built (S2) |
| R5.17 | Support role | t10–t13 |
| R5.18 | Size 72–104 px | t14 (≈ 88 × 88) |
| R5.19 | Behind the highest-threat ally, soft anchor | t11 |
| R5.20 | Repair beam | t3, t12 |
| R5.21 | Directional shield arc on another enemy | t2, t12 |
| R5.22 | Emergency escort | t3 (`accept_tow`, `accepts_tow`), t13 |
| R5.23 | Low HP, high evasiveness | t10 (HP 55), t11 (evade, jink) |
| R5.24 | Retarget when the ally dies | t11 |
| R5.25 | Assault: cannot hide above the camera | t4, t11 |
| R5.26 | Contact profile None | t10 |
| R5.27 | Support + Ram made possible | t12 (pairing test), t16 (hub pair), t17 (support with level-1 rams) |
| R5.28 | Carrier + Support + Drones | out (Carrier Ph10/Ph18) |
| R5.29 | Shields are a temporary resource | t2 |
| R5.30 | Directional, local-module, regenerating, projected bubble | t2 (all four as component features), t12 (projected directional arc shipped), **t13 (projected bubble shipped: the arc widens to 360° during the escort)**; local-module fixture-proven, shipped consumer Ph10 |
| R5.31 | DamageReaction decision | §2.3 decision (not adopted), logged by this plan |
| R5.32 | Interaction rules via profiles, not mask overwrites | t2 (hook, no mask change), t5 (rocket layers authored in scenes) |
| R5.33 | Readability layers, cyan = shield | t2 (cyan arc), t9, t14 |
| R5.34 | Specialist silhouettes 80–128 px | t9, t14 |
| R5.35 | Projector unfolds while supporting | t12 (behaviour), t14 (art) |
| R5.36 | Strict top-down 72–112 px sprites | t9, t14 |
| R5.37 | Added to existing Assault waves | t17 |
| R5.38 | Added to the hub's ambient spawn | t16 |
| R5.39 | Tests in both harnesses for the listed behaviours | t5, t6, t2, t12, t11, t13 (§4.2) |
| R5.40 | Every enemy tested in both modes | t7–t13 dual-mode cases |
| R5.41 | §43 checklist | §2.20, written into `ENEMY.md` by t18; audit Ph17 |

## 7. Out of scope

- Rocket warning audio (Ph17), flare/decoy reactions (no player countermeasure exists), the Hijack Pulse (Ph9).
- Shipped module shields (Ph10 modular damage) and fortress shield nodes (Ph11); this phase ships the component, proves the
  module kind with a fixture and ships the bubble only as the Support Ship's escort bubble.
- Enemy friendly fire from blasts and beams (Ph8).
- Owner-distance projectile lifetime (S2) and `BulletPool` container injection (S3).
- Placing either enemy in `ENEMIES_CLEARED` sections, the station's reinforcements or `level_2_waves.gd` (Ph15).
- Encounter composition (Corvette + Fighter, heavy patrol, Carrier + Support) — Ph13/Ph14; this phase makes the pairings
  mechanically possible.
- Difficulty tiers (Ph16): the levers are `EnemyRocket.lead_max`, `turn_rate`, `guidance_seconds`, the corvette's
  `salvo_period_*`, the support's `repair_fraction` / `shield_capacity`.
- A `StateLight` cyan state (the support's state is shown by its projector and tether).

## 8. Owner questions (not blocking; the plan takes the stated default)

1. **Enemy rockets wear down Ram plates** when baited into a Ram: a plate has 50 HP, so 4 Dumb or 3 Pursuit rockets break
   one. Default: yes (counterplay; pinned by a t5 test either way).
2. **Narrower shield arc in Assault** (90° vs 110°). Default: yes.
3. **Repair budget per support** (150 HP per life). Default: yes.
4. **Gate time cap.** The suite already runs at GUT 253 s against a ~300 s wall-clock cap; this epic adds ~57 s of tests.
   Default: the cap stays and t1 frees ≥ 70 s first; if it cannot, it stops before any other task and the owner chooses
   between raising the cap and trimming this epic's real-physics rows. **If the owner can raise the cap now, say so on
   approval** and t1's target drops accordingly.

## 9. Response to feedback (plan review round 1, `4-review.md`)

| # | Finding | What changed |
|---|---|---|
| 1 | Player missiles are eaten by enemy rockets (missile HitBox 32 / mask 513 sees the rocket's 512 hurtbox; mask 64 was one-way) | Decided: **mutual destruction**. The rocket's shoot-down `HurtBox` masks 96 (= 32 \| 64, the Ph4 ordnance value) and the rocket resolves each hit in its own `area_entered` handler (the `ArmorPlate._resolve` shape), ignoring any `EnemyRocket` HitBox; no blast. t5 row: a real homing missile and the rocket both expire, no `ContactBlast`. §2.6, §2.7. |
| 2 | "Impact + blast" is impossible against the 0.5 s i-frames and inverted the Warhead | The impact HitBox is on **layer 32 only**; its mask 128 still detonates on the player, but the player and allies take only the `ContactBlast`. A direct hit and a near miss both cost `blast_damage`; the damage table is re-tuned (blast = the player number; Warhead 30 either way). t5 asserts this on the real `player_ship.tscn` and `player_fighter.tscn`, including one shield charge per rocket. §2.6, §2.7, §2.8. |
| 3 | A launcher can overrun its own unarmed rocket (and the rail fallback does so every time) | Rockets **inherit the launcher's along-heading speed** (`launch_velocity()`, observed position delta on a rail) and **arm by clearance from the launcher's current position** (`rocket_clear_radius()` + `body_radius` + `arm_clearance`). Config inequalities: every `cruise_speed ≥ 1.1 × 210`, `launch_speed > 240 × boost_seconds` (Warhead cruise raised 200 → 240). Rows: a launcher moving at 210 px/s with a control that fails without inheritance (t5); a real corvette on a 330 px/s `straight()` rail firing its fallback for 3 s, HP unchanged (t7). The HitBox also drops mask bit 1, which would have detonated rockets on enemy bodies (including an armoured Ram's, before its plates). §2.6, §2.9. |
| 4 | The escort tow can drag a ward through a telegraphed attack; the brainless check was missing | New `EnemyBrain.accepts_tow()` (default true) with overrides in all eight brains for every committed or telegraphed phase; `BaseEnemy.accept_tow` requires `is_ai_driven()` (brain + mover, not suspended), not boosting, and `accepts_tow()`. While refused the escort only interposes. Rows: a real Sniper in LOCK and a real Ram in WIND_UP keep position within 1 px while offered a tow every tick, with a control that moves (t3), and the same through a real escort (t13). §2.4, §2.10, §2.14. |
| 5 | The gate-time budget gave the epic ~15 s, with no per-task shares and no import/boot measurement | Measured at `7916662`: import 4.7 s, boot 1.0 s, GUT 253.3 s, per-file table in §2.2. New §4.3: GUT ceiling 240 s after every task, per-task allotments from measured Ph4 analogues (56.5 s total), so **t1 must free ≥ 70 s** (to ≤ 183 s), with the files and expected yield named (three 1× real-physics files to 8×, fire density 4× → 8×, the fighter-squad replay computed once). `scripts/gate-time.sh` times all three gate steps. **t1 is now a dependency of every task** (t3 and t4 included). Owner question 4 is asked up front. |
| 6 | One rocket cannot break a 50 HP plate | t5 row: the plate's HP drops by exactly `impact_damage` (50 → 34) with no `plate_broken`; a second rocket on a plate at ≤ `impact_damage` HP breaks it. Owner question 1 says "about four rockets". |
| 7 | `get_screen_center_position()` can be stale in tests | `enemy_view_rect()` = centre `global_position + offset` (the `ArenaCamera` / `level_1_director.gd:140` convention), size `viewport / zoom`; t4 reads it in the same frame after changing `offset`, and at zoom 0.8. §2.5. |
| 8 | Two corvette rows could not pass | The chase is bounded (the stub closes for 2 s then stops; closest approach ≥ 0.6 × `min_range`, back outside within 3 s), and arcing is measured as cumulative \|Δbearing\| ≥ 60° over 10 s. §2.10. |
| 9 | A projected shield on an armoured Ram drains on hits the hull deflects | `EnemyShield.absorbs_hit` returns false while the host answers `is_armored() == true` (hit-blind; never `deflects_hit`, which damages a plate). Rows in t2 (fake armoured host, counting fake proving `deflects_hit` is never asked) and t12 (real warded Ram). §2.3, §2.13. |
| 10 | The rocket trail would come out of the nose | Rockets are **nose-up** (`rotation = heading.angle() + PI / 2`, the player missiles' convention), so `RocketTrail`'s local +Y is the tail; t9 asserts the trail sits behind the nose. §2.6, §2.15. |
| 11 | `score_value` threat weight with an incomplete table; gunship always wins but can never be towed; bonus drone excluded by accident | Full table in §2.12. Candidates must be `is_ai_driven()` (excludes the gunship, station and bonus drone), `counts_toward_wave_clear` (the bonus drone, explicitly) and `score_value ≥ ward_min_score` 20 (excludes swarm drones). Every ward is therefore escort-capable. Row: a real gunship and bonus drone beside a fighter → the fighter. |
| 12 | The Warhead's fairness rule ignored its own motion | The Warhead **stops dead** on trigger, so the mine rule is exact; t6 asserts < 0.5 px of motion from trigger to detonation. §2.8. |
| 13 | The support's shield bubble was deferred with a reason that did not cover it | Shipped: the projected arc widens to a 360° bubble during ESCORT and returns afterwards (t13 row). Only module shields and fortress nodes stay deferred. §2.14, §6, §7. |
| 14 | Missing `planSections` | t15 gains 2.10 and 2.14; t16 and t17 gain 2.12 (and every test-adding task gains 4.3). |
| 15 | Two owners of `arm_distance`; Warhead pair vs `salvo_count` | The rocket alone owns arming (`arm_clearance` export + the launcher's `rocket_clear_radius()`); `fire()` sets no rocket field. New `warhead_salvo_count` 2 (and `warhead_offset` 90) with `salvo_size(kind)`; Warhead pool 4. §2.6, §2.9, §2.10. |
