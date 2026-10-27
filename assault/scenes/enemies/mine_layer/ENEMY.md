# Mine Layer — area-denial minelayer

**Role:** Flies sideways across an encounter laying mines from its stern, so the player has to remember where the unsafe regions are.
**Fantasy / threat:** A slow, easy-to-hit hull whose threat is what it leaves behind. Enemies steer round its mines too (Phase 6 hazard perception).

> **Build state (Phase 7, complete).** Built: the scene, config, per-variant persistent pools, `drop_mine()`, the rail fallback, the `WaveBuilder` entry, the pass AI
> (APPROACH / LAY / BREAK_OFF / REPOSITION / DISENGAGE, the live-mine cap and the tail drop), the Open Space hub idle (IDLE / NOTICING / RETURNING) with its
> persistence rules, the hull art, the dispenser hatch and the `MineWake` trail (see **Art, hatch and wake** below), the hub patrol and the level-1 placement
> (see **Placement** below). Plan: `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.11–§2.16; t11's own plan `docs/plans/cmvkb0hdc00uiqs2xhvb2awai/3-plan.md`.
> The mine family itself is documented in `assault/scenes/projectiles/enemy_ordnance/mines/MINES.md`.

---

## Stats

| Property | Value |
|---|---|
| HP | 140 (`mine_layer_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 25 contact (`ContactHitBox`, COLLISION); mines deal their own blast |
| Speed | `max_speed` 240, `acceleration` 420, `max_turn_rate` 2.4, `lay_speed` 170, `exit_speed` 300 |
| Body | one `CircleShape2D` r 40 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | `mine_layer.png` (96 × 96, PixelLab `create_map_object`, strict top-down, nose-down, no rotation: a wide shield-shaped dark hull, red edge stripe, a full-width rear mine rack) + `mine_layer_hatch.png` over the rack |
| Scene / config | `mine_layer.tscn` / `mine_layer_config.tres` (flat `MineLayerConfig`) |
| Hazards | `hazard_avoidance` 0.8, `hazard_margin` 24, `hazard_resistance` 0.2; leaves a medium wreck 35 % of the time |

---

## Behaviour

- **Brain:** `MineLayerBrain` (`Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }`, append-only,
  `enter_phase()` seam, `start_engaged` seam). It flies **sideways across** the player's path laying one line of six mines a pass (plan §2.12, built in t11).
- **Player frame.** P = the player, v̄ = its velocity smoothed over `velocity_smoothing` 0.5 s (the Bomber's EMA). Moving when |v̄| ≥ `frame_speed` 60:
  f = v̄/|v̄|, read every tick. Standing: f is **latched** to P → layer at APPROACH start (and on every moving → standing switch) and kept until the plan
  freezes, so the run-in point is a fixed point. The axis u = f.orthogonal() × sign, the sign latched with the frame so the start S is on the layer's side
  (tie: the side its velocity points to; at rest +1).
- **The line.** Centre C; S = C − u·300, E = C + u·300 (`pass_length` 600); mines on axis coordinates −250 … +250 (`mine_step` 100), offset along the normal
  toward P: ZIGZAG ±`zigzag_amplitude` 35 (122.1 px chords) or ARC `4·arc_depth·t(1 − t)` (`arc_depth` 110), drawn per pass by `arc_chance` 0.5. Variants
  per mine from the flat `w_*` weights, at most one HOMING a pass. Path = S → mines → E. Run-in point R = S − u·`run_in` 150.
- **Where C goes (Open Space).** *Lead* (moving player it can get ahead of): the Bomber's earliest-feasible arrival scan (0.1 s steps up to `lead_scan_cap` 6 s,
  5 bisections); C = P + v̄·(T + run_in/lay_speed + min(c, `lead_horizon` 3)) + f·`ahead_distance` 260; `flight_time()` adds the spin-up from the layer's
  current speed. *Fence* (standing player, or no feasible arrival = the fence fallback, frozen at once): C = P + f·`fence_distance` 320, between the player and
  the layer. Spread: a new C keeps `min_pass_separation` 380 from every earlier pass that still has a live mine — fence by rotating C about P (+θ, −θ, +2θ,
  −2θ, turning f and u with it), lead by shifting C 390 px further along the heading; no legal candidate → the first one (`spread_fallbacks` + 1). The plan
  freezes within `commit_distance` 200 of R and is never re-planned (a reversing player does not move it). A lead plan that loses feasibility before the freeze
  is frozen as it stands.
