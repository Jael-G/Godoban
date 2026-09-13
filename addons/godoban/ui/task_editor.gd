@tool
extends Control

## Create/edit popup. Validates a non-empty title, then store.upsert_task.
##
## Modal overlay: a dimmed backdrop over the main screen with a centered panel. Nothing reaches
## the store until Save — Cancel, the ✕, ESC and a backdrop click all discard the edit. The form
## between the pinned header and footer scrolls, so Save stays reachable on a short window.

const Model = preload("res://addons/godoban/data/godoban_model.gd")
const Calendar = preload("res://addons/godoban/ui/calendar_popup.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

signal closed
signal new_epic_requested

## Fixed width, so the two-column field grid never reflows as the title is typed.
const PANEL_W := 660.0
## Gap between the popup and the editor edges; also what a backdrop click can land on.
const OUTER_MARGIN := 20.0
## Vertical gap between the header, body and footer.
const BAND_SEP := 10
## Guards on the body's scroll window, which is otherwise the form's own height (see
## `_fit_to_view`): a cap so a tall form can't take over the editor, and a floor so a short
## window can't collapse it to a slit.
const BODY_MAX_H := 740.0
const BODY_MIN_H := 260.0
## The tag grid scrolls on its own so a board with hundreds of tags can't push the rest of the
## form out of reach. Sized to show four rows of pills.
const TAG_AREA_H := 134.0
const TAG_COLS := 3

var store: RefCounted
var editing_id := ""  # "" == new task
var _default_status := "backlog"
var _due_ts := 0
var _tags: Array = []

var _panel: PanelContainer
## True while a fit is already queued for the end of this frame; see `_fit_to_view`.
var _fit_queued := false
var _header: HBoxContainer
var _head_icon: TextureRect
var _head_title: Label
var _scroll: ScrollContainer
var _footer: HBoxContainer
var _title: LineEdit
var _status_btn: OptionButton
var _priority_btn: OptionButton
var _epic_btn: OptionButton
var _epic_add: Button
var _due_btn: Button
var _chips_box: PanelContainer
var _chips: HFlowContainer
var _tag_search: LineEdit
var _tag_count: Label
var _create_row: Button
var _tag_grid: GridContainer
var _desc: TextEdit
var _save_btn: Button
var _delete_btn: Button
var _calendar: Calendar
var _confirm: PopupPanel

func setup(p_store: RefCounted) -> void:
	store = p_store
	_build()


func _build() -> void:
	# Full-rect, on top of the board. The backdrop swallows clicks landing outside the panel,
	# which is what makes the popup modal.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	# Insets the panel and centers it: the panel shrinks to its own size in both axes.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, int(OUTER_MARGIN))
	add_child(margin)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = PANEL_W
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER(), 10, 14, 14, 14, 14, 1))
	margin.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", BAND_SEP)
	_panel.add_child(v)

	v.add_child(_build_header())
	v.add_child(_build_body())
	v.add_child(_build_footer())

	resized.connect(_fit_to_view)

	_calendar = Calendar.new()
	add_child(_calendar)
	_calendar.date_selected.connect(_on_date_selected)

	_build_confirm()


## Header: mode glyph, title, ✕. The title mirrors the Title field (see `_on_title_changed`).
func _build_header() -> Control:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)

	_head_icon = TextureRect.new()
	_head_icon.texture = I.icon("plus", 16)
	_head_icon.custom_minimum_size = Vector2(16, 16)
	_head_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_head_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head_icon.modulate = T.TEXT()
	_header.add_child(_head_icon)

	_head_title = Label.new()
	_head_title.text = "New Task"
	_head_title.add_theme_font_override("font", T.title_font(0.7, 1.0))
	_head_title.add_theme_font_size_override("font_size", 16)
	_head_title.add_theme_color_override("font_color", T.TEXT())
	_header.add_child(_head_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)

	var close := Button.new()
	close.icon = I.icon("x", 14)
	close.flat = true
	close.tooltip_text = "Close"
	T.flat_button(close)
	close.add_theme_color_override("icon_normal_color", T.TEXT_DIM())
	close.add_theme_color_override("icon_hover_color", T.TEXT())
	close.add_theme_color_override("icon_pressed_color", T.TEXT())
	close.pressed.connect(_cancel)
	_header.add_child(close)

	return _header


