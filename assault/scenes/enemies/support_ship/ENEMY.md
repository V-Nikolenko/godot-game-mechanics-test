# Support Ship — unarmed healer / shield projector

**Role:** Shadows the most dangerous ally, repairs it, shields its player-facing side, and drags it away when it is badly hurt.
**Fantasy / threat:** A fragile, evasive hull with a dish projector. It deals no damage itself; it makes the enemies around it harder to kill, so the player has to decide whether to chase it.

> **Build state (Phase 5, complete).** Shell (t10), ward and Assault clamp (t11), repair pulse and projected shield (t12),
> emergency escort (t13), art (t14), hub idle (t15), hub placement (t16) and level 1 placement (t17) are all built.
> Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.11–§2.15. As built: `docs/epics-done/cmufs7elw001pnm2xr3b6fteb/REPORT.md`
> and the "Phase 5 - as built" section of `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`. The shield it projects is the shared
> `EnemyShield` (`global/components/enemy_shield.gd`, see `docs/architecture/modules/global.md`); it repairs through
> `BaseEnemy.repair()` and drags through `BaseEnemy.accept_tow()`.

---

## Stats

| Property | Value |
|---|---|
| HP | 55 (`support_ship_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | none: `ContactProfile` mode NONE, `ContactHitBox` closed and `damage` 0 |
| Speed | `max_speed` 270, `acceleration` 700, `max_turn_rate` 4.0 |
| Body | one `CircleShape2D` r 34 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | `support_ship.png` (88 x 88, nose-down slim hull with a ring emitter mount); `Projector` uses `support_projector.png` (48 x 40 dish, `offset` (0, 20) so its origin is the base and `scale.y` 0 to 1 opens it forward from (0, 6)); `sprite_forward_angle = PI / 2` |
| Scene / config | `support_ship.tscn` / `support_ship_config.tres` (flat `SupportShipConfig`) |
| Score | 60 |

---

## Behaviour

- **Brain:** `SupportShipBrain` (`Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }`, append-only; `enter_phase()` seam).
  It plays SEEK_WARD, FOLLOW, ESCORT and DISENGAGE, plus the hub idle (t15, Open Space only): IDLE = a slow `idle_radius` ring orbit round `patrol_anchor` (default: the spawn point) with no ward and the dish folded; NOTICING = stop and face the player for `notice_time`, then SEEK_WARD; RETURNING = `arrive` at the anchor, then IDLE. `AnchorIdle` runs ahead of the phase dispatch on the support-player distance (`perceive_radius` 600, `lose_radius` 1300 > `escort_safe_distance + follow_distance + interpose_distance` = 940). It has no protected phase, so RETURNING interrupts anything, an ESCORT included (the bubble is undone, the ward dropped). `start_engaged` skips the idle (tests; Assault ignores it).
- **Ward choice (t11):** a candidate is a `BaseEnemy` in group `enemies`, not a `SupportShip`, `is_ai_driven()` (brain + mover,
  not on a rail — so never the Gunship, Bonus Drone or Station), alive and not queued, `counts_toward_wave_clear`, `score_value`
  >= `ward_min_score` 20 (so never a Swarm Drone), within `ward_search_radius` 900, in Assault inside
  `view_rect().grow(ward_view_band 120)`, and not claimed by another live support (meta `support_claim` = the claimer's instance
  id). Threat = `score_value × 1 / (1 + d_player / 600) × (1 + (1 − hp_fraction))`. The ward is kept `min_ward_seconds` 2.0, then
  replaced only by a candidate scoring >= 1.3 × its own. `_set_ward()` is the only writer of `ward`, the claim and the
  `tree_exiting` link, and emits `ward_changed(new_ward: Node)` (null when lost).
- **Retarget (t11):** the ward is dropped when it leaves the tree, is killed (queued), is railed, is beyond `ward_keep_radius`
  1100 or (Assault) leaves `view.grow(120)`; a new one is picked on the next tick. No candidate → SEEK_WARD.
- **SEEK_WARD:** `arrive()` at `follow_distance` from `nearest_ally()` (any live non-support `BaseEnemy`), stopping inside 12 px;
  with no ally Open Space stands still. In Assault the hold point (or, with no ally, its own position) is clamped into
  `view.grow(−view_margin 48)`, and after `no_ward_grace` 1.5 s **spent inside the view** with no ward it DISENGAGEs.
- **FOLLOW (t11):** anchor = `ward + away × follow_distance + away.orthogonal() × follow_lateral × side` (`away` = player→ward,
  `side` ±1 by rng), clamped into the view in Assault. One request: a spring seek (`arrive` capped at `d_anchor × 2.0`), a
  sideways jink of `jink_strength` 60 px/s reversing by rng every `jink_period` 0.8 s, and inside `evade_radius` 300 the anchor
  gives way (fully at 0.8 × 300) to `break_contact` at `evade_speed` 240 (lateral weight 0.3), with any toward-player component
  removed — it never pursues. It faces the ward.
- **`is_supporting()`:** a valid ward within `beam_range` 380; in Assault also the support inside `view.grow(view_band 24)` and the
  ward inside `view.grow(120)` — so it cannot help from above the camera. t12 gates repair and shield on it.
- **DISENGAGE:** Assault only. When the `EngagementBudget` (`engage_seconds` 9.0) expires it releases the corridor, raises the
  mover cap to `exit_speed` 300, curves to the nearest edge of the projectile world rect and frees itself outside it (the Bomber's
  exit). It has no telegraphed attack, so nothing defers the exit. Open Space never expires.
- **Scene nodes:** `Projector` (`Sprite2D`, `scale.y` 0 = folded; Godot clamps a zero scale to an epsilon), `Tether` (`Line2D`,
  `top_level`, drawn in world space, hidden). No pool, weapon or `StateLight`: its state is the projector and the tether.
- **Repair pulse (t12):** while `is_supporting()` (ward within `beam_range` 380, and in Assault both ships in view), every `repair_period` 1.5 s
  of supporting time it calls `ward.repair(round(max_health × 0.06))` (6 on a 100 HP ward; never flashes, never above max), clamped to the
  `repair_budget` left (150 HP per life). No pulse when the budget is spent, `LineOfSight` is blocked by an asteroid (tether drawn dim) or
  the ward `can_be_repaired()` is false. Emits `repaired(ward, amount)`; the tether flashes pale green for 0.15 s. Plates are never
  repaired (`repair()` heals the hull `Health` only). A support is itself never repairable.
- **Projection (t12):** supporting unfolds the `Projector` over 0.4 s (`scale.y` 0→1, eased out); once open the brain adds an `EnemyShield`
  named `ProjectedShield` to the ward (`sustain_mode`, arc 110° or 90° in Assault, capacity 40, radius = hull + 6), attached to the ward's
  `HurtBox`; skipped if the slot is taken. It `sustain()`s the shield with the player's position every tick, so the arc turns toward the
  player at `shield_turn_rate`. The ward owns the shield: when the support dies, is EMP-disabled, goes out of range or view, or switches
  ward, it lapses after `heartbeat` 0.3 s and frees the slot. The dish folds (0.25 s) when it stops supporting; the tether is cyan while
  projecting.
- **Support + Ram (t12):** a Ram Corvette is an ordinary ward. While it has plates the shield absorbs nothing (`is_armored()`), so the
  plate fight is unchanged; once exposed, the arc absorbs the player's frontal fire and pulses refill the hull.
- **Escort (t13):** in FOLLOW, a ward at or below `escort_hp_ratio` 0.35 of its HP (and past its per-ward `escort_cooldown` 6 s) starts ESCORT.
  Each tick the support offers `ward.accept_tow(away × 1.25 × the ward's max speed)` — a nudge on the ward's own mover, refused while the
  ward boosts or its brain is in a telegraphed phase (so a Sniper's LOCK or a Ram's WIND_UP land where they showed; the support then only
  interposes). It sits on the interpose point 90 px from the ward toward the player (view-clamped in Assault), without jink or evasion,
  and the ward's `ProjectedShield` becomes a 360° bubble; the tether is drawn 2.5× thick. Ends at 50 % HP, a lost ward, 700 px from the
  player or 4 s, back to FOLLOW with the shield arc restored; the budget is never deferred by an escort.
- **Rails:** `on_suspended()` drops the ward, folds the projector and hides the tether. There is no weapon, so no rail fallback.
- **Death / scoring:** a normal `BaseEnemy` death; score 60.

---

## Config exports

`SupportShipConfig` carries the whole plan §2.11 table in groups: Base (`max_health` 55, `collision_damage` 0, `score_value` 60),
Movement, Follow, Ward (`ward_min_score` 20, `ward_search_radius` 900, `ward_keep_radius` 1100, `min_ward_seconds` 2.0,
`ward_switch_margin` 1.3, `no_ward_grace` 1.5), Repair, Shield, Escort and Assault. t10 reads Movement, `follow_distance` and the
Assault group; t11 reads Follow, Ward and the view fields; Repair, Shield and Escort are read by t12-t13. The Idle group (`perceive_radius` 600, `lose_radius` 1300, `notice_time` 0.35, `idle_radius` 150, `idle_speed` 0.5) is read by t15. See `support_ship_config.gd` for the meaning of each.

---

## Spawn notes

- WaveBuilder method: `b.support_ship()` — see `docs/enemy-roster.md`.
- **Level 1 (t17):** two AI spawns, each in the same wave as a Ram Corvette and 60 design units (120 px) behind it —
  deep_space 26.0 s at (-255, -460) and planet_approach 28.0 s at (0, -460). That spawn point is 116 px outside the
  projectile world rect, which is harmless: only DISENGAGE frees an AI enemy, and it reaches its ram in about 3 s. In
  every placed slice it wards that ram and has a `ProjectedShield` up with 5.5–6.0 s of budget left
  (`test_support_ship.gd`). Its count-gate life is `engage 9.0 + 4.58 s` measured over the corridor. Kept out of
  `ENEMIES_CLEARED` sections (`test_engagement_deadline.gd`).

---

## Files

```
support_ship/
├── ENEMY.md
├── support_ship.tscn
├── support_ship.gd              ← SupportShip: config, can_be_repaired() false, projector / tether drivers
├── support_ship_brain.gd        ← SupportShipBrain
└── support_ship_config.gd / .tres
```

Tests: `tests/integration/test_support_ship.gd` (structure, config, contact 0 in both harnesses, SEEK_WARD, DISENGAGE, suspend;
t12: pulse, budget, range, unrepairable ward, blocked line, projection, lapse (freed, EMP, switch), a real bullet, Ram pairing;
t11: ward choice and its filters, switch hysteresis, retarget on free / kill / rail / range / view, the grace, follow, jink, evasion,
facing and the Assault view clamp, dual-mode) plus the roster rows in `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
`test_base_enemy.gd` and a case in `test_enemy_dual_mode.gd`.

---

## Design checklist (ideas §43)

| Question | Answer |
|---|---|
| Silhouette | Slim hull, dish projector |
| Preferred distance | 150 px behind its ward |
| Movement signature | Shadowing, jinking, interposing |
| Attack | None: repair, shield, escort |
| Player behind it | It evades (break contact) |
| Player boosts away | It follows its ward, not the player |
| Off-screen | Assault: clamped into view, no effect outside it |
| Retreat / reposition | Evade radius 300; DISENGAGE with no ward |
| Telegraph | Projector unfold plus the cyan tether |
| Destroying it changes the encounter | Shields lapse, repair stops |
| Armour / shields | None of its own; it projects one |
| Alone / combined | Alone: an inert evader; with a Ram (§37) it is the ward's shield and healer |
| Deterministic tests | Yes (seeded rng, hand-ticked in both harnesses) |
