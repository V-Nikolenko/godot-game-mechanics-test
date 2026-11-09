# Context — t9 The Hijack Pulse (epic cmug23onr001pm52w9swwophy, plan §2.11)

The epic plan (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.5, §2.10, §2.11, §2.15, §2.18, §2.19) is approved; this task builds
§2.11 on top of t4 (the retarget contract on `homing_missile`) and t8 (the Hacker shell with TELEGRAPH / PULSE stubs).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/hacker_frigate/hacker_frigate_brain.gd` | `HackerFrigateBrain`: HOLD_ARC / BREAK_OFF / DISENGAGE / hub idle; TELEGRAPH and PULSE are `_tick_attack_stub()`; `_want_pulse()` returns false | t9 fills TELEGRAPH / PULSE, `_want_pulse()`, the cooldown, the damage cancel, the dart loop and the PULSE-end lock hook |
| `assault/scenes/enemies/hacker_frigate/hacker_frigate.gd` | `HackerFrigate extends BaseEnemy`; applies the config; `dish()`, `state_light()`, `body_radius()` | gains the dart pool accessor, `fire_dart()`, the lock call, the TELEGRAPH / PULSE tell (dish unfold, code-drawn rings) and the health watch |
| `assault/scenes/enemies/hacker_frigate/hacker_frigate_config.gd` / `.tres` | flat `HackerFrigateConfig` | t9 adds the pulse group (§2.11 "Config fields") |
| `assault/scenes/enemies/hacker_frigate/hacker_frigate.tscn` | the scene (body r 40, HurtBox, ContactHitBox, Mover, Brain, Hull, Dish/StateLight) | gains a `DartPool` (`BulletPool`, `pool_size` 4, no persist) root child |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` | the player's homing rocket with the t4 contract (`can_be_retargeted`, `retarget(target, seconds, source)`, tether, fizzle on source death) | the dart's only target; read-only here |
| `global/components/seeking_ordnance.gd` | `SeekingOrdnance.GROUP`, `eligible(tree, at, reach)` (nearest first, inclusive reach) | the PULSE claim query |
| `global/components/bullet_pool.gd` | pool: container = pool's grandparent; `acquire()` reparents + `reset()`; recycle on `expired` is **deferred**; `_exit_tree` → `cancel_active()` unless `persist_after_owner_death` | dart ownership; killing the Hacker frees its darts |
| `global/components/projectile_lifetime.gd` | `max_time` / `max_distance` / world rect; `reset()` re-arms the origin; `expire_now()` emits the host's `expired` through one latch | the dart's lifetime (1.6 s / 1400 px) and its single end |
| `global/enemy_ai/enemy_brain.gd` | `can_see_player()` (TargetInfo LOS, physics-step only), `on_emp_started()`, `accepts_tow()` | TELEGRAPH gate, hook gate, EMP answer |
| `global/enemy_ai/line_of_sight.gd` | `LineOfSight.clear(space, from, to, exclude)`: only asteroids and `blocks_line_of_sight()` bodies block | the per-rocket LOS check |
| `global/entities/player_base.gd` | `apply_ability_lock(seconds, source)`, `abilities_locked()`; the lock clock steps in `_step_disruption()` | the Disruptor hook target |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd` | `RocketState._launch_homing()` (3 rockets, 7 px spread, locked on the nearest `enemies` member, children of the state) | the "newly launched" rows |
| `tests/integration/test_hacker_frigate.gd` | t8 rows; the stub row; `_spawn()` writes `engage_seconds = 1000` | its movement rows must keep the pulse out (see the plan) |
| `tests/integration/test_enemy_dual_mode.gd` | the Hacker's dual-mode "closes to its held range" row (asserts HOLD_ARC at 4.0 s) | would read PULSE at 4.0 s once the pulse exists |
| `tests/integration/test_enemy_bullet_lifetime.gd` | the round lifetime sweep (`max_distance / slowest speed <= max_time`) | `HijackPulse` joins it |
| `tests/integration/test_seeking_ordnance.gd` | t4's rows: `_hand_rocket`, `_tick`, `_real_player`, `_salvo`, the dodge / primary-fire / clock helpers | the shapes this task's tests copy |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `MissileCorvetteBrain` (`_tick_telegraph`, `_end_salvo`, `salvo_cooldown`, NOTICING resets the clock) | the telegraph / cooldown pattern; the cooldown counts down every tick with the clock rule |
| `LaserTenderBrain._can_launch()` | the precedent `if Engine.is_in_physics_frame() and not can_see_player()`: hand-ticked rows skip LOS, real-physics rows test it |
| `BulletPool` + `ProjectileLifetime` (`EnemyBullet`, `EnemyRocket`) | pooled projectile with `signal expired`, `reset()`, a lifetime child; ends through `expire_now()` |
| `homing_missile._finish()` → `_lifetime.expire_now()` | the one-latch end pattern for the dart |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds with a player stub in group `player` |
| `tests/integration/test_seeking_ordnance.gd` helpers | hand rockets (physics off, `_tick` = rocket then lifetime), `_real_player`, `_salvo(p, type)`, the 8× clock, blast watcher |
| `tests/integration/test_sniper.gd` `_wreck()` | a real `wreck_medium.tscn` (a layer-1 body answering `blocks_line_of_sight()`); await 2 physics frames before a ray sees it |
| `tests/helpers/fixture_enemy.tscn` | a `BaseEnemy` in `enemies` (no body shape: one is added for the "bodies do not block" row) |
| `StateLight` | CHARGING = yellow (TELEGRAPH), COMMIT = white (PULSE), OFF |

## Conventions that constrain this

- Brains tick only through `BaseEnemy._physics_process`; only `EnemyMover` writes velocity / rotation (`test_enemy_mover_single_writer.gd` sweeps the brain and the
  root script); randomness only from `brain.rng`; `accepts_tow()` false in TELEGRAPH / PULSE (already).
- Physics queries (LOS) only on the physics step; such rows run on real physics at the 8× clock. Hand-ticked rows never cast.
- Every countdown: `x -= delta`, over at `x <= 1e-6`.
- Signals declared with their arity (`test_signal_emit_arity.gd`); per-frame prints behind `OS.is_stdout_verbose()`.
- Every projectile has exactly one owner: the dart is pooled (the pool recycles it), never self-freed; no `persist_after_owner_death`.
- IDEAS §21: a state shows on a light or part (yellow = charging, white = pulsing, amber = hacked), never a recoloured hull.
- No hand-typed `uid://`; new `.tscn` references stay UID-less.
- `BulletPool` recycle is deferred: a hand-ticked row that never yields cannot get a dart back, so each such row stays within `pool_size` 4 darts.
- A homing rocket claimed while flying away from the player never reaches a still player inside its 2.5 s window (measured with the rocket's rule:
  from 100–550 px heading straight away it fizzles; heading 135–180° off "away" from 350–550 px it hits in 0.9–1.4 s). The fairness control therefore uses rockets
  in flight toward the player, or it would be vacuous.
- Gate time before this task: GUT `Time` 219.817 s (2807 tests, `scripts/gate-time.sh`, this run). Allotment 2.5 s.