## The scrolling half of the popup: every field. Horizontal scrolling is off — the panel's
## width is set by `_fit_to_view`, so content wraps instead of sliding sideways.
func _build_body() -> Control:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BAND_SEP)
	_scroll.add_child(body)

	# Title/Status over Priority/Epic, in one grid so both rows share a single column split.
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 16)
	fields.add_theme_constant_override("v_separation", 12)
	body.add_child(fields)

	_title = LineEdit.new()
	_title.placeholder_text = "Task title"
	T.field(_title)
	_title.text_changed.connect(_on_title_changed)
	fields.add_child(_cell(_label("Title*"), _title))

	_status_btn = OptionButton.new()
	T.field(_status_btn)
	# Text only, like Priority below: the field's label already says what it is.
	for s in Model.STATUSES:
		_status_btn.add_item(Model.status_title(s))
	fields.add_child(_cell(_label("Status*"), _status_btn))

	_priority_btn = OptionButton.new()
	T.field(_priority_btn)
	# Text only, matching card.gd, which is deliberate about priority not being boxed.
	for p in Model.PRIORITIES:
		_priority_btn.add_item(Model.priority_title(p))
	_priority_btn.select(1)  # medium
	fields.add_child(_cell(_label("Priority"), _priority_btn))

	var epic_row := HBoxContainer.new()
	epic_row.add_theme_constant_override("separation", 6)
	_epic_btn = OptionButton.new()
	T.field(_epic_btn)
	_epic_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	epic_row.add_child(_epic_btn)
	_epic_add = Button.new()
	_epic_add.icon = I.icon("plus", 14)
	_epic_add.flat = true
	T.flat_button(_epic_add)
	_epic_add.tooltip_text = "New epic"
	_epic_add.add_theme_color_override("icon_normal_color", T.TEXT_DIM())
	_epic_add.add_theme_color_override("icon_hover_color", T.TEXT())
	_epic_add.add_theme_color_override("icon_pressed_color", T.TEXT())
	_epic_add.pressed.connect(func(): new_epic_requested.emit())
	epic_row.add_child(_epic_add)
	fields.add_child(_cell(_label("Epic"), epic_row))

	_due_btn = Button.new()
	_due_btn.text = "No due date"
	_due_btn.icon = I.icon("calendar", 14)
	_due_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	T.button(_due_btn)
	_due_btn.add_theme_color_override("icon_normal_color", T.TEXT_DIM())
	_due_btn.add_theme_color_override("icon_hover_color", T.TEXT())
	_due_btn.add_theme_color_override("icon_pressed_color", T.TEXT())
	_due_btn.pressed.connect(func(): _calendar.open_for_date(_due_ts))
	body.add_child(_cell(_label("Due date"), _due_btn))

	body.add_child(_cell(_label("Tags"), _build_tag_picker()))

	_desc = TextEdit.new()
	T.field(_desc)
	_desc.custom_minimum_size.y = 100
	body.add_child(_cell(_label("Description"), _desc))

	return _scroll


