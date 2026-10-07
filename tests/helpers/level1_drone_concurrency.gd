## Peak-concurrency arithmetic for a `LevelSection`'s waves, shared between Ph2's t1 legacy pin
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §3 step 1) and t15's post-migration concurrency
## check (§5 C3), and Ph3's `test_level1_fighter_spawns.gd` (docs/plans/cmufs7ekv000lnm2x7nbswijy/
## 3-plan.md §2.9.1). The Ph2 functions below share ONE lifetime constant across every DRONE/
## RAZOR_DRONE entry, because every legacy drone dies in the same single ramming pass. `fighter()`/
## `gatling_interceptor()` rails have no such shortcut — each entry's on-screen time is its OWN `free_after`
## or its OWN sampled `MovementResource` — so `spawn_intervals()`/`peak_interval_count()`/
## `peak_interval_rate()` (bottom of file) generalise the same interval-overlap arithmetic to a
## per-entry `{start, end, rate}` supplied by the caller instead of one shared float.
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


# ── t15: squad-aware lifetimes (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §5 C3) ─────────────

## How many members of a squad count as attack-capable: LEAD, FLANK_LEFT, FLANK_RIGHT (§2.4). The
## rest are REAR, which orbit and never attack.
const ATTACKERS_PER_SQUAD := 3


## The worst-case Assault exit after `engage_seconds`: straight to the nearest edge of the world rect
## (at most half its shorter side away) at `exit_speed`, plus the time lost accelerating from rest to
## it — the same terms as the §2.6 deadline formula (`test_engagement_deadline.gd`).
static func worst_exit_seconds(exit_distance: float, exit_speed: float, acceleration: float) -> float:
	return exit_distance / exit_speed + exit_speed / (2.0 * acceleration)


## The squad an entry's ships belong to, as `WaveManager._trigger_wave()` groups them: a formation
## entry is one squad, loose entries of one wave sharing a non-empty `squad_id` are one squad, anything
## else is a squad of one. `joins_squads` false keeps every entry on its own (Ph2's Razors never join).
## Shared by `squad_intervals()` and `shooter_squad_intervals()` so the keying exists once.
static func squad_key(wave_index: int, entry_index: int, entry: SpawnEntryResource,
		joins_squads: bool = true) -> String:
	if joins_squads and entry.formation == null and not String(entry.squad_id).is_empty():
		return "%d:%s" % [wave_index, entry.squad_id]
	return "%d:%d" % [wave_index, entry_index]


## One `{ "start", "end", "capable", "squad" }` per ship a section spawns whose path is `swarm_path` or
## `razor_path`. Squads follow `WaveManager._trigger_wave()`'s key: a formation entry is one squad,
## loose entries of one wave sharing a non-empty `squad_id` are one squad, anything else is a squad of
## one. Razors never join a squad. Members are ordered by spawn time (ties: entry order) and the first
## `ATTACKERS_PER_SQUAD` are attack-capable. `lifetimes` holds `swarm_attacker`, `swarm_rear` and `razor`.
static func squad_intervals(section: LevelSection, swarm_path: String, razor_path: String,
		lifetimes: Dictionary) -> Array[Dictionary]:
	var squads: Dictionary = {}   # key -> Array of { "t", "order", "razor" }
	var order := 0
	for wave_index in section.waves.size():
		var wave: WaveResource = section.waves[wave_index]
		for entry_index in wave.entries.size():
			var entry: SpawnEntryResource = wave.entries[entry_index]
			if entry.ship_scene == null:
				continue
			var path := entry.ship_scene.resource_path
			if path != swarm_path and path != razor_path:
				continue
			var is_razor := path == razor_path
			var key := squad_key(wave_index, entry_index, entry, not is_razor)
			var members: Array = squads.get(key, [])
			if entry.formation:
				for slot: FormationResource.FormationSlot in entry.formation.compute_slots():
					members.append({"t": wave.trigger_time + entry.spawn_delay + slot.delay, "order": order, "razor": false})
					order += 1
			else:
				members.append({"t": wave.trigger_time + entry.spawn_delay, "order": order, "razor": is_razor})
				order += 1
			squads[key] = members
	var out: Array[Dictionary] = []
	for key: String in squads:
		var members: Array = squads[key]
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["t"] < b["t"] or (a["t"] == b["t"] and a["order"] < b["order"]))
		for i in members.size():
			var m: Dictionary = members[i]
			var capable: bool = m["razor"] or i < ATTACKERS_PER_SQUAD
			var life: float = lifetimes["razor"] if m["razor"] \
				else (lifetimes["swarm_attacker"] if capable else lifetimes["swarm_rear"])
			out.append({"start": m["t"], "end": m["t"] + life, "capable": capable, "squad": key})
	return out


