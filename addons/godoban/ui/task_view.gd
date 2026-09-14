@tool
extends "res://addons/godoban/ui/modal_overlay.gd"

## The read-only task view: what a card click opens. Facts, tags and the description, with an
## **Edit** button that hands off to the task editor.
##
## Chrome — backdrop, centered bordered panel, header ✕, Esc, fit-to-window — is `modal_overlay.gd`'s,
## the same as the epics and tags dialogs; `T` and `I` come from there.
##
## **No `store.changed` subscription, on purpose.** This is a snapshot of one task, and it is modal
## over the only surface that can mutate the board — so there is no change it could miss. `open()`
## re-renders from scratch every time, so the next open is always current. Subscribing would only
## buy a repaint nobody can trigger.

const Model = preload("res://addons/godoban/data/godoban_model.gd")

## Wider than the other dialogs (and a touch wider than the editor's 660) because the facts are a
## two-column grid, not a list.
const PANEL_W := 680.0
## Fixed width of a fact's name column, so every value in a column starts at the same x regardless
## of how long its own name is.
const FIELD_NAME_W := 78.0
const ICON := 14

## The Edit button, i.e. "take me to the editor for this task". The view hides itself first, so the
## editor arrives as the topmost overlay.
signal edit_requested(task_id: String)

var store: RefCounted
var _task_id := ""
## Held rather than read off the task: a theme rebuild replaces the header — and the heading Label
## with it — and the rebuild has to be able to put the title back. Plain members cross a rebuild
## untouched; child nodes do not.
var _task_title := ""
var _facts: GridContainer
var _tags: HFlowContainer
var _desc: Label


func setup(p_store: RefCounted) -> void:
	store = p_store
	list_min_h = 180.0
	list_max_h = 660.0
	_build()
	_on_rebuilt()


## Everything that follows `_build()` — run once here and again by `rebuild_for_theme`.
func _on_rebuilt() -> void:
	panel.custom_minimum_size.x = PANEL_W
	# The heading is the task's own name, so it is content and can be any length. Clipping drops its
	# minimum width to ~1px, so the panel can never be widened past the window by a long title; the
	# stretch ratio (against the spacer's 1) is what stops the spacer from taking half the freed
	# width, which would leave the title an ellipsis at half a header.
	_contain_label(heading)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_stretch_ratio = 100.0
	_render()


## Show `task_id`. Re-resolved from the store by id rather than handed a `Task`, so a stale
## reference can't outlive a reload.
func open(task_id: String) -> void:
	var task: Model.Task = store.board.get_task(task_id)
	if task == null:
		return
	_task_id = task_id
	_task_title = task.title
	# May rebuild the whole modal if the palette moved since it was last built — which re-runs
	# `_on_rebuilt()` → `_render()` — so the title has to be set before this, and re-set after it.
	_show_modal()
	_set_heading(_task_title)
	_render()


func _modal_title() -> String:
	return _task_title


# --- body ---------------------------------------------------------------------


## Structure only. Per-task content is `_render()`'s job, because this runs again on every theme
## rebuild and there may be no task at all at setup time.
func _build_body(parent: VBoxContainer) -> void:
	# One scroll region for the whole information body, not a scroll box inside the description:
	# two nested `ScrollContainer`s fight over one wheel, and the base's `_apply_fit` sizes exactly
	# one `list`. So the header stays pinned while facts, tags and description scroll together.
	# Horizontal scrolling off is also what bounds the width, which is what makes the description
	# wrap.
	list = ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(list)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	list.add_child(body)

	_facts = GridContainer.new()
	_facts.columns = 2
	_facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts.add_theme_constant_override("h_separation", 24)
	_facts.add_theme_constant_override("v_separation", 10)
	body.add_child(_facts)

	body.add_child(HSeparator.new())

	body.add_child(_section_head("tag", "Tags"))
	_tags = HFlowContainer.new()
	_tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tags.add_theme_constant_override("h_separation", 5)
	_tags.add_theme_constant_override("v_separation", 4)
	body.add_child(_tags)

	body.add_child(HSeparator.new())

	body.add_child(_section_head("book-open", "Description"))
	# Recessed rather than a second panel: T.BG() is a step *away* from the panel's own
	# BG_PANEL(), so the inset reads as sunk into the card.
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", T.panel(T.BG(), T.BORDER(), 8, 12, 12, 12, 12, 1))
	body.add_child(inset)

	# Plain text, wrapped: the label is exactly as tall as its paragraph, so `list` is the only
	# thing that ever scrolls.
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc.add_theme_font_size_override("font_size", 12)
	_desc.add_theme_color_override("font_color", T.TEXT())
	_desc.add_theme_constant_override("line_spacing", 3)
	inset.add_child(_desc)


