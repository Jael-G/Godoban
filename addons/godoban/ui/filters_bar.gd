@tool
extends HFlowContainer

## Search box + five filter dropdowns (plus, in the toolbar, the two view-mode
## toggles are prepended as leading controls). Emits a composed filter dict that
## the board consumes via set_filters(). Uses a wrapping flow so the whole strip
## fits narrow editors without a horizontal scrollbar.

const Model = preload("res://addons/godoban/data/godoban_model.gd")
const T = preload("res://addons/godoban/ui/theme.gd")

const SORTS := [
	["Created (oldest)", "created_asc"],
	["Created (newest)", "created_desc"],
	["Latest edited", "updated"],
	["Priority", "priority"],
	["Due date", "due"],
	["Alphabetical", "alpha"],
]

signal filters_changed(filters: Dictionary)

var store: RefCounted
var _search: LineEdit
var _sort: OptionButton
var _priority: OptionButton
var _epic: OptionButton
var _label: OptionButton
var _date: OptionButton

func setup(p_store: RefCounted) -> void:
	store = p_store
	_build()

func _build() -> void:
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)

	_search = LineEdit.new()
	_search.placeholder_text = "Search features…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.x = 220
	_search.add_theme_font_size_override("font_size", 13)
	T.field(_search)
	_search.text_changed.connect(func(_s): _emit())
	add_child(_search)

	_sort = OptionButton.new()
	_sort.add_theme_font_size_override("font_size", 13)
	T.field(_sort)
	_sort.item_selected.connect(func(_i): _emit())
	add_child(_sort)
	for i in SORTS.size():
		_sort.add_item(SORTS[i][0])
		_sort.set_item_metadata(i, SORTS[i][1])

	_priority = _make_option("All priorities")
	for i in Model.PRIORITIES.size():
		_priority.add_item(Model.priority_title(Model.PRIORITIES[i]))
		_priority.set_item_metadata(i + 1, Model.PRIORITIES[i])

	_epic = _make_option("All epics")

	_label = _make_option("All labels")
	_label.search_bar_enabled = true
	_label.search_bar_fuzzy_search_enabled = true
	_label.search_bar_fuzzy_search_max_misses = 2
	_label.search_bar_min_item_count = 0  # keep the search bar visible even for short lists

	_date = _make_option("All dates")
	var date_opts := [["Overdue", "overdue"], ["Due today", "today"], ["Due this week", "week"], ["No due date", "none"]]
	for i in date_opts.size():
		_date.add_item(date_opts[i][0])
		_date.set_item_metadata(i + 1, date_opts[i][1])

	store.changed.connect(_refresh_dynamic)
	_refresh_dynamic()


func _make_option(text: String) -> OptionButton:
	var o := OptionButton.new()
	o.add_item(text)
	o.set_item_metadata(0, "any")
	o.add_theme_font_size_override("font_size", 13)
	T.field(o)
	o.item_selected.connect(func(_i): _emit())
	add_child(o)
	return o


func _refresh_dynamic() -> void:
	var cur_epic: String = str(_epic.get_item_metadata(_epic.selected)) if _epic.selected >= 0 else "any"
	var cur_label: String = str(_label.get_item_metadata(_label.selected)) if _label.selected >= 0 else "any"

	_epic.clear()
	_epic.add_item("All epics")
	_epic.set_item_metadata(0, "any")
	for e in store.board.epics:
		_epic.add_item(e.title)
		_epic.set_item_metadata(_epic.item_count - 1, e.id)

	var tags := _all_tags()
	_label.clear()
	_label.add_item("All labels")
	_label.set_item_metadata(0, "any")
	for tag in tags:
		_label.add_item(tag)
		_label.set_item_metadata(_label.item_count - 1, tag)

	_select_by_metadata(_epic, cur_epic)
	_select_by_metadata(_label, cur_label)


func _all_tags() -> Array:
	var s := {}
	for t in store.board.tasks:
		for tag in t.tags:
			s[tag] = true
	var out: Array = []
	for k in s:
		out.append(k)
	out.sort()
	return out


func _select_by_metadata(btn: OptionButton, value: String) -> void:
	for i in btn.item_count:
		if str(btn.get_item_metadata(i)) == value:
			btn.select(i)
			return
	btn.select(0)


## Clear the board-scoped dropdowns (epic + label) and re-emit, so a filter from one
## board can't hide every task after we switch to a board that lacks that epic/label.
## General filters (search, sort, priority, date) are left alone.
func reset_scope() -> void:
	_epic.select(0)
	_label.select(0)
	_emit()


func get_filters() -> Dictionary:
	return {
		"search": _search.text.strip_edges(),
		"sort": str(_sort.get_item_metadata(_sort.selected)),
		"priority": str(_priority.get_item_metadata(_priority.selected)),
		"epic": str(_epic.get_item_metadata(_epic.selected)),
		"label": str(_label.get_item_metadata(_label.selected)),
		"date": str(_date.get_item_metadata(_date.selected)),
	}


func _emit() -> void:
	filters_changed.emit(get_filters())
