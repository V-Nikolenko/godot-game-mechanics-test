# Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship — PRD

## The ask

> Enemy rework, phase 5 of 20. This phase finishes the specialist tier with two enemies that change how a fight reads without adding
> another bullet stream: an enemy rocket threat and a support unit. The enemy rocket family (Dumb Rocket, Pursuit Rocket, Cluster
> Rocket, Delayed Warhead) has a visible launch, an acceleration phase, mild steering toward the player's future path, and an
> explosion radius. Rockets can be outrun, out-turned, shot down, or made to hit other enemies and the environment. The Missile
> Corvette holds medium range on broad arcs and fires predicted salvos. The Support/Shield Ship stays behind the highest-threat ally
> on a soft formation anchor, repairs allies with a beam, projects a directional shield arc onto another enemy and runs an emergency
> escort that pulls a low-HP ally away. It has low HP and high evasiveness, switches target when its ally dies, and in Assault its
> range is clamped so it cannot hide above the camera. This phase settles the deferred question of adopting DamageReaction with
> Shield support for enemies, and introduces enemy shields as a temporary resource (directional, local-module, regenerating,
> projected bubble), not a second health bar. Both enemies are added to existing Assault waves and to the hub's ambient spawn, with
> strict top-down 72-112 px sprites and the support ship's unfolding projector state. Tests in both harnesses cover rocket steering
> toward the predicted point, splitting and proximity detonation, repair and shield application, retargeting when an ally dies, and
> the escort trigger.

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.1 Missile Corvette; §6.2 Shield/Repair Ship; §11.2 the rocket family except the
Hijack Pulse; §13.2 shields on enemies including the DamageReaction decision; §23 and §21-23 sprites; §40 tests in both modes; §41
Phase 3 items 4-5; the §37 Support + Ram combination made possible (not an encounter director).

## As finally understood

- Rockets are enemy ordnance whose **impact** hurts enemies, ordnance, Ram plates and asteroids, and whose **blast** is the player's
  only damage from them; a player projectile and a rocket destroy each other.
- Enemy shields are a hurtbox-side absorb hook plus one component, not an adoption of the racer `DamageReaction`.
- "Support + Ram" means a Ram is an eligible ward and the hub's Support shares the hub Ram's anchor.
- Out: warning audio, flare/decoy reactions, the Hijack Pulse, owner-distance lifetime, blast/beam friendly fire, shipped module shields.
- Gate budget: the phase needed room, so t1 freed at least 70 s of GUT time before anything else; GUT must stay <= 240 s.

## Acceptance for the closing task (t18)

Every listed doc names the new classes by their real names and paths; `DECISIONS.md` has the as-built section with every deviation; this
dossier's three files exist; the gate is green.