- **Assault ("clamped to the corridor").** No scan: a horizontal axis (S on the layer's side), C = (P.x, P.y − `assault_ahead` 220), clamped into
  `view_rect().grow(−(view_margin 64 + 110))`, so every mine lands inside `view_rect().grow(−64)`.
- **APPROACH** seeks R at `max_speed`; within `path_lookahead` 60 of R it runs in along R → S at `lay_speed` 170; **LAY starts on the tick the centre's projection
  on u crosses S** (< 0 to ≥ 0). Open Space backstops: an APPROACH unfrozen after `approach_max_seconds` 6 s takes the fence fallback; a frozen R the layer cannot
  reach (held off by an older line) is abandoned to REPOSITION (`abandoned_passes`; 6 s near R without a run-in, 12 s never near, 20 s in the run-in).
- **LAY** (committed, `accepts_tow()` false, StateLight ARMED, CHARGING 0.3 s before each drop): pure pursuit 60 px ahead on the path at `lay_speed`, driven
  through an acceleration-limited `mover.boost()` each tick, so an older line's mines do not push it off the line. Mine k drops once the Dispenser has passed its
  point by the eject lead (18 px) and ejects back onto it; what is left drops at the end; stall guard `path_length × 1.2 / lay_speed + 0.5` s. Open Space
  no-stacking: a rest point within `trigger_radius + 40` of another live mine is skipped.
- **BREAK_OFF** (Open Space): `break_contact` away from the player and off the far end of the fresh line at `break_speed` 260 for `break_seconds` 1.2.
  **REPOSITION**: orbits the player at `standoff_range` 600 for 5–7 s (`pass_period_min..max`), then the next APPROACH. So a line ends ≥ 6.2 s before the next
  starts, one line every ≈ 10–14 s.
- **Live cap:** at most `max_live_mines` 18 (Assault `assault_max_live_mines` 8) of this layer's mines are live; the next drop `retire()`s the oldest (a fade,
  no blast). In Open Space its mines never fizzle (backstop 240 s).
- **Tail drop:** in any engaged phase but LAY, a player within `tail_range` 280 of the Dispenser in the rear 60° cone gets a PROXIMITY mine at the Dispenser
  (no eject), at most every `tail_drop_cooldown` 2.5 s; the first one is immediate. Chasing it is punished.
- **DISENGAGE** (Assault: after its one pass, or when `engage_seconds` 9 runs out; an expiry mid-LAY waits for the LAY to finish): `mover.release_constraint()` and
  `mover.max_speed = exit_speed`, as the Bomber does, so the corridor never holds an exiting layer in. After a pass it leaves along the line's axis (off the far
  end); with no pass laid, along its heading on entry. Freed outside the world rect.
