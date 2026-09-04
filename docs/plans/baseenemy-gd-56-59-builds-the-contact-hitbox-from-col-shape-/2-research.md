# Research — contact hitbox sizing, and how to size a shape from code in Godot 4

Two questions from `1-context.md`: (1) is a full-size enemy contact box right for a shmup, and
(2) is copying a `CollisionShape2D`'s `scale` a legitimate construction in Godot 4?

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| The genre splits hitboxes deliberately and asymmetrically. Verbatim: *"Generally, the hit box for the player is a small circle placed center mass of the sprite… Player bullets, and enemy sprites have generous bounds to ensure your aim always feels solid, and fair."* And: *"I would avoid making the player hit box so large it extends beyond the actual pixels of the sprite. That just never feels like a fair challenge."* | The rule constrains the **player's** box, not the enemy's. Sizing enemy bounds to the visible ship is the stated norm; the cost is that players who currently treat an enemy's sprite edge as safe space lose that. | Player box: a small circle at centre of mass. Enemy bounds: "generous". | [SLYNYRD Pixelblog 63 — Horizontal Shmup](https://www.slynyrd.com/blog/2026/7/26/pixelblog-63-horizontal-shmup) |
| The player-side box is tiny by convention, and that is what makes generous enemy bounds fair. Verbatim: *"In most early shmup games, the hitbox was about the size of the player sprite. In most modern shmups, the hitbox is about 1X1 pixels in size, allowing the player to squeeze through rows of very close bullets."* | A tiny player box plus true-size enemy bodies is the balanced pair. Shrinking the enemy side **as well** (what this codebase does by accident) makes contact damage nearly unreachable rather than merely forgiving. | Player hitbox ≈ 1×1 px in modern shmups. This project's player `HurtBox` is radius 5.0 × scale 2.7 = **13.5 px** against a 2.7-scaled sprite — already firmly on the "small" side of the convention. | [Shmup Wiki — Hitbox](https://shmup.fandom.com/wiki/Hitbox) |
| **Godot's own guidance is not to scale collision shapes.** Verbatim: *"Godot does not currently support scaling of physics bodies or collision shapes. As a workaround, change the collision shape's extents instead of changing its scale… Since resources are shared by default, you'll have to make the collision shape resource unique if you don't want the change to be applied to all nodes using the same collision shape resource in the scene."* | Baking extents is the docs-blessed route, but it needs per-`Shape2D`-subclass code (`CircleShape2D.radius` vs `RectangleShape2D.size` vs capsules), allocates a duplicated resource per spawn, and **cannot represent a non-uniform scale on a circle at all**. Copying the node transform is shape-agnostic and one line, at the cost of relying on behaviour the docs discourage. | — | [Godot docs — Troubleshooting physics issues](https://docs.godotengine.org/en/stable/tutorials/physics/troubleshooting_physics_issues.html) |
| The open Godot report that sounds like "scaled collision shapes are wrong" is not about collision maths. It reports that *"depending on window/resolution/scaling settings, it's like the collision shape is located a bit bellow the shape that is drawn"*, disappears in exclusive fullscreen and disappears when the viewport is shrunk by one pixel — i.e. a debug-draw alignment artefact of window scaling. Still open, no maintainer diagnosis. | It removes the strongest-looking argument against transform-copying, but it is an open issue rather than a confirmation that scaling is fine. Weight it as "not evidence against", not as "evidence for". | — | [godotengine/godot#117813](https://github.com/godotengine/godot/issues/117813) |

## What this means for the design

**On sizing:** the convention is a small player box against generous enemy bounds. This project
already has the small player box (13.5 px). The enemy side is currently *also* shrunk — by an
accident of construction rather than a decision — so the pairing is small-vs-small and contact
damage lands far inside the visible hull. Restoring the enemy side to the size the scene author
drew is the convention-conforming direction, not a difficulty increase invented here.

**On construction:** the docs say don't scale, bake extents instead. But this codebase **already
scales collision shapes everywhere** — every affected scene's sibling `HurtBox` collision node
carries the same scale as the body's (`gunship.tscn:74` 2.289, `interceptor.tscn:73` 1.8,
`light_assault_ship.tscn:88` 2.2, `drone_interceptor.tscn:72` 3.08), and so does the player's own
`HurtBoxCollision` (`player_fighter.tscn:342`, scale 2.7). Those hurtboxes demonstrably work —
they are what every enemy is killed through. So:

- Following the docs literally would mean the enemy's **hurtbox stays scaled** while its
  **hitbox bakes extents**, i.e. two different constructions for two boxes that are meant to
  describe the same hull. That is worse to maintain and easy to get out of step.
- Every scale in play is **uniform** (`Vector2(s, s)`), which is the case where a transformed
  circle or rect is exactly representable. The docs' warning bites hardest on non-uniform scale,
  which no scene here uses.

Judgement call, stated plainly: **copy the node transform**, matching the authoring the scenes and
the player already rely on, and add a test assertion that fails if anyone ever introduces a
*non-uniform* scale on one of these body collision shapes — that is the case Godot genuinely
cannot represent, and it is cheap to guard.

## Not researched

No source was found on whether a *ramming* enemy specifically should have tighter bounds than its
hurtbox. Treated as out of scope: this change restores the size the scene declares, and any
deliberate "ram box is smaller than the hull" tuning would be new design, not a bug fix.
