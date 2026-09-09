# Test logs on the open-space map

## Problem

`LogState`, the ESC-menu Lore Logs reader, and `InfoLogInteractable` are all built and unit-tested,
but nothing in any actual level places a `LoreLogPickup` (the class does not exist yet — see
`1-context.md`), and `sector_hub.tscn` places none of either log type. A player who boots the game
and flies the hub today cannot find a single log record there, cannot see the collectible counter
move, and cannot see the ESC Lore Logs section hold anything other than "0/0, nothing found". This
task makes the whole system demonstrable in the one place the player actually free-roams.

## Design

### 1. Build `LoreLogPickup` (prerequisite — see `1-context.md` for why)

Reused verbatim from the sibling task's twice-reviewed design:

```gdscript
# global/pickups/lore_log_pickup.gd
class_name LoreLogPickup
extends PickupBase

## Grants the next lore-log entry in catalogue order (LogState.collect_next()). Anonymous by
## design: LogState decides which entry a collection grants, not the pickup — see LogState's
## own docstring for why placement order must not control reading order.

var _collected_id: StringName = &""

func _collect(_player: PlayerBase) -> void:
	_collected_id = LogState.collect_next()

func _get_dialog_text() -> String:
	if _collected_id == &"":
		return ""  # catalogue already exhausted - LogState.collect_next() was a no-op
	var entry := LogState.get_entry(_collected_id)
	if entry == null:
		return "Log recovered."
	return "Log recovered: %s" % entry.title
```

No `@export` field — `LogState.collect_next()` takes no id and this pickup has nothing else to
configure, unlike `ShipModuleUnlockerPickup`/`WeaponModeUnlockerPickup`.

**Scene** `global/pickups/scenes/lore_log_pickup.tscn`: copy
`global/pickups/scenes/weapon_mode_unlocker_pickup.tscn`'s shape — `Area2D` root
(`collision_layer = 16`, `collision_mask = 4`, script attached), `Sprite2D` child with the new
texture, `CollisionShape2D` child (`CircleShape2D`, radius 8, scaled to match sprite size).

**Sprite** `global/assets/sprites/lore_log.png` — a small glowing sci-fi datapad, top-down
orthographic (`pixel-art-generation` skill, `create_map_object`, 64×64 to match
`ship_module_unlocker.png`/`upgrade_1.png`).

### 2. `tests/unit/test_lore_log_pickup.gd`

Same pattern as `tests/unit/test_info_log_interactable.gd` / the fixture setup in
`tests/unit/test_log_state.gd`. Points the live `LogState.catalogue_dir` at
`tests/unit/fixtures/log_entries` (3 entries: alpha/beta/gamma) for the duration of the test.

- `before_all`: `SaveSandbox.capture()`, snapshot `LogState.catalogue_dir`.
- `before_each`: `LogState.catalogue_dir = FIXTURE_DIR`, `SaveSandbox.clear_all()`,
  `LogState._load_catalogue()`, `LogState._load()`.
- `after_all`: restore `catalogue_dir`, reload, `SaveSandbox.restore()`.

Cases:

1. **Colliding with the pickup collects the next entry and advances `LogState`.** Instantiate
   `LoreLogPickup`, call `_collect(PlayerStub.spawn())`, assert
   `LogState.collected_count() == 1` and `LogState.is_collected(&"entry_beta")` (lowest
   `sequence` in the fixture set).
2. **The notification names the entry.** After the same collect, assert
   `pickup._get_dialog_text()` contains `"Test Entry Beta"`.
3. **Boundary — collecting after the catalogue is exhausted does not double-count.** Drain the
   3-entry fixture catalogue via three direct `LogState.collect_next()` calls, then `_collect()` a
   fourth `LoreLogPickup`: assert `LogState.collected_count()` is unchanged (still 3) and
   `_get_dialog_text() == ""` (no false notification).
