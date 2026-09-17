@tool
extends PanelContainer

## One task card: drag source + drop target, click-to-view. Flat dark panel
## modeled on the reference: title (top-left, wraps up to 2 lines) + a compact
## text-only priority label (top-right), a dim up-to-2-line description, then
## the tags as small tight pills that wrap, and a footer with the epic
## (bottom-left) and due date (bottom-right) shown as plain tinted text.

const Model = preload("res://addons/godoban/data/godoban_model.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

const TITLE_LINES := 2
const DESC_LINES := 2
## Hover tooltip body: the description re-flowed into a readable column that doesn't depend on
## how narrow the owning column has been dragged, capped so a wall of text can't cover the board.
const TOOLTIP_WIDTH := 320
const TOOLTIP_LINES := 12

signal open_requested(task_id: String)
## Right-click: the card's context menu was asked for, at `at` — the pointer's position in
## viewport pixels, which is the space a `PopupMenu` places itself in, embedded or not (see
## `godoban_main_screen._open_card_menu`). The card doesn't own that menu: it reports the
## request and lets the screen, which owns every overlay, put it up. That right-press is only
## half of the gesture, though: moving an already-open menu from one card to another is a click
## the card never hears, and the screen picks it up on its own (`godoban_main_screen._input`).
signal context_requested(task_id: String, at: Vector2)

var store: RefCounted
var task: Model.Task
var _show_epic := true
var _base_style: StyleBoxFlat
## The description label, kept so `_make_custom_tooltip` can ask whether the card is actually
## hiding anything (the label knows its own wrapped line count; the model doesn't).
var _desc_label: Label
## The owning column. Because this card is MOUSE_FILTER_STOP, a drag-and-drop over
## it is resolved against the card (Godot stops the ancestor walk here), so the
## card forwards the drop to its column. Set by the column when the card is built.
var _column = null

func setup(p_store: RefCounted, p_task: Model.Task, p_show_epic := true, p_column = null) -> void:
	store = p_store
	task = p_task
	_show_epic = p_show_epic
	_column = p_column
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	_build()

func _build() -> void:
	for c in get_children():
		c.free()
	_base_style = T.panel(T.BG_CARD(), T.BORDER_SOFT(), 8, 12, 12, 10, 10, 1)
	add_theme_stylebox_override("panel", _base_style)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	# Top row: title (expand) + priority badge (compact, top-right).
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)

	var title := _lines_label(task.title, T.TEXT(), 13, TITLE_LINES)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	var badge := _priority_badge()
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(badge)

	# Description: dim, smaller, always reserving two lines.
	var desc := _lines_label(task.description, T.TEXT_DIM(), 10, DESC_LINES)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	_desc_label = desc

	# Tags: small tight pills that wrap (only if any).
	if not task.tags.is_empty():
		var tags := HFlowContainer.new()
		tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tags.add_theme_constant_override("h_separation", 5)
		tags.add_theme_constant_override("v_separation", 4)
		for tag in task.tags:
			tags.add_child(_pill(tag))
		v.add_child(tags)

	# Footer: epic (bottom-left) ... due date (bottom-right), plain tinted text.
	var has_epic := _show_epic and task.epic_id != ""
	var has_due := task.due_date != 0
	if has_epic or has_due:
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 8)
		footer.size_flags_vertical = Control.SIZE_SHRINK_END
		v.add_child(footer)

		var left := HBoxContainer.new()
		left.add_theme_constant_override("separation", 5)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if has_epic:
			left.add_child(_epic_label())
		footer.add_child(left)

		if has_due:
			footer.add_child(_due_label())


