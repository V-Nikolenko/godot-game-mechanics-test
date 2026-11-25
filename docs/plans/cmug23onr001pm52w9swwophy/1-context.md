# Context — Enemy rework, phase 9: electronic warfare (Jamming Structure, Hacker Frigate and EMP)

Epic `cmug23onr001pm52w9swwophy`, research task `cmug23onx001tm52wky2h8qj9`, written 2026-11-06 against
`agent/auto-dev` at `5fbc01f` (Phase 8 closed). Idea folder: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`
(`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` = "IDEAS", `ENEMIES.md`, `DECISIONS.md`).

Read with `2-research.md`, which starts with the **scope check** (what changed against this phase's scope as written)
and holds the external findings, the candidate approaches with tradeoffs, starting values and the recommended answers
to the open questions at the end of this file.

Every `file:line` below was read on this commit. Line numbers drift: cite the symbol when you build on one.

---

## Requirements from the attached documents

Quoted briefly; R-numbers are this phase's and are reused in `2-research.md` and (expected) in the plan's coverage
table. "Epic" = the Phase 9 epic text on the board.

### Player-side hooks (epic; Ph1 roadmap row 9: "the player's seeking weapons must expose retargeting")
- **R9.1 Ability lock** — epic: "The first hook is an ability/skill lock." Built and "pinned with tests before any
  enemy uses it".
- **R9.2 Seeking-rocket retarget** — epic: "The second hook is retargeting for the player's automated, seeking
  rockets." Also built and pinned before an enemy uses it.
- **R9.3 Primary fire never affected** — epic: "Tests in both harnesses cover lock and unlock timing, in-flight hijack
  and retargeting, and that primary fire is never affected." IDEAS §6.6: "It should not normally disable basic
  movement or primary fire."

### Jamming Structure (IDEAS §6.6, all of it; §18.6 "jammer towers")
- **R9.4 Role** — "A stationary battlefield structure that suppresses **special abilities / skills** in a radius. …
  its purpose is to temporarily change what tools the player can use."
- **R9.5 Visible field** — "The structure broadcasts a visible interference field."
- **R9.6 Interaction** — "Inside the field, affected abilities can be disabled or put into a locked/recharging
  state. Leaving the field restores access after a short stabilization delay."
- **R9.7 Enemies fight around it** — "Enemies can deliberately fight around it because the structure is part of their
  tactical advantage." Epic: "enemies deliberately fight around it".
- **R9.8 Enemies respect it** — "Enemies should also respect the jammer when appropriate rather than treating it as a
  magical player-only effect."
- **R9.9 Counterplay** — "Destroy the structure or move the fight outside its field."
- **R9.10 Variants** — "local jammer: small radius", "sector jammer: large field around an objective", "pulsed jammer:
  periodically turns on/off, creating movement windows".

### Hacker Frigate (IDEAS §6.4, all of it) and the Hijack Pulse (IDEAS §11.2)
- **R9.11 Role / size** — "A specialist ship that attacks the player's automated weapons rather than the hull
  directly. It is a high-priority disruption target." "80–120 px."
- **R9.12 Movement** — "avoids direct confrontation. It maintains medium/long range, drifts through asymmetric arcs,
  and tries to keep line of sight while staying outside the player's easiest attack angle." §18.6: "hackers stay
  outside the player's preferred route while jamming from range".
- **R9.13 Hijack** — "temporarily take control of **automated player weapons**, especially rockets/missiles that
  normally acquire targets automatically. The effect can target both newly launched ordnance and eligible rockets
  already in flight, so a projectile can visibly rotate away from its original target and turn back toward the
  player."
- **R9.14 Hijack Pulse** — §11.2: "A non-damaging control projectile emitted by the Hacker Frigate. It temporarily
  claims ownership of eligible automated player projectiles and changes their target to the player. The effect should
  have a clear visual and short duration."
- **R9.15 Tell** — "The hijack should be clearly telegraphed. A hacked rocket can change its visual accent, emit a
  warning sound, or receive a distinct targeting indicator." Epic: "with a clear visual, audio and indicator tell and a
  short duration".
- **R9.16 Scope of the base Hacker** — "The default version should affect **automated/seeking weapons**, not the
  player's direct-fire primary weapon. More advanced Hacker variants can briefly disrupt a skill/ability system, but the
  base enemy should have one clean, understandable trick." Epic: "A variant that briefly disrupts abilities is decided
  by this phase's research."
- **R9.17 Counterplay** — "Destroy the Hacker Frigate." "Avoid launching automated weapons while the hacker is in its
  active pulse." "Force the hacker behind cover or other enemies." "Lure the hijacked projectile into another enemy or
  hazard where appropriate." Epic: "kill the source, holding rockets during the pulse, or luring a hijacked rocket into
  another enemy".
- **R9.18 Assault** — "The hacker must remain inside a bounded lateral/vertical region, but the weapon hijack behavior
  remains unchanged." Epic: "Both enemies are clamped to the corridor in Assault".

### EMP (IDEAS §11.4, §18.6 "EMP zones"; Ph7 hand-over)
- **R9.19 EMP Pulse** — §11.4: "Disrupts enemy/player systems only if this fits the existing player mechanics." Epic:
  "The EMP Pulse area weapon and phase 7's EMP mine disrupt systems through the same hooks, but only where they fit the
  existing player mechanics."
- **R9.20 EMP zones** — §18.6 lists "EMP zones" among energy/physics structures.
- **R9.21 Ph7 hand-over** — DECISIONS Ph7: "EMP on enemies and seeking weapons; the real EMP player effect (replace the
  one line in `PlayerBase.apply_emp`, keep `EmpPulse.emit` / `apply_emp` / `is_emp_disrupted` / `emp_changed`);
  jammers; hijack pulse" → Ph9; "Pulse / EMP mines affecting enemies" → Ph9 "if wanted".

### Placement, art, tests
- **R9.22 Placement** — epic: both enemies "join Assault waves and the hub's ambient spawn".
- **R9.23 Art** — epic: both enemies "own their art"; IDEAS §21 (silhouette + faction accents + gameplay lights; "do
  not recolor the entire enemy according to state"; cyan = shield, yellow = charging, white = locked, red = armed),
  §22 (specialists 80×80–128×128, distinct silhouettes), §23 (every specialist has a readable state change).
- **R9.24 Tests both modes** — IDEAS §40: "Every enemy should have at least one automated test in both Open Space /
  Assault … The same behavior specification should be used in both tests"; epic: lock and unlock timing, in-flight
  hijack and retargeting, primary fire never affected.
- **R9.25 Design checklist** — IDEAS §43 (unique silhouette, preferred distance, movement signature, behaviour when
  approached from behind / when the player boosts away, retreat, telegraph, testable deterministically …).

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/entities/player_base.gd` | Base of both player ships: `apply_boost_disruption` / `boost_efficiency` / `disrupted_speed` (:182-209), `apply_emp` / `is_emp_disrupted` / `_step_emp` (:215-250), `emp_changed(active: bool)` (:13), `_step_disruption(delta)` (:228) called first in each ship's physics tick (`player_fighter.gd:75`, `player_ship.gd:204`), the code-built `BoostDisruptionRing` (:252) | Home of the ability lock (R9.1) and the real EMP effect (R9.21). The stand-in is the single line `apply_boost_disruption(1.0, seconds)  # Phase 7 stand-in, Phase 9's to replace.` (:220). Nothing reads `is_emp_disrupted()` or listens to `emp_changed` today. |
| `open_space/scenes/entities/player/player_ship.gd` | Open Space ship. `_input` H loop over `_module_pool` (:235-258, skips `is_open_space_boost_verb()`), `_step_boost` with the three `boost_efficiency()` refusals (:414, :427, :454), `cruise_speed()` = `max_speed` 420 (:479), `BoostBar` hook-up (:159-164) | One lock check per path: H modules, Shift boost / Boost Drive. |
| `assault/scenes/player/player_fighter.gd` | Assault fighter. `_input` H loop (:138-148, `DialogPlayer.is_active` early return), module `tick` loop (:99-100), `cruise_speed()` = `MoveState.move_speed` 360 (:128), `face_instant()` | Second H loop; Assault has no Shift boost (Boost Drive on H). |
| `assault/scenes/player/states/dash_state.gd` | Double-tap roll / warp. Refusal at :48-53 (`_boost_efficiency() < MIN_BOOST_EFFICIENCY`) before warp (:55) and cooldown (:59); roll speed `disrupted_speed` (:143) | Dash/warp are movement verbs; whether the jammer locks them is a design call (Q2). |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd` (`RocketState`) | The player's K "special weapon" in **both** ships (`player_fighter.tscn:358`, `player_ship.tscn:279`): `_on_action` (:38) fires on `special_weapon` when the 5 s `CooldownTimer` is stopped (:43); Q toggles warhead/homing; `_launch_warhead` (:53-58, 3 straight rockets) and `_launch_homing` (:60-76, `homing_count` 3, targets chosen once from group `enemies` sorted by distance, round-robin `locked_target`) | The single launch point for every player rocket — the "newly launched" hijack seam (R9.13) and a lock point (R9.1). Rockets are `add_child`ed to this state node (a plain `Node`). No launch signal, no group. |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` (`class_name homing_missile`, lowercase) | The only seeking player projectile. `@export var locked_target: Node`; `_fly_to_target` points **straight** at the target (no turn rate) at `speed` 500, bent by `Hazards.bend_heading`; else `_fly_forward`. Frees itself outside a **hardcoded Assault arena box** in world coordinates (:6-10, :29-32). HitBox layer 32, mask 513 (environment + enemy hurtbox), `damage` 100, ROCKET; frees on any non-deflected hit. No HurtBox (cannot be shot down), no `ProjectileLifetime`, unpooled, no owner | R9.2/R9.13 target. Today it **cannot hurt the player** (player HurtBox mask 1281 does not see 32; its mask does not see 128), it re-acquires nothing in flight, and in Open Space it dies the moment it leaves an Assault-sized box around the world origin (S3 in `2-research.md`). |
| `assault/scenes/projectiles/missiles/warhead/warhead_missile.gd` (`WarheadMissile`) | Straight player rocket, 640 px/s, damage 50, same HitBox layers; frees on `screen_exited` | **Not seeking** → out of the base Hacker's reach (R9.16). |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` (`EnemyRocket`) | Ph5 enemy rocket contract: HitBox layer 32 mask 640 (sees the player HurtBox only to detonate), player damage only through `ContactBlast` (layer 256), HurtBox 512/96 for shoot-down, `Steering.turn_toward` with `turn_rate`, finite `guidance_seconds`, `ProjectileLifetime`, `expired` | The pattern a hijacked rocket should follow to hurt the player fairly (blast, turn-limited, finite guidance). Pursuit rocket: cruise 440, `turn_rate` 1.6, `guidance_seconds` 3.0, blast 18 / r 40, `max_time` 6 (`pursuit_rocket.tscn:25-37`). |
| `global/components/emp_pulse.gd` (`EmpPulse`, 21 lines) | `emit(tree, at, radius, seconds, source) -> int`: calls duck-typed `apply_emp(seconds, source)` on group `player` by centre distance; returns 0 for `seconds <= 0`; "Phase 9's EMP Pulse weapon and any jammer call it too and extend the target set (enemies, the player's seeking weapons) without changing this signature" | R9.19/R9.21: the one EMP entry point. `tests/unit/test_emp_pulse.gd::test_never_touches_group_enemies_in_phase_7` is the row this phase flips. |
| `global/ship_modules/emp_blast_module.gd` (`EMPBlastModule`) | The **player's own** EMP (cockpit slot, H): sets `PROCESS_MODE_DISABLED` on every node in group `enemies` (no radius, despite its description "nearby") for 5 s via a `SceneTreeTimer`; 15 s cooldown; immune list by class name incl. `RamCorvette` | Second, older EMP-on-enemies path (S5). Disabling a `CollisionObject2D` removes it from physics by default (`disable_mode` REMOVE), so a stunned enemy's body and HurtBox drop out — it cannot be shot for 5 s. Pinned only by `test_ram_corvette.gd::test_emp_still_skips_the_corvette`. |
| `global/ship_modules/*.gd`, `ship_module_base.gd`, `global/autoloads/ship_module_state.gd` | 15 modules in 4 slots; `try_activate(player) -> bool` (:58), `can_activate()` (:65, only Boost Drive overrides), `tick()`; H-activated: Boost Drive (Assault), AI Targeting, EMP Blast, Trajectory Calc, Cockpit Heal, Parry, Shield Overload, Final Resort, Plasma Nova, Heat Flush; passive: Warp, Armor Plating, Overclock, Pierce, Shooting | The "special abilities / skills" the jammer suppresses (R9.4). There is no module/cooldown HUD at all. |
| `assault/scenes/player/states/weapon_state.gd` | Primary fire (`shoot`, J / LMB) for all five weapon modes in `_physics_process` (:91-135), gated on `actor.can_attack` and overheat | R9.3: must stay untouched; a row asserts it fires inside a jammer and during a hijack. |
| `global/ui/mission_hud.gd`, `assault/scenes/gui/hud.tscn`, `open_space/scenes/gui/hud.tscn`, `assault/scenes/gui/ability_chip.gd`, `open_space/scenes/gui/boost_bar.gd` | Shared HUD: `WeaponIcon` + `CooldownOverlay` bound to `RocketState` (:36-54); `AbilityChip` exists (Assault HUD only, hidden, "to be repurposed for module HUD display"); `BoostBar` has a violet disrupted state | Where "locked" is shown (R9.6 "locked/recharging state"). |
| `global/components/shield_component.gd` | Player `Shield` has `is_hacked` / `set_hacked()` ("API hook for the future hacked-state trigger (no caller yet)", :110-114) and `ShieldIcon.play_hacked()` art | A ready "hacked" visual and mechanic nobody calls; a candidate for the Hacker variant (Q5) — but it drains every charge on one hit, so it is not a "brief" disruption. |
| `global/hazards/hazard_info.gd`, `hazards.gd`, `hazard_field.gd` | Registry; `HazardInfo.disables_abilities` (:25, "Carried for Phase 9; no producer or consumer"); `Hazards.around(pos, reach)`; `HazardField` cycle TELEGRAPH → ACTIVE → QUIET on accumulated delta (`cycle_*` exports), `phase_changed(phase: int)`, registers in `_enter_tree()` | The jammer's field is a hazard (`kind = &"jammer"`, Ph6 decision) and the pulsed variant is this cycle. An info with `avoid_weight` 0 is skipped by `Steering.context_avoid` (`steering.gd:250`). |
| `assault/scenes/enemies/power_source/`, `shield_generator/` | Ph8 brainless / brain-only static structures: `BaseEnemy`, no mover, `AssaultDrift`, `is_laser_blocking()` false, `ContactProfile` NONE, `counts_as_escape` false in `.tres`, joins `enemies` and an owner group; `ShieldGenerator` has cyan tethers and a dark-lens "off" draw | The jammer's shape (S6). |
| `assault/scenes/structures/turret_group/turret_group.gd` | Coordinator; `add_power_provider(node)` ("the Ph20 jammer seam"), `power_changed(powered: bool)` | Jammer-linked groups are Ph20's; Ph9 must not take that seam (S9). |
| `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` | HOLD_ARC: broad orbit at `held_range()` ± `range_drift`, reversals every `reversal_min..max`, `min_range` break-off blending `Steering.break_contact`, nose tracks player, attack only inside `launch_cone_deg`, TELEGRAPH → SALVO, Assault `EngagementBudget` gate + DISENGAGE, hub idle through `AnchorIdle` | The movement template for the Hacker (R9.12): a medium-range arc shooter that keeps away. |
| `assault/scenes/enemies/support_ship/support_ship_brain.gd` | Assault view clamp `_clamp_into_view()` into `EnemyWorld.view_rect().grow(−view_margin)` (:501-513); evasion / never pursues | The "bounded region" for the Hacker in Assault (R9.18); its ward-search filter is a precedent for "is this rocket eligible". |
| `assault/scenes/enemies/sniper/sniper_brain.gd` | Firing-position scoring by bearing relative to the player's velocity / facing, cover bonus (Ph6) | Precedent for "stay outside the player's preferred route / easiest attack angle" (R9.12). |
| `global/enemy_ai/target_info.gd`, `line_of_sight.gd`, `enemy_brain.gd` | `TargetInfo.player()`, `velocity`, `facing`, `relative_angle_from`, `intercept`; `LineOfSight.clear/first_blocker/blocks`; `EnemyBrain.can_see_player()` | Hacker keeps LOS; "force it behind cover" means the pulse needs LOS. |
| `open_space/scenes/levels/sector_hub.gd` | Ambient patrol: 17 seeded draws, appended only (`_spawn_patrol`, :82-103); rings 1300/1500/1700/1900/2600; on the 2600 ring bearings −22.5 (Mine Layer), 112.5 (tender), −157.5 (twin pair) are taken | Hub placement (R9.22): draws 18+ appended; `tests/integration/test_sector_hub_patrol.gd` clearance sweeps. |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Sections: deep_space (DURATION 30 s), asteroid_belt (DURATION 30 s, **no specialists**), planet_approach (DURATION 110 s), cloud_descent (ENEMIES_CLEARED), station_assault (ENEMIES_CLEARED 180 s); `laser_column_schedule()` | Assault placement (R9.22). |
| `tests/integration/test_level1_specialist_spawns.gd` | Frozen `_LEGACY_PEAK_SPECIALISTS` deep_space 5 / planet_approach 3 / cloud_descent 4, `_COUNT_RATIO` 2.5; Ph8 left deep_space at 12 of 12.5 and planet_approach ≤ 7 of 7.5 | Little density headroom (S12). |
| `tests/integration/test_engagement_deadline.gd` | "No X in an `ENEMIES_CLEARED` section" guard rows | Jammer and Hacker get guards. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `PlayerBase.apply_boost_disruption` / `_step_disruption` pattern | The shape of a timed player debuff: strongest/longest wins, accumulated delta, hand-steppable, signal on change only. The ability lock copies it (a lock "source" set plus a stabilisation clock). |
| `PlayerBase.disrupted_speed` (excess rule) | DECISIONS Ph7: "use it for any later speed debuff". The real EMP effect keeps using it for boost. |
| `EmpPulse.emit` | The one EMP entry point; extend its target set (keep the signature). |
| `Hazards` / `HazardInfo` (`disables_abilities`, `contains`, `kind`, `avoid_weight`, `source`) / `HazardField` cycle | Jammer field registration, AI knowledge of the field, the pulsed variant's TELEGRAPH → ACTIVE → QUIET clock. |
| `ShieldGenerator` / `PowerSource` (+ `AssaultDrift`, `ContactProfile` NONE, `is_laser_blocking()`, owner group, `_draw()` off-state) | Jammer structure shell, Assault scroll, death → field off. |
| `MissileCorvetteBrain` HOLD_ARC + `AnchorIdle` + `EngagementBudget` + `StateLight` | Hacker movement, hub idle, Assault life, telegraph light. |
| `SupportShipBrain._clamp_into_view` | Hacker Assault clamp (view, not just corridor). |
| `EnemyRocket` (`Steering.turn_toward`, `ContactBlast.spawn`, `ProjectileLifetime`, `expired`) | How a hijacked rocket turns (rate-limited), hurts the player (blast only), and ends. |
| `ProjectileLifetime` (`global/components/projectile_lifetime.gd`) | A world-aware lifetime to replace the homing missile's hardcoded box (S3). |
| `EnemyBullet` / `EnemyRocket` + `BulletPool` (`persist_after_owner_death`) | The Hijack Pulse projectile's ownership (one owner, pooled). |
| `EmpRing`, `PulseRing` (`enemy_ordnance/mines/`) | Code-built expanding rings — the EMP Pulse and Hijack Pulse visuals. |
| `StateLight` (`global/components/state_light.gd`) | IDEAS §21 gameplay light on the Hacker. |
| `Shield.set_hacked` / `ShieldIcon.play_hacked` | Existing "hacked" look, if a variant uses it. |
| `tests/helpers/enemy_ai_harness.gd` (`open_space()` / `assault()`), `test_enemy_dual_mode.gd` | Dual-mode harness (label-parameterised, never `use_parameters([HARNESS…])`). |
| `tests/integration/test_player_boost_disruption.gd` | Both real player scenes, hand-ticked, refusals pinned without spending a tank — the template for the lock rows. |
| `tests/helpers/specialist_exit_probe.gd`, `ph8_exit_keys.gd`, `level1_slice_replay.gd` | Measured Assault exits and level-1 slice replays for the Hacker's placement rows. |

