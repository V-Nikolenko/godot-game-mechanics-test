# Enemy rework, phase 10: modular damage, Heavy Gunship and Carrier — PRD

## The ask

> Enemy rework, phase 10 of 20. Large enemies stop using one Health bar: a generic module framework (health, armour, accepted damage types, disabled state, dark wreckage, a gameplay-consequence hook),
> generalised from the Space Station's turrets, with weak points the player finds by looking. The Heavy Gunship (112–160 px) becomes a mobile gun platform (distance, broadside, wide arcs, boost away)
> with batteries, a central cannon and rear missiles as separate modules, and phases controlled → overheat-and-vent → emergency boost with rear missiles; its retreat keeps it in the encounter. The Carrier
> (192–320 px) has engines, gun batteries, hangar doors and a core, each with its own HP: engines cost turning, a gun makes one side safe, a hangar cuts launches, an exposed core panics it; heavy cannon,
> missile bank, hangar launches, anti-approach pulse, emergency deployment; in Assault it crosses vertically as a moving arena. Both own multi-part art and damage states and replace the level-1 gunship
> spawns; the Carrier joins Assault waves and the hub's ambient spawn. Tests in both harnesses.

**Scope:** `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §13.3, §14, §26, §7, §6.11, §38, §6.5, §22, §23, §21–23 art, §40, §41 Phase 4.

**The epic's tasks:** gate room (t1); `EnemyModule` / `ModularHull` (t2); mount builder, traverse, heavy cannon (t3); Heavy Gunship shell (t4) and phases (t5); Carrier shell (t6), weapons (t7), hangars (t8);
art (t9); hub placement (t10); level-1 Heavy Gunships (t11) and Carrier (t12); docs, roster, dossier, phase record (t13).

## Player-facing goal

Big ships are fights you read and take apart. A Gunship turns a battery side-on, glows orange when it vents (the one moment its hull takes double), and boosts away firing rockets when hurt; shoot a battery
off and that side is safe. A Carrier's plated core only opens once three outer parts are wrecks; its hangars are hittable only with doors open; broken parts stay on the hull as dark wreckage.

## Scope

- **In:** `EnemyModule`, `ModularHull`, beam / nova reach of parts, `TurretMountBuilder`, mount traverse, `HEAVY_CANNON`; `HeavyGunship` (+ brain, config, phases, vents, shield, rear pod); `Carrier` (+ brain, hangars,
  pulse ring, config); 19 sprites; hub draws 19 / 20; level 1's four Heavy Gunships and one Carrier; lit-laser slice replay; docs.
- **Out (owner phase):** boss-machinery module-tied launches / phase rules (Ph18); enemy beams vs parts (Ph18 / Ph19); LOS-blocking wrecks, capital wrecks, mass rules (Ph19); EMP on the bonus drone, station and
  Ph8 structures, station onto `EnemyModule` (Ph11); encounters (Ph13 / Ph14); audio, part score, part HUD (Ph17); difficulty scaling (Ph16); level 2 beyond the rename (Ph15).
