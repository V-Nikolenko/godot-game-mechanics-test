# Contact hitboxes: type them CONTACT, not LASER

## Problem

Nothing the player experiences today is wrong — the player's `HurtBox` accepts every damage type,
so this is invisible. But every ram/contact `HitBox` the game builds in code
(`HitBox.matching_shape()`, used by the generic enemy ram box, the drone interceptor, the kamikaze
drone, and the ally fighter) is silently mistyped as `LASER` damage, because `matching_shape()`
never sets `damage_type` and the `HitBox` default is `LASER`. The one hand-authored contact hitbox
in the project (`asteroid_base.gd`'s `$ContactHitBox`) is explicitly set to `CONTACT` in
`_ready()`, so the code-built path disagrees with the hand-authored one for no reason. The moment
any future enemy or armour piece wants to resist or react to contact damage specifically (e.g. a
laser-immune shield that should still take ram damage), it will silently also become ram-immune,
because the two damage types are indistinguishable in the data.

## Design

Add an optional `damage_type` parameter to `HitBox.matching_shape()`
(`global/components/hitbox_component.gd`), defaulting to `HitBox.DamageType.CONTACT`:

```gdscript
static func matching_shape(
	source: CollisionShape2D, layer: int, mask: int, dmg: int,
	dmg_type: DamageType = DamageType.CONTACT
) -> HitBox:
	var hb := HitBox.new()
	hb.collision_layer = layer
	hb.collision_mask = mask
	hb.damage = dmg
	hb.damage_type = dmg_type
	...
```

Defaulting to `CONTACT` rather than adding an explicit argument at all 4 call sites is deliberate:
every existing caller builds a *ram* hitbox (that is what `matching_shape()` is for — the doc
comment on it is entirely about contact-hitbox geometry), so `CONTACT` is correct for all of them
with zero call-site changes, and a future caller that genuinely needs a different type (none exist
today) can still pass one explicitly. This also means no behaviour at any of the 4 call sites
needs to change beyond the type tag — `1-context.md`'s grep confirms no `HurtBox` anywhere
currently filters in a way that distinguishes `LASER` from `CONTACT` for these targets, so this is
a pure correctness fix with no observable gameplay change today.

### Alternative considered and rejected

Setting `damage_type = CONTACT` explicitly at each of the 4 call sites, leaving `matching_shape()`
untouched. Rejected: it repeats the same line 4 times for a function whose entire purpose is
building contact hitboxes, and a 5th future call site (which `test_contact_hitbox_geometry.gd`'s
own doc comment already anticipates — "this file is what keeps a fifth call site from getting it
wrong again") would default back to `LASER` and reintroduce the exact bug this task fixes. A
default on the factory closes the hole permanently instead of for four call sites.

## Build sequence

1. Add the failing test first: in `tests/integration/test_contact_hitbox_geometry.gd`, add
   `test_every_contact_hitbox_is_typed_as_contact_damage()`, reusing the existing `ROSTER`,
   `_spawn()` and `_contact_hitbox()` helpers (skip `no_hitbox` entries exactly like the existing
   geometry test does). Assert `hb.damage_type == HitBox.DamageType.CONTACT` for each. Run it and
   confirm it fails against current code (10 of 11 roster entries typed `LASER`).
2. Change `HitBox.matching_shape()` in `global/components/hitbox_component.gd` to add the
   `dmg_type: DamageType = DamageType.CONTACT` parameter and set `hb.damage_type = dmg_type`.
3. Re-run the new test and the full `test_contact_hitbox_geometry.gd` file — confirm green and
   that the existing geometry assertions are untouched.
4. Run the full GUT suite and the resource-UID/project-load integrity gates
   (`bash /agent/verify.sh`) to confirm nothing else regresses — in particular
   `tests/unit/test_hitbox_hurtbox.gd::test_hitbox_defaults()`, which pins bare `HitBox.new()` at
   `LASER` and must stay green since that default is untouched.

Each step is independently small and testable; there is no step that isn't trivially reversible.

## Test plan

- `tests/integration/test_contact_hitbox_geometry.gd::test_every_contact_hitbox_is_typed_as_contact_damage`
  (new): for every non-`no_hitbox` roster entry (10 entities: `ally_fighter`, `bomber`,
  `drone_interceptor`, `gunship`, `interceptor`, `kamikaze_drone`, `light_assault_ship`,
  `ram_ship`, `space_station`, `sniper_enemy`), assert the contact `HitBox`'s `damage_type` is
  `HitBox.DamageType.CONTACT`.
  - Boundary case covered by the existing roster for free: `kamikaze_drone` and
    `drone_interceptor` are the two call sites that pass a non-default `mask` (128, for detecting
    the player `HurtBox` directly) — proving the default `damage_type` argument still applies when
    other optional/positional arguments are already in use at the call site.
- No existing test needs to change: `test_hitbox_hurtbox.gd::test_hitbox_defaults()` exercises
  `HitBox.new()` directly, not `matching_shape()`, so it is unaffected and stays as the pin for the
  *bare* constructor default.

## Risks

- None identified for current behaviour (see `1-context.md`'s grep). The only real risk is future:
  if a later change adds a `HurtBox` that filters specifically on `LASER` and expects a ram
  hitbox to pass that filter, it would now correctly fail to — which is the point of the fix, not
  a regression.

## Out of scope

- Any change to `HurtBox.accepted_damage_types` filtering logic.
- Any change to the 3 hazard `HurtBox`es already filtering on `ROCKET`.
- Any change to `asteroid_base.gd`'s hand-authored `$ContactHitBox` (already correct).
- Adding contact-damage resistance/immunity gameplay — out of scope per the task body, which frames
  this purely as fixing dead/misleading metadata.