## Repaint every per-task value into the nodes `_build_body` made. Safe to run with no task loaded
## (which is the state a theme rebuild after `setup()` finds it in).
func _render() -> void:
	if _desc == null:
		return
	for c in _facts.get_children():
		_facts.remove_child(c)
		c.free()
	for c in _tags.get_children():
		_tags.remove_child(c)
		c.free()
	_desc.text = ""

	if _task_id == "":
		return
	var task: Model.Task = store.board.get_task(_task_id)
	if task == null:
		return

	# Status, priority and epic are plain text in their own color — the color is the signal, so a
	# chip around it only adds a second frame around a word that is already telling you the answer.
	_facts.add_child(_field("circle-dot", "Status",
			_value(Model.status_title(task.status), T.status_color(task.status))))
	_facts.add_child(_field("flag", "Priority",
			_value(Model.priority_title(task.priority), T.priority_color(task.priority))))
	_facts.add_child(_field("layers-2", "Epic", _epic_value(task)))
	_facts.add_child(_field("calendar-plus", "Created at",
			_value(Model.format_date(task.created_at), T.TEXT())))
	_facts.add_child(_field("calendar-days", "Due date", _due_value(task)))
	_facts.add_child(_field("clock", "Updated at",
			_value(Model.format_date(task.updated_at), T.TEXT())))

	if task.tags.is_empty():
		# A dim placeholder rather than nothing, so the row keeps its height and the panel doesn't
		# jump between tasks with and without tags.
		var none := Label.new()
		none.text = "No tags"
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", T.TEXT_FAINT())
		_tags.add_child(none)
	else:
		for tag in task.tags:
			_tags.add_child(_tag_pill(tag))

	# Last, and after every other height-affecting change, so the list is measured against the final
	# text. A dim placeholder for an empty description, the same as the tag row's "No tags" — an
	# empty inset reads as a rendering bug rather than as "nothing written here".
	var has_desc := not task.description.strip_edges().is_empty()
	_desc.text = task.description if has_desc else "No description"
	_desc.add_theme_color_override("font_color", T.TEXT() if has_desc else T.TEXT_FAINT())
	# The list's height depends on the description's, which only settles across layout passes —
	# `_fit_to_view` re-queues itself until the answer stops moving.
	_fit_to_view()


# --- value parts --------------------------------------------------------------


## One fact: glyph, fixed-width name, then the value. Two of these are one grid row, which is where
## the mockup's Status|Priority, Epic|Created-at, Due|Updated pairing comes from.
func _field(icon: String, name: String, value: Control) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var glyph := TextureRect.new()
	glyph.texture = I.icon(icon, ICON)
	glyph.custom_minimum_size = Vector2(ICON, ICON)
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.modulate = T.TEXT()
	row.add_child(glyph)

	var label := Label.new()
	label.text = name
	label.custom_minimum_size.x = FIELD_NAME_W
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", T.TEXT())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	row.add_child(value)
	return row


## A plain fact value. Empty renders as a faint dash so an absent value keeps the row's height and
## the grid stays rectangular. Clipped and expanding: the leftover width in the cell is what a long
## value gets to use, and nothing it contains can widen the panel.
func _value(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text if text != "" else "—"
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col if text != "" else T.TEXT_FAINT())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The due date, red while it's late — the same rule the card's footer uses: a done task is never
## overdue, and 0 means no date at all.
func _due_value(task: Model.Task) -> Label:
	var overdue := task.status != "done" and task.due_date != 0 \
		and task.due_date < int(Time.get_unix_time_from_system())
	return _value(Model.format_date(task.due_date), T.OVERDUE if overdue else T.TEXT())


## The epic's title in the epic's own color, or a dash when the task has none. A dangling `epic_id`
## (the epic was deleted) falls back to showing the raw id, exactly as the card does.
##
## No length cap: `_value` clips to the width the cell actually has, so the title uses whatever room
## is there rather than a fixed character budget.
func _epic_value(task: Model.Task) -> Label:
	if task.epic_id == "":
		return _value("", T.TEXT())
	var epic = store.board.get_epic(task.epic_id)
	if epic == null:
		return _value(task.epic_id, T.TEXT())
	return _value(epic.title, Color(epic.color))


## A board tag: a rounded rectangle, built to match the task editor's tag chip
## (`task_editor.gd:710`) — same `T.pill` fill and radius, same text size — minus the editor's
## asymmetric right margin, which only exists to tuck its remove button in. Not a stadium: a tag is
## a discrete label, not a severity, so it has no business wearing a status chip's outline.
## The text is made opaque: Godot's editor text colors carry alpha (font_color is white at 0.75),
## and a translucent tag on a translucent ground washes into its own background (see `card.gd`).
func _tag_pill(tag: String) -> Control:
	var txt := T.TEXT()
	txt.a = 1.0
	var sb := T.pill(Color(txt, 0.12), 6)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_pill_label(Model.tag_label(tag), txt))
	return p


func _pill_label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A small "glyph + word" heading for the body's sections. Same weight as the facts: it names what is
## under it, and a label you have to squint at is a label that failed.
func _section_head(icon: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var glyph := TextureRect.new()
	glyph.texture = I.icon(icon, 13)
	glyph.custom_minimum_size = Vector2(13, 13)
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.modulate = T.TEXT()
	row.add_child(glyph)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", T.TEXT())
	row.add_child(label)
	return row


# --- header -------------------------------------------------------------------


## The handoff. Hide first: the editor is a sibling *below* this modal, so emitting while still
## visible would leave the editor filling itself in underneath an opaque backdrop.
## The pencil is the same control the Epics, Tags and Boards rows use for their rename — quiet
## until you point at it, accent under the pointer — so "change this" reads the same everywhere.
func _modal_header_extras() -> Control:
	var b := _icon_button("pencil", "Edit task")
	_tint_button_icon(b, T.TEXT_FAINT(), T.ACCENT())
	b.pressed.connect(func():
		hide()
		edit_requested.emit(_task_id))
	return b