- **Hub idle (Open Space, t12).** `AnchorIdle` runs ahead of the phase dispatch (as the Bomber's): `patrol_anchor` (default the spawn), `idle_phase_offset` from `rng`,
  `perceive_radius` 650 · `lose_radius` 1500 · `notice_time` 0.35 · `idle_radius` 160 · `idle_speed` 0.5. **IDLE** is a slow ring round the anchor and never lays or
  tail-drops; **NOTICING** blinks the light, faces the player for `notice_time`, then goes to **REPOSITION** (not straight to APPROACH), whose wait is drawn afresh from
  `pass_period_min..max` — a layer that idled for a minute does not lay the instant it notices; **RETURNING** `arrive`s home (within `idle_radius`) and reaches IDLE. A **LAY is
  never interrupted** (the return is retried every tick, so a line already begun is finished first), nor a DISENGAGE. `start_engaged` and Assault (`EngagementBudget.active`) build no
  `AnchorIdle`; `on_suspended()` drops it. `lose_radius` clears the layer's own cycle (600 + 260 × 1.2 + 300 + 150 = 1362) and the lead form's farthest point against a 220 px/s
  player (1415.8); a faster player is let go on purpose.
- **Persistence (Open Space).** Mines have `mine_life` 0 and a 240 s backstop; RETURNING does not touch them and a layer's death hands them over, so an area the player
  comes back to is still dangerous (Assault: gone after `assault_mine_life` 9 s).
- **Test seams:** `pass_centre` / `pass_start` / `pass_end` / `pass_run_in_point` / `pass_axis` / `pass_normal` / `pass_shape` / `pass_form`
  (`&"lead"`, `&"fence"`, `&"assault"`), `plan_frozen`, `frame_f`, `arrival_time`, `planned_rest_points`, `planned_variants`, `drops_this_pass`,
  `skipped_this_pass`, `passes_started`, `tail_drops`, `run_in_active`, `spread_fallbacks`, `fence_fallbacks`, `abandoned_passes`, `pass_spread_fallback`;
  `plan_pass(p, v_bar, earlier)`, `freeze_plan()`, `flight_time(point)`, `lead_run_in_point(p, v_bar, t)`, `lay_mine(variant, rest)`, `live_mines()`,
  `live_mine_count()`, `live_pass_centres()`, `smoothed_velocity()`, `path_points()`; `signal mine_dropped(mine: EnemyMine)` for every drop; t12 adds `patrol_anchor`, `anchor_idle`, `idle_phase_offset`.

## Mines

- One root `BulletPool` per variant with a weight above 0: `ProximityPool` (`max_live_mines + 2` = 20), `ChainPool` 6, `PulsePool` 5, `HomingPool` 5; `DriftingPool` and
  `EmpPool` only if `w_drifting` / `w_emp` are raised. Each is `persist_after_owner_death`, so mines laid before the layer dies outlive it. Sizes equal
  `EnemyMineScenes.pool_size_for(variant, config)` (gated).
- `MineLayer.drop_mine(variant, rest_point) -> EnemyMine`: acquires at the `Dispenser` (local (0, −38), the stern) and falls back to PROXIMITY when the pool is absent
  or exhausted. It sets **only** `arm_delay` (0.5), `eject_time` (0.3) and the life: Assault `assault_mine_life` 9.0; Open Space `open_space_mine_life` 0 (never fizzles)
  with a `ProjectileLifetime` backstop of `open_space_mine_backstop` 240 s. Trigger, warning and blast numbers are the variant scene's (a pulse mine keeps its blast of 8).
  The eject is launched at `2d / (eject_time − one tick)` so the mine comes to rest on the point (within 4 px).
- `MineLayer._ready()` joins group `enemies` (`BaseEnemy` does not; placed `ALL` mines look for that group).
- **Rail fallback:** while an `EnemyPathMover` owns it, a PROXIMITY mine drops at the dispenser every `rail_mine_interval` 1.6 s (speed 0, Assault life).

## Art, hatch and wake

- **Hull:** `assault/assets/sprites/enemies/mine_layer.png`, 96 × 96, PixelLab `create_map_object` (`view: "high top-down"`), nose-down so the `Sprite2D` has no
  rotation (`sprite_forward_angle` stays the default `PI/2`). A wide shield-shaped dark hull with a red edge stripe and a full-width rack across the stern (top of the
  image), where the `Dispenser` sits. No painted glow or flame. Picked from four candidates (a narrow dart, a pointed arrow, a manta shape and this one); the others
  read as a fighter or came back nose-up.
- **Hatch:** `Hatch` (`Sprite2D`, `mine_layer_hatch.png`) at local (0, −34) over the rack, scaled (0.92, 0.55). `MineLayer.set_hatch_open(0..1)` sets its `scale.y` to
  `closed × max(1 − open, 0.001)` (a zero scale is not a valid transform, so tests compare with a tolerance); `hatch_open()` reads the value back. The brain eases it
  toward 1 during LAY and toward 0 otherwise over `hatch_seconds` 0.25 (`_ease_hatch()`, at the end of every `tick()`). A railed layer never opens it.
- **Wake:** `MineWake` (`mine_wake.gd`, a code-built `Line2D`, no texture) is added to the layer's parent container when LAY starts (`brain.wake`). It appends the
  Dispenser's global position every 12 px (several points when one tick covers more, so a 24 px stretch always has two), width 3, dark red to transparent, alpha 0.45.
  Leaving LAY calls `finish()`; it then fades `modulate.a` over `wake_fade` 2.5 s on its own clock and frees itself (`RailTrail`'s precedent: no `Timer`, no
  `create_timer`). It outlives a dead layer: a freed Dispenser ends the following by itself.

## Placement

- **Level 1:** `b.mine_layer().at(-400, -160)` inside deep_space's existing 16.0 s wave (enters from the left) and `b.mine_layer().at(400, -160)` inside planet_approach's
  existing 47.0 s wave (from the right). AI spawns (no `.move()` / `.free_after()`), no new wave, so no other wave's effective trigger moved. Neither section is
  `ENEMIES_CLEARED`. Pinned in `EXPECTED_PH7` (`test_level1_specialist_spawns.gd`): the layer counts as a specialist in the frozen 2.5× gate (deep_space peaks at **8** of
  12.5, planet_approach at **7** of 7.5), its life is `engage_seconds` + the ZIGZAG stall guard 5.67 s + a tick slack + the **measured** corridor exit **7.53 s** (the
  exit probe, 2166 starts, 0 capped, with the probe player stub out of group `player` and `tail_range` 0), and its mines add `assault_mine_life` 9 s to the spill-over row
  (nothing outlives the next `ENEMIES_CLEARED` section's last trigger: deep_space's last is gone 47.2 s into its section, planet_approach's 116.4 s). From both spawns
  the layer reaches LAY with 6.3 s of budget left, lays 6 mines, all inside `view_rect()` (`test_mine_layer.gd` slice replays, 16× clock); a 2.0 s budget reaches no LAY.
- **Hub:** one Mine Layer patrols `SectorHub` on a 2600 px ring at bearing −22.5° (anchor ≈ (2402, −995)), seed draw 15 (earlier seeds unchanged), idle 160 / perceive
  650 / lose 1500; its mines land in `EnemyContainer`. A placed RING `Minefield` (9 mines, radius 200, seed 7, hostility ALL) sits beside the battleground at (3300, 560),
  so the player can lure enemies into it. Clearances (printed by `test_sector_hub_patrol.gd`): field to Mine Layer group 585.6 px, to the Gatling group 775.1 px.

## Gates

`tests/integration/test_mine_layer.gd` (shell rows, t10; the "Passes" section, t11: geometry, the lead / fence / fallback / guard / spread planner rows,
the run-in crossing, LAY on its path for aligned, perpendicular and older-line arrivals, two seeded 60 s Open Space scenarios (gradual passes, clear of
older lines), the live cap, Assault's one pass and its budget deferral, the tail drop; t13: the hull's opacity, the hatch closed outside LAY / open in it / eased over 0.25 s, the wake's spacing, path offset, fade and self-free in both modes; t12: the idle radii inequalities, frame-0 IDLE, NOTICING, RETURNING (and not during LAY), the persistence scenario, Assault's expiry); the Mine Layer is in the rosters of
`test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` and `test_wreck.gd` (`_SHIP_SCENES`);
`test_config_instance_isolation.gd` finds it by its directory sweep; `test_enemy_dual_mode.gd` has the APPROACH case (it closes on its run-in point).

Spawn with `b.mine_layer().at(x, y)`. No Mine Layer (or anything else dropping persistent mines) goes in an `ENEMIES_CLEARED` section.
Level 1 and the hub: `test_level1_specialist_spawns.gd` (`EXPECTED_PH7`), `test_engagement_deadline.gd` (no `ENEMIES_CLEARED` section holds a Mine Layer, with a boundary row),
`test_sector_hub_patrol.gd` (patrol group, seed draw 15, clearance sweep including the field).