4. **`_on_body_entered` wiring** — sibling task's round-2 review option (a), applied precisely
   (not option (b), which — as round 2 itself already found for this exact call chain — does NOT
   avoid the coroutine when applied to a call that reaches `_show_notification()` with non-empty
   text): before calling `_on_body_entered`, pre-set `DialogPlayer.is_active = true` so
   `_show_notification()`'s existing guard (`pickup_base.gd:63` — skip `play()` when a dialog is
   already active) short-circuits and `DialogPlayer.play()` is never called at all. Add the
   pickup as a child (`add_child_autofree`), call `_on_body_entered(PlayerStub.spawn())` once,
   assert the pickup `is_queued_for_deletion()` and `LogState.collected_count() == 1` (the effect
   still applies — only the notification is skipped), then reset `DialogPlayer.is_active = false`
   in `after_each` so the guard doesn't leak into later tests. `PickupBase`'s own generic
   signal-to-`_collect`-to-`queue_free` dispatch is already covered by
   `tests/unit/test_pickup_base.gd`, so this case only needs to prove `LoreLogPickup`'s override
   is reached through the real signal path with the notification guarded off, not re-prove the
   dispatch itself.

This sidesteps both review rounds' objection entirely: `DialogPlayer.play()` is never called by
any case in this file, so no coroutine is ever started, so `scripts/check-test-leaks.sh` has
nothing to catch. (Case 1-3's direct `_collect()` calls never reach `_show_notification()` at
all — only case 4 calls `_on_body_entered()`, and it does so with the guard pre-armed.)

### 3. Lore-log catalogue content — `global/resources/logs/entries/`

Three new `LogEntryResource` `.tres` files (the directory does not exist yet; creating it and
putting files in it *is* the entire catalogue-registration step, per `LogState`'s own docstring —
nothing else needs updating). Real flavour text consistent with locations already named in
`sector_hub.tscn` (`edelia.tres`, `voeter_k05m.tres` planet configs, `fortuna_station.tres`):

| file | id | sequence | title |
|---|---|---|---|
| `log_beacon_static.tres` | `beacon_static` | 0 | "Beacon Static" |
| `log_edelia_survey.tres` | `edelia_survey` | 1 | "Edelia Survey, Entry 12" |
| `log_fortuna_manifest.tres` | `fortuna_manifest` | 2 | "Fortuna Station Manifest" |

Bodies are short (2-4 sentences), first-person or terse-log-style, naming the sector/planets the
hub already shows the player (`edelia`, `voeter_k05m`, `fortuna_station`) — not placeholder text.

### 4. Place pickups and interactables in `sector_hub.tscn`

Add both `LoreLogPickup` (new `ext_resource`) and a second instance reference to the existing
`InfoLogInteractable` scene (`id="21_ilog"`-style `ext_resource`, reusing the one already at
`uid://bgtlo5mhub0mh`) as sibling nodes under `SectorHub`, same pattern as the 19 existing pickups.

**3 lore logs** (`LoreLogPickup`, no `@export` to set):

| node name | position | why here |
|---|---|---|
| `LoreLogBeaconStatic` | `(620, -212)` | Extends the existing pickup row past its rightmost occupant (`TemporaryDamageUpPickup` at `519, -210`) with clearance for each pickup's ~25px-radius collision circle — the original `(420, -212)` draft would have overlapped `ShipShieldUpPickup` at `(413, -212)` almost completely. Found on the direct mission-select path, the "easy" one. |
| `LoreLogEdeliaSurvey` | `(720, 420)` | Off the row, near the `edelia` planet (`(595, 342)`) — requires flying to the planet arc. |
| `LoreLogFortunaManifest` | `(-700, 460)` | Near `fortuna_station` (`(-635, 385)`) — the opposite corner of the hub from the pickup row. |

**2 information logs** (`InfoLogInteractable`, `message` set per instance):

| node name | position | message | why here |
|---|---|---|---|
| `InfoLogHubTerminal` | `(0, -150)` | "Sector hub maintenance terminal: all patrol drones nominal. Somebody left the coffee dispenser running for six years." | Just off the mission-select lane — easy to stumble into. |
| `InfoLogVoeterWreck` | `(-480, -300)` | "Salvaged hull plate, drifting near Voeter K05M: scorch pattern doesn't match any registered weapon signature." | Near `voeter_k05m` (`(-530, -384)`) — requires leaving the mission-select lane entirely, the far side of the hub from spawn. |

Together, 2 of the 5 records sit in the existing pickup row and 3 sit near the planets/station —
satisfying "spread them so at least one requires actually leaving the mission-select lane" many
times over, not just once.

