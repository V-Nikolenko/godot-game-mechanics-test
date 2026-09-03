# global/systems/event_bus.gd
## Centralized event bus for decoupling gameplay systems from UI.
## Subscribe here instead of querying the player via get_nodes_in_group().
## Registered as an autoload named "EventBus" in project.godot.
extends Node

# ── Player health & shield ────────────────────────────────────────────────────

## Emitted whenever the player's health value changes (including on death).
signal player_health_changed(current: int, maximum: int)

# ── Overheat ──────────────────────────────────────────────────────────────────

## Emitted every 0.1 s with the current heat percentage (0.0 – 100.0).
signal player_overheat_changed(percentage: float)

# ── Weapons ───────────────────────────────────────────────────────────────────

## Emitted when the player switches main weapon mode.
signal player_weapon_changed(mode: WeaponModeResource)

## Emitted when the player switches sub-weapon (rocket type).
signal player_rocket_changed(icon: Texture2D)

# ── Player lifecycle ──────────────────────────────────────────────────────────

## Emitted when the player dies (health reaches zero).
signal player_died

# ── Abilities ─────────────────────────────────────────────────────────────────

## Emitted when an ability is activated.
signal ability_activated(id: StringName, damage_mult: float, fire_rate_mult: float)

## Emitted when an ability is deactivated / deselected.
signal ability_deselected

# ── Mission events ────────────────────────────────────────────────────────────

## Emitted when a new wave starts in an assault mission.
signal mission_wave_started(wave_index: int)

## Emitted when the current mission is completed successfully.
signal mission_complete

## Emitted when the current mission is failed.
signal mission_failed

# ── Scoring ───────────────────────────────────────────────────────────────────

## Emitted whenever the running mission total score changes.
signal score_changed(total: int)

## Emitted whenever the combo multiplier or its decay timer changes.
## decay_remaining is seconds left before combo resets to x1; 0 when combo == 1.
signal combo_changed(multiplier: float, decay_remaining: float)

## Emitted for every individual scoring event so popups / SFX can react.
## reason is one of "kill", "wave_clear", "survival", "skill_clean",
## "skill_partial", "bonus_target".
signal score_event(world_position: Vector2, points: int, reason: String)

## Emitted by SkillChallengeRunner at the end of a challenge window.
signal skill_challenge_completed(clean: bool, bonus: int)

## Emitted when an enemy is spawned OUTSIDE the WaveManager flow — e.g. a big
## asteroid splitting into smaller ones, or a script-spawned medal. ScoreTracker
## subscribes here so the resulting kill still awards points.
signal enemy_spawned_orphan(enemy: Node)
