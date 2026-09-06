@tool
extends Control

## Root control for the Godoban main-screen tab. Owns the store and composes a
## two-tab layout (Board / Overview), each full width: the board tab holds the
## toolbar (view mode, epics, filters, New Task) + the board; the overview tab
## holds the full-page stats. Task editor overlays both tabs.

const GodobanStore = preload("res://addons/godoban/data/godoban_store.gd")
const Board = preload("res://addons/godoban/ui/board.gd")
const TaskEditor = preload("res://addons/godoban/ui/task_editor.gd")
const EpicDialog = preload("res://addons/godoban/ui/epic_dialog.gd")
const FiltersBar = preload("res://addons/godoban/ui/filters_bar.gd")
const Overview = preload("res://addons/godoban/ui/overview.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

var store: GodobanStore
var board: Board
var editor: TaskEditor
var epic_dialog: EpicDialog
var filters_bar: FiltersBar
var overview: Overview
var _epic_toggle: Button
var _orientation_toggle: Button
var _pages: Dictionary = {}
var _tabs: Dictionary = {}

func _ready() -> void:
	store = GodobanStore.new()
	store.load()
	# Apply the shared theme (Geist default font) to the whole tab; children inherit it.
	theme = T.theme()
	_build_ui()
	_build_overlays()


## Builds the task editor + epics dialog once; they persist across chrome rebuilds
## so an open edit survives a theme change. Added after the chrome so they layer on top.
func _build_overlays() -> void:
	if editor != null:
		return
	editor = TaskEditor.new()
	editor.setup(store)
	editor.visible = false
	editor.anchor_left = 1.0
	editor.anchor_right = 1.0
	editor.anchor_top = 0.0
	editor.anchor_bottom = 1.0
	editor.offset_left = -340.0
	editor.offset_right = 0.0
	add_child(editor)

	epic_dialog = EpicDialog.new()
	epic_dialog.setup(store)
	add_child(epic_dialog)
	epic_dialog.changed.connect(func(id): editor.refresh_epics(id))
	editor.new_epic_requested.connect(func(): epic_dialog.open())


## Rebuilds the theme-colored chrome when the editor theme changes, keeping the
## task editor + epics dialog (and any open edit) intact. Colors resolve through
## the editor theme, so re-applying them repaints every surface.
func _rebuild_chrome() -> void:
	for c in get_children():
		if c == editor or c == epic_dialog:
			continue
		remove_child(c)
		c.free()
	_pages.clear()
	_tabs.clear()
	_build_ui()
	# Overlays were added before the chrome, so raise them back to the top.
	if editor != null:
		move_child(editor, get_child_count() - 1)
	if epic_dialog != null:
		move_child(epic_dialog, get_child_count() - 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and editor != null:
		# Defer so we don't free the child tree mid-notification walk.
		call_deferred("_rebuild_chrome")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = T.BG()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_tab_bar())

	# --- Board tab ---
	var board_page := VBoxContainer.new()
	board_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Gap between the toolbar and the board columns.
	board_page.add_theme_constant_override("separation", 12)
	root.add_child(board_page)
	_pages["board"] = board_page

	board_page.add_child(_build_toolbar())

	# Hold the board in from the editor's left/right/bottom edges so the
	# first/last columns sit the same distance from the sides as between columns.
	var board_margin := MarginContainer.new()
	board_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_margin.add_theme_constant_override("margin_left", 12)
	board_margin.add_theme_constant_override("margin_right", 12)
	board_margin.add_theme_constant_override("margin_bottom", 12)
	board_page.add_child(board_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# AUTO (not DISABLED): when the board's columns can't fit the available width,
	# scroll horizontally instead of pinning the whole screen wide / sliding under
	# the Inspector. When it does fit, AUTO behaves like DISABLED (no scrollbar).
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	board_margin.add_child(scroll)

	board = Board.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.setup(store)
	board.open_requested.connect(func(id): _open_editor(id, ""))
	board.add_requested.connect(func(s): _open_editor("", s))
	scroll.add_child(board)

	filters_bar.filters_changed.connect(func(f): board.set_filters(f))

	# --- Overview tab ---
	overview = Overview.new()
	overview.setup(store)
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(overview)
	_pages["overview"] = overview

	_switch_tab("board")


func _build_toolbar() -> Control:
	var area := PanelContainer.new()
	var sb := T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 0, 12, 12, 9, 9, 1)
	sb.border_width_top = 0
	sb.border_width_left = 0
	sb.border_width_right = 0
	area.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	area.add_child(vb)

	# Row 1: the two primary actions get their own line so they always lead the
	# bar, even when the bar wraps on a narrow editor.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	vb.add_child(actions)

	var new_btn := Button.new()
	new_btn.text = "+ New Task"
	T.button(new_btn, true)
	new_btn.pressed.connect(func(): _open_editor("", "backlog"))
	actions.add_child(new_btn)

	var epics_btn := Button.new()
	epics_btn.text = "Epics"
	epics_btn.tooltip_text = "Manage epics"
	T.button(epics_btn, true)
	epics_btn.pressed.connect(func(): epic_dialog.open())
	actions.add_child(epics_btn)

	# Row 2: view-mode toggles + search + filter dropdowns share one wrapping
	# flow. Wide editors show a single line; narrow ones wrap onto more lines,
	# so the bar fits without a horizontal scrollbar.
	_epic_toggle = Button.new()
	_epic_toggle.toggle_mode = true
	_epic_toggle.toggled.connect(_on_epic_toggled)
	_apply_epic_toggle()

	_orientation_toggle = Button.new()
	_orientation_toggle.toggle_mode = true
	_orientation_toggle.toggled.connect(_on_orientation_toggled)
	_apply_orientation_toggle()

	filters_bar = FiltersBar.new()
	filters_bar.setup(store)
	filters_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The toggles lead the strip (ahead of the search box).
	filters_bar.add_child(_orientation_toggle)
	filters_bar.move_child(_orientation_toggle, 0)
	filters_bar.add_child(_epic_toggle)
	filters_bar.move_child(_epic_toggle, 0)
	vb.add_child(filters_bar)

	return area


## Top tab strip: Board / Overview toggles, styled by theme.gd's tab_button.
func _build_tab_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 0, 12, 12, 9, 9, 1)
	sb.border_width_top = 0
	sb.border_width_left = 0
	sb.border_width_right = 0
	bar.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	bar.add_child(h)

	_tabs["board"] = _add_tab(h, "Board")
	_tabs["overview"] = _add_tab(h, "Overview")
	return bar


