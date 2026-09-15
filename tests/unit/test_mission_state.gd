## Characterization tests for MissionState (global/autoloads/mission_state.gd).
## These pin down what the code does TODAY. Where behaviour looks surprising it is
## marked "CHARACTERIZED" and the suspicion is logged in BACKLOG.md → Discovered.
## The star-scale tests are the exception: they are individually marked "INTENT"
## because the 1–3 clamp was reviewed and confirmed deliberate, so they assert what
## the code SHOULD do and a change to it is a regression, not a re-baseline.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const MissionStateScript := preload("res://global/autoloads/mission_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


## A fresh, tree-less instance: `_ready()` never fires, so `_load()` never runs
## and the store starts empty regardless of what is on disk.
func _fresh() -> Node:
	return MissionStateScript.new()


func test_unknown_mission_reads_as_untouched() -> void:
	var ms := _fresh()
	assert_false(ms.is_complete(7), "never-played mission is not complete")
	assert_eq(ms.get_stars(7), 0, "never-played mission has 0 stars")
	assert_eq(ms.get_high_score(7), 0, "never-played mission has 0 high score")
	ms.free()


func test_complete_records_completion_and_stars() -> void:
	var ms := _fresh()
	ms.complete(1, 2)
	assert_true(ms.is_complete(1))
	assert_eq(ms.get_stars(1), 2)
	ms.free()


func test_complete_keeps_the_higher_star_count() -> void:
	var ms := _fresh()
	ms.complete(1, 3)
	ms.complete(1, 1)
	assert_eq(ms.get_stars(1), 3, "a worse replay must not lower the recorded stars")
	ms.free()


## INTENT (not characterization): the 1–3 clamp is deliberate and load-bearing.
## 0 is the reserved "never completed" sentinel — `get_stars()` returns it for a
## mission that was never played, and `MissionListItem.configure()` renders it as
## three empty stars — so a stored clear is always worth at least one star. A real
## 0-star clear would be indistinguishable from never having played the mission.
func test_stars_are_clamped_into_one_to_three() -> void:
	var ms := _fresh()
	ms.complete(1, 0)
	assert_eq(ms.get_stars(1), 1, "0 stars is clamped up to 1, keeping 0 as the never-played sentinel")
	ms.complete(2, 99)
	assert_eq(ms.get_stars(2), 3, "stars above 3 are clamped down to 3")
	ms.free()


## INTENT: the clamp must not be silent. Every shipped caller reaches `complete()`
## through `MissionConfigResource.stars_for_score()`, which already floors at 1 and
## caps at 3, so an out-of-range value means the caller computed it wrong — a bug
## worth a warning, not something to quietly round into the valid range.
func test_out_of_range_stars_warn_the_caller() -> void:
	var ms := _fresh()
	ms.complete(1, 0)
	ms.complete(2, 99)
	assert_push_warning_count(2, "each out-of-range star count warns once")
	ms.free()


## INTENT: the in-range path stays quiet, so the warning above keeps its signal.
func test_in_range_stars_do_not_warn() -> void:
	var ms := _fresh()
	ms.complete(1, 1)
	ms.complete(2, 2)
	ms.complete(3, 3)
	assert_push_warning_count(0, "a valid star count is not a caller bug")
	ms.free()


func test_record_score_keeps_only_the_maximum() -> void:
	var ms := _fresh()
	ms.record_score(4, 500)
	assert_eq(ms.get_high_score(4), 500)
	ms.record_score(4, 100)
	assert_eq(ms.get_high_score(4), 500, "a lower score must not overwrite the high score")
	ms.record_score(4, 900)
	assert_eq(ms.get_high_score(4), 900)
	ms.free()


func test_record_score_alone_does_not_complete_the_mission() -> void:
	var ms := _fresh()
	ms.record_score(5, 250)
	assert_false(ms.is_complete(5), "scoring without completing leaves the mission incomplete")
	assert_eq(ms.get_stars(5), 0)
	ms.free()


func test_cutscene_flags() -> void:
	var ms := _fresh()
	assert_false(ms.has_cutscene_been_seen("intro"), "unseen cutscene reads false")
	ms.mark_cutscene_seen("intro")
	assert_true(ms.has_cutscene_been_seen("intro"))
	assert_false(ms.has_cutscene_been_seen("outro"), "marking one does not mark another")
	ms.free()


func test_progress_survives_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer.complete(2, 3)
	writer.record_score(2, 1234)
	writer.mark_cutscene_seen("act1_end")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_true(reader.is_complete(2), "completion survives the round trip")
	assert_eq(reader.get_stars(2), 3, "stars survive the round trip")
	assert_eq(reader.get_high_score(2), 1234, "high score survives the round trip")
	assert_true(reader.has_cutscene_been_seen("act1_end"), "cutscene flag survives the round trip")
	reader.free()


func test_cutscene_section_name_never_collides_with_a_mission() -> void:
	## The reserved section is "__cutscenes__", which `String.to_int()` maps to 0,
	## so the loader must special-case it rather than treating it as mission 0.
	_sandbox.clear_all()
	var writer := _fresh()
	writer.complete(0, 2)               ## mission number 0 is legal
	writer.mark_cutscene_seen("boot")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_stars(0), 2, "mission 0 is unaffected by the cutscene section")
	assert_true(reader.has_cutscene_been_seen("boot"))
	reader.free()
