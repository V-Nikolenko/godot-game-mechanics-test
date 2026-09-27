## Peak-concurrency arithmetic for a `LevelSection`'s waves, shared between t1's legacy pin
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §3 step 1) and t15's post-migration concurrency
## check (§5 C3). Same lifetime-window model; t15 supplies a different ship set and lifetime.
##
## No class_name: test-only, like every other `tests/helpers/` fixture. Preload it instead:
##     const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")
extends RefCounted


## Every spawn moment for entries whose `ship_scene` path is in `ship_paths`: `wave.trigger_time +
## entry.spawn_delay`, plus a formation slot's own `delay` when the entry expands into one —
## the same arithmetic `WaveManager._expand_formation()` / `_spawn_with_delay()` apply
## (wave_manager.gd:130-154), reproduced here rather than driven through a live WaveManager so the
## computation stays a pure function of `LevelSection` data.
static func spawn_times(section: LevelSection, ship_paths: Array[String]) -> Array[float]:
	var out: Array[float] = []
	for wave: WaveResource in section.waves:
		for entry: SpawnEntryResource in wave.entries:
			if entry.ship_scene == null or not ship_paths.has(entry.ship_scene.resource_path):
				continue
			if entry.formation:
				for slot: FormationResource.FormationSlot in entry.formation.compute_slots():
					out.append(wave.trigger_time + entry.spawn_delay + slot.delay)
			else:
				out.append(wave.trigger_time + entry.spawn_delay)
	return out


## The largest number of `times` simultaneously "alive" under a fixed `lifetime` starting at each
## spawn moment — i.e. the largest `|{t2 : t2 <= t < t2 + lifetime}|` over every `t` in `times`.
## Sampling only at spawn moments is sufficient: the alive count can only step up at an arrival.
static func peak_concurrency(times: Array[float], lifetime: float) -> int:
	var peak := 0
	for t: float in times:
		var alive := 0
		for t2: float in times:
			if t2 <= t and t < t2 + lifetime:
				alive += 1
		peak = maxi(peak, alive)
	return peak
