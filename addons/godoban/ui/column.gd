@tool
extends PanelContainer

## A godoban column: flat dark panel with header (title + count pill + "+")
## and a scroll of cards. Doubles as a drop target for dragging tasks.

const Card = preload("res://addons/godoban/ui/card.gd")
const Model = preload("res://addons/godoban/data/godoban_model.gd")
const T = preload("res://addons/godoban/ui/theme.gd")

## Epic mode: a column sizes to its content up to FIT_MAX_CARDS cards, then the
## inner scroll takes over. Off (default) means "all" mode: expand to fill the
## available height.
const FIT_MAX_CARDS := 3
## How far the ScrollContainer's child (the cards box) may legitimately sit inside
## the scroll viewport before we call it stale. A vertical scrollbar plus rounding
## normally eats only a few px; anything past this is the engine having skipped the
## nested re-layout, not a real content measurement.
const CONTENT_TOLERANCE := 24.0

signal open_requested(task_id: String)
signal add_requested(status: String)
## Fired when the user toggles the collapse arrow (board columns only). Carries
## the target status and the *new* collapsed state (true = collapse to a pill).
signal collapse_toggled(status: String, collapsed: bool)

var store: RefCounted
var status: String
var show_epic := true
## When true (board "all" mode) the header shows a collapse arrow and the column
## can fold into a vertical pill. Disabled in per-epic boards, where collapsing is
## handled at the epic level instead.
var show_collapse := true
## When true the column renders as a narrow vertical pill (dot + title + count),
## or a thin horizontal bar in "horizontal" orientation.
var collapsed := false
## When true the column fits its content (capped & scrollable) instead of
## expanding to fill the parent — used by the per-epic boards.
var fit := false
## "vertical" (default) stacks cards down the column; "horizontal" flows them
## across the row. The board sets this per status group based on its orientation.
var orientation := "vertical"
var _sizing := false
## Set between the two passes of a width "kick": the scroll's min width has been
## briefly raised to force it to fill the column, and needs to be reset next pass.
var _kick_pending := false
var _cards_container: BoxContainer
var _cards_wrap: MarginContainer
var _scroll: ScrollContainer
var _center: CenterContainer
var _count_label: Label
var _content: VBoxContainer
var _header: HBoxContainer

func setup(p_store: RefCounted, p_status: String) -> void:
	store = p_store
	status = p_status
	_build()
	set_process(true)


## Safety net for the editor's skipped card-area relayout: the EDITOR can widen a
## column without re-laying-out the card area, and the resize notification alone
## isn't always enough to catch it. Re-check each frame and stretch back (cheap:
## one `absf` width check + a stale-content check; no-op when the width matches).
func _process(_delta: float) -> void:
	if not collapsed and orientation == "vertical" and not _sizing:
		_stretch_card_area()
func _build() -> void:
	if collapsed:
		_build_collapsed()
		return
	custom_minimum_size.x = 150
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER_SOFT, 8, 10, 10, 10, 10, 1))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_content = v
	add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_header = header
	v.add_child(header)

	var dot := _status_dot()
	header.add_child(dot)

	var title := Label.new()
	title.text = Model.status_title(status)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", T.TEXT)
	header.add_child(title)

	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", T.TEXT_DIM)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_count_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var add := Button.new()
	add.text = "+"
	add.flat = true
	add.tooltip_text = "Add task to %s" % Model.status_title(status)
	T.flat_button(add)
	add.add_theme_color_override("font_color", T.TEXT_DIM)
	add.add_theme_font_size_override("font_size", 18)
	add.pressed.connect(func(): add_requested.emit(status))
	header.add_child(add)

	if show_collapse:
		var collapse := Button.new()
		collapse.flat = true
		collapse.icon = T.arrow_icon(true, 12)
		collapse.tooltip_text = "Collapse %s" % Model.status_title(status)
		collapse.add_theme_color_override("icon_normal_color", T.TEXT_DIM)
		collapse.add_theme_color_override("icon_hover_color", T.TEXT)
		collapse.add_theme_color_override("icon_pressed_color", T.TEXT)
		collapse.add_theme_color_override("icon_focus_color", T.TEXT_DIM)
		collapse.pressed.connect(func(): collapse_toggled.emit(status, true))
		header.add_child(collapse)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if orientation == "horizontal":
		# A row: cards flow sideways, the row scrolls horizontally instead of
		# vertically. Width is the bounded axis now.
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)

	# Gutter keeps the scrollbar clear of the cards (right for columns, bottom for rows).
	_cards_wrap = MarginContainer.new()
	_cards_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_wrap)

	_cards_container = VBoxContainer.new()
	if orientation == "horizontal":
		_cards_container = HBoxContainer.new()
		_cards_container.add_theme_constant_override("separation", 10)
		_cards_wrap.add_theme_constant_override("margin_bottom", 10)
	else:
		_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards_container.add_theme_constant_override("separation", 10)
		_cards_wrap.add_theme_constant_override("margin_right", 10)
	_cards_wrap.add_child(_cards_container)

	var empty_hint := Label.new()
	empty_hint.text = "No features"
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.add_theme_color_override("font_color", T.TEXT_FAINT)
	empty_hint.add_theme_font_size_override("font_size", 13)

	_center = CenterContainer.new()
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.add_child(empty_hint)
	v.add_child(_center)