## The largest number of `intervals` alive at once (`start <= t < end`), optionally only the
## attack-capable ones. Sampling at starts is sufficient, as in `peak_concurrency()`.
static func peak_intervals(intervals: Array[Dictionary], capable_only: bool = false) -> int:
	var peak := 0
	for a: Dictionary in intervals:
		if capable_only and not a["capable"]:
			continue
		var t: float = a["start"]
		var alive := 0
		for b: Dictionary in intervals:
			if capable_only and not b["capable"]:
				continue
			if b["start"] <= t and t < b["end"]:
				alive += 1
		peak = maxi(peak, alive)
	return peak


## The more conservative count (review N5, recorded, not asserted): roles really rotate by
## distance, so at any moment a squad may field up to min(alive members, 3) attackers.
static func peak_min_alive_three(intervals: Array[Dictionary]) -> int:
	var peak := 0
	for a: Dictionary in intervals:
		var t: float = a["start"]
		var alive_per_squad: Dictionary = {}
		for b: Dictionary in intervals:
			if b["start"] <= t and t < b["end"]:
				alive_per_squad[b["squad"]] = int(alive_per_squad.get(b["squad"], 0)) + 1
		var n := 0
		for k: String in alive_per_squad:
			n += mini(int(alive_per_squad[k]), ATTACKERS_PER_SQUAD)
		peak = maxi(peak, n)
	return peak


