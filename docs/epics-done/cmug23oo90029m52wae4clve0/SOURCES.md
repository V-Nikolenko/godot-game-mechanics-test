# Enemy rework, phase 10: modular damage, Heavy Gunship and Carrier — sources

The research stage left no file; the findings are in plan §1.2 (`docs/plans/cmug23oo90029m52wae4clve0/3-plan.md`). Numbers marked *judgement* in plan §2.16 are starting values, **not play-tested**.

| Source | What it contributed | Where it shows up |
|---|---|---|
| gamedeveloper.com, "11 Boss Battles of X-Morph: Defense part 5 – KM-2 Redwing" | Fewer, clearer hitboxes; component damage changes the attack pattern; last stand when all weapons die | 6 Gunship parts, 7 Carrier parts; each loss changes one visible thing |
| shmups.wiki, Battle Garegga / DonPachi | Locked parts released by killing others; core pattern change; stall backstop | Carrier core plated until 3 outer parts die; hangars hittable only with doors open; the Assault crossing leaves |
| madheadgames.com, "The Alpha: an apex of aggression"; Bloodborne Amygdala analysis (lizard-error.pages.dev) | Hard / weak / critical points; weak points where the boss attacks push aggression | Gunship vents: `hull_share` 1.0, orange glow, on the hull edge |
| ftl.fandom.com "Ship"; vigaroeentertainment.blogspot.com "FTL Analysis: Subsystems" | Subsystem damage impairs the enemy physically | Engines cut turn rate / speed and list; a battery makes one side safe |
| itch.io shmup thread (post 6895475); Raiden Fighters "Carrier Ship" (breezewiki) | An undamageable carrier is the classic complaint; the carrier hull as an arena with support craft | Core always reachable; capped launches |
| `moddb.com/features/destroying-procedural-carriers` | Death explosions only (403, read via `scripts/fetch-page.sh`) | Not used |
| Internal: `StationTurret`, `ArmorPlate`, `EnemyShield` local mode, `TurretMount`, `EnemyRounds.HEAVY_SHELL`, `LaserTender.launch_pair()`, `EnergyRing`, Ph9 `answers_emp()` | Everything reused | Plan §1.1 (S1–S14) |
| `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.5, §6.11, §7, §13.3, §14, §21–23, §26, §38, §40, §41 | The author's spec | Everything |
| Plan review (`docs/plans/cmug23oo90029m52wae4clve0/4-review.md`) | Flush-edge rule, rocket term, lit laser replay, enemy beams vs parts | Plan revision 2 (§8) |