## Conventions that constrain this

- **Brains:** physics-ticked from `BaseEnemy._physics_process`, accumulated `delta`, no `Timer`, randomness from
  `brain.rng`; requests only (`test_enemy_mover_single_writer.gd`); a moverless structure root may move itself
  (`AssaultDrift`).
- **Configs:** flat `ShipConfig` subclasses with `@export_group`s, `.tres` wins, `privatise()`; never nested resources
  (`test_config_instance_isolation.gd`). Weapon/projectile tuning lives in the projectile scene's exports (Ph5/Ph7/Ph8).
- **Signals** declared with their emitted arity (`test_signal_emit_arity.gd`); per-frame logs behind `OS.is_stdout_verbose()`.
- **One owner per projectile** (CLAUDE.md); a runtime hazard spawns deferred into `Hazards.container(tree)`; a pooled hazard
  registers on `launch()`, a scene-placed one in `_enter_tree()`.
- **Every new enemy joins group `enemies` in its own `_ready()`**; static structures set `counts_as_escape = false`; no
  persistent-effect enemy in an `ENEMIES_CLEARED` section; Assault static structures use world-anchored x and must clear
  level 1's lit laser columns and the level-start `LaserWallWave` (x 0–672).
- **Mode detection** only through `EnemyWorld` (`has_view_rect`, `view_rect`, `movement_constraint`); nothing under
  `global/` names `ArenaCamera`.
