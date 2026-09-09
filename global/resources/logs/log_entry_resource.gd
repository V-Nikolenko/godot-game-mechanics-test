class_name LogEntryResource
extends Resource

## One lore log entry. One `.tres` per entry, loaded from LogState.catalogue_dir.

## Stable id. Matches the catalogue `.tres` filename by convention, but LogState reads it
## from this field, not from the filename.
@export var id: StringName = &""
## Shown as the entry title wherever a log is listed (menu, popup).
@export var title: String = ""
@export_multiline var body: String = ""
## Position in the reading order. Lore logs unlock in ascending `sequence` order regardless
## of collection order in the world — see LogState.collect_next().
@export var sequence: int = 0
