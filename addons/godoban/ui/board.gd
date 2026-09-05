@tool
extends VBoxContainer

## The board area. Renders a single 5-column board in "all" mode, or one
## compact board per epic in "epic" mode. Rebuilds on store.changed.

const Column = preload("res://addons/godoban/ui/column.gd")
const Model = preload("res://addons/godoban/data/godoban_model.gd")
const T = preload("res://addons/godoban/ui/theme.gd")

signal open_requested(task_id: String)
signal add_requested(status: String)

## Columns are equal-width no matter how much content each holds: every column
## is pinned to the same share of the row, recomputed on layout/resize.
const COLUMN_MIN_WIDTH := 140.0

var store: RefCounted
var mode := "all"  # "all" | "epic"
## "vertical" stacks cards down each column (classic); "horizontal"
## flows them across a row per status. Pure view transform, like `mode`.
var orientation := "vertical"
var filters := {}  # composed filter set (see filters_bar.gd)
## Collapsed column state for the single "all" board, keyed by status. Lives here
## so it survives the wholesale rebuilds on `store.changed` and on mode switches.
var _collapsed_statuses := {}
## Collapsed epic boards in "epic" mode, keyed by epic id ("__none__" = no epic).
var _collapsed_epics := {}

func setup(p_store: RefCounted) -> void:
	store = p_store
	store.changed.connect(_on_changed)
	_rebuild()

func set_mode(m: String) -> void:
	mode = m
	_rebuild()

func set_orientation(o: String) -> void:
	orientation = o
	_rebuild()

func set_filters(f: Dictionary) -> void:
	filters = f
	_rebuild()

func _on_changed() -> void:
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.free()
	if mode == "all":
		_build_board()
	else:
		_build_per_epic()

func _build_board() -> void:
	if store.board.tasks.is_empty():
		add_child(_empty_hint("No tasks yet. Click \"+ New Task\" to get started."))
		return
	var group: BoxContainer = HBoxContainer.new()
	if orientation == "horizontal":
		group = VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 12)
	add_child(group)
	if orientation == "vertical":
		group.resized.connect(_equalize.bind(group))
	var cols := {}
	var visible := 0
	for status in Model.STATUSES:
		var col := Column.new()
		col.orientation = orientation
		col.show_epic = true
		col.show_collapse = true
		col.collapsed = _collapsed_statuses.get(status, false)
		col.setup(store, status)
		col.open_requested.connect(func(id): open_requested.emit(id))
		col.add_requested.connect(func(s): add_requested.emit(s))
		col.collapse_toggled.connect(func(s, c):
			_collapsed_statuses[s] = c
			call_deferred("_rebuild"))
		group.add_child(col)
		cols[status] = col
	for status in Model.STATUSES:
		var tasks: Array = _filtered(store.board.tasks_in_status(status))
		visible += tasks.size()
		cols[status].set_tasks(tasks)
	if orientation == "vertical":
		_equalize(group)
	if visible == 0:
		group.queue_free()
		add_child(_empty_hint("No tasks match the current filters."))


func _build_per_epic() -> void:
	add_theme_constant_override("separation", 24)
	var epics: Array = store.board.epics
	var groups := {}
	groups["__none__"] = {"title": "No Epic", "color": T.TEXT_FAINT, "ids": []}
	for e in epics:
		groups[e.id] = {"title": e.title, "color": Color(e.color), "ids": []}
	for t in store.board.tasks:
		var key: String = t.epic_id if t.epic_id != "" else "__none__"
		if groups.has(key):
			groups[key]["ids"].append(t.id)
	for key: String in groups:
		var g: Dictionary = groups[key]
		if g["ids"].is_empty():
			continue
		add_child(_compact_board(key, g["title"], g["color"], g["ids"]))


func _compact_board(key: String, title: String, color: Color, task_ids: Array) -> Control:
	var collapsed := _collapsed_epics.get(key, false)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 0)
	dot.color = color
	dot.size_flags_vertical = Control.SIZE_FILL
	header.add_child(dot)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", T.TEXT)
	header.add_child(t)

	# Arrow points down when expanded, right when collapsed; only the header stays.
	var arrow := Button.new()
	arrow.flat = true
	arrow.icon = T.arrow_icon(not collapsed, 15)
	arrow.tooltip_text = ("Expand" if collapsed else "Collapse") + " " + title
	arrow.add_theme_color_override("icon_normal_color", T.TEXT_DIM)
	arrow.add_theme_color_override("icon_hover_color", T.TEXT)
	arrow.add_theme_color_override("icon_pressed_color", T.TEXT)
	arrow.add_theme_color_override("icon_focus_color", T.TEXT_DIM)
	arrow.pressed.connect(func():
		_collapsed_epics[key] = not _collapsed_epics.get(key, false)
		call_deferred("_rebuild"))
	header.add_child(arrow)
	box.add_child(header)

	if collapsed:
		return box

	var row: BoxContainer = HBoxContainer.new()
	if orientation == "horizontal":
		row = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var cols := {}
	for status in Model.STATUSES:
		var col := Column.new()
		col.orientation = orientation
		col.show_epic = false
		col.show_collapse = false
		col.fit = true
		col.setup(store, status)
		col.open_requested.connect(func(id): open_requested.emit(id))
		col.add_requested.connect(func(s): add_requested.emit(s))
		row.add_child(col)
		cols[status] = col
	box.add_child(row)
	if orientation == "vertical":
		row.resized.connect(_equalize.bind(row))

	var by_status := {}
	for status in Model.STATUSES:
		by_status[status] = []
	for id in task_ids:
		var task = store.board.get_task(id)
		if task and by_status.has(task.status):
			by_status[task.status].append(task)
	for status in Model.STATUSES:
		cols[status].set_tasks(_filtered(by_status[status]))
	if orientation == "vertical":
		_equalize(row)
	return box


