# Research — enemy/boss hurtbox geometry and "armoured core" bosses

Question being researched: is a boss body hurtbox that is **smaller than the boss sprite** a
shipped-genre technique, and if the fantasy is "shoot the guns, then the core", how do shipped
games keep the parts and the body legible?

| Finding | Tradeoff it implies | Typical values | Source |
|---|---|---|---|
| **The small-hitbox rule is a *player* rule and it inverts for enemies.** "Enemies should have big hitboxes and slower predictable movement. Dense and difficult bullet patterns make up most of the challenges in danmaku games, so making enemies needlessly elusive and difficult to hit will likely cause frustration for the player." | Generous enemy hitboxes cost some of the "skilled aim" feeling; the genre pays that price deliberately and buys difficulty back with bullet density instead. A boss you can miss *while aiming at it* is the frustration this warns about. | Player hitbox ~1x1 px in modern shmups vs a full-size sprite; enemy hitbox at or near sprite bounds | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101) |
| **An enemy that does not visibly react to a hit reads as unreal.** "Enemies should react to getting hit or else they will feel like ethereal forces rather than objects that exist in the game's world. This can take the form of simple flashing, damage particles/effects or shaking." | A reaction on a *no-damage* hit (the station's armour flash) slightly muddies "did that hurt it?" — but the alternative failure, no reaction at all, is the one the genre names as fatal. The fix for the ambiguity is to make the deflect reaction *different* from the damage reaction, not to delete the hurtbox. | — | [Boghog's bullet hell shmup 101](https://shmups.wiki/library/Boghog's_bullet_hell_shmup_101) |
| **The canonical "armoured core" boss guards its core with *objects*, not with absent collision.** Gradius core warships are "large warship bosses with one or more energy cores housed within, usually (if not always) **guarded by a series of small walls or force fields the player must break through** before they can attack the cores themselves." The Gunwall family's tagline is literally *"Take out the defenses, and shoot the Core!"* | Armour-as-object gives unambiguous feedback (the shot stops, the wall reacts, the wall can be destroyed) at the cost of an extra HP pool and extra art. Armour-as-missing-hurtbox is free but gives the player nothing to read — the shot simply vanishes. Every reference implementation pays for the former. | Cores change colour blue -> red near death; destroying one core disables the part it powered | [Gradius Wiki — Bosses](https://gradius.fandom.com/wiki/Bosses) |
| **Destructible boss parts are a deliberate design dimension, not free decoration** — "one of the easiest, but also most fun, ways to add scoring potential to a boss is to add destructable parts to it." | Every part is another bar the player has to empty, and the guide frames them as a *scoring* layer bolted onto a boss that is already killable. This project's active `boss-fight-escalation` epic is moving the opposite way — one shared pool — so parts here must stay *consequences*, not gates. | — | [Giest118's Guide to Making Good Bullet Hell Bosses](https://shmups.system11.org/viewtopic.php?f=9&t=44816) (retrieved via `scripts/fetch-page.sh`; direct fetch 403s) |
| **Hitbox dissonance — a sprite that visibly overlaps but does not register — is a named, player-visible defect.** Search-index summaries of TV Tropes' *Hitbox Dissonance* and of player threads describe hits that look like they connect but do not, and hitboxes that do not match the visual, as reading "annoying rather than difficult" and "poorly done". | The symmetric complaint exists for hitboxes that are too *large*, so "bigger is always better" is not the lesson; "match what the player can see" is. | — | **Source not verifiable.** `tvtropes.org/.../Main/HitboxDissonance` returned 403 to both a browser User-Agent and the reader proxy; `en.namu.wiki`'s *core-type boss* article returned a CAPTCHA interstitial. Recorded here as a search-index summary only, not quoted as fact. |

## What the genre does *not* do

Nothing found describes a boss whose visible hull has **no collision response at all** across a
quarter of its width. The two shipped idioms are:

1. **Armour as a destructible object** (Gradius walls / force fields) — the shot stops, something
   reacts, and the obstacle can be removed.
2. **Armour as a damage rule on a full-size hurtbox** — the shot registers, plays a "clang", and
   deals 0. This is what `space_station.gd::_on_received_damage` already implements.

The 88 x 240 proposal is a third thing — **armour as absence** — and it is the only one of the
three the player cannot perceive.

## In-repo evidence, which outranks all of the above for this decision

- Commit `501d662`, "Give every contact hitbox the hull the player can see", and its gate
  `tests/integration/test_contact_hitbox_geometry.gd`: the project has already ruled that a
  collision box smaller than the visible ship is a **defect**. The gunship shipped with an 18 px
  ram box on a 41.5 px hull and "62 % of the heaviest ship in the roster passed through the
  player like a ghost".
- Ten of ten assault enemies give their `HurtBox` the body's own `Shape2D` at the same scale
  (measured in `1-context.md`).
- Active epic `boss-fight-escalation-...`, task 1: *"Every shot that lands on the station hurts
  the station."*

## Judgement calls, labelled as such

- No source was found that measures the *readability cost* of a boss body that flashes on a hit
  which also damages a part. Finding 2 above is the closest evidence, and it argues for keeping
  the reaction. The conclusion that the double flash is acceptable is a **judgement call**.
- No source was found for a "minimum visible-hull coverage" threshold. The 1 px tolerance chosen
  in the plan is derived from the repo's own smallest projectile radius, not from a citation.
