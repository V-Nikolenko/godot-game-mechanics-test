# Laser Emitter — a destructible laser fence post

**Role:** One of the two posts of a [laser fence](../../structures/laser_fence/STRUCTURE.md). It never moves or fires on its own; the fence draws its
beam between two of them. Shooting one drops the whole fence.
**Fantasy / threat:** A pylon with a red lens. The wall between two pylons is lethal, but each pylon is a cheap target: the answer to a fence is the
post, not the gap.

> **Build state (Phase 8, t10).** Built with `LaserFence`. The art task (t15) replaces the code-drawn placeholder; the hub site (t18) and level 1 (t19)
> place fences. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.11.

---

## Stats

| Property | Value |
|---|---|
| HP | 140 (`laser_emitter_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 0: `ContactProfile` NONE and **no `ContactHitBox`** (the power source / turret precedent) |
| Speed | none: no brain, no `EnemyMover`, no `AssaultDrift` of its own — the fence's `AssaultDrift` carries both posts in Assault |
| Body | one `CircleShape2D` r 18 shared by the body (layer 1) and the `HurtBox` (layer 512, mask 65) |
| Sprite | placeholder, code-drawn: a dark post disc with a red lens. The art task (t15) replaces it |
| Scene / config | `laser_emitter.tscn` / `laser_emitter_config.tres` (flat `LaserEmitterConfig`, no extra fields) |
| Score | 40; **`counts_as_escape` false**, so a post that drifts off the bottom never breaks the combo |

---

## Behaviour

- **No behaviour of its own.** It has no brain. It joins group `enemies` in `_ready()`, refuses tows (no mover) and answers `is_laser_blocking()` false,
  so the player's mining beam treats it as a target.
- **`is_fence_post() -> true`.** A `ShieldGenerator` skips anything that answers it, and a fence is not a `BaseEnemy` member of its group anyway, so a
  post is **never shielded**, even inside a defended site: shooting a post stays the cheap counterplay.
- **Owned by its fence.** The fence adds both posts to its owner group (a turret group's, else its own `laser_fence_<id>`), so the fence's beam never
  hurts them, and drives the post's `StateLight` (CHARGING while the fence warns, ARMED while it burns, OFF otherwise or when dark).
- **Death.** `died` is emitted before the explosion, so the fence collapses its beam in the same call. The explosion particles spawn into the post's
  parent — the fence — which is why the fence lingers after its last post.
