@tool
extends ScrollContainer

## Full-page Overview tab — a dashboard that reads high-level → analytical →
## actionable: a row of summary stats, the primary by-status visualization, and
## the attention-needed lists. Rebuilds live from the store. "New Task" lives in
## the board toolbar, not here.

const Model = preload("res://addons/godoban/data/godoban_model.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const W = preload("res://addons/godoban/ui/overview_widgets.gd")

var store: RefCounted
var _body: VBoxContainer


## A panel card with a ready-made content column. Overview sections append their
## rows into `box`.
class CardPanel:
	extends PanelContainer

	var box: VBoxContainer

	func _init() -> void:
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		add_child(box)

func setup(p_store: RefCounted) -> void:
	store = p_store
	store.changed.connect(rebuild)
	_build()
	rebuild()

func _build() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	v.add_child(_title())

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	_body = body


func rebuild() -> void:
	for c in _body.get_children():
		c.free()
	_body.add_child(_summary_row())
	_body.add_child(_analytics_row())
	_body.add_child(_action_row())


# --- layout ------------------------------------------------------------------

func _title() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = "Overview"
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", T.TEXT())
	box.add_child(t)
	var s := Label.new()
	s.text = "Track the health and progress of your board at a glance."
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", T.TEXT_DIM())
	box.add_child(s)
	return box


## Four compact stat cards: total / completed / in progress / attention.
func _summary_row() -> Control:
	var c := _counts()
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	h.add_child(_stat_card("Total tasks", str(c.total), "Across all columns", 0.0, false))
	h.add_child(_stat_card("Completed", str(c.done), _suffix(c.total, c.done), _frac(c.done, c.total), true))
	h.add_child(_stat_card("In Progress", str(c.in_progress), _suffix(c.total, c.in_progress), _frac(c.in_progress, c.total), true))
	h.add_child(_stat_card("Overdue / Blocked", str(c.overdue), _suffix(c.total, c.overdue), _frac(c.overdue, c.total), true))
	return h


## The primary visualization row: by-status donut (widest), then priority bars
## and epic shares.
func _analytics_row() -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	var status := _status_card()
	status.size_flags_stretch_ratio = 1.6
	h.add_child(status)
	var priority := _priority_card()
	priority.size_flags_stretch_ratio = 1.0
	h.add_child(priority)
	var epic := _epic_card()
	epic.size_flags_stretch_ratio = 1.1
	h.add_child(epic)
	return h


## Bottom actionable row: overdue / no-epic / upcoming, one card each.
func _action_row() -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	h.add_child(_overdue_card())
	h.add_child(_no_epic_card())
	h.add_child(_upcoming_card())
	return h


# --- summary stat cards ------------------------------------------------------

func _counts() -> Dictionary:
	return {
		"total": store.board.tasks.size(),
		"done": store.board.tasks_in_status("done").size(),
		"in_progress": store.board.tasks_in_status("in_progress").size(),
		"overdue": _overdue().size(),
	}


func _frac(part: int, total: int) -> float:
	return float(part) / float(total) if total > 0 else 0.0


func _suffix(total: int, part: int) -> String:
	return "%d%% of all tasks" % _pct_int(part, total)


func _stat_card(title: String, big: String, caption: String, frac: float, ring: bool) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 8, 16, 16, 13, 13, 1))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", T.TEXT_DIM())
	box.add_child(t)

	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 10)
	var num := Label.new()
	num.text = big
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	num.add_theme_font_size_override("font_size", 26)
	num.add_theme_color_override("font_color", T.TEXT())
	hr.add_child(num)
	if ring:
		var rp := W.RingProgress.new()
		rp.value = frac
		rp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(rp)
	box.add_child(hr)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", T.TEXT_FAINT())
	box.add_child(cap)
	return card


# --- by status ---------------------------------------------------------------

func _status_card() -> Control:
	var card := _card()
	var box := card.box
	box.add_child(_card_title("Tasks by status"))

	var total: int = store.board.tasks.size()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	box.add_child(hb)

	var donut := W.Donut.new()
	donut.font = T.theme().default_font
	donut.total = total
	var segs: Array = []
	for status in Model.STATUSES:
		segs.append({"color": T.status_color(status), "value": store.board.tasks_in_status(status).size()})
	donut.segments = segs
	donut.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(donut)

	var legend := VBoxContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend.add_theme_constant_override("separation", 3)
	for status in Model.STATUSES:
		legend.add_child(_legend_row(status, store.board.tasks_in_status(status).size(), total))
	hb.add_child(legend)
	return card


