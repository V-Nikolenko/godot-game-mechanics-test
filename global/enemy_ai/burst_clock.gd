## BurstClock — counts down a fixed-size burst of evenly spaced shots (docs/plans/
## cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.3). No node, no `Timer`: the owning brain calls
## `advance(delta)` from its own tick and fires `attack.fire_now()` once per shot it reports due,
## so a burst's size is exact even on a long frame — never more than `count` shots, regardless of
## how large a single `delta` is.
##
## Time is accumulated `delta` with subtract-not-reset, the same rule `AttackController.tick()`
## uses, to preserve overshoot accuracy across steps. The first shot is due immediately on the
## first `advance()` call, whatever `delta` is — the internal clock starts pre-loaded with `gap`.
class_name BurstClock
extends RefCounted

var shots_fired: int = 0

var _remaining: int = 0
var _gap: float = 0.0
var _timer: float = 0.0


## Begins a burst of `count` shots spaced `gap` seconds apart. `count <= 0` starts nothing.
func start(count: int, gap: float) -> void:
	_remaining = maxi(count, 0)
	_gap = gap
	_timer = gap
	shots_fired = 0


## Advances the clock by `delta` and returns how many shots are due this tick (0 or more).
## Never returns more than the shots remaining in the burst.
func advance(delta: float) -> int:
	if _remaining <= 0:
		return 0
	if _gap <= 0.0:
		var count := _remaining
		shots_fired += count
		_remaining = 0
		return count
	_timer += delta
	var due := 0
	while _remaining > 0 and _timer >= _gap:
		_timer -= _gap
		_remaining -= 1
		shots_fired += 1
		due += 1
	return due


func is_running() -> bool:
	return _remaining > 0


## Ends the burst early. No further shots are reported due.
func stop() -> void:
	_remaining = 0
	_timer = 0.0