- **Collision bits:** every bit in use named (`test_collision_layer_names.gd`). Ph6 decided hazards are *sampled*, so bit 12
  stays unallocated unless an overlap body truly needs it.
- **IDEAS §21:** a state shows on a small light / part, never a recoloured hull; `test_entity_sprite_transparency.gd` for
  every new sprite; art via the `pixel-art-generation` skill, strict top-down.
- **The mouse is read in one line**; nothing here may read input outside the existing `_input` / `MovementController` paths.
- **Hub draws are appended** (seeds of draws 1–17 unchanged); hub clearance sweeps cover new patrols.
- **Gate time:** GUT ≤ 240 s; Ph8 closed at 212.4 s (2634 tests). Rules in `tests/README.md` → *Gate time*.
- **UIDs:** never hand-typed; never `update_project_uids`.

## Dependencies and blast radius

- **`PlayerBase` and both ship scripts** are touched by every hook. Every player test file (`test_player_boost_disruption.gd`,
  `test_open_space_*`, `test_player_*`, `test_ship_rotation_single_writer.gd`, module tests) is in the blast radius; the lock
  must be a pure addition whose "unlocked" path is bit-identical (the Ph7 excess-rule discipline).
- **`RocketState` and `homing_missile`** are shared by both ships and are used by `test_enemy_rockets.gd:624` (enemy and
  player rockets destroy each other), `test_player_bullet_lifetime.gd` (projectile ownership sweep over `WeaponBehavior`;
  rockets are not `WeaponBehavior`s), `test_armor_query.gd` / Ram plate rows (`homing_point`), `test_hazard_projectiles.gd`
  (rockets bend). Changing the missile's lifetime or layers ripples into those.
