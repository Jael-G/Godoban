@tool
extends Control

## Shared chrome for Godoban's modals — the epics dialog, the board switcher and the message box.
##
## The task editor is the reference look: a dimmed backdrop over the main screen with a centered,
## rounded, bordered panel whose header ends in a ✕. The other dialogs used to be `PopupPanel`s,
## i.e. Godot `Window`s. An *embedded* window paints its own opaque `embedded_border` frame behind
## its panel stylebox, and that frame has square corners — which is what showed as black wedges in
## the rounded corners. Drawing the modal as plain canvas UI instead leaves the panel's own
## stylebox as the only chrome there is, so the corner radius, the border, the ✕ and the centering
## are literally one piece of code for every popup and can't drift apart again.
##
## A subclass fills `_modal_icon` / `_modal_title` / `_build_body`, calls `_build()` from its
## `setup()`, and ends its `open()` with `_show_modal()`. `_cancel()` is what the ✕, ESC and a
## backdrop click all funnel into, so dismissal stays in one place.

const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

## Panel width. Narrower than the task editor's 660 on purpose: these dialogs hold lists, not forms.
const MODAL_W := 400.0
## Gap between the panel and the editor edges; also what a backdrop click can land on.
const OUTER_MARGIN := 20.0
## Vertical gap between the header, body and footer bands.
const BAND_SEP := 10

var panel: PanelContainer
var content: VBoxContainer
var header: HBoxContainer
## The list this modal scrolls, if any. Subclasses assign it in `_build_body` so `_apply_fit` can
## cap its height and keep the panel inside the editor; left null, the panel is just its content's
## height. `list_min_h` / `list_max_h` are the floor and ceiling it gets clamped between.
var list: ScrollContainer
var list_min_h := 150.0
var list_max_h := 320.0

## True while a fit is already queued for the end of this frame; see `_fit_to_view`.
var _fit_queued := false


func _build() -> void:
	# Full-rect, on top of the chrome. The backdrop swallows clicks landing outside the panel,
	# which is what makes the modal modal.
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

	panel = PanelContainer.new()
	panel.custom_minimum_size.x = MODAL_W
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The exact stylebox the task editor wears, so all three modals read as one family.
	panel.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER(), 10, 14, 14, 14, 14, 1))
	margin.add_child(panel)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", BAND_SEP)
	panel.add_child(content)

	header = _build_header()
	content.add_child(header)
	_build_body(content)

	resized.connect(_fit_to_view)
	# A `Control` is visible the moment it's built, unlike the `PopupPanel`s this replaces.
	visible = false


## Header: mode glyph, title, whatever the subclass adds, then the ✕. Same left-to-right order as
## the task editor's header, so the close control always sits in the same spot.
func _build_header() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var kind := _modal_icon()
	if kind != "":
		var glyph := TextureRect.new()
		glyph.texture = I.icon(kind, 16)
		glyph.custom_minimum_size = Vector2(16, 16)
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glyph.modulate = T.TEXT()
		h.add_child(glyph)

	var heading := _modal_title()
	if heading != "":
		var t := Label.new()
		t.text = heading
		t.add_theme_font_override("font", T.title_font(0.7, 1.0))
		t.add_theme_font_size_override("font_size", 16)
		t.add_theme_color_override("font_color", T.TEXT())
		h.add_child(t)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var extras := _modal_header_extras()
	if extras != null:
		h.add_child(extras)

	var close := Button.new()
	close.icon = I.icon("x", 14)
	close.flat = true
	close.tooltip_text = "Close"
	T.flat_button(close)
	close.add_theme_color_override("icon_normal_color", T.TEXT_DIM())
	close.add_theme_color_override("icon_hover_color", T.TEXT())
	close.add_theme_color_override("icon_pressed_color", T.TEXT())
	close.pressed.connect(_cancel)
	h.add_child(close)

	return h


## Reveals the modal and sizes its list to the window. `open()` on the subclass calls this last.
func _show_modal() -> void:
	visible = true
	_fit_to_view()


## Collapsed: a burst of calls in one frame needs one fit, not several.
func _fit_to_view() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_apply_fit.call_deferred()


func _apply_fit() -> void:
	_fit_queued = false
	if not is_inside_tree() or list == null:
		return
	var inner := list.get_child(0) as Control
	if inner == null:
		return
	var room := size.y - OUTER_MARGIN * 2.0 - _chrome_height()
	var was := list.custom_minimum_size.y
	list.custom_minimum_size.y = clampf(minf(inner.get_combined_minimum_size().y, room),
			list_min_h, list_max_h)
	# Re-fit while the answer is still moving: a container's minimum size settles over several
	# layout passes, so this takes as many frames as it needs rather than guessing a count.
	if not is_equal_approx(was, list.custom_minimum_size.y):
		_fit_to_view()


