# Support Ship — unarmed healer / shield projector

**Role:** Shadows the most dangerous ally, repairs it, shields its player-facing side, and drags it away when it is badly hurt.
**Fantasy / threat:** A fragile, evasive hull with a dish projector. It deals no damage itself; it makes the enemies around it harder to kill, so the player has to decide whether to chase it.

> **Build state (Phase 5, in progress).** t10 built the **shell** (scene, flat config with every §2.11 field, contact profile NONE,
> `can_be_repaired()` false, the Assault budget exit); t11 the **ward**: scored choice, claim, retarget, the soft anchor behind
> the ward with jink and evasion, and the Assault view clamp. Still to come: repair and shield (t12), the escort (t13), the real art with the
> unfolding projector (t14), the hub idle (t15), the hub patrol (t16) and level 1 (t17).
> Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.11–§2.15. Decisions: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` ("t10 as built", "t11 as built").

---

## Stats

| Property | Value |
|---|---|
| HP | 55 (`support_ship_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | none: `ContactProfile` mode NONE, `ContactHitBox` closed and `damage` 0 |
| Speed | `max_speed` 270, `acceleration` 700, `max_turn_rate` 4.0 |
| Body | one `CircleShape2D` r 34 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | **placeholder** (`sniper.png`, `Projector` uses `sniper_barrel.png`) until t14; `sprite_forward_angle = PI / 2` |
| Scene / config | `support_ship.tscn` / `support_ship_config.tres` (flat `SupportShipConfig`) |
| Score | 60 |

---

## Behaviour

- **Brain:** `SupportShipBrain` (`Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }`, append-only; `enter_phase()` seam).
  It plays SEEK_WARD, FOLLOW and DISENGAGE (ESCORT is t13, IDLE / NOTICING / RETURNING t15).
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
- **Repair:** `can_be_repaired()` is false, so supports never repair each other.
- **Rails:** `on_suspended()` drops the ward, folds the projector and hides the tether. There is no weapon, so no rail fallback.
- **Death / scoring:** a normal `BaseEnemy` death; score 60.

---

## Config exports

`SupportShipConfig` carries the whole plan §2.11 table in groups: Base (`max_health` 55, `collision_damage` 0, `score_value` 60),
Movement, Follow, Ward (`ward_min_score` 20, `ward_search_radius` 900, `ward_keep_radius` 1100, `min_ward_seconds` 2.0,
`ward_switch_margin` 1.3, `no_ward_grace` 1.5), Repair, Shield, Escort and Assault. t10 reads Movement, `follow_distance` and the
Assault group; t11 reads Follow, Ward and the view fields; Repair, Shield and Escort are read by t12-t13. See `support_ship_config.gd` for the meaning of each.

---

## Spawn notes

- WaveBuilder method: `b.support_ship()` — see `docs/enemy-roster.md`. Not yet placed in any level (t16, t17).

---

## Files

```
support_ship/
├── ENEMY.md
├── support_ship.tscn
├── support_ship.gd              ← SupportShip: config, can_be_repaired() false, fold_projector()
├── support_ship_brain.gd        ← SupportShipBrain
└── support_ship_config.gd / .tres
```

Tests: `tests/integration/test_support_ship.gd` (structure, config, contact 0 in both harnesses, SEEK_WARD, DISENGAGE, suspend;
t11: ward choice and its filters, switch hysteresis, retarget on free / kill / rail / range / view, the grace, follow, jink, evasion,
facing and the Assault view clamp, dual-mode) plus the roster rows in `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
`test_base_enemy.gd` and a case in `test_enemy_dual_mode.gd`.
