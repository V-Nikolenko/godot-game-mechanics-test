# t2 — Enemies can carry a directional shield (HurtBox absorb hook + EnemyShield)

## Problem
Enemies have no shield. Later tasks (the Support Ship's projected arc, the escort bubble) need one: a temporary,
directional resource that eats shots from one side, breaks, reboots and regenerates — never a second HP bar. Today a
`HurtBox` turns every hit straight into `received_damage(damage)`, which carries no hit, so no listener can decide
"from which side did this come". Nothing changes for the player in this task (no shipped enemy carries a shield yet);
it lands the mechanism and proves it on fixtures.

## Design (as approved in the epic plan §2.3 — not re-designed here)
1. **`HurtBox` absorb hook** (`global/components/hurtbox_component.gd`): `signal hit_absorbed(hit_box: HitBox)`,
   one `_absorber` slot (`set_absorber(obj) -> bool` false while another *live* absorber holds it; a freed holder is
   replaced; `clear_absorber(obj)` no-op unless `obj` holds it; `has_absorber()` = live holder). In `_on_area_entered`,
   after the damage-type filter: a live absorber answering `absorbs_hit(hb)` true → `hit_absorbed.emit(hb)` and return;
   else `received_damage.emit(hb.damage)` as before. With no absorber the path is unchanged.
2. **`EnemyShield`** (`global/components/enemy_shield.gd`, `class_name EnemyShield extends Node2D`) with the exports,
   methods and signals of §2.3. Choices made here (inside the approved design):
   - *host* = the attached `HurtBox`'s parent (so a local-module shield on a part measures bearings from the part);
   - initial facing `Vector2.DOWN` (Assault nose-down / toward the player); `face(world_dir)` snaps it (owner setup and
     tests), `set_threat_point` turns it at ≤ `turn_rate × delta` per tick in `_tick(delta)` (called from
     `_physics_process`, hand-tickable);
   - points are a float internally, `points()` returns `int(floor)`; "up" = not rebooting, not lapsed, `points() > 0`;
   - `restored()` fires each time points climb back to `capacity` after any loss (once per refill — covers the
     post-break refill the plan names and the partial-regen row's "restored once");
   - armoured host: `host.has_method("is_armored") and host.is_armored()` → false, nothing spent; `deflects_hit` is
     never called;
   - sustain mode: the heartbeat clock starts at creation; a lapse emits `lapsed()` once, stops absorbing, fades
     `fade_seconds`, then `queue_free()`; `_exit_tree()` clears the hurtbox slot.
   - drawing: `_draw()` cyan arc at `radius`, angles `world − global_rotation`; alpha by points fraction; 0.12 s flare on
     absorb; a short burst of radial strokes on break; the post-break refill drawn as the arc growing from its centre.
3. **P-15 record**: `DamageReaction` not adopted by `BaseEnemy` — appended to the Phase 5 section of `DECISIONS.md`.

Alternatives rejected (already in §2.3): adopting `DamageReaction` (no hit in its signal, player-shaped `Shield`);
deciding in a `received_damage` listener (no `HitBox`; `area_entered` order undefined).

## Build sequence
1. Failing absorber rows in `tests/unit/test_hitbox_hurtbox.gd` → implement the hook → green.
2. Failing `tests/unit/test_enemy_shield.gd` (hand-ticked) → implement `EnemyShield` → green.
3. `tests/integration/test_enemy_shield_hits.gd` (8× clock, ≤ 6 awaited cases) → green.
4. DECISIONS.md line, `global.md` component entry (docs skill), gate-time after, verify, leak check.

## Test plan
- `test_hitbox_hurtbox.gd` (new rows): no absorber → `received_damage` as before; absorber true → `hit_absorbed(hb)`,
  no `received_damage`; false → `received_damage`; freed absorber ignored (and its slot can be retaken); second
  `set_absorber` false; `clear_absorber` by non-holder no-op; filter runs before the absorber (absorber not asked).
- `test_enemy_shield.gd`: inside arc absorbed, points drop; **54° absorbed / 56° lands** (110° arc); bubble absorbs from
  behind; `arc_deg` 110 → 360 while attached; **boundary 40 vs 25+25+25**: 15 left, breaks whole (`broken` once),
  third lands; nothing absorbed during reboot; regen waits `regen_delay`, then full after the proportional time,
  `restored` once; facing turn ≤ `turn_rate × delta`; sustain lapse after `heartbeat` → `lapsed` once, fade, freed;
  freeing detaches the slot; armoured host false + points unchanged, true once unarmoured; counting-fake `deflects_hit`
  never asked.
- `test_enemy_shield_hits.gd` (real projectiles): bullet front consumed + hull HP unchanged and bullet from behind
  damages the hull (one case); warhead + homing rocket front detonate, no hull damage; beam-style
  `received_damage.emit` bypasses; local-module part shielded while hull is not; bubble absorbs four bullets from four
  directions.

## Risks
- Real-bullet bearing is measured at overlap time (the hitbox at the hull edge); test geometry keeps shots on-axis.
- Gate time: budget 3.0 s; ≤ 6 awaited cases, each a few dozen 8× frames.

## Out of scope
Any shipped enemy carrying a shield (t12/t13), the Support Ship, rockets of the enemy family.

## Revisions after review round 1 (4-review.md)
1. **Integration fixture values**: the default player bullet deals 50 and `fixture_enemy.tscn` has 10 HP, so every
   integration case sets hull `Health` to 1000 (max and current) and the shield `capacity` to 1000 (≥ 4 × 50) before the
   shield enters the tree; the hull's `CircleShape2D` (r 20) is added at runtime. Rows read HP deltas, not deaths.
2. **Local module = a plain part**, never an `ArmorPlate`: a `Node2D` part with its own `HurtBox` (layer 512, mask 96)
   → `received_damage` → its own `Health`, placed 60 px to the side, clear of the hull hurtbox. **Limitation, recorded
   in DECISIONS.md:** a shield does not cover an `ArmorPlate` (the plate damages itself in its own `area_entered`).
3. **Turn row** asserts the facing turns by exactly `turn_rate × delta` per tick while far off, settles on the bearing
   without overshoot (angle to the target never grows / never changes sign past it), and holds still with no threat point.
4. **Regen rows**: (a) the regen delay restarts on every absorbed hit (F10) — its own row; (b) after a break, refill starts
   straight after `reboot_seconds` (no extra `regen_delay`) and is full with `restored` once at
   `reboot_seconds + regen_seconds`.
5. **Slot released at lapse**: `_lapse()` clears the hurtbox slot at once (the fade is drawing only), so a projector that
   re-acquires the same ward in the fade window can `attach()` a new shield. The lapse row asserts `has_absorber()` false
   and the hurtbox reports the next hit as `received_damage` right after `lapsed`.
6. **DECISIONS.md** records for t12/t13: `face()` + initial facing `Vector2.DOWN` (call `face()` before the first
   `sustain()`), `restored()` = every refill to full, slot release at lapse, the ArmorPlate limitation, and that at the
   epic's capacity 40 one Standard shot (50) breaks the projected shield (t12 tunes).
7. `scripts/gate-time.sh` was run before (GUT 177.6 s, 1593 tests) and will be run after; both reported.
