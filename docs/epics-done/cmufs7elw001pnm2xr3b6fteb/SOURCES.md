# Enemy rework, phase 5 — sources

From `docs/plans/cmufs7elw001pnm2xr3b6fteb/2-research.md` (§1 findings F1-F13) and `1-context.md`. Doom wiki pages returned 403 directly
and through `scripts/fetch-page.sh`; their claims are not relied on. Values with no citable source are **[judgement]**.

| Source | What it contributed | Where it shows up |
|---|---|---|
| https://starsector.wiki.gg/wiki/Harpoon_MRM | Launch speed accelerating to cruise, 30 deg/s turn, finite flight time; a 2:1 speed ratio against the target is dodgeable | Pursuit rocket: boost then accelerate, `turn_rate` 1.6 rad/s for `guidance_seconds` 3.0, `max_time` |
| https://starsector.wiki.gg/wiki/Hurricane_MIRV_Launcher | MIRV splits on closing with the target; killing the parent kills the submunitions; fewer, more accurate submunitions read better | Cluster rocket: splits at 260 px or 2.0 s into 4 submunitions, nothing if shot first |
| https://starsector.wiki.gg/wiki/Flare_Launcher ; https://acecombat.wiki.gg/wiki/Flares | Rationed flares draw missiles | Recorded as out of scope (no player countermeasure); the aim-point function is the hook |
| https://www.red3d.com/cwr/steer/gdc99/ ; https://www.red3d.com/cwr/steer/LeaderFollow.html | Pursuit with look-ahead, offset pursuit, leader following | Rocket guidance on the predicted path (`lead_max`); the Support Ship's soft anchor and stepping aside; the Warhead pair offset across the path |
| https://www.moddb.com/features/flint-lead-pursuit-guidance-principles | Lead pursuit principles | Predicted aim points in the salvo |
| https://kidscancode.org/godot_recipes/3.x/ai/homing_missile/ | Clamped steering so a missile does not turn on a dime | A degrees-per-second cap in `Steering.turn_toward`, asserted against acceleration |
| https://descentbb.net/viewtopic.php?t=9962 | Homers became undodgeable at high frame rates | Guidance runs on accumulated physics `delta`; tested on the 8x clock |
| https://shmups.wiki/library/Help:Dodging_strategy | Dodging conventions for shmups | Rockets are slower and brighter than rounds and outrunnable |
| https://www.halopedia.org/Energy_shielding | Regen starts after a pause and refills over seconds; visible recharge | `EnemyShield` `regen_delay` 3.0, `regen_seconds` 1.5, `reboot_seconds` 4.0, cyan arc |
| https://wiki.warframe.com/w/Shield_Osprey | A shield-granter shows its link with a tether and attacks only when idle | Cyan tether; the Support Ship has no weapon |
| https://wiki.warframe.com/w/Deimos_Ancient_Healer ; https://riskofrain2.fandom.com/wiki/His_Reassurance | Healers need rate limits and a budget; do not heal other healers | `repair_period` 1.5 s, `repair_fraction`, `repair_budget` 150, supports never wards |
| https://www.halopedia.org/Huragok | Support units that keep others fighting | Role framing for the Support Ship |
| Hub: corvette ring 1900 px at 315 deg, radii 720 / 1500; support radii 600 / 1300 | Plan start values | Asserted by `test_sector_hub_patrol.gd` |
| Level 1 density: <= 2.5x the frozen specialist peak; measured peaks 7 of 12.5 / 7 of 7.5 / 6 of 10 | The plan's bound | `test_level1_specialist_spawns.gd` |