## The tag picker: selected tags, a filter field, then every tag the board already uses. One
## bordered section wraps all three — they are three views of a single choice rather than three
## controls — so only the search field, the one real input, carries its own fill.
func _build_tag_picker() -> Control:
	var section := PanelContainer.new()
	section.add_theme_stylebox_override("panel",
			T.panel(Color(0, 0, 0, 0), T.BORDER(), 8, 10, 10, 10, 10, 1))

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 8)
	section.add_child(block)

	# Borderless: it holds pills, which are their own shapes. Hidden while nothing is selected
	# (see `_refresh_chips`).
	_chips_box = PanelContainer.new()
	_chips_box.add_theme_stylebox_override("panel", T.panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0, 0, 0))
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 5)
	_chips.add_theme_constant_override("v_separation", 5)
	_chips_box.add_child(_chips)
	block.add_child(_chips_box)

	# The field and its length indicator share a row; the indicator sits outside the field's box
	# because `clear_button_enabled` already owns the right-hand slot inside a LineEdit.
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	var field := _build_search_field()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(field)
	_tag_count = Label.new()
	_tag_count.add_theme_font_size_override("font_size", 11)
	_tag_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Width reserved so the field doesn't twitch as the count goes from one digit to two.
	_tag_count.custom_minimum_size.x = 42
	_tag_count.visible = false
	search_row.add_child(_tag_count)
	block.add_child(search_row)

	var grid_scroll := ScrollContainer.new()
	grid_scroll.custom_minimum_size.y = TAG_AREA_H
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(grid_scroll)

	var grid_v := VBoxContainer.new()
	grid_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_v.add_theme_constant_override("separation", 4)
	grid_scroll.add_child(grid_v)

	# Shown only when the typed text matches nothing known (see `_query_is_new`).
	_create_row = Button.new()
	_create_row.flat = true
	_create_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_create_row.visible = false
	_create_row.add_theme_font_size_override("font_size", 12)
	T.flat_button(_create_row)
	_create_row.add_theme_color_override("font_color", T.ACCENT())
	_create_row.pressed.connect(_commit_tag_query)
	grid_v.add_child(_create_row)

	_tag_grid = GridContainer.new()
	_tag_grid.columns = TAG_COLS
	_tag_grid.add_theme_constant_override("h_separation", 6)
	_tag_grid.add_theme_constant_override("v_separation", 6)
	_tag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_v.add_child(_tag_grid)

	return section


## The tag filter: a field with the magnifier inside its left edge. LineEdit has no left-icon
## slot, and `clear_button_enabled` already owns the right one, so this is a composite — a
## field-styled panel carrying the border, with a chrome-less LineEdit and the glyph inside it.
## The wrapper owning the border is why focus has to be repainted onto it by hand.
func _build_search_field() -> Control:
	var box := PanelContainer.new()
	var border := func(focused: bool) -> StyleBoxFlat:
		return T.panel(T.BG_INPUT(), T.ACCENT() if focused else T.BORDER(), 6, 9, 9, 5, 5, 1)
	box.add_theme_stylebox_override("panel", border.call(false))
	# Clicking the field's own padding should land the caret, not fall through to the panel.
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_tag_search.grab_focus())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	var mag := TextureRect.new()
	mag.texture = I.icon("search", 14)
	mag.custom_minimum_size = Vector2(14, 14)
	mag.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mag.modulate = T.TEXT_DIM()
	row.add_child(mag)

	_tag_search = LineEdit.new()
	_tag_search.placeholder_text = "Search tags…"
	_tag_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Capped at the source rather than trimmed afterwards: the field stops accepting input (paste
	# included), so nothing is silently cut. `clamp_tag` still guards the commit path.
	_tag_search.max_length = Model.MAX_TAG_LEN
	# Bare inside the wrapper — two borders on one field reads as a mistake.
	for s in ["normal", "hover", "pressed", "focus"]:
		_tag_search.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	_tag_search.clear_button_enabled = true
	_tag_search.text_changed.connect(func(_t): _refresh_tag_grid())
	# Enter commits whatever is typed: a new tag, or an existing one picked from memory.
	_tag_search.text_submitted.connect(func(_t): _commit_tag_query())
	_tag_search.focus_entered.connect(func(): box.add_theme_stylebox_override("panel", border.call(true)))
	_tag_search.focus_exited.connect(func(): box.add_theme_stylebox_override("panel", border.call(false)))
	row.add_child(_tag_search)

	return box


func _build_footer() -> Control:
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_style_danger(_delete_btn)
	_delete_btn.pressed.connect(_delete)
	_footer.add_child(_delete_btn)
	var tail := Control.new()
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(tail)
	var cancel := Button.new()
	cancel.text = "Cancel"
	T.button(cancel)
	cancel.pressed.connect(_cancel)
	_footer.add_child(cancel)
	_save_btn = Button.new()
	_save_btn.text = "Add"
	T.button(_save_btn, true)
	_save_btn.pressed.connect(_save)
	_footer.add_child(_save_btn)
	return _footer


func _build_confirm() -> void:
	_confirm = PopupPanel.new()
	_confirm.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER(), 0, 24, 24, 24, 24, 2))
	_confirm.min_size = Vector2i(440, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	_confirm.add_child(cv)
	var title_msg := Label.new()
	title_msg.text = "Delete task"
	title_msg.add_theme_font_size_override("font_size", 18)
	cv.add_child(title_msg)
	var msg := Label.new()
	msg.text = "Delete this task? This cannot be undone."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 14)
	msg.add_theme_color_override("font_color", T.TEXT_DIM())
	msg.custom_minimum_size.x = 380
	cv.add_child(msg)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	var csc := Control.new()
	csc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(csc)
	var c_cancel := Button.new()
	c_cancel.text = "Cancel"
	T.button(c_cancel)
	c_cancel.pressed.connect(func(): _confirm.hide())
	crow.add_child(c_cancel)
	var c_del := Button.new()
	c_del.text = "Delete"
	_style_danger(c_del)
	c_del.pressed.connect(_do_delete)
	crow.add_child(c_del)
	cv.add_child(crow)
	add_child(_confirm)