func _legend_row(status: String, count: int, total: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = T.status_color(status)
	h.add_child(dot)
	var l := Label.new()
	l.text = Model.status_title(status)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", T.TEXT_DIM())
	h.add_child(l)
	var cnt := Label.new()
	cnt.text = str(count)
	cnt.add_theme_font_size_override("font_size", 12)
	cnt.add_theme_color_override("font_color", T.TEXT())
	h.add_child(cnt)
	var pct := Label.new()
	pct.text = "%d%%" % _pct_int(count, total)
	pct.add_theme_font_size_override("font_size", 12)
	pct.add_theme_color_override("font_color", T.TEXT_DIM())
	h.add_child(pct)
	return h


# --- by priority -------------------------------------------------------------

func _priority_card() -> Control:
	var card := _card()
	card.box.add_child(_card_title("Tasks by priority"))

	var bars: Array = []
	for p in Model.PRIORITIES:
		bars.append({"color": T.priority_color(p), "value": _priority_count(p), "label": Model.priority_title(p)})
	var vbars := W.VBars.new()
	vbars.font = T.theme().default_font
	vbars.bars = bars
	vbars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbars.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.box.add_child(vbars)
	return card


func _priority_count(p: String) -> int:
	var n := 0
	for t in store.board.tasks:
		if t.priority == p:
			n += 1
	return n


# --- by epic -----------------------------------------------------------------

func _epic_card() -> Control:
	var card := _card()
	var box := card.box
	box.add_child(_card_title("Tasks by epic"))

	if store.board.epics.is_empty():
		box.add_child(_list_row("No epics."))
	else:
		for e in store.board.epics:
			box.add_child(_epic_row(e))
		box.add_child(HSeparator.new())
		box.add_child(_footer_kv("Total epics", str(store.board.epics.size())))
	return card


func _epic_count(id: String) -> int:
	var n := 0
	for t in store.board.tasks:
		if t.epic_id == id:
			n += 1
	return n


func _epic_done(id: String) -> int:
	var n := 0
	for t in store.board.tasks:
		if t.epic_id == id and t.status == "done":
			n += 1
	return n


func _epic_row(e) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = Color(e.color)
	h.add_child(dot)
	var l := Label.new()
	l.text = e.title
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", T.TEXT())
	h.add_child(l)
	var total := _epic_count(e.id)
	var done := _epic_done(e.id)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 8
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = maxi(total, 1)
	bar.value = done
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(e.color)
	fill.set_corner_radius_all(4)
	var track := StyleBoxFlat.new()
	track.bg_color = T.BORDER()
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", track)
	h.add_child(bar)
	var cnt := Label.new()
	cnt.text = "%d/%d" % [done, total]
	cnt.add_theme_font_size_override("font_size", 12)
	cnt.add_theme_color_override("font_color", T.TEXT_DIM())
	h.add_child(cnt)
	return h


# --- actionable cards --------------------------------------------------------

func _overdue_card() -> Control:
	var od := _overdue()
	var rows: Array = []
	if od.is_empty():
		rows.append(_list_row("Nothing overdue."))
	else:
		for t in od:
			rows.append(_list_row("• " + t.title))
	return _action_card("Overdue", od.size(), rows)


func _no_epic_card() -> Control:
	var tasks_no_epic := _no_epic()
	var rows: Array = []
	if tasks_no_epic.is_empty():
		rows.append(_list_row("All tasks have an epic."))
	else:
		var limit := 5
		var i := 0
		for t in tasks_no_epic:
			if i >= limit:
				break
			rows.append(_list_row("• " + t.title))
			i += 1
		if tasks_no_epic.size() > limit:
			rows.append(_list_row("+ %d more" % (tasks_no_epic.size() - limit)))
	return _action_card("No epic", tasks_no_epic.size(), rows)


func _upcoming_card() -> Control:
	var up := _upcoming()
	var rows: Array = []
	if up.is_empty():
		rows.append(_list_row("No upcoming due dates."))
	else:
		var groups := {}
		var order: Array = []
		for t in up:
			var key := Model.format_date(t.due_date)
			if not groups.has(key):
				groups[key] = []
				order.append(key)
			groups[key].append(t)
		for key in order:
			rows.append(_date_header(key))
			for t in groups[key]:
				rows.append(_list_row("• " + t.title))
	return _action_card("Upcoming", up.size(), rows)


func _action_card(title: String, count: int, rows: Array) -> Control:
	var card := _card()
	var box := card.box
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", T.TEXT())
	hb.add_child(t)
	var c := Label.new()
	c.text = str(count)
	c.add_theme_font_size_override("font_size", 13)
	c.add_theme_color_override("font_color", T.TEXT_DIM())
	hb.add_child(c)
	box.add_child(hb)
	for r in rows:
		box.add_child(r)
	return card


# --- data queries ------------------------------------------------------------

func _overdue() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var out: Array = []
	for t in store.board.tasks:
		# A passed date on a Done task is not overdue anymore.
		if t.status != "done" and t.due_date != 0 and t.due_date < now:
			out.append(t)
	return out


func _no_epic() -> Array:
	var out: Array = []
	for t in store.board.tasks:
		if t.epic_id == "":
			out.append(t)
	return out


func _upcoming() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var out: Array = []
	for t in store.board.tasks:
		if t.due_date != 0 and t.due_date >= now:
			out.append(t)
	out.sort_custom(func(a, b): return a.due_date < b.due_date)
	return out


# --- widgets / shared helpers ------------------------------------------------

## A base panel card with an internal VBox; callers append content to `card.box`.
func _card() -> CardPanel:
	var card := CardPanel.new()
	card.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 8, 16, 16, 14, 14, 1))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return card


func _card_title(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", T.TEXT())
	return l


func _list_row(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", T.TEXT_DIM())
	return l


func _date_header(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", T.TEXT())
	return l


func _footer_kv(key: String, value: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = key
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", T.TEXT_DIM())
	h.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", T.TEXT())
	h.add_child(v)
	return h


func _pct_int(part: int, total: int) -> int:
	return roundi(_frac(part, total) * 100.0)