## A small colored dot marking the column's status, sized to hug the header.
func _status_dot() -> Control:
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := StyleBoxFlat.new()
	s.bg_color = T.status_color(status)
	s.set_corner_radius_all(4)
	s.set_border_width_all(0)
	s.set_content_margin_all(0)
	dot.add_theme_stylebox_override("panel", s)
	return dot


## The collapsed layout: a narrow vertical pill with the status dot, the title
## and the task count, both rotated to read bottom-to-top. The whole pill is a
## click target that re-expands the column.
func _build_collapsed() -> void:
	# A collapsed column shrinks along its cross axis while keeping its extent
	# along the flow axis. Vertical orientation → a narrow tall pill; horizontal
	# orientation → a thin wide bar.
	if orientation == "horizontal":
		_build_collapsed_row()
	else:
		_build_collapsed_pill()


## Collapsed vertical orientation: a narrow 32px-wide pill spanning the full
## height. The status dot, title and count are rotated to read bottom-to-top
## (dot, title, count from the bottom), so the whole column folds into a sliver.
func _build_collapsed_pill() -> void:
	custom_minimum_size.x = 32
	custom_maximum_size.x = 32
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER_SOFT, 8, 6, 6, 8, 8, 1))
	if not show_collapse:
		return

	var btn := Button.new()
	btn.flat = true
	btn.tooltip_text = "Expand %s" % Model.status_title(status)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	btn.pressed.connect(func(): collapse_toggled.emit(status, false))
	add_child(btn)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner)

	# Kept top-to-bottom as count, title, bullet so that reading the pill from
	# the bottom up gives: bullet, title, count (title + count run bottom-to-top).
	# The count is rotated to match the title. Keep `_count_label` pointing at the
	# enclosed Label so set_tasks() can still update it.
	var count_cell := _vertical_label("0", 11, T.TEXT_DIM)
	_count_label = count_cell.get_child(0) as Label
	inner.add_child(count_cell)

	var t := _vertical_label(Model.status_title(status), 14, T.TEXT)
	inner.add_child(t)

	var dot := _status_dot()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(dot)


## Collapsed horizontal orientation: a thin full-width bar with the status dot,
## title and count laid out left-to-right (horizontal text). Occupies minimal
## height so a collapsed row returns its vertical space to the board.
func _build_collapsed_row() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL, T.BORDER_SOFT, 8, 10, 10, 6, 6, 1))
	if not show_collapse:
		return

	var btn := Button.new()
	btn.flat = true
	btn.tooltip_text = "Expand %s" % Model.status_title(status)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	btn.pressed.connect(func(): collapse_toggled.emit(status, false))
	add_child(btn)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner)

	var dot := _status_dot()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(dot)

	var title := Label.new()
	title.text = Model.status_title(status)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", T.TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(title)

	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", T.TEXT_DIM)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(_count_label)


