# Research — projectile lifetime, and piercing vs armoured boss parts

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| Letting player shots **pass through an invulnerable enemy** is an accepted shmup convention, not a bug: *"If an enemy is invulnerable (shields are up, boss hasn't settled yet, etc.), don't change a thing about it. Some games let your bullets pass through during these times, which is also fine."* | Pass-through keeps parts behind the invulnerable one reachable (which the station needs) but weakens the "my shot connected" read, so the game must supply the feedback some other way. This project already does: `SpaceStation._on_received_damage` plays the hit flash and emits `armor_deflected` before returning. | n/a | [shmuptheory — The Anatomy of a Shmup](http://shmuptheory.blogspot.com/2010/02/anatomy-of-shmup.html) |
| Enemies must visibly react to being hit or players read them as invulnerable: *"Enemies should react to getting hit or else they will feel like ethereal forces rather than objects that exist in the game's world. This can take the form of simple flashing, damage particles/effects or shaking."* Also: *"Enemies should have big hitboxes."* | Big hurtboxes + always-visible reaction is the opposite of hiding armour by removing collision. Confirms the existing rule (`test_enemy_hurtbox_geometry.gd`): armour is a damage rule on a full-size hurtbox. | n/a | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog%27s_bullet_hell_shmup_101) |
| **Piercing is a weapon's distinguishing property with a cost, not a baseline.** The laser archetype *"makes up for it with sheer power and the ability to shoot through multiple solids"* — it pays for penetration with a narrow profile and precise aiming, while the spread shot buys coverage with lower per-bullet damage. | If the *default* gun already pierces infinitely, the whole weapon-choice axis collapses and a dedicated pierce upgrade has nothing left to grant. That is exactly this project's `PierceModule` state today. But un-piercing the default gun is a **balance change across every encounter**, not a lifetime fix. | Spread trades damage for coverage; homing trades damage for zero aiming | [SLYNYRD — Pixelblog 32, Shmup Design Part 2](https://www.slynyrd.com/blog/2021/2/15/pixelblog-32-shmup-design-part-2) |
| The **cores-and-turrets boss** — a hull whose core only becomes vulnerable once its turrets are destroyed — is a named genre archetype (a Compile trademark, from *Zanac* onward), and the standard is that turret count drives the fight's escalation. | The archetype only works if the player can reach the turrets. Any change that lets the hull absorb the shot aimed at a turret breaks the archetype, not just this one boss. | Compile bosses: several cores + turrets, fire rate rises as they die | [TV Tropes — Cores-and-Turrets Boss](https://tvtropes.org/pmwiki/pmwiki.php/Main/CoresAndTurretsBoss) |
| `VisibleOnScreenNotifier2D` emits `screen_exited` *"when no part of it remains visible"*, **relies on render culling** and so needs `CanvasItem.visible == true`, and takes **one frame** after entering the tree before its visibility is determined (`is_on_screen()` returns `false` before the first draw pass). | Cheap and needs no arena constants — but it is a *render* signal, so it silently does nothing for a node that is hidden, and it can never fire for one that was never drawn. A projectile that must despawn regardless (e.g. behind a disabled canvas) needs a bounds or lifetime check instead. `EnemyBullet` already chose explicit arena bounds for that reason (`enemy_bullet.gd:6-16`). | 1 frame before `is_on_screen()` is meaningful | [Godot docs — VisibleOnScreenNotifier2D](https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html) |
| The Godot recipe for despawning projectiles is exactly *"add a `VisibleOnScreenNotifier2D` and connect its `screen_exited` signal"* → `queue_free()`. In Godot 4 node creation is cheap enough that pooling should follow a profiler measurement, not precede it. | Confirms the fix shape and argues **against** widening this task into "pool the player's bullets too" — the leak, not the allocation rate, is the defect. | n/a | [Godot 4 Recipes — Entering/Exiting the screen](https://kidscancode.org/godot_recipes/4.x/2d/enter_exit_screen/index.html), [Object pooling in Godot](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/) |

## What this means for the plan

1. The **leak** is unambiguous and has an off-the-shelf fix that the project already ships twice
   (`warhead_missile.gd:19-20`, `homing_missile.gd:47`): unpooled player projectile frees itself on
   `screen_exited`.
2. The **pass-through-on-hit** behaviour is *defensible as a design*, and it is load-bearing for
   the station boss. It should therefore stop being an accident of `range_px = 0.0` and become a
   stated, gated rule.
3. Whether the **default** gun should pierce *damageable* targets is a genuine balance question
   with a clear genre answer (no — piercing is what an upgrade buys). It is not a lifetime bug and
   it changes every encounter in the game, so it is a separate decision and a separate task.

## Judgement calls with no citable source

- No source found on whether a projectile should be consumed by an overlap that dealt **zero**
  damage. The genre convention above (pass through invulnerable enemies) is the closest analogue
  and points the same way; treat the "consume on first *damaging* hit" refinement as a design
  proposal, not a documented standard.