- **`EmpPulse` target set**: the Ph7 EMP mine and the hub `Minefield` (EMP weight 0.15, hostility ALL) would start hitting
  enemies if the extension is unconditional — the hub field's behaviour changes. `test_enemy_mines.gd` EMP rows pin "reaches the
  player"; a row pins "never enemies" (`test_emp_pulse.gd`).
- **`EMPBlastModule`**: re-routing it changes a shipped player ability (stun semantics, radius, immunity).
- **Hub** `sector_hub.gd` draws and `test_sector_hub_patrol.gd`; **level 1** gates (`test_level1_specialist_spawns.gd`,
  `test_engagement_deadline.gd`, `test_ph8_static_members_clear_every_lit_column`), roster sweeps
  (`test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`
  rosters, `test_config_instance_isolation.gd`, `test_entity_sprite_transparency.gd`, `test_project_load_integrity.gd`).
- **HUD** scenes for both modes (`mission_hud.gd`), shared.
- **Docs:** `PROJECT.md` Conventions, `global.md`, `assault.md`, `open_space.md`, `docs/enemy-roster.md`, per-entity `ENEMY.md`
  / `STRUCTURE.md`, CLAUDE.md gate list.

## Risks, edge cases, testing requirements

- **Unfair hijack.** A homing missile turns instantly at 500 px/s — faster than the Assault fighter (360) and the Open
  Space cruise (420). Retargeted as-is it is unescapable without boost, and three arrive together. A hijacked rocket needs
  a turn-rate limit, a finite hijack window and blast-only damage, gated by the Ph5 dodge rows (straight run, late boost)
  and the 0.5 s player i-frames (`player_base.gd:32`). Player HP is 50 in both modes.