## A label rotated a full 90° so the glyphs themselves read bottom-to-top, as a
## narrow cell (used for both the rotated title and the task count). The cell
## reports a *swapped* minimum size (line-height wide ×
## text-length tall) so the surrounding container reserves the right footprint
## for the rotated text instead of the label's upright size.
func _vertical_label(text: String, font_size: int, color: Color) -> Control:
	var th := T.theme()
	var font = th.default_font if th else null

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font:
		label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centre alignment: the glyphs are drawn centred inside the label's rect, so
	# no matter the rect size, its centre IS the glyph centre. That lets us pivot
	# on the box centre and keep the rotated text perfectly centred.
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# True glyph box from the font (the Label's reported minimum is padded). The
	# label rect is sized at or above that box so it never gets clamped.
	var w := 0.0
	var h := 0.0
	if font:
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		h = font.get_height(font_size)
	var gmin := label.get_combined_minimum_size()
	if w <= 0.0:
		w = gmin.x
	if h <= 0.0:
		h = gmin.y
	label.size = Vector2(maxf(gmin.x, w), maxf(gmin.y, h))

	label.pivot_offset = label.size * 0.5
	label.rotation = -PI / 2.0  # glyphs read bottom-to-top
	# Land the (sized) box centre on the cell centre; the cell footprint is the
	# true glyph box swapped (thickness × text-length).
	label.position = Vector2(h, w) * 0.5 - label.size * 0.5

	var cell := Control.new()
	cell.custom_minimum_size = Vector2(h, w)  # thickness × text-length
	cell.size = cell.custom_minimum_size
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell


func is_collapsed() -> bool:
	return show_collapse and collapsed


func set_tasks(tasks: Array) -> void:
	if collapsed:
		_count_label.text = str(tasks.size())
		return
	for c in _cards_container.get_children():
		c.free()
	_count_label.text = str(tasks.size())
	for t in tasks:
		var card := Card.new()
		card.setup(store, t, show_epic, self)
		if orientation == "horizontal":
			card.custom_minimum_size.x = 220
			# In a row, cards stretch to fill the row when there's room, falling
			# back to their 220px floor (and the row scrollbar) when they exceed it.
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.open_requested.connect(func(id): open_requested.emit(id))
		_cards_container.add_child(card)
	# drop-zone padding so empty rows stay droppable
	var pad := Control.new()
	if orientation == "horizontal":
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_container.add_child(pad)

	if tasks.is_empty():
		_scroll.visible = false
		_center.visible = true
	else:
		_scroll.visible = true
		_center.visible = false
	_apply_sizing()


func _apply_sizing() -> void:
	if collapsed:
		return
	if orientation == "horizontal":
		# A row hugs its content height (one card tall); wide card runs overflow
		# sideways. Sizing recomputes on resize since cards wrap, see _notification.
		size_flags_vertical = Control.SIZE_FILL
		_recompute_fit()
		return
	if not fit:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size.y = 0
		return
	# Fit the content (header + up to FIT_MAX_CARDS cards); anything past that
	# is left to the inner ScrollContainer. NOTE: ScrollContainer reports a 0
	# minimum, so card heights are measured directly from the cards.
	size_flags_vertical = Control.SIZE_FILL
	custom_minimum_size.y = _fit_height()


func _fit_height() -> float:
	var style := get_theme_stylebox("panel") as StyleBox
	var margins := 0.0
	if style:
		margins = style.content_margin_top + style.content_margin_bottom
	var head := _header.get_combined_minimum_size().y
	var sep := _content.get_theme_constant("separation")
	var content_h := 0.0
	if _center.visible:
		content_h = _center.get_combined_minimum_size().y
	elif orientation == "horizontal":
		content_h = _horiz_cards_height()
	else:
		content_h = _cards_fit_height()
	return margins + head + sep + content_h


## Height to reserve for the cards, capped at FIT_MAX_CARDS real cards. Cards
## wrap taller than their single-line minimum once laid out, so prefer the
## actual `size.y` when available. The cap is by card COUNT, not pixels, so
## "up to 3 cards" always fits regardless of how tall each card ends up.
func _cards_fit_height() -> float:
	var cards := []
	for c in _cards_container.get_children():
		if c is Card:
			cards.append(c)
	var n := cards.size()
	if n == 0:
		return 0.0
	var limit := mini(n, FIT_MAX_CARDS)
	var height := 0.0
	for i in limit:
		var c = cards[i]
		var h: float = c.get_combined_minimum_size().y
		if float(c.size.y) > 0.0:
			h = float(c.size.y)
		height += h
	return height + limit * 10.0