`LogState.total_count()` after this task is 3 (three `.tres` files), and exactly 3
`LoreLogPickup` instances are placed — catalogue size and placed-pickup count match, so 100% lore
log completion is reachable entirely from the hub, with nothing orphaned on either side.

### 5. Placement invariant test

`tests/integration/test_hub_log_placement.gd`, modeled on
`tests/integration/test_log_record_mission_placement.gd` (extract-by-name, detach, exercise via
`_on_body_entered`/`_collect`, never drive a real `DialogPlayer.play()`):

- Loads `sector_hub.tscn`, counts `LoreLogPickup` instances and `InfoLogInteractable` instances
  under the root: asserts `>= 3` and `>= 2` respectively (matches the task's literal "done when").
- Asserts `LogState.total_count() == ` the number of `LoreLogPickup` instances found — the
  "catalogue total matches what is placeable" criterion, checked in code rather than by hand
  count, so it stays true if either side changes later without the other.
- One placed `LoreLogPickup` is extracted, collected via a direct `_collect(PlayerStub.spawn())`
  call (never `_on_body_entered()` — that would reach `_show_notification()` with non-empty text
  and start a real `DialogPlayer.play()` coroutine, same trap as §2 case 4) against a real
  `LogState` (fixture-swapped catalogue via the same `SaveSandbox` + `catalogue_dir` pattern
  `test_log_state.gd` uses) to prove the placed instance is a real, working pickup and not just
  present in the scene tree.
- One placed `InfoLogInteractable` is extracted and asserted to have non-empty `message` (guards
  against a placeholder/empty string slipping through).

## Build sequence

1. Generate and visually verify `lore_log.png` (`pixel-art-generation` skill).
2. Write `tests/unit/test_lore_log_pickup.gd` (failing — script doesn't exist yet).
3. Write `global/pickups/lore_log_pickup.gd`.
4. Build `global/pickups/scenes/lore_log_pickup.tscn`.
5. Run the GUT suite — `test_lore_log_pickup.gd` passes, nothing else regresses.
6. Author the 3 `LogEntryResource` `.tres` files under `global/resources/logs/entries/`.
7. Place the 3 `LoreLogPickup` + 2 `InfoLogInteractable` instances in `sector_hub.tscn`.
8. Write `tests/integration/test_hub_log_placement.gd`.
9. `bash /agent/verify.sh`; `scripts/check-test-leaks.sh`.
10. `updating-project-docs` skill: `docs/architecture/modules/global.md` (pickups table §6,
    autoload list), `docs/architecture/PROJECT.md`, `open_space.md`, `CLAUDE.md`.

Each step is independently checkable.

## Test plan

Covered inline in Design §2 and §5 above:
`tests/unit/test_lore_log_pickup.gd` (4 cases, incl. the exhausted-catalogue boundary case) and
`tests/integration/test_hub_log_placement.gd` (placement counts, catalogue-match invariant,
one real end-to-end collect, one non-empty-message check).

## Risks

- Same coroutine-leak trap the sibling task's review surfaced twice — mitigated by never driving
  a real `DialogPlayer.play()` in any new test (§2 case 4, §5). Run `scripts/check-test-leaks.sh`
  after writing these tests, per `CLAUDE.md`.
- `sector_hub.tscn` is hand-edited `.tscn` text (uid-referenced `ext_resource`s, `unique_id`
  attributes on some nodes) — new nodes follow the existing un-`unique_id`'d pattern the most
  recent additions (`ModuleUnlocker*`, `WeaponUnlocker*`) already use, so no UID minting is
  needed for the new scene-instance nodes themselves (only for the new `lore_log_pickup.tscn`
  root and the new `.tres` catalogue files, via `ResourceUID.create_id()` if a UID is warranted at
  all — matching `armor_tank_pickup.tscn`-style scenes that ship without one is also acceptable
  per `CLAUDE.md`).

## Out of scope

- Any further log placements in assault/infiltration missions beyond the two `InfoLogInteractable`
  instances already shipped in `ad4d5d7` — that task is done.
- Changing `LogState`, `InfoLogInteractable`, or the ESC-menu Lore Logs reader — all built and
  tested already; this task is a pure consumer.
- Sequential-unlock UI polish beyond what `lore_log_list.gd` already renders.