## Everything in the panel that isn't the list: the panel's own padding, each visible sibling's
## height, and the gaps between them. Measured fresh rather than cached, because the board
## switcher's create box comes and goes.
func _chrome_height() -> float:
	var sb := panel.get_theme_stylebox("panel") as StyleBox
	var h := 0.0
	if sb != null:
		h = sb.content_margin_top + sb.content_margin_bottom
	var kids := content.get_children()
	for c in kids:
		var ctrl := c as Control
		if ctrl == list or not ctrl.visible:
			continue
		h += ctrl.get_combined_minimum_size().y
	h += float(content.get_theme_constant("separation")) * float(maxi(0, kids.size() - 1))
	return h


## Whether `node` is the topmost visible modal among its siblings, i.e. whether an ESC that lands
## on it should dismiss it. The overlays are laid out as siblings (the main screen keeps their
## order; see `_rebuild_chrome`), and the task editor is one of them without being a subclass of
## this script — so "who owns ESC" is answered here, once, for every modal in the plugin.
##
## Scanned rather than left to input propagation order: the editor and the epics dialog both
## implement `_unhandled_input`, and whichever the engine happens to call first, an unguarded
## handler would dismiss the one *underneath* while the one on top stayed up.
static func owns_escape(node: Control) -> bool:
	var parent := node.get_parent()
	if parent == null:
		return true
	var passed_self := false
	for c in parent.get_children():
		if c == node:
			passed_self = true
			continue
		var ctrl := c as Control
		if passed_self and ctrl != null and ctrl.visible:
			return false
	return true


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cancel()


## ESC dismisses, matching the ✕. `is_visible_in_tree` rather than `visible`: the whole main
## screen is hidden on another editor tab, and the modal shouldn't swallow ESC from there.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# A modal stacked above us (the message box over the board switcher) owns the key.
		if not owns_escape(self):
			return
		# An inline editor may want ESC for itself; it outranks dismissing the modal. Its own
		# consumer handles the key, so we merely stay quiet.
		if _modal_escape_consumed():
			return
		_cancel()
		get_viewport().set_input_as_handled()


# --- subclass hooks -----------------------------------------------------------


## Glyph shown before the title; "" for none.
func _modal_icon() -> String:
	return ""

## Heading text; "" for a header that is just the ✕.
func _modal_title() -> String:
	return ""

## Widgets between the title and the ✕ — a count, a hint. Null for none.
func _modal_header_extras() -> Control:
	return null


## Fill `content` with everything below the header. Assign `list` if the body scrolls.
func _build_body(_parent: VBoxContainer) -> void:
	pass


## What the ✕, ESC and a backdrop click all do. Hiding is the default; a subclass that stages
## edits overrides this to throw them away first.
func _cancel() -> void:
	hide()


## True while the subclass is mid-edit and wants ESC for itself (an inline rename field, say).
func _modal_escape_consumed() -> bool:
	return false


# --- shared list-row parts ----------------------------------------------------
# The board switcher and the tags dialog both draw rows of "a name, then small icon actions",
# with an inline rename that swaps the name for a field. Those parts live here rather than in
# either subclass: the switcher resolves them through `extends`, and a second copy is how the
# two lists would drift apart.


## A small flat icon-only button: no background/border, a hand cursor, and a tooltip. The glyph is
## tinted separately via `_tint_button_icon`.
func _icon_button(kind: String, tooltip: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.icon = I.icon(kind, 16)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(16, 16)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	return b


## Tint an icon button's glyph: `base` while idle/focused/pressed, `hover` while the pointer is
## over it. Lets two icons in the same row read as distinct (pencil, rename, remove).
func _tint_button_icon(btn: Button, base: Color, hover: Color) -> void:
	for s in ["icon_normal_color", "icon_focus_color", "icon_pressed_color"]:
		btn.add_theme_color_override(s, base)
	btn.add_theme_color_override("icon_hover_color", hover)
	btn.add_theme_color_override("icon_hover_pressed_color", hover)


## Make a row's name label take the width it's given instead of demanding its text's width.
## `clip_text` is what does it (measured: it drops the label's minimum width to ~1px, so the
## HBox can always fit the panel and the trailing buttons hold their spot); the overrun
## behavior only decides how the cut looks — an ellipsis rather than a hard chop.
## Pair with `SIZE_EXPAND_FILL`, which is what makes the label fill the leftover width.
func _contain_label(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true


## The tooltip a row should carry: the full name while its label is too narrow to show it,
## empty while it fits. Measured against the label's own font rather than counted in
## characters, so it reflects what's actually rendered; before the first layout pass the
## label has no width yet, so assume trimmed and let the `resized` hook correct it.
func _name_tooltip(label: Label) -> String:
	if label.size.x <= 0.0:
		return label.text
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return label.text if text_w > label.size.x else ""
