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
## The card the current drag would be inserted *before* (null = end of the column).
var _drop_hint: Card
## True while a card is being dragged over this column, so the insertion line is drawn.
var _drop_hint_active := false
## Colour of the insertion line: the dragged task's priority, so the line matches the
## coloured border of the card riding under the cursor.
var _drop_hint_color := T.ACCENT()
## Full-rect overlay that paints the insertion line (see `_draw_drop_hint`).
var _drop_overlay: Control

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
	# The hint is refreshed on hover, but the engine only calls that hook while the mouse
	# actually MOVES — so expiring on "no refresh this frame" made the line blink off
	# whenever the cursor held still. Drive it from where the cursor *is* instead: keep the
	# line while the cursor is inside this column, drop it once the cursor leaves.
	if _drop_hint_active and not get_global_rect().has_point(get_global_mouse_position()):
		_clear_drop_hint()
	if not collapsed and orientation == "vertical" and not _sizing:
		_stretch_card_area()
func _build() -> void:
	if collapsed:
		_build_collapsed()
		return
	custom_minimum_size.x = 150
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 8, 10, 10, 10, 10, 1))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	# PASS so a drop over the column's own padding still reaches the column: STOP would
	# break the engine's drop walk here (see the DropArea note below).
	v.mouse_filter = Control.MOUSE_FILTER_PASS
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
	title.add_theme_color_override("font_color", T.TEXT())
	header.add_child(title)

	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", T.TEXT_DIM())
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
	add.add_theme_color_override("font_color", T.TEXT_DIM())
	add.add_theme_font_size_override("font_size", 18)
	add.pressed.connect(func(): add_requested.emit(status))
	header.add_child(add)

	if show_collapse:
		var collapse := Button.new()
		collapse.flat = true
		collapse.icon = T.arrow_icon(true, 12)
		collapse.tooltip_text = "Collapse %s" % Model.status_title(status)
		collapse.add_theme_color_override("icon_normal_color", T.TEXT_DIM())
		collapse.add_theme_color_override("icon_hover_color", T.TEXT())
		collapse.add_theme_color_override("icon_pressed_color", T.TEXT())
		collapse.add_theme_color_override("icon_focus_color", T.TEXT_DIM())
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

	# Invisible hit-area over the card region, added FIRST so it sits *under* the cards in
	# both draw and hit order. The engine's drop resolution breaks at the first
	# MOUSE_FILTER_STOP control that does not accept the drop, and the cards box below is
	# one of those — so without this overlay a drop in the gap between two cards, below
	# the last card, or into an empty column dead-ends on the container and never reaches
	# the column. Points over a card still resolve to the card (children are hit-tested
	# first), so this only ever sees the gaps.
	var drop_area := DropArea.new()
	drop_area.column = self
	# STOP: this overlay is the hit-test target for the gaps, so it must accept the drop
	# rather than fall through. Scroll events are propagated through STOP by the engine,
	# so the column still scrolls with the wheel over the gaps.
	drop_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_cards_wrap.add_child(drop_area)

	_cards_container = VBoxContainer.new()
	if orientation == "horizontal":
		_cards_container = HBoxContainer.new()
		_cards_container.add_theme_constant_override("separation", 10)
		_cards_wrap.add_theme_constant_override("margin_bottom", 10)
	else:
		_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards_container.add_theme_constant_override("separation", 10)
		_cards_wrap.add_theme_constant_override("margin_right", 10)
	# IGNORE: this box has no input behaviour of its own, and children are hit-tested
	# before their parent, so the cards still win over their own rects while points that
	# miss every card fall through to the DropArea underneath.
	_cards_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_wrap.add_child(_cards_container)

	var empty_hint := Label.new()
	empty_hint.text = "No features"
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.add_theme_color_override("font_color", T.TEXT_FAINT())
	empty_hint.add_theme_font_size_override("font_size", 13)

	_center = CenterContainer.new()
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# IGNORE so that with the scroll hidden (an empty column) a drop resolves through to
	# the column itself instead of dead-ending here — the DropArea lives inside the
	# hidden scroll and is not hit-tested in that state.
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(empty_hint)
	v.add_child(_center)

	# Insertion indicator. Added last so it paints above the cards, and IGNORE so it never
	# intercepts the drop itself. The PanelContainer fits it to the column's content rect.
	_drop_overlay = Control.new()
	_drop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_overlay.draw.connect(_draw_drop_hint)
	add_child(_drop_overlay)


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
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 8, 6, 6, 8, 8, 1))
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
	var count_cell := _vertical_label("0", 11, T.TEXT_DIM())
	_count_label = count_cell.get_child(0) as Label
	inner.add_child(count_cell)

	var t := _vertical_label(Model.status_title(status), 14, T.TEXT())
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
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 8, 10, 10, 6, 6, 1))
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
	title.add_theme_color_override("font_color", T.TEXT())
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(title)

	_count_label = Label.new()
	_count_label.text = "0"
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", T.TEXT_DIM())
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
	# Clear the insertion line whenever a drag ends, wherever it ended.
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_hint()
		return
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


func _can_drop_data(at: Vector2, data) -> bool:
	var ok := can_accept_drop(data)
	if ok:
		update_drop_hint(data, get_global_transform() * at)
	return ok


func _drop_data(_at: Vector2, data) -> void:
	apply_drop(data, get_global_mouse_position())


## Whether this column takes the given drag payload. Shared by the column's own drop
## hook and the DropArea overlay so the two can never disagree.
func can_accept_drop(data) -> bool:
	if collapsed:
		return false
	return data is Dictionary and data.get("type") == "godoban_task"