func _add_tab(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 13)
	b.toggled.connect(func(_on): _switch_tab(text.to_lower()))
	parent.add_child(b)
	return b


## Shows exactly one page and updates the matching tab's pressed + style state.
func _switch_tab(page: String) -> void:
	for k in _pages:
		_pages[k].visible = (k == page)
	for k in _tabs:
		var on: bool = k == page
		var b: Button = _tabs[k]
		b.set_pressed_no_signal(on)
		T.tab_button(b, on)


func _on_epic_toggled(on: bool) -> void:
	board.set_mode("epic" if on else "all")
	_apply_epic_toggle()


func _on_orientation_toggled(on: bool) -> void:
	board.set_orientation("horizontal" if on else "vertical")
	_apply_orientation_toggle()


## Re-paint a view-mode toggle to match its current state: icon, label, tooltip
## and accent, so it's obvious which mode is active. Shared by both the
## board/epic and vertical/horizontal toggles.
func _apply_view_toggle(btn: Button, on: bool, icon_on: String, icon_off: String,
		label_on: String, label_off: String, tip_on: String, tip_off: String) -> void:
	var color := T.TEXT() if on else T.TEXT_DIM()
	btn.icon = I.icon(icon_on, 18) if on else I.icon(icon_off, 18)
	btn.text = label_on if on else label_off
	btn.tooltip_text = tip_on if on else tip_off
	T.button(btn, on)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_hover_pressed_color", "icon_focus_color"]:
		btn.add_theme_color_override(c, color)
	for f in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(f, color)


## Re-paints the view-mode toggle: label + icon show whether you're in the single
## board or grouped-by-epic view.
func _apply_epic_toggle() -> void:
	_apply_view_toggle(_epic_toggle, _epic_toggle.button_pressed,
			"layers-2", "grid-2x2", "By Epic", "Board",
			"Grouped by epic — see one board per epic",
			"Single board — show all tasks in one view")


## Re-paints the layout toggle: label + icon show whether cards flow down columns
## or across rows.
func _apply_orientation_toggle() -> void:
	_apply_view_toggle(_orientation_toggle, _orientation_toggle.button_pressed,
			"rows-2", "columns-2", "Rows", "Columns",
			"Rows — cards flow horizontally, one row per status",
			"Columns — cards stack in vertical columns (classic)")


func _open_editor(task_id: String, status: String) -> void:
	if task_id != "":
		editor.open_edit(task_id)
	else:
		editor.open_new(status)
