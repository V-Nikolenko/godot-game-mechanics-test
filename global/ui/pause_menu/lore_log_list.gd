class_name LoreLogList
extends Node2D

## Full-catalogue lore-log reader, opened from the ESC menu's Lore Logs option.
## Every catalogue entry (LogState.total_count() of them) gets a row, in catalogue order: found
## entries show their real title and — once the cursor lands on them — their full body; unfound
## entries show a "???" title and a locked placeholder body. Visibly present, not hidden, so the
## player can see there is more to find and roughly how much.
##
## Reading is just navigating — there is no separate "confirm to read" step, the same way
## ModuleList shows a hovered row's description without a confirm.
##
## Paged in fixed PAGE_SIZE chunks rather than ModuleList's MAX_ITEMS truncation: a log catalogue
## is expected to outgrow one screen, where ModuleList's slot lists never do.

const _ITEM_SCENE: PackedScene = preload("res://global/ui/pause_menu/lore_log_list_item.tscn")
const _ROW_HEIGHT: float = 34.0
const _ROW_ORIGIN: Vector2 = Vector2(-440.0, -190.0)
const PAGE_SIZE: int = 8
const _LOCKED_BODY: String = "LOCKED — this record has not been recovered yet."
const _EMPTY_BODY: String = "No log records catalogued yet."

@onready var _header_lbl: Label = $HeaderLabel
@onready var _body_lbl: RichTextLabel = $BodyLabel

var _ids: Array[StringName] = []
var _items: Array[LoreLogListItem] = []
var _page: int = 0
var _cursor_row: int = 0


func _ready() -> void:
	visible = false


## Show the reader from the top: first page, cursor on the first row.
func open() -> void:
	_ids = LogState.all_ids()
	_page = 0
	_cursor_row = 0
	_build_page()
	visible = true


func close() -> void:
	visible = false
	_clear_items()


## +1/-1 moves the cursor within the current page.
func navigate(delta: int) -> void:
	if _items.is_empty():
		return
	_cursor_row = clampi(_cursor_row + delta, 0, _items.size() - 1)
	_refresh_cursor()


## +1/-1 changes page, wrapping past the last one. No-op with a single page or an empty catalogue.
func page(delta: int) -> void:
	var pages := _page_count()
	if pages <= 1:
		return
	_page = wrapi(_page + delta, 0, pages)
	_cursor_row = 0
	_build_page()


func _page_count() -> int:
	if _ids.is_empty():
		return 1
	return ((_ids.size() - 1) / PAGE_SIZE) + 1


func _build_page() -> void:
	_clear_items()
	var start: int = _page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, _ids.size())
	for i: int in range(start, end):
		var id: StringName = _ids[i]
		var locked: bool = not LogState.is_collected(id)
		var entry: LogEntryResource = LogState.get_entry(id)
		var item := _ITEM_SCENE.instantiate() as LoreLogListItem
		add_child(item)
		item.position = _ROW_ORIGIN + Vector2(0.0, (i - start) * _ROW_HEIGHT)
		item.configure(entry.title if (entry != null and not locked) else "???", locked)
		_items.append(item)
	_refresh_header()
	_refresh_cursor()


func _refresh_header() -> void:
	var text := "Lore Logs — %d / %d" % [LogState.collected_count(), LogState.total_count()]
	var pages := _page_count()
	if pages > 1:
		text += "   (Page %d/%d)" % [_page + 1, pages]
	_header_lbl.text = text


func _refresh_cursor() -> void:
	for i: int in _items.size():
		_items[i].set_cursor(i == _cursor_row)
	_refresh_body()


func _refresh_body() -> void:
	if _items.is_empty():
		_body_lbl.text = _EMPTY_BODY
		return
	var id: StringName = _ids[_page * PAGE_SIZE + _cursor_row]
	if LogState.is_collected(id):
		var entry: LogEntryResource = LogState.get_entry(id)
		_body_lbl.text = entry.body if entry != null else ""
	else:
		_body_lbl.text = _LOCKED_BODY


func _clear_items() -> void:
	for item: LoreLogListItem in _items:
		remove_child(item)
		item.queue_free()
	_items.clear()