## A label that hugs its own height (wraps to natural line count), capped at
## `lines` and ellipsized beyond that.
func _lines_label(text: String, col: Color, font_size: int, lines: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.max_lines_visible = lines
	return l


func _priority_color() -> Color:
	return T.priority_color(task.priority)


## Compact text-only priority indicator: a small right-justified label, colored
## by priority, top-right. No pill/box around it.
func _priority_badge() -> Control:
	var col := _priority_color()
	var l := Label.new()
	l.text = Model.priority_title(task.priority)
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## Epic at the bottom-left: plain text in the epic's own color (no icon). Wraps
## so a long epic title doesn't force the whole card (and column) wider than the
## column allows — it just takes another line instead.
func _epic_label() -> Label:
	var epic = store.board.get_epic(task.epic_id)
	var title: String = epic.title if epic else task.epic_id
	var col: Color = Color(epic.color) if epic else T.TEXT_DIM()
	var l := _footer_text(title, col, true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Due date at the bottom-right: a small calendar glyph + date text. Overdue
## turns both red.
func _due_label() -> Control:
	var overdue := task.status != "done" and task.due_date != 0 \
		and task.due_date < int(Time.get_unix_time_from_system())
	var col: Color = T.OVERDUE if overdue else T.TEXT_DIM()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -1)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cal := TextureRect.new()
	cal.texture = I.icon("calendar-days", 11)
	cal.modulate = col
	cal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cal)
	var l := _footer_text(Model.format_date(task.due_date), col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	return row


## A small tag pill (has a tight background). The pill is a faint tint of the
## foreground and the text is the opaque foreground: Godot's editor text colors
## carry alpha (font_color is white at 0.75, placeholder at 0.35), so stacking a
## translucent tag on a translucent background washed it into its own pill. Making
## the text opaque keeps tags legible in both dark and light themes.
func _pill(text: String) -> Control:
	var txt := T.TEXT()
	txt.a = 1.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _tint_pill(Color(txt, 0.12)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Truncated: pills wrap, so an over-long tag would take a line to itself and drag the
	# whole column wider with it. (No tooltip — the pill is MOUSE_FILTER_IGNORE and never
	# receives the hover.)
	p.add_child(_pill_text(Model.tag_label(text), txt))
	return p


func _pill_text(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _footer_text(text: String, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if wrap:
		# Take the width the card's footer leaves (after the due date) and wrap
		# inside it, rather than demanding its full text width as a minimum.
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Tight pill stylebox so tag boxes hug their text. Minimal horizontal padding.
func _tint_pill(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_border_width_all(0)
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


func _on_hover(hovered: bool) -> void:
	if _base_style == null:
		return
	var s: StyleBoxFlat = _base_style.duplicate()
	s.bg_color = T.BG_HOVER() if hovered else _base_style.bg_color
	s.border_color = T.BORDER() if hovered else _base_style.border_color
	add_theme_stylebox_override("panel", s)


## Hovering a card shows the description it had to cut off. This is Godot's own tooltip path:
## the viewport calls this override (even with no `tooltip_text` set), parents whatever we return
## to a `PopupPanel` themed as `TooltipPanel`, and handles placement, screen-edge flipping and
## dismissal. So we supply the body only — no panel, no margins, no positioning, no timer, and no
## popup of our own. The popup sizes itself to the returned control's minimum size, which is why
## the body carries an explicit width: a wrapping Label left to itself would report one word's
## width and the description would re-wrap to the column's width instead of a readable one.
##
## Returning `null` means "no tooltip" — that's the whole "only when there's something to see"
## rule: a description that already fits on the card, or an empty one, stays quiet.
##
## Note this fires on the *project-wide* tooltip delay (`gui/timers/tooltip_delay_sec`, 0.5s by
## default); Godot exposes no per-control delay, and `Viewport.show_tooltip` isn't script-callable,
## so the timing isn't ours to tune.
func _make_custom_tooltip(_for_text: String) -> Control:
	if _desc_label == null or task.description.is_empty():
		return null
	# `get_line_count()` is the total *wrapped* count — `max_lines_visible` only clamps what's
	# drawn — so this is a real truncation test, not a guess at the text's length.
	if _desc_label.get_line_count() <= DESC_LINES:
		return null
	var body := Label.new()
	body.text = task.description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.max_lines_visible = TOOLTIP_LINES
	body.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	body.add_theme_color_override("font_color", T.TEXT())
	body.add_theme_font_size_override("font_size", 11)
	return body


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		open_requested.emit(task.id)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# This asks the viewport rather than reading `event.position`: the engine hands a
		# `_gui_input` event already localized to the control it's going to, and the menu wants
		# viewport pixels. Right-click can't collide with dragging either — the engine only starts
		# a drag from a motion whose button mask holds LEFT, so this never reaches
		# `_get_drag_data` (which would put a drag preview up instead of a menu).
		context_requested.emit(task.id, get_viewport().get_mouse_position())


func _can_drop_data(_at: Vector2, data) -> bool:
	# A card is MOUSE_FILTER_STOP, so with the cursor over it the engine resolves the drop
	# against the card, not its column. Accept so the drop registers, and forward both the
	# drop and every hover to the column — the card is the drop target for the whole area
	# it covers, so without forwarding the position the insertion line would never appear
	# over a card and a release there would land in the wrong slot.
	if _column == null or not _column.can_accept_drop(data):
		return false
	_column.update_drop_hint(data, get_global_mouse_position())
	return true


func _drop_data(_at: Vector2, data) -> void:
	if _column != null:
		# `get_global_mouse_position()` is exactly the point the engine used — its drop
		# point is derived from the mouse — so no coordinate conversion is needed.
		_column.apply_drop(data, get_global_mouse_position())


func _get_drag_data(_at: Vector2) -> Variant:
	set_drag_preview(_make_preview())
	return {"type": "godoban_task", "task_id": task.id}


func _make_preview() -> Control:
	var preview := PanelContainer.new()
	var style := T.panel(T.BG_CARD(), _priority_color(), 6, 10, 10, 8, 8, 1)
	style.border_width_left = 3
	preview.add_theme_stylebox_override("panel", style)
	var l := Label.new()
	l.text = task.title
	l.add_theme_color_override("font_color", T.TEXT())
	preview.add_child(l)
	preview.custom_minimum_size = Vector2(size.x, 0)
	return preview