## The card a drop at `drop_pos` should be inserted *before*, or null to append. Walks the
## live cards in flow order, skips the card being dragged (it is still in the list
## mid-drag, and must never be its own anchor), and returns the first card whose centre
## along the flow axis lies past the drop point. A card's lower half and the next card's
## upper half therefore both mean "insert before the next card" — which is what makes
## releasing in the gap between cards 3 and 4 land the dragged card in slot 4.
##
## Cards are compared by GLOBAL rect centre against the global drop point: a
## ScrollContainer moves its child's rect rather than applying a canvas transform, so
## global rects already fold in every scroll offset between the card and the screen — the
## column's inner scroll and the board's outer one — and no conversion is needed.
func _anchor_before(dragged_id: String, drop_pos: Vector2) -> Card:
	var vertical := orientation != "horizontal"
	for c in _cards_container.get_children():
		var card := c as Card
		if card == null or card.task == null or card.task.id == dragged_id:
			continue
		var centre := card.get_global_rect().get_center()
		if (centre.y > drop_pos.y) if vertical else (centre.x > drop_pos.x):
			return card
	return null


## Shared move logic: the Godot `_drop_data` hook delegates here, and a child card that is
## hit-tested as the drop target calls the same path, so a drop on a card moves the task to
## this column's status just like a drop on the column's gap. `drop_pos` is in global
## (canvas) space, matching the cards' global rects — see `_anchor_before`.
func apply_drop(data, drop_pos: Vector2) -> void:
	var task = store.board.get_task(data["task_id"])
	if task == null:
		return
	var anchor := _anchor_before(task.id, drop_pos)
	var before_id: String = anchor.task.id if anchor != null else ""
	# Hide the line FIRST, then hand the move to the store *deferred*. `move_task` emits
	# `changed`, the board rebuilds synchronously, and `_rebuild` frees every column —
	# including this one, while this very method (or the card's) is still on the stack.
	# Touching `self` after that is a use-after-free, and freeing the drop target inside
	# its own drag callback is what takes the engine down. Deferring lets the drop handler
	# unwind cleanly before anything is freed.
	_clear_drop_hint()
	store.move_task.call_deferred(task.id, status, before_id)


## Recompute the insertion line for a drag hovering this column, and repaint it. The line
## takes the dragged task's priority colour — the same colour as the border on the card
## following the cursor — so the line reads as "this card goes here". Falls back to the
## accent colour when the payload names a task this board does not have.
func update_drop_hint(data, drop_pos: Vector2) -> void:
	var dragged := ""
	if data is Dictionary:
		dragged = str(data.get("task_id", ""))
	var task = store.board.get_task(dragged) if dragged != "" else null
	_drop_hint_color = T.priority_color(task.priority) if task != null else T.ACCENT()
	_drop_hint = _anchor_before(dragged, drop_pos)
	_drop_hint_active = true
	if _drop_overlay != null:
		_drop_overlay.queue_redraw()


func _clear_drop_hint() -> void:
	if not _drop_hint_active:
		return
	_drop_hint_active = false
	_drop_hint = null
	if _drop_overlay != null:
		_drop_overlay.queue_redraw()


## The last Card in the cards box, or null. The box also holds a trailing drop-zone pad,
## so `get_child(-1)` would not do.
func _last_card() -> Card:
	var cards := _cards_container.get_children()
	for i in range(cards.size() - 1, -1, -1):
		var card := cards[i] as Card
		if card != null:
			return card
	return null


## Paint the insertion line in the gap the drop would land in. Drawn on the overlay rather
## than the column so it sits above the cards, and positioned from the neighbouring cards'
## GLOBAL rects so it follows the scrolling content.
func _draw_drop_hint() -> void:
	if not _drop_hint_active or _cards_container == null or _drop_overlay == null:
		return
	var vertical := orientation != "horizontal"
	var box := _cards_container.get_global_rect()
	var origin := _drop_overlay.get_global_position()
	var at := 0.0
	if _drop_hint != null:
		# The top edge of the card it will be inserted before.
		var r := _drop_hint.get_global_rect()
		at = r.position.y if vertical else r.position.x
	else:
		# Appending: just past the last card. An empty column has no gap to point at.
		var last := _last_card()
		if last == null:
			return
		var e := last.get_global_rect().end
		at = e.y if vertical else e.x
	# Sit the line in the middle of the gap, so a card's lower half and the next card's
	# upper half clearly resolve to the same slot.
	var mid := at - _cards_container.get_theme_constant("separation") * 0.5
	var a: Vector2
	var b: Vector2
	if vertical:
		a = Vector2(box.position.x, mid) - origin
		b = Vector2(box.end.x, mid) - origin
	else:
		a = Vector2(mid, box.position.y) - origin
		b = Vector2(mid, box.end.y) - origin
	_drop_overlay.draw_line(a, b, _drop_hint_color, 2.0)


## Invisible hit-area laid over the card region (see `_build`). It exists because the
## engine's drop resolution breaks at the first MOUSE_FILTER_STOP control that does not
## accept the drop, and the cards box is one of those: without this, a drop in the gap
## between two cards, below the last card, or into an empty column never reaches the
## column. An inner class keeps it to one file — no extra .gd to import.
class DropArea extends Control:
	var column = null  # untyped: the column is this file's outer script

	func _can_drop_data(_at: Vector2, data) -> bool:
		return column != null and column.can_accept_drop(data)

	func _drop_data(_at: Vector2, data) -> void:
		if column != null:
			column.apply_drop(data, get_global_mouse_position())
