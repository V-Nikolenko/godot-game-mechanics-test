# Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship

Epic `cmufs7elw001pnm2xr3b6fteb`, plan task `cmufs7em4001xnm2xwo26fzlf`, 2026-10-14, Revision 1. Built on `1-context.md`
(code inventory, requirement ids `R5.x`, risks `C1`–`C18`) and `2-research.md` (scope check `S1`–`S20`, findings `F1`–`F13`,
starting values) in this directory. Facts were read at `eeaec80` on `agent/auto-dev`.

## Summary for the owner

- **For the player:** a **Missile Corvette** keeps its distance on wide arcs and fires telegraphed rocket salvos aimed where
  you are going. Four rocket kinds: fast straight, mildly guided for a few seconds, cluster (splits into four near you), and
  slow warheads that blow up when you come close. Every rocket can be outrun, out-turned (a late break or a boost), shot
  down, or lured into other enemies and asteroids, which it damages. A **Support Ship** has no gun: it shadows the most
  dangerous nearby enemy, repairs it in small pulses, projects a cyan shield arc on that enemy's side facing you, and drags a
  badly hurt ally away while putting itself in your line of fire. It is fragile and dodgy; kill it first.
- **Where:** the Open Space hub patrol (the support guards the hub's Ram Corvette) and level 1's two timed sections.
  Neither goes into a section that waits for enemies to be cleared.
- **Built:** a reusable enemy shield, an enemy repair path, a "what the camera shows" query, the rocket family, both enemies
  with art, tests in both modes.
- **Left out:** rocket audio, flare reactions (the player has no flares), the Hijack Pulse (phase 9), shields on enemy
  modules and bubble shields in real content (phases 10–11; proven by test fixtures here), encounter design (phase 13).
- **Risks:** the test gate is ~30 s under its 5-minute cap, so the first task buys headroom; rockets must feel fair
  (gated by "a straight runner escapes, a late boost escapes, a parked ship is hit"); a shield facing the player is hard to
  flank in the vertical Assault lane (narrower there, turns slowly).
- **Questions [default taken]:** (1) May enemy rockets break a Ram Corvette's armour plates when baited into it? [Yes.]
  (2) Narrower shield arc in Assault, 90° vs 110°? [Yes.] (3) Cap one Support Ship's repair at 150 HP per life? [Yes.]
  (4) Can the gate's 5-minute cap be raised? [Assumed not; the first task frees ≥ 30 s or stops and asks.]

## For every task

**Shared rules (all from earlier phases, all still binding).** A brain decides, `EnemyMover` is the single writer of an
enemy's `velocity` / `rotation` and its one `move_and_slide()` (gate `test_enemy_mover_single_writer.gd`, empty allowlist).
Clocks are accumulated `delta`; randomness only from `brain.rng`; the player only via `TargetInfo`. A curve is a brain-side
`Steering.turn_toward` request and `turn_rate × speed ≤ acceleration` is asserted for any config that curves. Configs are
flat `ShipConfig` subclasses with `@export_group`s; `.tres` values win; contact damage comes from `config.collision_damage`
via `ContactProfile`. Signals are declared with the arguments they emit. Never hand-type a `uid://`. Art only through
PixelLab under the `pixel-art-generation` skill (strict top-down), ≤ 90 % opaque. Projectiles have exactly one owner (a
pool, or `expired → queue_free`); pools are direct root children with `persist_after_owner_death = true` for anything that
outlives its ship. Ordnance and rockets are never in group `enemies` and never scored. Rail fallbacks (`on_suspended()`)
are mandatory for a shooter. A telegraphed attack is never cut off by the Assault budget (the budget defers, bounded).

**New names this epic introduces (use exactly these):**
- `EnemyShield` (`global/components/enemy_shield.gd`, a `Node2D`) and the `HurtBox` absorb hook:
  `HurtBox.set_absorber(obj) -> bool`, `HurtBox.clear_absorber(obj)`, `signal hit_absorbed(hit_box: HitBox)`; an absorber
  answers duck-typed `absorbs_hit(hit_box: HitBox) -> bool`.
- `BaseEnemy.repair(amount: int) -> int` (HP actually restored, never flashes) and `BaseEnemy.accept_tow(v: Vector2) -> bool`
  (forwards to the enemy's own mover as `add_nudge(v)`; false when suspended, boosting, or brainless).
- `EnemyWorld.has_view_rect(tree)` / `EnemyWorld.view_rect(tree) -> Rect2`, backed by `ArenaCamera.enemy_view_rect()`.
- `EnemyRocket` (`assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd`, `extends Area2D`,
  `enum Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }`), scenes `dumb_rocket.tscn`, `pursuit_rocket.tscn`,
  `cluster_rocket.tscn`, `delayed_warhead.tscn`, `submunition.tscn`, and `EnemyRocketScenes.scene_for(kind)` /
  `pool_size_for(kind, cfg)`. API: `signal expired`, `reset()`, `launch(dir: Vector2, aim_point: Vector2, launcher: Node)`.
  **A rocket's tuning lives in its own scene's exports**, not in the launcher's config.
- `MissileCorvette` / `MissileCorvetteBrain` / `MissileCorvetteConfig` in `assault/scenes/enemies/missile_corvette/`;
  `MissileCorvette.fire(kind, aim_point) -> EnemyRocket`. `WaveBuilder.missile_corvette()`, const `MISSILE_CORVETTE`.
- `SupportShip` / `SupportShipBrain` / `SupportShipConfig` in `assault/scenes/enemies/support_ship/`.
  `WaveBuilder.support_ship()`, const `SUPPORT_SHIP`. Contact profile `NONE`.

**Phase enums (append-only; values fixed once a task ships them):**
- `MissileCorvetteBrain.Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }`.
- `SupportShipBrain.Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }`.

**Collision (no layer is renamed):** a rocket's impact `HitBox` is on layers `32 | 256` (`CollisionLayers.PLAYER_ROCKETS |
ENEMY_HITBOX`), mask `1 | 128 | 512`, `damage_type = ROCKET`, closed until armed. Its own `HurtBox` is layer 512, mask
**64 only**. Its blast is `ContactBlast.spawn` (player-only). So: a rocket's **impact** hurts the player, enemies, ordnance,
Ram plates and asteroids; its **blast** hurts only the player; rockets never hurt each other.

**Decisions that close earlier questions:** `DamageReaction` is **not** adopted by `BaseEnemy` (closes Ph1 P-15); no
owner-distance lifetime rule is built; `BulletPool` container injection stays deferred; enemy friendly fire = rocket
impacts only (blasts and beams stay undecided, Ph8). Direct emitters (beam, nova, dash, shield overload, engine boost)
bypass enemy shields exactly as they bypass armour plates.

**Tests:** dual-mode specs parameterise on a bare label (`use_parameters(["open_space", "assault"])`), build the harness
(`tests/helpers/enemy_ai_harness.gd`) in the body and drive brains with hand-ticked `_tick()`. Any test that awaits real
physics runs on the 8× clock (`Engine.time_scale`, `physics_ticks_per_second`, `max_physics_steps_per_frame` scaled
together, restored in `after_each`). **Gate wall-clock budget:** the harness kills verification at ~300 s. Every task
reports `GUT time` before and after in its final message; this epic's new tests together may add at most the headroom t1
freed minus 15 s. Read `tests/README.md` before writing a test. Run `scripts/check-test-leaks.sh` after touching anything
that awaits. New enemy directories join the rosters of `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`,
`test_enemy_hurtbox_geometry.gd` and `test_base_enemy.gd`'s `_AUTHORED_CONTACT_MODES`.

**Phase log:** a deviation a later phase will depend on (renamed interface, changed number, dropped piece) is appended
as a line under this phase's section of `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` before the task finishes.

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
| S5 | "On the collision layer phase 1 named for rockets" | Bit 32, named `player_rockets`, constant `CollisionLayers.PLAYER_ROCKETS`. Enemy rockets' impact HitBox sits on it (and on 256 to reach the player). **The layer is not renamed** (name-only churn over ~20 references, no player value); the constant's doc comment says enemy rockets use it too. |
| S6 | Rockets "made to hit other enemies" | Decided for rockets only: the **impact** hits enemies; the **blast** stays player-only. Beams and other blasts: still undecided (Ph8). |
| S7 | "warning audio" | Out (no enemy SFX pipeline; Ph17). The telegraph is visual. |
| S8 | "flare/decoy reaction" | Out: the player has no countermeasure. A later countermeasure retargets rockets through `EnemyRocket`'s aim-point function. |
| S9 | "bait it into a carrier escort" | Covered generically by impact friendly fire (Carrier is Ph10). |
| S10 | Hijack Pulse | Out (Ph9). Nothing here makes player missiles retargetable. |
| S11 | Shield kinds: directional, local-module, regenerating, projected bubble | One `EnemyShield` whose arc (360° = bubble), capacity, regeneration and lifetime are fields. Shipped consumer: the Support Ship's projected directional arc. Local-module and bubble are proven by fixtures; their shipped consumers are Ph10/Ph11. |
| S12 | Repair | A heal path that never flashes: `BaseEnemy.repair()` (§2.4). |
| S13 | Escort "pulls the target away" | A tow **request** on the ward's own mover through `BaseEnemy.accept_tow()`; never a write to the ward's motion (§2.4, §2.14). |
| S14 | Assault "cannot hide above the camera" | New `EnemyWorld.view_rect()` (§2.5); the corridor rect is the whole 1480 × 1480 pan range and does not stop it. |
| S15 | §37 Support + Ram "made possible" | A Ram is an eligible ward; repair heals its hull only; the hub Support shares the hub Ram's anchor (§2.13, §2.17). |
| S16–S17 | Assault placement and density | DURATION sections only; both kinds count as specialists in the existing count gate (§2.18). |
| S18 | Sprites and the unfolding projector | Corvette ≈ 96 × 96, Support ≈ 88 × 88, a separate projector sprite that unfolds (§2.15). |
| S19 | Both harnesses, gate time | Hand-ticked specs; t1 frees gate headroom first (§2.2). |
| S20 | Station reinforcements, `level_2_waves.gd` | Untouched; the corvette still gets a rail fallback. |

### 2.1 Names and places

| Thing | Path | Kind |
|---|---|---|
| Enemy shield component | `global/components/enemy_shield.gd` (`class_name EnemyShield extends Node2D`) | new |
| Absorb hook | `global/components/hurtbox_component.gd` (`HurtBox.set_absorber`, `clear_absorber`, `hit_absorbed`) | changed |
| Repair and tow | `assault/scenes/enemies/base_enemy.gd` (`repair`, `accept_tow`, decrease-only flash) | changed |
| View rect | `global/enemy_ai/enemy_world.gd` (`has_view_rect`, `view_rect`), `assault/scenes/systems/arena_camera.gd` (`enemy_view_rect`) | changed |
| Rocket family | `assault/scenes/projectiles/enemy_rockets/` — `enemy_rocket.gd` (`EnemyRocket`), `enemy_rocket_scenes.gd` (`EnemyRocketScenes`), five `.tscn`, art | new |
| Missile Corvette | `assault/scenes/enemies/missile_corvette/` — `missile_corvette.gd/.tscn`, `missile_corvette_brain.gd`, `missile_corvette_config.gd/.tres`, `ENEMY.md` | new |
| Support Ship | `assault/scenes/enemies/support_ship/` — `support_ship.gd/.tscn`, `support_ship_brain.gd`, `support_ship_config.gd/.tres`, `ENEMY.md` | new |
| Art | `assault/assets/sprites/enemies/missile_corvette.png`, `support_ship.png`, `support_projector.png`; `assault/assets/sprites/projectiles/enemy_rocket.png`, `enemy_cluster_rocket.png`, `enemy_warhead.png`, `enemy_submunition.png` | new |
| WaveBuilder | `assault/scenes/systems/wave_builder.gd` — `missile_corvette()`, `support_ship()`, consts `MISSILE_CORVETTE`, `SUPPORT_SHIP` | changed |
| Hub | `open_space/scenes/levels/sector_hub.gd` `_spawn_patrol()` | changed |
| Level 1 | `assault/scenes/levels/edelia/1/level_1_director.gd` | changed |
| Tests | `tests/unit/test_enemy_shield.gd`, `tests/integration/test_enemy_shield_hits.gd`, `tests/integration/test_enemy_rockets.gd`, `tests/integration/test_missile_corvette.gd`, `tests/integration/test_support_ship.gd`; rows in existing gates | new / changed |

### 2.2 Gate time headroom (t1)

**Why first.** Phase 4 closed at GUT time 256.8 s; the harness kills verification at ~300 s wall clock (import + boot +
GUT, measured in Ph4 t10: attempts ended exactly 5:00 after start). This epic adds two enemies with dual-mode specs, the
rocket family, shields and level-1 rows. Without headroom the later tasks fail the gate for time, not for correctness.

**What t1 does.**
1. Measure per-file wall time of the GUT run (GUT's `-gjunit_xml_file=<path>` gives per-test times; or time each
   `-gselect` run). Record the top 15 files and their seconds in `tests/README.md` under a new "Gate time" heading, with
   the date, the total, and the rule "a test that awaits real physics scales the clock; a hand-ticked loop that replays the
   same scenario in several tests computes it once".
2. Cut at least **30 s** of GUT time **without removing or weakening any assertion**. Allowed means, in order:
   (a) put any remaining file that awaits real physics frames at 1× on the 8× clock (the Ph4 pattern:
   `Engine.time_scale`, `physics_ticks_per_second` and `max_physics_steps_per_frame` scaled together, step kept at
   1/60 game-second, restored in `after_each`), checking every assertion's outcome is unchanged;
   (b) in hand-ticked files (the heaviest known is `tests/integration/test_fighter_squad.gd`, ~65 s), share a simulation
   that several tests replay identically: compute it once in `before_all` and assert on the shared log, leaving each
   test's assertions intact; (c) drop per-tick bookkeeping that no assertion reads (e.g. a frame-log field nobody asserts).
   Never lower a tick count, a duration, a sample count or a start-grid size that an assertion depends on.
3. Add `scripts/gate-time.sh` that runs gate step 3 with the JUnit option and prints the 15 slowest files, so later tasks
   can measure their own cost.
4. If 30 s cannot be found without weakening a test, stop with `Result: ESCALATE`, listing what was measured; the owner
   decides between raising the harness cap and trimming coverage.

**Acceptance:** total GUT time ≥ 30 s lower than the measured "before" on the same machine; the test count is unchanged;
every test still passes; `scripts/check-test-leaks.sh` clean.

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

**`EnemyShield` (`global/components/enemy_shield.gd`, `class_name EnemyShield extends Node2D`).** A child of the entity it
protects; attaches to a `HurtBox` with `attach(hurt_box: HurtBox) -> bool` (calls `set_absorber(self)`), detaches on
`_exit_tree()`. Exports (all `@export`, defaults = Open Space projected values):

| Field | Default | Meaning |
|---|---|---|
| `arc_deg` | 110.0 | Width of the protected arc; ≥ 360 = bubble (every direction) |
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

**The absorb rule (one decision per hit; no state outside the call):** `absorbs_hit(hb)` returns true when the shield is
up (not rebooting, not lapsed, points > 0) **and** the bearing from the host's `global_position` to `hb.global_position`
lies within `arc_deg / 2` of `facing()` (always true when `arc_deg >= 360`). On true: points −= `hb.damage` (floor 0);
**the breaking hit is absorbed whole** (no bleed-through); at 0 emit `broken()` and start `reboot_seconds`; after reboot,
refill from 0 over `regen_seconds` and emit `restored()` when full. A hit from outside the arc returns false and lands on
the hull normally. The regen delay restarts on every absorbed hit (switching targets resets it; focus fire wins, F10).

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
  and points drop by its damage; with a 110° arc a hit 54° off the facing is absorbed and one 56° off lands; bubble (360°) absorbs from behind;
  the breaking hit is absorbed whole and `broken` fires once; nothing absorbed during `reboot_seconds`; regen starts only
  `regen_delay` after the last hit and reaches full after `regen_seconds` (`restored` once); the facing turns at no more
  than `turn_rate × delta` per tick; `sustain_mode` lapses `heartbeat` after the last `sustain()`, then fades and frees
  (`lapsed` once); detaching on free clears the hurtbox slot.
- `tests/integration/test_enemy_shield_hits.gd` (real projectiles, 8× clock where awaited): on `fixture_enemy.tscn`
  (`tests/helpers/`) with a 110° shield facing a shooter, a real player `Bullet` from the front is consumed and hull HP is
  unchanged; from behind it damages the hull; a real homing/warhead player rocket from the front detonates and does no hull
  damage; a beam (`received_damage.emit`) bypasses the shield; **local-module fixture**: a shield attached to a
  part's own hurtbox (an `ArmorPlate`-like child hurtbox) protects that part only; **bubble fixture**: 360° absorbs from
  four directions.
- Boundary: capacity 40 against two 25-damage hits → first absorbed (15 left), second absorbed whole and breaks, third
  lands on the hull.

### 2.4 BaseEnemy support hooks: repair and tow (t3)

Changes to `assault/scenes/enemies/base_enemy.gd` only (plus tests):

- **Decrease-only feedback.** `_on_health_changed(current)` plays the hit flash and `_hit_effect.burst()` **only when
  `current` is lower than the previous value.** Track `_last_health` (−1 = unset): on each call, if unset take
  `health.max_health` as the previous value (enemies start full; subclasses write health from config without a signal),
  compare, then store `current`. Death at 0 is unchanged. Today health never goes up, so no shipped behaviour changes; the station's
  `_on_health_changed` override (`space_station.gd:197`) is untouched.
- **`repair(amount: int) -> int`:** returns 0 if `amount <= 0`, health is 0, or `is_queued_for_deletion()`; else
  `before = health.current_health; health.increase(amount)` and returns `health.current_health − before` (0 at full HP).
  Never flashes (rule above). Subclasses that must not be repaired override `can_be_repaired() -> bool` (default
  `true`); `SpaceStation` overrides it to false in this task.
- **`accept_tow(v: Vector2) -> bool`:** returns false when `_ai_suspended`, `_mover == null`, or `_mover.is_boosting()`;
  else `_mover.add_nudge(v)` and true. It is a request summed onto the brain's own primary request for one mover step and
  limited to the mover's `max_speed`; nothing else writes motion (the single-writer gate stays green).
- **`ai_mover_max_speed() -> float`:** the mover's `max_speed`, or 0 without a mover (the escort sizes its tow from it).

**Tests (t3), in `tests/integration/test_base_enemy.gd`:** a damaged fixture enemy repaired by 10 regains 10 and the
`HitFlashAnimationPlayer` is not playing and the hit burst did not fire; at full HP `repair` returns 0; repair of a dead or
queued-for-deletion enemy returns 0; a hit after a repair still flashes; `accept_tow` on a suspended enemy returns false
and on a live one moves it by the nudge within one step (velocity component along the nudge > 0); `accept_tow` while
the mover boosts returns false; the station answers `can_be_repaired() == false`.

### 2.5 Assault view rect (t4)

The Assault corridor rect (`AssaultCorridorConstraint.inner_rect()`, 1480 × 1480) is the camera's whole pan range; the
camera shows 1280 × 720 of it, so a ship can sit ~380 px above the visible screen with no pressure. "The support cannot
hide above the camera" needs the rect the camera actually shows now.

- `assault/scenes/systems/arena_camera.gd`: `func enemy_view_rect() -> Rect2` = centre `get_screen_center_position()`,
  size `get_viewport().get_visible_rect().size / zoom`. (Includes the offset pan; correct under the pause-menu zoom.)
- `global/enemy_ai/enemy_world.gd`: `static func has_view_rect(tree) -> bool` and `static func view_rect(tree) -> Rect2`,
  duck-typed on `enemy_view_rect`, following the existing `cull_rect` pair exactly (empty `Rect2()` with no provider).
  Nothing under `global/` names `ArenaCamera`.

**Tests (t4), `tests/unit/test_enemy_world.gd` (or the existing provider test file):** no provider → `has_view_rect`
false and `Rect2()`; a fake provider in group `assault_arena` answering a rect → that rect; a real `ArenaCamera` with
`offset = (0, -300)` → the rect's top is 300 px higher than with offset zero and its size is 1280 × 720 at zoom 1.

### 2.6 Enemy rocket family: common contract, layers and friendly fire (t5, t6)

**Class shape.** `EnemyRocket` is a sibling of Ph4's `EnemyOrdnance`, not new kinds on it (the ordnance script is
bomb-shaped: no rotation, proximity-only trigger, `pool_size_for` keyed on `BomberConfig`; Ph7's Mine Layer extends it).
Path `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd`, `class_name EnemyRocket extends Area2D`,
`enum Kind { DUMB, PURSUIT, CLUSTER, WARHEAD, SUBMUNITION }`.

**Contract (mirrors `EnemyOrdnance`):** `signal expired`; `reset()` restores every export to the scene's own value
(the `_RESET_PROPS` capture at `_ready()`, as `EnemyOrdnance` does) and clears state; `launch(dir: Vector2, aim_point:
Vector2, launcher: Node)`; one `_mark_done()` latch so `expired` fires once; accessors `heading() -> Vector2`,
`speed() -> float`, `is_armed() -> bool`, `is_guiding() -> bool`, `aim_point() -> Vector2`. Never in group `enemies`,
never registered with `ScoreTracker`. The rocket writes its own `global_position` and `rotation` (it is not an
`EnemyMover` actor; the single-writer gate sweeps brains, `global/enemy_ai/` and mover-driven enemy roots, not projectiles).

**Scene shape (every kind):**

```
<Kind>Rocket (Area2D, enemy_rocket.gd; collision_layer 0, mask 0)
├── HitBox (HitBox) layer 32|256 = 288, mask 1|128|512 = 641, damage_type ROCKET, damage = impact_damage
│   └── CollisionShape2D (circle, r = body_radius)
├── HurtBox (HurtBox) layer 512, mask 64           # player bullets only
│   └── CollisionShape2D (circle, r = body_radius + 2)
├── Health (max 1)
├── ProjectileLifetime                              # max_time, max_distance from origin, use_world_rect in Assault
├── RocketTrail                                     # global/components/rocket_trail.gd, emits along local +Y
└── Sprite2D                                        # nose-down art; rotation = heading.angle() − PI/2
```

Warheads add `ProximityArea` (Area2D, layer 0, mask 128, circle `trigger_radius`), polled with
`get_overlapping_areas()` (the Ph4 B1b rule: a player already inside at arm time still triggers it).

**Arming (C1).** The impact HitBox starts with `monitoring = false` and `monitorable = false` (set deferred) and opens
once the rocket is `arm_distance` from its launch point (`arm_distance` = launcher hull radius + 12; the launcher passes
it, default 60). Until armed, it can neither hurt nor be triggered — so it never hits its own launcher. The shoot-down
HurtBox is live from launch.

**Contact and friendly fire (S5, S6, C2, C3).** When armed, the HitBox's `area_entered` / `body_entered` detonates the
rocket, except for areas belonging to another `EnemyRocket` (a sibling's HurtBox sits on 512) — those are ignored. What
each target does with the impact is its own rule:
- player / allies (hurtbox mask includes 256): take `impact_damage`;
- any `BaseEnemy` (runtime hurtbox mask 1121 includes 32): takes `impact_damage` through its normal flow (a shielded ward's
  arc can absorb it; an armoured Ram hull refuses it and the rocket still detonates);
- a Ram's `ArmorPlate` (mask 96, breaks on ROCKET): **breaks** — accepted counterplay (owner question 1, default yes);
- Ph4 enemy ordnance (mask 96): is defused;
- asteroids (hurtbox mask 32) take the hit; environment bodies (layer 1) just detonate it.

Then `ContactBlast.spawn(container, global_position, blast_radius, blast_damage, blast_frames)` — layer 256, mask 0, hits
the player only. A **direct hit on the player deals `impact_damage + blast_damage`**; a near miss inside the radius deals
`blast_damage`; enemies only ever take `impact_damage`.

**Shoot-down.** Any player bullet on the HurtBox → Health 0 → **defuse**: a small pop, no blast, `expired`. Player
rockets (layer 32) pass through enemy rockets (their HurtBox masks 64 only). Rockets never shoot each other down.

**Lifetime.** `ProjectileLifetime` with per-kind `max_time` / `max_distance` (from origin) and, in Assault,
`use_world_rect` (the corridor's projectile rect) — this is "limited by the corridor". No owner-distance rule (S2).

**Ownership.** Corvette pools (one per kind, direct root children, `persist_after_owner_death = true`) own pooled
rockets; submunitions are **unpooled** and own themselves (`expired → queue_free`), spawned into the parent rocket's own
parent (the container). `EnemyRocketScenes.pool_size_for(kind, cfg)` = `cfg.salvo_count × ceil(rocket.max_time /
cfg.salvo_period_min)` for the kinds a corvette fires, duck-typed on `salvo_count` / `salvo_period_min`.

**Tuning lives in the rocket scenes' exports** (one source of truth per kind, whoever fires it — the Ph10 Carrier and
Ph11 fortress will fire the same rockets). The launcher passes only direction, aim point and itself. This differs from Ph4,
where the Bomber's config carries its ordnance numbers; logged in DECISIONS with that reason. Ph16 difficulty tiers scale
a rocket by setting exports before `launch()`.

**Common exports (`EnemyRocket`):** `kind`, `launch_speed`, `cruise_speed`, `boost_seconds` (straight, no steering, at
`launch_speed`: the visible launch), `accel` (px/s² from `launch_speed` to `cruise_speed` after the boost),
`turn_rate` (rad/s), `guidance_seconds`, `lead_max` (s), `impact_damage`, `blast_radius`, `blast_damage`,
`blast_frames` (3), `arm_distance`, `body_radius`, `max_time`, `max_distance`.

**Shipped values (judgement, F1/F2/F6/F8/F9; `2-research.md` §3.1):**

| Kind | launch → cruise px/s | boost s | accel | turn rad/s | guidance s | impact / blast dmg | blast r | life s / px |
|---|---|---|---|---|---|---|---|---|
| DUMB | 140 → 520 | 0.25 | 900 | 0 | 0 | 16 / 10 | 36 | 4.0 / 1800 |
| PURSUIT | 120 → 440 | 0.35 | 600 | 1.6 | 3.0 (`lead_max` 0.8) | 18 / 10 | 40 | 6.0 / 2400 |
| CLUSTER | 120 → 380 | 0.35 | 600 | 0.7 | until split | 16 / 10 | 36 | 4.0 / 1200 |
| SUBMUNITION | 520 → 520 | 0 | 0 | 0 | 0 | 8 / 5 | 22 | 1.2 / 600 |
| WARHEAD | 100 → 200 | 0.35 | 300 | 0.6 | 4.0 | 12 / 30 | 110 | 7.0 / 1300 |

**Lifetime rows (t5 for DUMB / PURSUIT, t6 for the rest)** in `tests/integration/test_enemy_bullet_lifetime.gd`, one per
kind, speeds read from the rocket scene's exports, in the Ph4 pursuit-bomb form: the straight-line time to cover
`max_distance` — `boost_seconds` at `launch_speed`, then accelerating at `accel` to `cruise_speed`, then the rest at
`cruise_speed` — must fit `max_time` (so the distance cap, not the clock, ends a straight rocket). Computed today: DUMB
3.80 ≤ 4.0 s, PURSUIT 5.90 ≤ 6.0, CLUSTER 3.54 ≤ 4.0, SUBMUNITION 1.15 ≤ 1.2, WARHEAD 6.76 ≤ 7.0. (The 2-research starting
values DUMB 3.5 s, CLUSTER 1800 px, SUBMUNITION 1.0 s and WARHEAD 1600 px failed this row and were adjusted.) Rocket speeds never
enter `_every_shipped_enemy_bullet_speed()` (round family only).

### 2.7 Dumb and Pursuit rockets (t5)

**Guidance law (lead pursuit with a turn cap and a finite window — `2-research.md` §2.1 option C):** each physics tick,
while `is_guiding()` (after `boost_seconds`, before `boost_seconds + guidance_seconds`):
`aim = _aim_point()`; `heading = Steering.turn_toward(heading, aim − global_position, turn_rate, delta)`. `_aim_point()` =
`TargetInfo.player(get_tree()).intercept(global_position, speed())`; if not `ok` or its `time > lead_max`, use
`predicted_position(lead_max)`. No player → keep heading. After the window the heading freezes and the rocket coasts at
`cruise_speed` — still armed, still a hazard to everything it crosses (F2 "flameout"). Speed: `launch_speed` during the
boost, then `move_toward(cruise_speed, accel × delta)`. All per physics tick with `delta` (F6: no frame-rate dependence).

- **DUMB**: no guidance (`turn_rate` 0). The launcher aims it at an intercept point at launch; it flies straight.
- **PURSUIT**: the law above. Turn radius `cruise_speed / turn_rate` = 275 px, tighter than the Open Space ship's
  sustained turn (≈ 464 px at 420 px/s), so the counter is the **late break / boost** and the **finite window**, not a
  sustained turn — that is the design (F1, F6).

**t5 builds:** `enemy_rocket.gd` with the common contract (§2.6) and both guidance kinds, `dumb_rocket.tscn`,
`pursuit_rocket.tscn`, `enemy_rocket_scenes.gd`, the placeholder look (`_draw()` body + `RocketTrail`; t9 swaps in the
sprite), the two lifetime rows, and a test fixture launcher (`tests/helpers/rocket_launcher_fixture.gd`: a `BaseEnemy`-like
node with a HurtBox on 512 / mask 1121 that calls `launch()` from a pool with `persist_after_owner_death`).

**Tests (t5), `tests/integration/test_enemy_rockets.gd`, parameterised `["open_space", "assault"]` where marked:**
- (both) a PURSUIT rocket's heading converges on `intercept()`'s point for a constant-velocity player stub: the angle
  between heading and `aim − pos` shrinks monotonically after the boost until < 3°; per tick the heading never turns more
  than `turn_rate × delta` (+1e-4); after `boost_seconds + guidance_seconds` the heading is constant to 1e-6.
- (both) dodgeability, hand-ticked against a scripted stub: (a) a stub running straight away at 420 px/s from 300 px
  ahead at launch is never touched before the rocket expires; (b) a stub flying at 220 px/s toward the rocket that boosts
  perpendicular at 700 px/s when the rocket is 150 px away is missed (closest approach > `body_radius` + the player hurtbox
  radius); (c) a stationary stub 600 px away is hit; (d) config inequality `cruise_speed / turn_rate >= 250` for PURSUIT.
- (both) a DUMB rocket keeps its launch heading to 1e-6 for its life; its speed reaches `cruise_speed` within
  `boost_seconds + (cruise − launch) / accel + 2 ticks`.
- (open_space, real physics, 8×) shoot-down: a real player `Bullet` on the rocket → `expired`, no `ContactBlast` child
  appears in the container, the bullet is consumed; a real player homing rocket passes through it (rocket alive after).
- (open_space, real physics, 8×) friendly fire: an armed rocket crossing a fixture enemy damages it by `impact_damage`
  and detonates; the blast that follows does not damage the enemy (HP drops by exactly `impact_damage`); the launcher is
  not hit when the rocket leaves it (launcher HP unchanged after 0.5 s, `is_armed()` false for the first
  `arm_distance / launch_speed` s); two rockets launched 2 px apart on the same heading both survive 1 s (no sibling hit);
  a real `ram_corvette.tscn` plate on the path breaks (`plate_broken` once) and the rocket is consumed; a big asteroid
  on the path takes `impact_damage`.
- (open_space) the player takes `impact_damage + blast_damage` on a direct hit and `blast_damage` from a detonation 30 px
  away; a rocket in Assault expires on leaving the projectile world rect.
- Pool: `persist_after_owner_death` — freeing the fixture launcher leaves its in-flight rockets flying; each frees itself
  on expiry (`queue_free`, no leak — `scripts/check-test-leaks.sh`).

### 2.8 Cluster rocket and Delayed Warhead (t6)

**CLUSTER** (`cluster_rocket.tscn`, `Kind.CLUSTER`): guided by the §2.7 law with `turn_rate` 0.7 until it splits. It
**splits by distance** (F8): when within `split_distance` (260 px) of the player, or after `split_time` (2.0 s from
launch) if never that close. On split it emits `expired` **without a blast** (it is gone, not exploded) and spawns
`cluster_count` (4; export range 3–5) `SUBMUNITION`s **unpooled** into its own parent (the container): positions = the
split point; headings fanned evenly across `cluster_fan_deg` (36° total) centred on the direction to the predicted point
`TargetInfo.predicted_position(distance / submunition cruise_speed)`; each connected `expired → queue_free`. Children are
unguided (F8 "aim, then unguided burn"), armed after `arm_distance` 12 px from the split point, and never hit each other or
their parent (sibling rule, §2.6). **Shooting the parent before the split kills all of it** (no children). A split after
the launcher died works (children go to the container, not to a pool).

**WARHEAD** (`delayed_warhead.tscn`, `Kind.WARHEAD`): slow, mild steering (`turn_rate` 0.6, `guidance_seconds` 4.0, aim =
§2.7 law). Arms its proximity trigger `prox_arm_seconds` (0.6 s) after launch (independent of `arm_distance`, which still
gates the impact HitBox). Once armed it polls `ProximityArea.get_overlapping_areas()` for the player hurtbox; on the first
hit it starts `warning_time` (0.4 s): blinks (body flashes at 12 Hz, the ring of `blast_radius` drawn faint), stops
steering, keeps moving, then detonates (`ContactBlast`, radius 110, damage 30). It also detonates on impact like any
rocket. **Fairness inequality (the Ph4 mine rule):** `(trigger_radius + blast_radius) / warning_time >= 420` (Open Space
max speed): (70 + 110) / 0.4 = 450 — a player crossing at cruise is caught, a 700 px/s boost escapes (700 × 0.4 = 280 >
180).

**Tests (t6), in `tests/integration/test_enemy_rockets.gd`:**
- (both) CLUSTER splits when the stub is within `split_distance` (not before: one tick earlier it is still whole); splits
  at `split_time` when the stub is 2000 px away; exactly `cluster_count` children, headings fanned across
  `cluster_fan_deg` (max − min angle within 0.5° of 36°, centred within 1° on the predicted direction); children are not in
  any pool, each frees itself on expiry; the parent emits `expired` once and spawns no `ContactBlast`.
- (open_space, real physics, 8×) a player bullet on the parent before the split → no children ever; children launched
  together survive 0.3 s (no sibling hits); a split after the launcher was freed still produces 4 children in the
  container.
- (both) WARHEAD does not trigger before `prox_arm_seconds` with the stub inside the radius from launch, then triggers on
  the first armed tick (B1b); detonates exactly `warning_time` after the trigger; the inequality above is asserted from the
  scene's exports; a stub crossing the trigger edge at 420 px/s is inside `blast_radius` at detonation; one boosting at
  700 px/s away from the trigger point is outside it.
- Lifetime rows for CLUSTER, SUBMUNITION and WARHEAD in `test_enemy_bullet_lifetime.gd` (§2.6).

### 2.9 Missile Corvette: scene, config, pools, rail fallback (t7)

Follows the Ph4 specialist template (`bomber/`, `ram_corvette/`): root script adds to `enemies`, `_apply_config`, an actor
API, a rail fallback in `_process` while suspended, a brain with `start_engaged` seam.

**Scene `assault/scenes/enemies/missile_corvette/missile_corvette.tscn`** (root `MissileCorvette extends BaseEnemy`):
body `CircleShape2D` r 40 shared (same `SubResource`, same scale) by the body, the root `HurtBox` and `ContactHitBox`
(contact-geometry and hurtbox-geometry gates); `Health`, `HitFlashAnimationPlayer`, `Sprite2D` (placeholder until t9),
`StateLight`, `Tubes/TubeL` and `Tubes/TubeR` (`Marker2D` at local (±18, 30), nose = local +y), `Tubes/TubeLightL` /
`TubeLightR` (small `Sprite2D`s, modulate driven by the telegraph, the `ArmorPlate.set_glow` idiom), `EnemyMover`,
`MissileCorvetteBrain` (node `Brain`), four pools `DumbPool`, `PursuitPool`, `ClusterPool`, `WarheadPool` (`BulletPool`,
direct root children, `persist_after_owner_death = true`, `pool_size` = `EnemyRocketScenes.pool_size_for` = `salvo_count ×
ceil(max_time / salvo_period_min)`: Dumb 3, Pursuit 6, Cluster 3, Warhead 6 — pinned in the test). `sprite_forward_angle = PI / 2` (nose-down art).

**`MissileCorvetteConfig extends ShipConfig`** (flat; `.tres` = these values; `2-research.md` §3.2):

| Group | Field = value |
|---|---|
| Base | `max_health` 160, `collision_damage` 30, `score_value` 70 |
| Movement | `max_speed` 210, `acceleration` 240, `max_turn_rate` 1.2 |
| Range | `preferred_range` 620, `assault_preferred_range` 460, `min_range` 380, `range_drift` 80, `range_tolerance` 120 |
| Arc | `orbit_angular_speed` 0.22, `reversal_min` 4.0, `reversal_max` 7.0 |
| Salvo | `launch_cone_deg` 45, `salvo_telegraph` 0.7, `salvo_count` 3, `salvo_gap` 0.22, `salvo_period_min` 4.0, `salvo_period_max` 5.0, `salvo_lead_step` 0.25, `warhead_range` 420, `cluster_min_range` 700, `pursuit_flee_speed` 300 |
| Engagement | `engage_seconds` 7.0, `exit_speed` 280 |
| Rail | `rail_rocket_interval` 2.5 |

**`MissileCorvette.fire(kind: EnemyRocket.Kind, aim_point: Vector2) -> EnemyRocket`**: the one place a rocket is taken from
a pool: alternates tubes, `acquire()`s from that kind's pool at the tube's global position, sets `arm_distance` 52 (hull
40 + 12), calls `launch(dir_to_aim, aim_point, self)`; returns the rocket (null if the pool is exhausted, counted in
`rockets_refused`).

**Minimal brain (t7):** `Phase` enum as in *For every task*; t7 plays APPROACH (seek to `preferred_range` along the
line to the player) and the Assault `EngagementBudget(engage_seconds)` → DISENGAGE (the Bomber's exit: away from the
player toward the nearest corridor edge at `exit_speed`, freed on leaving the cull rect as the Bomber does). No salvos
yet.

**Rail fallback (`on_suspended()`):** a root `_process` clock fires a DUMB rocket straight DOWN (aim point 600 px below)
every `rail_rocket_interval`. Nothing places it on a rail; this keeps a future `.move()` from being silent (Ph3 rule).

**Outside:** `WaveBuilder.missile_corvette()` + const `MISSILE_CORVETTE`; rows in `test_enemy_contact_damage.gd` (30),
`test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` rosters, `test_base_enemy.gd`
`_AUTHORED_CONTACT_MODES` (COLLISION); a `test_enemy_dual_mode.gd` case (spawns and moves in both harnesses with
`start_engaged`).

**Tests (t7), `tests/integration/test_missile_corvette.gd`:** pool sizes equal `pool_size_for`; `fire()` alternates tubes
and returns an armed-later rocket at the tube; config isolation picks it up (directory sweep, nothing to add); rail
fallback: `suspend_ai()` then 2.6 s of `_process` → one DUMB rocket heading DOWN; budget expiry → DISENGAGE (Assault);
corvette freed with rockets in flight → rockets keep flying (persist).

### 2.10 Missile Corvette behaviour: broad arcs, launch cone, predicted salvos (t8)

Brain `MissileCorvetteBrain` (`missile_corvette_brain.gd`). Phases `APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE`
(+ hub phases from t15). Range `R` = `preferred_range` in Open Space, `assault_preferred_range` in Assault.

1. **APPROACH** → seek toward a point at range `R` on the line player→corvette; enter HOLD_ARC within `range_tolerance`.
2. **HOLD_ARC (broad arcs, R5.3):** `Steering.orbit` about the player at radius `R + drift` where `drift` wanders in
   ±`range_drift` (a slow rng-seeded sine, period 6–9 s), angular speed `orbit_angular_speed`, direction ±1; the direction
   reverses after an rng interval in [`reversal_min`, `reversal_max`] (the Razor idiom). Inside `min_range` it blends
   `Steering.break_contact` (side = orbit direction) until back outside. The **nose** turns toward the player through
   `mover.face_toward(player)` at the mover's `max_turn_rate` (1.2 rad/s), independent of travel direction. Never pursues
   closer than `min_range`.
3. **Launch cone (R5.1 "get behind it"):** a salvo may start only when the player lies within `launch_cone_deg / 2` (22.5°)
   of the nose and `salvo_period` (rng in [min, max]) has elapsed since the last salvo ended. A player who circles behind
   faster than 1.2 rad/s of nose turn has a real window.
4. **Kind choice** (`choose_kind(distance, player_speed)`, judgement, the Bomber `choose_kind` precedent; checked in
   order): `distance < warhead_range` → WARHEAD (area denial at close range, `salvo_count` 2 laid across the predicted
   path); player speed ≥ `pursuit_flee_speed` and moving away (radial velocity > 0) → PURSUIT; `distance >=
   cluster_min_range` and player crossing (|tangential| > |radial|) → CLUSTER; else DUMB. A seeded `rng` swaps a DUMB
   choice for PURSUIT one time in four, so the rotation is not fixed.
5. **TELEGRAPH** (`salvo_telegraph` 0.7 s): `StateLight` CHARGING; tube lights ramp 0→1; the corvette keeps orbiting at
   half angular speed; the nose keeps tracking. If the player leaves the cone by more than 2× during it, the salvo is
   cancelled (back to HOLD_ARC, light OFF) — not in Assault, where it always fires once started (deadline bound).
6. **SALVO:** `BurstClock` of `salvo_count` rockets at `salvo_gap`, `StateLight` ARMED, tube lights flash per launch.
   **Aim points (R5.4, R5.5):** DUMB rocket *i* aims at `predicted_position(t_i)` with `t_i = intercept(tube, dumb cruise).time
   + i × salvo_lead_step` (successive points along the player's predicted path, so the salvo covers where the player will be
   and forces a turn, R5.9); PURSUIT / CLUSTER aim at the intercept point (the rocket re-aims itself); WARHEAD rocket *i*
   aims at the predicted point offset ±90 px perpendicular to the player's velocity (a pair across the path).
   Then HOLD_ARC; `StateLight` OFF. **Never COMMIT** (Ph2/Ph3: shooters do not use it).
7. **Assault:** one or two salvos per life. The budget defers to a started TELEGRAPH/SALVO (bound `salvo_telegraph +
   (salvo_count − 1) × salvo_gap` = 1.14 s, + 2 ticks); a TELEGRAPH starts only if `budget.remaining() >= 1.14 + 0.05`
   (the Ph4 attack-gate margin). The corridor constraint filters motion; the orbit centre is the player.

**Tests (t8), in `tests/integration/test_missile_corvette.gd`, dual-mode unless marked (hand-ticked):**
- holds range: from 1200 px, a stationary stub; after 6 s the corvette–player distance stays within `R ± (range_drift +
  range_tolerance)` for the next 10 s, and its bearing about the player changes by ≥ 60° over those 10 s (it arcs, it does
  not park); it is never inside `min_range` for more than 1.0 s cumulatively when the stub closes at 200 px/s.
- orbit direction reverses at least once in 15 s (Open Space).
- launch cone: a stub kept exactly behind the corvette (180° off the nose) by a scripted follower for 6 s → zero salvos;
  in front → first TELEGRAPH within `salvo_period_max + 1` s.
- salvo shape: after TELEGRAPH (exactly `salvo_telegraph` ± 1 tick) exactly `salvo_count` rockets leave at `salvo_gap`
  intervals; `StateLight` goes CHARGING → ARMED → OFF and never COMMIT.
- predicted path: for a stub at constant 250 px/s crossing, the three DUMB aim points lie on the stub's predicted line
  (within 1 px) at lead times spaced `salvo_lead_step`; a PURSUIT salvo is chosen for a stub fleeing at 350 px/s; a
  WARHEAD pair for a stub at 300 px; the two warhead aim points are 180 px apart across the velocity.
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
| Ward | `ward_search_radius` 900, `ward_keep_radius` 1100, `min_ward_seconds` 2.0, `ward_switch_margin` 1.3, `no_ward_grace` 1.5 |
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

**Candidates** (scan of group `enemies`, the `FighterBrain._mates()` filter shape): `BaseEnemy`, not self, not a
`SupportShip`, not a `SpaceStation`, `health.current_health > 0`, not `is_queued_for_deletion()`, not
`is_ai_suspended()` (rail ships), within `ward_search_radius` of the support; in Assault also inside
`EnemyWorld.view_rect(tree).grow(ward_view_band)`; and **not claimed by another live support** (claim = the ward's meta
`&"support_claim"` holding the claiming support's instance id; a stale id — `instance_from_id` null — counts as free).

**Threat score (judgement):** `score_value × (1 / (1 + d_player / 600)) × (1 + (1 − hp_fraction))`, where `d_player` is the
candidate's distance to the player and `hp_fraction` its health fraction — kind weight (fighter 25, ram 35, sniper 50,
bomber 80, corvette 70), closeness to the player, and damage taken.

**Stability:** keep the current ward at least `min_ward_seconds`; afterwards switch only to a candidate scoring ≥
`ward_switch_margin` × the current ward's score. Claim on select, release (remove the meta if it is ours) on switch, on
DISENGAGE and on `_exit_tree()`.

**Retarget (R5.24):** the support connects to the ward's `tree_exiting`; when it fires, or each tick when the ward is
invalid, dead, queued, suspended, beyond `ward_keep_radius`, or (Assault) outside `view_rect().grow(ward_view_band)`, the
ward is dropped and a new one is selected **on the next tick** (the minimum hold does not apply to a lost ward). No
candidate → SEEK_WARD (Open Space: hold `follow_distance` from the nearest ally or drift; Assault: after `no_ward_grace`
s with none → DISENGAGE).

**FOLLOW (soft anchor, R5.19):** anchor = `ward + (ward − player).normalized() × follow_distance + perp × follow_lateral
× side` (Reynolds leader-following, F4; `side` ±1 chosen at selection by rng), sought with `mover.arrive`; plus a jink
nudge (rng direction change every `jink_period`, magnitude `jink_strength`); plus, when the player is inside
`evade_radius`, `Steering.break_contact(pos, player, player_vel, side, evade_speed)` blended in (R5.23 "high
evasiveness"). The support never pursues the player. It faces the ward (`face_toward`), so the projector points at it.

**Assault view clamp (R5.25):** the anchor is clamped into `EnemyWorld.view_rect(tree).grow(−view_margin)`; the support
**supports** (repair, projection — t12) only while its own position is inside `view_rect().grow(view_band)`. So it cannot
hide above the camera: it is pulled into view to follow, and loses its effect if it is pushed out.

**Brain state for tests and later tasks:** `ward` (weak, validity-checked), `ward_score`, `ward_held_for`,
`wards_selected` (count), `anchor`, `is_supporting() -> bool` (in range, in view in Assault, ward valid), `signal
ward_changed(new_ward: Node)` (null when lost).

**Tests (t11), dual-mode, hand-ticked:**
- selection: with a fighter (25) and a bomber (80) at equal distance, it picks the bomber; a damaged fighter at 20 % HP
  close to the player beats an undamaged one far away; another support is never chosen; a rail-suspended enemy is never
  chosen; a ward claimed by another support is skipped.
- stability: a candidate scoring 1.2× the ward does not take over; 1.4× does, but only after `min_ward_seconds`.
- **retarget on death (R5.39):** free the ward → `ward_changed` fires with a new ward on the next tick; kill it via
  `health` → same; with no other candidate → `ward == null` and SEEK_WARD (Open Space) / DISENGAGE after `no_ward_grace`
  (Assault).
- follow: after 4 s the support sits within 60 px of the anchor (behind the ward relative to the player) and never
  within `evade_radius` × 0.8 of a player stub that approaches at 200 px/s for 3 s (evasion works); it never moves toward
  the player by more than 50 px net over 5 s.
- (assault) view clamp: with the ward 300 px above the view top, the support stays inside `view_rect()` (+ `view_band`)
  every tick and `is_supporting()` is false while the ward is out of `ward_view_band`; when the view pans to include it,
  support resumes. Provider injected (a fake `assault_arena` node answering `enemy_view_rect`).
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
refuses all damage, so the shield and repair only matter once it is exposed; then the arc absorbs the player's frontal fire
and pulses refill the hull, giving it more charges in Open Space (in Assault a ram lives one charge, so the pairing shows
only as a tougher exposed hull).

**Tests (t12), dual-mode, hand-ticked unless marked:**
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

### 2.14 Support Ship: emergency escort (t13)

**Trigger (R5.22):** the ward's health fraction ≤ `escort_hp_ratio` (0.35), the ward is not boosting, and the per-ward
cooldown (`escort_cooldown`, keyed by ward instance id) has elapsed → ESCORT.

**In ESCORT, each tick:**
- **"pulls the target away":** `ward.accept_tow(away × escort_tow_ratio × ward.ai_mover_max_speed())` where `away` =
  (ward − player).normalized(). `accept_tow` (§2.4: `BaseEnemy.accept_tow(v) -> bool`) adds a nudge to the **ward's own
  mover**, summed onto the ward brain's own request and limited to its `max_speed`; with 1.25× the ward's max speed the
  net motion is away from the player even while the ward's brain seeks the player at full speed. It is a request, not a
  write (the single-writer gate stays green); a boosting ward (charging Ram, dashing Razor) refuses it (`accept_tow` false)
  and the escort waits.
- **"becomes the closer target itself":** the support's anchor switches to the interpose point `ward + (player −
  ward).normalized() × interpose_distance` (judgement; Buckland "interpose", unsourced), clamped into the view in Assault;
  its evade blend is suspended (it accepts fire).
- The tether is drawn thicker as a tow beam; repair and projection continue.

**End:** ward HP fraction ≥ `escort_release_ratio` (0.5, hysteresis), ward lost (→ retarget, §2.12), ward–player
distance ≥ `escort_safe_distance`, or `escort_max_seconds` elapsed → FOLLOW, and the ward's cooldown starts.

**Assault:** the corridor constraint clamps the tow; the escort still triggers and ends by the same rules; the support's
budget is not deferred by an escort.

**Tests (t13), dual-mode, hand-ticked:**
- trigger: ward at 36 % → no escort; at 34 % → ESCORT on the next tick; the ward's mover received a nudge pointing away from
  the player (angle < 5°) of magnitude `1.25 × max_speed`.
- effect: a ward whose fixture brain seeks the player at full speed **increases** its distance to the player over 1 s of
  escort (control run without a support: distance decreases).
- interpose: within 1.5 s the support lies within 40 px of the interpose point (Open Space; in Assault within 40 px of its
  view-clamped image).
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
glow, modulate 0..1 driven by the brain's telegraph value). Rockets: `enemy_rocket.png` (≈ 20 × 10, nose-down orientation
used by every kind but the cluster), `enemy_cluster_rocket.png` (fatter, ≈ 24 × 14), `enemy_submunition.png` (≈ 10 × 6),
`enemy_warhead.png` (≈ 18 × 18, rounder, with a light the blink modulates) — each with `RocketTrail`; replace the
placeholder `_draw()` bodies. Rockets are in `assault/scenes/projectiles/`, so the transparency gate covers them.

**Support Ship (t14):** `support_ship.png` ≈ 88 × 88, nose-down, a distinct silhouette (a ring or dish projector mount
amidships, slim hull — readable as "not a gunship"); `support_projector.png` (the dish/emitter, folded = `scale.y` 0,
unfolded = 1; anchored so it opens forward toward the ward). The tether stays a `Line2D` (cyan while projecting, pale green
pulse on repair, thicker during escort). The shield arc is `EnemyShield`'s own cyan drawing.

**Tests:** the transparency gate (automatic); the existing node-name references in each enemy's test file still resolve.

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

**Tests (t15):** per enemy, the Ph4 `test_*_hub_idle` shape: idles on its ring with no player; NOTICING then combat when
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

`tests/integration/test_sector_hub_patrol.gd`: two clearance rows (corvette, support); "the seven patrol anchors are well
apart" becomes **eight distinct anchors > 1000 px apart, and the support's anchor equals the ram's**; the existing 12
draws' seeds unchanged; the container count and the frame-0 IDLE list include both; a hub corvette's rocket lands in
`EnemyContainer` (`start_engaged`, 8× clock); a hub support engaged with the hub Ram selects the Ram as its ward
(hand-ticked, `start_engaged` on both).

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
  support has a `ProjectedShield` attached to a ward (`is_supporting()` true) before its budget expires. Asserted in
  `test_missile_corvette.gd` / `test_support_ship.gd`.
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

1. **t1 gate-headroom** (§2.2) — first; every later test-adding task depends on the headroom.
2. **t2 enemy-shield** (§2.3) — the `HurtBox` hook and `EnemyShield` on fixtures.
3. **t3 support-hooks** (§2.4) — `repair`, decrease-only flash, `accept_tow`, `can_be_repaired`.
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

**Dependencies:** t1 is the root of everything that adds real-physics rows: t2 and t5 need t1. t3 and t4 are independent
roots (tiny unit tests). t6 needs t5. t7 needs t6 (four pools). t8 needs t7. t9 needs t8. **t10 needs t7** and t3 (`can_be_repaired`); t7 and t10 both edit the
contact-damage / geometry rosters, `test_base_enemy.gd` and `test_enemy_dual_mode.gd`, so they run in series. t11 needs
t10 and t4. t12 needs t11, t2 and t3. t13 needs t12 (same brain file) and t3. t14 needs t13. t15 needs t8 and t13 (both
brains and both configs). t16 needs t15. t17 needs t15 (it may write the same `.tres` files) and t8, t13. t18 needs t9,
t14, t16 and t17. Critical path: t1 → t5 → t6 → t7 → t10 → t11 → t12 → t13 → t15 → t17 → t18.

## 4. Test plan

The test rows for each task are listed under its design section (§2.2–§2.18); this section holds the rules they share.

### 4.1 Shared test rules

- **Dual mode:** `use_parameters(["open_space", "assault"])` on a bare label; build `tests/helpers/enemy_ai_harness.gd` in
  the test body (never in a default argument — the GUT leak); drive brains with hand-ticked `_tick()`; Open Space spawns
  set `start_engaged = true` once t15 has landed (mark earlier ones `# pre-t15` so t15 can find them).
- **Real physics only where a real collision is the point** (shoot-down, shield consumption, friendly fire, attack-in-
  budget); those run on the 8× clock with the step kept at 1/60 game-second, restored in `after_each`.
- **Every gate must be able to fail:** each new invariant row has a boundary case that a deliberately wrong value trips
  (listed in §2.x rows: the 35 % / 36 % escort edge, the shield's 55° / 56° arc edge, the split one tick early, the extra
  corvette at the 65.7 s peak, the corvette in cloud_descent).
- **Automatic sweeps that will see the new code without edits:** config isolation, sprite transparency, single writer,
  signal arity, UID integrity, project load, suite integrity. Do not add allowlist entries to any of them.
- **Gate time:** each task reports `GUT time` before/after (`scripts/gate-time.sh` from t1). Budget for the whole epic:
  t1's freed headroom minus 15 s. A task that would exceed its share moves rows to hand-ticked form before asking.
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

## 5. Risks

| Risk | Mitigation |
|---|---|
| Gate wall clock (GUT 256.8 s plus import and boot, against a ~300 s cap, before this epic) | t1 frees ≥ 30 s first or escalates; hand-ticked specs; 8× clock for real physics; per-task reporting. |
| The `HurtBox` hook touches every hurtbox in the project | No absorber = byte-identical path; unit rows pin it; the slot is set only by `EnemyShield`. |
| Rockets feel unfair (fast and tight-turning) | One kind is fast/wide or slow/tight, never both; finite guidance; dodge rows (straight run, late boost) are gates. |
| Enemy rockets strip Ram plates / kill allies — surprising | Owner question 1; pinned by a test either way; impact damage to enemies is small (8–18). |
| A shield that always faces the player is unflankable in the vertical Assault lane | Arc turns at a capped 1.6 rad/s and is 90° in Assault; capacity is small with a long regen delay; recorded as an accepted limitation. |
| Support stalls fights (repair + shield) | Pulsed 6 % repair, 150 HP budget per life, supports never repair each other, shield lapses without its projector. |
| Escort tow fights the ward's own brain | It is a nudge summed onto the brain's request through the mover; boosting wards refuse it; bounded by `escort_max_seconds`. |
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
| R5.15 | Rocket collision layer | t5 (bit 32 + 256) |
| R5.16 | World-space lifetime, persist after owner death | t5/t6 (lifetime rows), t7 (pools); owner-distance rule not built (S2) |
| R5.17 | Support role | t10–t13 |
| R5.18 | Size 72–104 px | t14 (≈ 88 × 88) |
| R5.19 | Behind the highest-threat ally, soft anchor | t11 |
| R5.20 | Repair beam | t3, t12 |
| R5.21 | Directional shield arc on another enemy | t2, t12 |
| R5.22 | Emergency escort | t3 (`accept_tow`), t13 |
| R5.23 | Low HP, high evasiveness | t10 (HP 55), t11 (evade, jink) |
| R5.24 | Retarget when the ally dies | t11 |
| R5.25 | Assault: cannot hide above the camera | t4, t11 |
| R5.26 | Contact profile None | t10 |
| R5.27 | Support + Ram made possible | t12 (pairing test), t16 (hub pair), t17 (support with level-1 rams) |
| R5.28 | Carrier + Support + Drones | out (Carrier Ph10/Ph18) |
| R5.29 | Shields are a temporary resource | t2 |
| R5.30 | Directional, local-module, regenerating, projected bubble | t2 (all four as component features; module and bubble fixture-proven), t12 (projected directional shipped); shipped module/bubble consumers Ph10/Ph11 |
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
- Shipped module shields and shield bubbles (Ph10 modular damage, Ph11 fortress shield nodes); this phase ships the
  component and proves both with fixtures.
- Enemy friendly fire from blasts and beams (Ph8).
- Owner-distance projectile lifetime (S2) and `BulletPool` container injection (S3).
- Placing either enemy in `ENEMIES_CLEARED` sections, the station's reinforcements or `level_2_waves.gd` (Ph15).
- Encounter composition (Corvette + Fighter, heavy patrol, Carrier + Support) — Ph13/Ph14; this phase makes the pairings
  mechanically possible.
- Difficulty tiers (Ph16): the levers are `EnemyRocket.lead_max`, `turn_rate`, `guidance_seconds`, the corvette's
  `salvo_period_*`, the support's `repair_fraction` / `shield_capacity`.
- A `StateLight` cyan state (the support's state is shown by its projector and tether).

## 8. Owner questions (not blocking; the plan takes the stated default)

1. **Enemy rockets break Ram plates** when baited into a Ram. Default: yes (counterplay; pinned by a t5 test).
2. **Narrower shield arc in Assault** (90° vs 110°). Default: yes.
3. **Repair budget per support** (150 HP per life). Default: yes.
4. **Gate time cap.** Default: the cap stays; t1 frees ≥ 30 s or escalates with measurements.