# ── Ph3 t1: per-entry lifetime/rate, generalised beyond one kind-wide constant ─────────────────
##
## Fighters and interceptors don't share Ph2's "every drone dies in one ramming pass" shortcut: a
## rail's on-screen lifetime is its OWN `free_after`, or its OWN `MovementResource` sampled from
## its OWN spawn offset — never a single constant applied to every entry of a kind. `spawn_intervals()`
## takes that per-entry model as two Callables instead of one shared float:
##   lifetime_fn(path: String, offset: Vector2, movement: MovementResource, exit_mode: int, exit_time: float) -> float
##   rate_fn(path: String, offset: Vector2, movement: MovementResource, exit_mode: int, exit_time: float, aim_mode: String) -> float
## so the caller supplies the ArenaCamera-sampling and config-reading logic (both need live nodes/
## resources this RefCounted helper has no business holding) and this file stays the same pure
## interval arithmetic `peak_intervals()` already uses.
static func spawn_intervals(section: LevelSection, ship_paths: Array[String],
		lifetime_fn: Callable, rate_fn: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for wave: WaveResource in section.waves:
		for entry: SpawnEntryResource in wave.entries:
			if entry.ship_scene == null or not ship_paths.has(entry.ship_scene.resource_path):
				continue
			var path: String = entry.ship_scene.resource_path
			var aim_mode: String = String(entry.initial_props.get("aim_mode", ""))
			if entry.formation:
				for slot: FormationResource.FormationSlot in entry.formation.compute_slots():
					var t: float = wave.trigger_time + entry.spawn_delay + slot.delay
					var off: Vector2 = entry.base_offset + slot.offset
					var life: float = lifetime_fn.call(path, off, entry.movement, entry.exit_mode, entry.exit_time)
					var rate: float = rate_fn.call(path, off, entry.movement, entry.exit_mode, entry.exit_time, aim_mode)
					out.append({"start": t, "end": t + life, "rate": rate})
			else:
				var t: float = wave.trigger_time + entry.spawn_delay
				var life: float = lifetime_fn.call(path, entry.base_offset, entry.movement, entry.exit_mode, entry.exit_time)
				var rate: float = rate_fn.call(path, entry.base_offset, entry.movement, entry.exit_mode, entry.exit_time, aim_mode)
				out.append({"start": t, "end": t + life, "rate": rate})
	return out


## Peak concurrency over `spawn_intervals()`'s per-entry `{start, end}` pairs — the same sampling-
## at-starts argument as `peak_concurrency()`, generalised off a single shared lifetime.
static func peak_interval_count(intervals: Array[Dictionary]) -> int:
	var peak := 0
	for a: Dictionary in intervals:
		var t: float = a["start"]
		var alive := 0
		for b: Dictionary in intervals:
			if b["start"] <= t and t < b["end"]:
				alive += 1
		peak = maxi(peak, alive)
	return peak


## Peak summed `rate` (shots/s) of every interval alive at the same moment.
static func peak_interval_rate(intervals: Array[Dictionary]) -> float:
	var peak := 0.0
	for a: Dictionary in intervals:
		var t: float = a["start"]
		var total := 0.0
		for b: Dictionary in intervals:
			if b["start"] <= t and t < b["end"]:
				total += float(b["rate"])
		peak = maxf(peak, total)
	return peak


# ── Ph3 t16: AI shooters off rails (docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md) ──────────────

## The Razor-shaped worst-case Assault exit (epic docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md
## §2.9.3): the ship may start leaving at `speed` heading AWAY from its nearest edge, so it first
## brakes and turns that speed around (`(speed + exit_speed) / min(acceleration, braking)`), then
## covers the edge distance plus the ground it lost braking, at `exit_speed`.
static func worst_exit_after_speed(speed: float, exit_speed: float, acceleration: float,
		braking: float, exit_distance: float) -> float:
	return (speed + exit_speed) / minf(acceleration, braking) \
		+ (exit_distance + speed * speed / (2.0 * braking)) / exit_speed


## One `{ "start", "end", "capable", "squad", "rate", "cap" }` per ship a section spawns whose scene
## path is a key of `kinds`, where `kinds[path]` is `{ "life": float, "capable_per_squad": int,
## "rate": float }`. Squads are keyed by `squad_key()`. Members are ordered by spawn time (ties:
## entry order) and the first `capable_per_squad` are attack-capable; `rate` is the kind's rate for a
## capable member and 0.0 otherwise, so `peak_interval_rate()` sums attackers only.
static func shooter_squad_intervals(section: LevelSection, kinds: Dictionary) -> Array[Dictionary]:
	var squads: Dictionary = {}   # key -> Array of { "t", "order", "kind" }
	var order := 0
	for wave_index in section.waves.size():
		var wave: WaveResource = section.waves[wave_index]
		for entry_index in wave.entries.size():
			var entry: SpawnEntryResource = wave.entries[entry_index]
			if entry.ship_scene == null or not kinds.has(entry.ship_scene.resource_path):
				continue
			var path := entry.ship_scene.resource_path
			var key := squad_key(wave_index, entry_index, entry)
			var members: Array = squads.get(key, [])
			if entry.formation:
				for slot: FormationResource.FormationSlot in entry.formation.compute_slots():
					members.append({"t": wave.trigger_time + entry.spawn_delay + slot.delay, "order": order, "kind": path})
					order += 1
			else:
				members.append({"t": wave.trigger_time + entry.spawn_delay, "order": order, "kind": path})
				order += 1
			squads[key] = members
	var out: Array[Dictionary] = []
	for key: String in squads:
		var members: Array = squads[key]
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["t"] < b["t"] or (a["t"] == b["t"] and a["order"] < b["order"]))
		for i in members.size():
			var m: Dictionary = members[i]
			var kind: Dictionary = kinds[m["kind"]]
			var cap: int = kind["capable_per_squad"]
			var capable: bool = i < cap
			out.append({"start": m["t"], "end": m["t"] + float(kind["life"]), "capable": capable,
				"squad": key, "rate": float(kind["rate"]) if capable else 0.0, "cap": cap})
	return out