## Height to reserve for a horizontal row: one card tall (the tallest card in
## the row), NOT the sum — cards are laid out side by side.
func _horiz_cards_height() -> float:
	var max_h := 0.0
	for c in _cards_container.get_children():
		if c is Card:
			var h: float = c.get_combined_minimum_size().y
			if float(c.size.y) > 0.0:
				h = float(c.size.y)
			max_h = maxf(max_h, h)
	return max_h


## The first layout sizes the column from card *minimum* heights, which is too
## short for wrapped titles. Re-measure once laid out (and on resize) so each
## column reserves room for the real rendered cards.
func _notification(what: int) -> void:
	if collapsed:
		return
	if what == NOTIFICATION_RESIZED and (fit or orientation == "horizontal") and not _sizing:
		call_deferred("_recompute_fit")


## Stretch the card area to the column's current content width. The editor can
## grow a column's width without re-laying-out the nested card area, so the inner
## ScrollContainer keeps its old (narrow) width: the cards stop short, the
## vertical scrollbar sits right beside them, and a band of empty column
## background shows to the right.
##
## Writing the scroll's `size` back does not stick — the parent re-lays the scroll
## from its reported minimum on the next pass, so the manual width is overwritten
## and it stays a step behind. Instead we *kick* it: briefly raising the scroll's
## minimum width to the column's content width forces the box up to the right
## size, which makes the ScrollContainer re-measure and re-fill its content. The
## min is then reset on the next pass (see `_kick_pending`), so the board can
## still shrink — a permanent min would ratchet the board's minimum width upward
## and stop the columns reflowing narrower.
## Guarded: this is a no-op when the engine already laid things out correctly.
func _stretch_card_area() -> void:
	if _content == null or _scroll == null or size.x <= 0.0:
		return
	var style := get_theme_stylebox("panel") as StyleBox
	var inset := 0.0
	if style:
		inset = style.content_margin_left + style.content_margin_right
	var target := maxf(1.0, size.x - inset)
	# Content can be stale even when the scroll width already matches: a width-only
	# resize skips re-laying-out the scroll's child. That child never exceeds the
	# viewport, so a big shortfall means the content wasn't re-laid out.
	var wrap := _scroll.get_child(0) as Control
	var content_stale := false
	if wrap != null:
		var vp: float = _scroll.size.x
		content_stale = wrap.size.x > vp + 1.0 or wrap.size.x < vp - CONTENT_TOLERANCE
	if absf(_scroll.size.x - target) > 1.0 or content_stale:
		_scroll.custom_minimum_size.x = target
		_kick_pending = true
		_scroll.queue_sort()
		_content.queue_sort()
		queue_sort()
	elif _kick_pending:
		# The column has filled; drop the temporary min-width kick so the board
		# keeps reflowing narrower under the Inspector.
		_scroll.custom_minimum_size.x = 0
		_kick_pending = false
		_scroll.queue_sort()


func _recompute_fit() -> void:
	if collapsed or (not fit and orientation != "horizontal") or _sizing:
		return
	_sizing = true
	var h := _fit_height()
	if absf(h - custom_minimum_size.y) > 0.5:
		custom_minimum_size.y = h
	_sizing = false


func _can_drop_data(_at: Vector2, data) -> bool:
	if collapsed:
		return false
	return data is Dictionary and data.get("type") == "godoban_task"


func _drop_data(_at: Vector2, data) -> void:
	if collapsed:
		return
	apply_drop(data)


## Shared move logic: the Godot `_drop_data` hook delegates here, and a child card
## that is hit-tested as the drop target calls the same path, so a drop on a card
## moves the task to this column's status just like a drop on the column's gap.
func apply_drop(data) -> void:
	var task = store.board.get_task(data["task_id"])
	if task == null:
		return
	store.move_task(task.id, status)