- **The homing missile's lifetime is Assault-only** (a world box near the origin). In Open Space, anywhere off that box,
  a launched homing rocket frees itself on its first tick — so "in-flight hijack" cannot happen there today, and the
  player's homing rockets are already nearly useless in the hub. Fixing it changes a shipped player weapon (S3).
- **Rocket ↔ player collision does not exist** in either direction; adding it must not let a player's own fresh rocket
  hurt the player at launch (arming clearance, the `EnemyRocket` rule).
- **Ownership:** a hijacked rocket stays a child of the player's `RocketState`; if the player dies, it is freed with
  the player (fine), and a hijacked rocket that outlives the Hacker must still end (one owner).
- **Lock timing:** enter → locked on the first physics tick inside; exit → unlocked exactly `stabilise_seconds` later,
  re-entry resets; a pulsed field's QUIET phase counts as "outside". Overlapping jammers and an EMP must not stack or
  unlock early. Test boundary: a press one tick before / after the unlock.
- **An ability refused by the lock must not spend its cooldown, charge or tank** (Ph7 "checked before a tank is spent").
  Missiles: the cooldown timer must not start on a refused press.
- **Primary fire, movement, Shift boost** (if movement) never change inside a field: bit-identical rows.
- **Passive modules** (Pierce, Overclock, Shooting, Armor Plating, Warp flag) — locked or not is a design call; locking
  them means per-module edits.