## Cap every *expanded* column at an equal share of the row so they stay equal
## width even when a column holds wide cards. Collapsed columns keep their narrow
## pill width and simply eat that much of the row; the remaining columns share
## what's left. Re-runs on resize.
##
## The cap is an upper bound ONLY — a column's minimum width is never raised to
## the share. (Raising it makes the board's minimum width ratchet up to whatever
## layout it last saw; the enclosing ScrollContainer then can't shrink the board,
## so columns stop reflowing when the window / Inspector gets narrower and get
## clipped under it.) Minimums stay at each column's intrinsic floor, so the row
## keeps reflowing down to that floor; below it the columns simply don't fit and
## the row overflows, same floor behaviour as the Overview tab.
func _equalize(row: Control) -> void:
	var expanded: Array = []
	var collapsed_w := 0.0
	for c in row.get_children():
		var col := c as Column
		if col and col.is_collapsed():
			var w: float = col.get_combined_minimum_size().x
			col.custom_minimum_size.x = w
			col.custom_maximum_size.x = w
			collapsed_w += w
		else:
			expanded.append(c)
	var n := expanded.size()
	if n == 0:
		return
	var sep: float = row.get_theme_constant("separation")
	var share: float = COLUMN_MIN_WIDTH
	if row.size.x > 0.0:
		share = maxf(COLUMN_MIN_WIDTH, (row.size.x - collapsed_w - sep * (row.get_child_count() - 1)) / n)
	for c in expanded:
		var col := c as Control
		col.custom_maximum_size.x = share


func _empty_hint(text: String) -> Control:
	var c := CenterContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", T.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 14)
	c.add_child(l)
	return c


func _filtered(tasks: Array) -> Array:
	if filters.is_empty():
		return _sorted(tasks)
	var out: Array = []
	for t in tasks:
		if _matches(t):
			out.append(t)
	return _sorted(out)


## Reorder a column's tasks by the current sort mode. Default ("created_asc")
## sorts by creation date, oldest first.
func _sorted(tasks: Array) -> Array:
	var out := tasks.duplicate()
	match str(filters.get("sort", "created_asc")):
		"created_asc":
			out.sort_custom(func(a, b): return a.created_at < b.created_at)
		"created_desc":
			out.sort_custom(func(a, b): return a.created_at > b.created_at)
		"updated":
			# Most recently edited first.
			out.sort_custom(func(a, b): return a.updated_at > b.updated_at)
		"priority":
			# High priority first (PRIORITIES runs low → critical).
			out.sort_custom(func(a, b):
				return Model.PRIORITIES.find(a.priority) > Model.PRIORITIES.find(b.priority))
		"due":
			# Soonest due first; tasks with no due date sink to the end.
			out.sort_custom(func(a, b):
				var ka: int = a.due_date if a.due_date != 0 else 0x7fffffff
				var kb: int = b.due_date if b.due_date != 0 else 0x7fffffff
				return ka < kb)
		"alpha":
			out.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
	return out


func _matches(t: Model.Task) -> bool:
	if filters.has("search") and filters["search"] != "":
		var q: String = filters["search"].to_lower()
		var hay := (t.title + " " + t.description + " " + " ".join(t.tags)).to_lower()
		if q not in hay:
			return false
	if filters.has("priority") and filters["priority"] != "" and filters["priority"] != "any":
		if t.priority != filters["priority"]:
			return false
	if filters.has("epic") and filters["epic"] != "" and filters["epic"] != "any":
		if t.epic_id != filters["epic"]:
			return false
	if filters.has("label") and filters["label"] != "" and filters["label"] != "any":
		if filters["label"] not in t.tags:
			return false
	if filters.has("date") and filters["date"] != "" and filters["date"] != "any":
		if not _date_matches(t, filters["date"]):
			return false
	return true


func _date_matches(t: Model.Task, mode_str: String) -> bool:
	var now := int(Time.get_unix_time_from_system())
	match mode_str:
		"overdue":
			# A passed date on a Done task is not overdue anymore.
			return t.status != "done" and t.due_date != 0 and t.due_date < now
		"today":
			if t.due_date == 0:
				return false
			return _same_day(t.due_date, now)
		"week":
			if t.due_date == 0:
				return false
			# Current calendar week: Monday 00:00:00 .. next Monday 00:00:00
			# (i.e. through Sunday 23:59:59), local time. Overdue tasks count
			# only if they fall inside this week, not long past ones.
			var week_start := _start_of_week(now)
			var week_end := _start_of_week(now + 7 * 86400)
			return t.due_date >= week_start and t.due_date < week_end
		"none":
			return t.due_date == 0
	return true


func _start_of_week(unix: int) -> int:
	# Unix time of the Monday (00:00:00, local) starting the week containing
	# `unix`. Back up whole days — never more than 6 — and read the engine's own
	# normalized calendar date each step, so the day-of-month can't under/overflow
	# across month boundaries.
	for k in 7:
		var probe := Time.get_datetime_dict_from_unix_time(unix - k * 86400)
		if probe["weekday"] == 1:  # weekday: 0=Sun..6=Sat
			probe["hour"] = 0
			probe["minute"] = 0
			probe["second"] = 0
			return Time.get_unix_time_from_datetime_dict(probe)
	return 0


func _same_day(a: int, b: int) -> bool:
	var da := Time.get_datetime_dict_from_unix_time(a)
	var db := Time.get_datetime_dict_from_unix_time(b)
	return da["year"] == db["year"] and da["month"] == db["month"] and da["day"] == db["day"]