## A field label. Full-strength text rather than the dim placeholder color: these name the
## fields, so they have to read at a glance.
func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", T.TEXT())
	l.add_theme_font_size_override("font_size", 11)
	return l


## A label stacked over its control, expanding so both grid cells share the panel's width.
func _cell(label: Control, control: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	v.add_child(label)
	v.add_child(control)
	return v


## Sizes the popup to its contents: the body's scroll window takes the form's own height and
## the header and footer sit outside it, so the panel is exactly as tall as the form — up to
## BODY_MAX_H, and down to BODY_MIN_H when the window is too short to show it all. Measured
## budget: the tallest form is 572px and the chrome 144px, so nothing scrolls at 716px or more.
##
## Deferred, and re-run until it converges (`_apply_fit`): a container's minimum size is only
## correct once the layout system has processed the children added this frame, and a flow
## container reports the height it wrapped to at its previous width. Read too early, the answer
## comes up 20px short — a scrollbar on a window with room to spare.
func _fit_to_view() -> void:
	# Collapsed: a burst of calls in one frame needs one fit, not several.
	if _fit_queued:
		return
	_fit_queued = true
	_apply_fit.call_deferred()


func _apply_fit() -> void:
	_fit_queued = false
	if not is_inside_tree() or _scroll == null or _header == null or _footer == null:
		return
	# PANEL_W, unless the editor is too narrow to hold it with its margins.
	_panel.custom_minimum_size.x = minf(PANEL_W, maxf(320.0, size.x - OUTER_MARGIN * 2.0))

	var sb := _panel.get_theme_stylebox("panel") as StyleBox
	var pad := 0.0
	if sb != null:
		pad = sb.content_margin_top + sb.content_margin_bottom
	var chrome := OUTER_MARGIN * 2.0 + pad + _header.size.y + _footer.size.y
	chrome += float(BAND_SEP) * 2.0  # the outer VBox's two gaps

	# As tall as the form is, not as tall as the window: the footer is pinned to the bottom of
	# the panel, so any height the body doesn't use collects as a gap above it.
	var body := _scroll.get_child(0) as Control
	var want := BODY_MAX_H
	if body != null:
		# Safe to read: the layout pass has been through by now (see `_fit_to_view`).
		want = body.get_combined_minimum_size().y
	var was := _scroll.custom_minimum_size.y
	_scroll.custom_minimum_size.y = clampf(minf(want, size.y - chrome), BODY_MIN_H, BODY_MAX_H)
	# Re-fit while the answer is still moving: the min size above settles over several layout
	# passes, so this takes as many frames as it needs rather than guessing a count.
	if not is_equal_approx(was, _scroll.custom_minimum_size.y):
		_fit_to_view()


func open_new(status: String) -> void:
	editing_id = ""
	_default_status = status
	_due_ts = 0
	_tags = []
	_title.text = ""
	_desc.text = ""
	_refresh_epics()
	_status_btn.select(Model.STATUSES.find(status))
	_priority_btn.select(1)
	_refresh_due()
	_reset_tag_ui()
	_save_btn.text = "Add"
	_delete_btn.visible = false
	_head_icon.texture = I.icon("plus", 16)
	_on_title_changed(_title.text)
	visible = true
	_fit_to_view()


func open_edit(task_id: String) -> void:
	var task = store.board.get_task(task_id)
	if task == null:
		return
	editing_id = task_id
	_default_status = task.status
	_due_ts = task.due_date
	_tags = task.tags.duplicate()
	_title.text = task.title
	_desc.text = task.description
	_refresh_epics()
	_status_btn.select(Model.STATUSES.find(task.status))
	_priority_btn.select(Model.PRIORITIES.find(task.priority))
	if task.epic_id != "":
		_select_epic(task.epic_id)
	_refresh_due()
	_reset_tag_ui()
	_save_btn.text = "Save"
	_delete_btn.visible = true
	_head_icon.texture = I.icon("pencil", 16)
	_on_title_changed(_title.text)
	visible = true
	_fit_to_view()
	# Caret at the end of the loaded name, so the first keystroke doesn't edit a word mid-way.
	_title.caret_column = _title.text.length()


## Keeps the popup's heading in step with the Title field; an emptied field has no name to
## show, so the heading falls back to naming the operation.
func _on_title_changed(text: String) -> void:
	var name := text.strip_edges()
	_head_title.text = name if name != "" else "New Task"


func _refresh_epics() -> void:
	_epic_btn.clear()
	_epic_btn.add_item("None")
	for e in store.board.epics:
		_epic_btn.add_item(e.title)
		_epic_btn.set_item_metadata(_epic_btn.item_count - 1, e.id)


func _select_epic(epic_id: String) -> void:
	for i in _epic_btn.item_count:
		if str(_epic_btn.get_item_metadata(i)) == epic_id:
			_epic_btn.select(i)
			return


func refresh_epics(select_id := "") -> void:
	_refresh_epics()
	if select_id != "":
		_select_epic(select_id)


func _on_date_selected(ts: int) -> void:
	_due_ts = ts
	_refresh_due()


func _refresh_due() -> void:
	if _due_ts == 0:
		_due_btn.text = "No due date"
	else:
		_due_btn.text = Model.format_date(_due_ts)


# --- tags ---------------------------------------------------------------------


## Clears the filter and rebuilds the tag UI. Signals are blocked around the clear so the
## field's own `text_changed` doesn't trigger a second, redundant rebuild.
func _reset_tag_ui() -> void:
	_tag_search.set_block_signals(true)
	_tag_search.clear()
	_tag_search.set_block_signals(false)
	_refresh_tags()


func _refresh_tags() -> void:
	_refresh_chips()
	_refresh_tag_grid()


## The selected tags, each a pill carrying its own remove button. The box is hidden when
## nothing is selected: the grid below already highlights what's picked, so an empty box would
## only repeat it.
func _refresh_chips() -> void:
	for c in _chips.get_children():
		c.free()
	_chips_box.visible = not _tags.is_empty()
	if _tags.is_empty():
		# The one row whose height changes while the popup is open, so the fit has to re-run.
		_fit_to_view()
		return
	for tag in _tags:
		_chips.add_child(_build_chip(String(tag)))
	_fit_to_view()


func _build_chip(tag: String) -> Control:
	# Opaque: editor text colors carry alpha, and a translucent tag on a translucent ground
	# washes into its own pill (same note as card.gd's pills).
	var txt := T.TEXT()
	txt.a = 1.0

	var chip := PanelContainer.new()
	var sb := T.pill(Color(txt, 0.12), 6)
	# Snug on the right: the remove button brings its own hover padding.
	sb.content_margin_left = 7
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	chip.add_child(row)

	var l := Label.new()
	# Only bites on a tag predating MAX_TAG_LEN; the tooltip below keeps the full text reachable.
	l.text = Model.tag_label(tag)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", txt)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if l.text != tag:
		l.tooltip_text = tag
	row.add_child(l)

	var rm := Button.new()
	rm.icon = I.icon("x", 10)
	rm.flat = true
	rm.tooltip_text = "Remove %s" % tag
	T.flat_button(rm)
	rm.add_theme_color_override("icon_normal_color", T.TEXT_DIM())
	rm.add_theme_color_override("icon_hover_color", T.OVERDUE)
	rm.add_theme_color_override("icon_pressed_color", T.OVERDUE)
	rm.pressed.connect(func(): _remove_tag(tag))
	row.add_child(rm)

	return chip


func _remove_tag(tag: String) -> void:
	_tags.erase(tag)
	# Deferred: the rebuild frees every chip, including the button still emitting this signal.
	call_deferred("_refresh_tags")


## Adds or drops a tag from the selection. Deferred for the same reason as `_remove_tag`.
func _toggle_tag(tag: String) -> void:
	if _tags.has(tag):
		_tags.erase(tag)
	else:
		_tags.append(tag)
	call_deferred("_refresh_tags")


## The board's tags matching the filter; the full set shows when nothing is typed, so the
## picker doubles as a browse of the vocabulary.
func _visible_tags() -> Array:
	var q := _tag_search.text.strip_edges().to_lower()
	var out: Array = []
	for tag in store.all_tags():
		if q == "" or String(tag).to_lower().contains(q):
			out.append(tag)
	return out


## The selected or board-wide tag matching `name` case-insensitively, or "" if there is none.
## Stops typing a name from spawning a near-duplicate of one already in use; stored case is kept.
func _match_tag(name: String) -> String:
	var want := name.to_lower()
	for t in _tags:
		if String(t).to_lower() == want:
			return String(t)
	for t in store.all_tags():
		if String(t).to_lower() == want:
			return String(t)
	return ""


## Whether the typed text is a tag the board doesn't have yet, and so worth offering to create.
## Comma-separated input is excluded: it is a batch, and no single Create row describes it.
func _query_is_new() -> bool:
	var q := _tag_search.text.strip_edges()
	if q == "" or q.contains(","):
		return false
	return _match_tag(q) == ""


## Commits the search box: Enter, or a click on the Create row. Comma-separated text adds one
## tag per part. This is the one place a tag enters a task, so `clamp_tag` is applied here: the
## field's `max_length` already stops over-long input, and this holds the rule for every path
## that doesn't come through the field.
func _commit_tag_query() -> void:
	var raw := _tag_search.text.strip_edges()
	if raw == "":
		return
	for part in raw.split(","):
		var p := Model.clamp_tag(part)
		if p == "":
			continue
		var existing := _match_tag(p)
		if existing != "":
			if not _tags.has(existing):
				_tags.append(existing)
		else:
			_tags.append(p)
	_tag_search.set_block_signals(true)
	_tag_search.clear()
	_tag_search.set_block_signals(false)
	_refresh_tags()


func _refresh_tag_grid() -> void:
	for c in _tag_grid.get_children():
		c.free()
	for tag in _visible_tags():
		_tag_grid.add_child(_build_tag_row(String(tag)))
	_create_row.visible = _query_is_new()
	if _create_row.visible:
		# Shows the name as it will be stored, so the cap is visible where it applies.
		_create_row.text = "+ Create \"%s\"" % Model.clamp_tag(_tag_search.text)
	_refresh_tag_count()


## The length indicator beside the tag field. It counts the raw field text — the string the
## cap counts — and turns danger red *at* the cap, where the field stops accepting input.
func _refresh_tag_count() -> void:
	var n := _tag_search.text.length()
	_tag_count.visible = n > 0
	if not _tag_count.visible:
		return
	_tag_count.text = "%d/%d" % [n, Model.MAX_TAG_LEN]
	_tag_count.add_theme_color_override("font_color",
			T.OVERDUE if n >= Model.MAX_TAG_LEN else T.TEXT_FAINT())


## One tag in the picker. Selected rows take an accent surface and a trailing check, so
## membership reads from more than color alone.
func _build_tag_row(tag: String) -> Button:
	var b := Button.new()
	b.text = Model.tag_label(tag)
	b.tooltip_text = tag
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	# Empty focus style: a focus ring over the selected surface reads as a second selection.
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Stadium pills (radius 14 against the row's ~30px height) with a surface in both states, so
	# a row reads as a chip rather than as clickable text. The fill is the text color at low
	# alpha, which moves away from whatever it sits on in either theme.
	var fill := Color(T.TEXT(), 0.10)
	var edge := T.BORDER_SOFT()
	if _tags.has(tag):
		b.add_theme_stylebox_override("normal", T.panel(Color(T.ACCENT(), 0.18), T.ACCENT(), 14, 11, 11, 6, 6, 1))
		b.add_theme_stylebox_override("hover", T.panel(Color(T.ACCENT(), 0.28), T.ACCENT(), 14, 11, 11, 6, 6, 1))
		b.add_theme_stylebox_override("pressed", T.panel(Color(T.ACCENT(), 0.34), T.ACCENT(), 14, 11, 11, 6, 6, 1))
		b.add_theme_color_override("font_color", T.TEXT())
		b.icon = I.icon("check", 12)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_theme_color_override("icon_normal_color", T.ACCENT())
	else:
		b.add_theme_stylebox_override("normal", T.panel(fill, edge, 14, 11, 11, 6, 6, 1))
		b.add_theme_stylebox_override("hover", T.panel(Color(T.TEXT(), 0.16), T.BORDER(), 14, 11, 11, 6, 6, 1))
		b.add_theme_stylebox_override("pressed", T.panel(Color(T.TEXT(), 0.20), T.BORDER(), 14, 11, 11, 6, 6, 1))
		b.add_theme_color_override("font_color", T.TEXT_DIM())
	b.pressed.connect(func(): _toggle_tag(tag))
	return b


# --- commit / dismiss ---------------------------------------------------------


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cancel()


## ESC dismisses, matching Cancel. `is_visible_in_tree` rather than `visible`: the whole main
## screen is hidden on another editor tab, and the popup shouldn't swallow ESC from there.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# The delete confirmation is a popup of its own and owns ESC while it's up.
		if _confirm != null and _confirm.visible:
			return
		_cancel()
		get_viewport().set_input_as_handled()


func _save() -> void:
	var title := _title.text.strip_edges()
	if title == "":
		_title.grab_focus()
		return
	var status: String = Model.STATUSES[_status_btn.selected]
	var priority: String = Model.PRIORITIES[_priority_btn.selected]
	var epic_id := ""
	if _epic_btn.selected > 0:
		epic_id = str(_epic_btn.get_item_metadata(_epic_btn.selected))
	var id: String = editing_id if editing_id != "" else store.board.new_id("task")
	store.upsert_task(id, title, _desc.text, status, priority, epic_id, _due_ts, _tags)
	hide()
	closed.emit()


func _delete() -> void:
	if editing_id == "":
		return
	_confirm.popup_centered()


func _do_delete() -> void:
	_confirm.hide()
	store.delete_task(editing_id)
	hide()
	closed.emit()


func _style_danger(b: Button) -> void:
	b.add_theme_stylebox_override("normal", T.panel(T.OVERDUE, T.OVERDUE.lightened(0.08), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("hover", T.panel(T.OVERDUE.lightened(0.10), T.OVERDUE.lightened(0.12), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("pressed", T.panel(T.OVERDUE.darkened(0.12), T.OVERDUE.darkened(0.04), 6, 12, 12, 5, 5, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for s in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, T.ACCENT_TEXT())


func _cancel() -> void:
	hide()
	closed.emit()