- **Enemy side of EMP** must not disable physics (the EMP Blast bug) and must not stall an Assault section (a stunned AI
  enemy's `EngagementBudget` still runs; a stunned ENEMIES_CLEARED enemy must still leave).
- **Gate time**: two enemies + structure + player hooks + HUD; Ph8 used ~33 s allotment. Headroom ≈ 27.6 s.
- **Art**: Hacker 80–120 px, jammer tower (local and sector sizes), Hijack Pulse, hacked-rocket accent, jammer field,
  EMP zone; readability on dark backgrounds.
- **No audio pipeline exists** (every phase deferred SFX to Ph17), yet the epic text names an audio tell (S10).

## Open questions for the plan

- **Q1** What exactly is locked by the jammer: H abilities only, or H + K missiles, or also dash / warp / Shift boost?
- **Q2** Are dash / warp / Shift boost "movement" (never locked) or "abilities"?
- **Q3** Passive modules: locked inside the field or not?
- **Q4** Lock model: a refcounted source set on `PlayerBase` vs. per-module flags vs. a sampled hazard query?
- **Q5** The Hacker variant (epic: "decided by this phase's research"): which ability disruption, and is it built in Ph9?
- **Q6** Hijack Pulse delivery: a travelling projectile that claims rockets it touches, or an expanding pulse from the
  Hacker? How does "newly launched" work (a window on the player, a launch hook, or both)?
- **Q7** What a hijacked rocket does: speed, turn rate, duration, damage path, what ends the hijack, and what it does after.
- **Q8** Which player rockets are "eligible": homing only (seeking) — confirm warheads are excluded.
- **Q9** The homing missile's Assault-only lifetime: fix in this phase (prerequisite for in-flight hijack in Open Space)?
- **Q10** EMP: what does the real player effect do (replace the stand-in with the ability lock? keep boost?), what does it
  do to enemies, to enemy rockets, to player rockets? Does the hub EMP minefield start hitting enemies?
- **Q11** The player's EMP Blast module: re-route through the new enemy hook (fixing intangibility) or leave it?
- **Q12** Who fires the "EMP Pulse area weapon": a jammer variant, an EMP-zone structure, the Hacker variant?
- **Q13** How do enemies "fight around" a jammer and "respect" it (R9.7/R9.8)?
- **Q14** HUD: where is "locked" shown, given no module HUD exists?
- **Q15** Placement: which level-1 sections and times; which hub draws / sites; an asteroid_belt placement has no frozen
  density constant.
- **Q16** Audio tell: defer to Ph17 as every earlier phase did, or build a minimal hook now?