## `peak_min_alive_three()` generalised to each interval's own `cap`: at any moment a squad may field
## up to min(alive members, cap) attackers, because roles rotate (a REAR is promoted when an attacker
## leaves). Printed beside the first-N count, never asserted (t16 review N3).
static func peak_min_alive_cap(intervals: Array[Dictionary]) -> int:
	var peak := 0
	for a: Dictionary in intervals:
		var t: float = a["start"]
		var alive_per_squad: Dictionary = {}
		var cap_per_squad: Dictionary = {}
		for b: Dictionary in intervals:
			if b["start"] <= t and t < b["end"]:
				alive_per_squad[b["squad"]] = int(alive_per_squad.get(b["squad"], 0)) + 1
				cap_per_squad[b["squad"]] = int(b["cap"])
		var n := 0
		for k: String in alive_per_squad:
			n += mini(int(alive_per_squad[k]), int(cap_per_squad[k]))
		peak = maxi(peak, n)
	return peak


## The start of the interval at which the attack-capable count peaks (the first such moment).
static func capable_peak_time(intervals: Array[Dictionary]) -> float:
	var peak := -1
	var at := 0.0
	for a: Dictionary in intervals:
		if not a["capable"]:
			continue
		var t: float = a["start"]
		var alive := 0
		for b: Dictionary in intervals:
			if b["capable"] and b["start"] <= t and t < b["end"]:
				alive += 1
		if alive > peak:
			peak = alive
			at = t
	return at


## The measured shots/s gate's arithmetic (owner option A): the most shots in any `window` seconds,
## divided by `window`. Windows are anchored at each shot (`[t, t + window)`), which is sufficient:
## the count inside a sliding window can only step up when its start crosses a shot.
static func peak_window_rate(times: Array[float], window: float) -> float:
	var peak := 0
	for t: float in times:
		var n := 0
		for t2: float in times:
			if t2 >= t and t2 < t + window:
				n += 1
		peak = maxi(peak, n)
	return float(peak) / window


## Each AI shooter kind's worst-case Assault lifetime, attackers per squad and analytic rate per
## attacker, all read from the shipped configs (epic docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md
## §2.9.2 / §2.9.3), keyed by scene path in the shape `shooter_squad_intervals()` takes:
##   life = engage_seconds + deferral (the attack the budget may not interrupt) + Razor-shaped exit;
##   rate (printed only since the owner's option A) = fighter max over modes of
##   n_max / (gap × n_max + min_burst_period), Gatling stream_rounds_max / the brain's own
##   min_window_period().
## `exit_distance` is half the shorter side of the live `ArenaCamera.projectile_world_rect()`.
static func ai_shooter_kinds(f: FighterConfig, g: GatlingInterceptorConfig, exit_distance: float) -> Dictionary:
	var f_deferral: float = f.burst_telegraph + maxf(f.aimed_max * f.aimed_gap, f.forward_max * f.forward_gap)
	var g_deferral: float = g.spin_up_seconds + g.sync_wait_max + g.stream_rounds_max * g.stream_interval
	var gatling_brain := GatlingInterceptorBrain.new()
	gatling_brain.config = g
	var g_period: float = gatling_brain.min_window_period()
	gatling_brain.free()
	return {
		WaveBuilder.FIGHTER: {
			"life": f.engage_seconds + f_deferral
				+ worst_exit_after_speed(f.max_speed, f.exit_speed, f.acceleration, f.braking, exit_distance),
			"capable_per_squad": 3,
			"rate": maxf(f.aimed_max / (f.aimed_gap * f.aimed_max + f.min_burst_period),
				f.forward_max / (f.forward_gap * f.forward_max + f.min_burst_period)),
		},
		WaveBuilder.GATLING_INTERCEPTOR: {
			"life": g.engage_seconds + g_deferral
				+ worst_exit_after_speed(g.max_speed, g.exit_speed, g.acceleration, g.braking, exit_distance),
			"capable_per_squad": 2,
			"rate": g.stream_rounds_max / g_period,
		},
	}
