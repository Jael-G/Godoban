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
const BoardSwitcher = preload("res://addons/godoban/ui/board_switcher.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

var store: GodobanStore
var board: Board
var editor: TaskEditor
var epic_dialog: EpicDialog
var filters_bar: FiltersBar
var overview: Overview
var board_switcher: BoardSwitcher
var _import_dialog: FileDialog
var _message_box: PopupPanel
var _message_label: Label
var _epic_toggle: Button
var _orientation_toggle: Button
var _board_chip: Control
var _chip_name_label: Label
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
# Board+Overview live in `_content` so the whole thing can be hidden when no board is
# loaded; `_empty_state` takes its place. `_active_tab` tracks the last shown tab so a
# switch from zero→board restores it.
var _content: Control
var _empty_state: Control
var _active_tab := "board"

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

	# The import file picker lives here, not inside the popup, so it stays open even
	# if the popup closes on an outside click mid-selection.
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.title = "Import a board"
	_import_dialog.filters = PackedStringArray(["*.json ; Godoban board"])
	add_child(_import_dialog)

	board_switcher = BoardSwitcher.new()
	board_switcher.setup(store, _import_dialog)
	add_child(board_switcher)
	# Switching boards: refresh the chip and clear any open task editor so a stray
	# "Save" can't create a bogus task in the new board.
	store.board_switched.connect(_on_board_switched)
	# Renaming the *current* board also renames the chip label. Non-current boards don't
	# affect the chip; their rows/internal name are refreshed by the switcher's rebuild.
	store.board_renamed.connect(_on_board_renamed)
	# A refused (duplicate) import surfaces here; the message popup is owned here rather
	# than by the switcher, so it stays up after the switcher hides. A missing board
	# needs no popup — the switcher just drops it from the list.
	store.board_import_rejected.connect(func(): show_message("That board is already on the list."))


## Rebuilds the theme-colored chrome when the editor theme changes, keeping the
## task editor + epics dialog (and any open edit) intact. Colors resolve through
## the editor theme, so re-applying them repaints every surface.
func _rebuild_chrome() -> void:
	for c in get_children():
		if c == editor or c == epic_dialog or c == board_switcher or c == _import_dialog or c == _message_box:
			continue
		remove_child(c)
		c.free()
	_pages.clear()
	_tabs.clear()
	_chip_name_label = null
	_build_ui()
	# Overlays were added before the chrome, so raise them back to the top.
	if editor != null:
		move_child(editor, get_child_count() - 1)
	if epic_dialog != null:
		move_child(epic_dialog, get_child_count() - 1)
	if board_switcher != null:
		move_child(board_switcher, get_child_count() - 1)
	if _import_dialog != null:
		move_child(_import_dialog, get_child_count() - 1)


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

	# Board + Overview live inside a single content wrapper so it can be hidden wholesale
	# when there's no current board; the empty state takes its place below.
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 0)
	root.add_child(_content)

	# --- Board tab ---
	var board_page := VBoxContainer.new()
	board_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Gap between the toolbar and the board columns.
	board_page.add_theme_constant_override("separation", 12)
	_content.add_child(board_page)
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
	_content.add_child(overview)
	_pages["overview"] = overview

	# The zero-board placeholder, shown in place of the content wrapper.
	_empty_state = _build_empty_state()
	root.add_child(_empty_state)

	_apply_board_state()


## The zero-board placeholder: a single centered hint (no buttons) that points the user to
## the board chip to create or import one. Matches the `_empty_hint` styling in board.gd.
func _build_empty_state() -> Control:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "No board yet.\nClick the board chip above to create or import one."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", T.TEXT_DIM())
	label.add_theme_font_size_override("font_size", 14)
	center.add_child(label)
	return center


## Reflect whether a board is loaded: show the board+overview content (and the view tabs)
## when there is one, or the empty state when there is none. Keeps the two states in sync
## after a switch, rename, or a zero→board transition (create/import).
func _apply_board_state() -> void:
	var has_board := store.current_board_id() != ""
	_content.visible = has_board
	_empty_state.visible = not has_board
	for t in _tabs.values():
		t.visible = has_board
	if has_board:
		_switch_tab(_active_tab)
	if _chip_name_label != null:
		_chip_name_label.text = store.board_name if store.board_name != "" else "Board"


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

	# The board chip leads the bar (left of the view tabs). It's a *data* control,
	# deliberately styled differently from the page toggles so it reads as "which
	# board am I on", not as a tab. Clicking it opens the board switcher.
	h.add_child(_build_board_chip())

	_tabs["board"] = _add_tab(h, "Board")
	_tabs["overview"] = _add_tab(h, "Overview")
	return bar


## A clickable chip showing the current board's name with a chevron hint + hover
## highlight. Built as a PanelContainer (not a Button) so it can freely lay out
## icon + label + chevron while the whole surface stays one click target; the
## children are mouse-Ignore so clicks land on the chip itself.
func _build_board_chip() -> Control:
	var chip := PanelContainer.new()
	# PanelContainer draws only the "panel" stylebox (it has no normal/hover/pressed
	# Button states), so the border + fill live there; hover is wired manually.
	var panel_normal := T.panel(T.BG_INPUT(), T.BORDER_STRONG(), 10, 11, 11, 5, 5, 1)
	var panel_hover := T.panel(T.BG_HOVER(), T.BORDER_STRONG(), 10, 11, 11, 5, 5, 1)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", panel_normal)
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.tooltip_text = "Switch board"
	chip.mouse_entered.connect(func(): chip.add_theme_stylebox_override("panel", panel_hover))
	chip.mouse_exited.connect(func(): chip.add_theme_stylebox_override("panel", panel_normal))
	chip.gui_input.connect(_on_chip_input)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(hb)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.texture = I.icon("kanban", 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = T.TEXT()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(icon)

	_chip_name_label = Label.new()
	_chip_name_label.text = store.board_name if store.board_name != "" else "Board"
	_chip_name_label.add_theme_font_size_override("font_size", 16)
	_chip_name_label.add_theme_font_override("font", T.title_font(0.7, 1.0))
	_chip_name_label.add_theme_color_override("font_color", T.TEXT())
	_chip_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_chip_name_label)

	var chev := TextureRect.new()
	chev.custom_minimum_size = Vector2(20, 20)
	chev.texture = I.icon("chevron-down", 20)
	chev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chev.modulate = T.TEXT()
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(chev)

	_board_chip = chip
	return chip


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
## Records the choice in `_active_tab` so a zero→board switch can restore the last tab.
func _switch_tab(page: String) -> void:
	_active_tab = page
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


func _on_chip_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_open_board_switcher()


func _open_board_switcher() -> void:
	if _board_chip == null or board_switcher == null:
		return
	var r := _board_chip.get_global_rect()
	board_switcher.open(Rect2i(r.position, r.size))


## A board was just switched (or the last one removed): repaint the whole state — chip,
## view tabs, and content vs. empty state — and clear any open task editor, so a lingering
## "Save" can't write a stale task into the new board.
func _on_board_switched(_id: String) -> void:
	_apply_board_state()
	if editor != null:
		editor.hide()
	if filters_bar != null:
		filters_bar.reset_scope()


## The current board was renamed in-place (no switch): repaint just the chip label.
func _on_board_renamed(board_id: String, board_name: String) -> void:
	if board_id != store.current_board_id():
		return
	if _chip_name_label != null:
		_chip_name_label.text = board_name if board_name != "" else "Board"


## Show a small centered message popup (currently: a refused duplicate import). Owned
## here — not by the board switcher — so it stays up after the switcher hides
## itself following the action that triggered the message. Deferred: we may be inside a
## gui_input signal handler (a board row click), so opening the popup this frame can be
## swallowed; pop it on the next idle frame instead.
func show_message(text: String) -> void:
	if _message_box == null:
		_build_message_box()
	_message_label.text = text
	call_deferred("_popup_message")


func _popup_message() -> void:
	_message_box.popup_centered()


func _build_message_box() -> void:
	_message_box = PopupPanel.new()
	_message_box.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 8, 14, 14, 12, 12, 1))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_message_box.add_child(v)
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.custom_minimum_size = Vector2(280, 0)
	v.add_child(_message_label)
	var ok := Button.new()
	ok.text = "OK"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	T.button(ok)
	ok.pressed.connect(func(): _message_box.hide())
	v.add_child(ok)
	add_child(_message_box)


func _open_editor(task_id: String, status: String) -> void:
	if task_id != "":
		editor.open_edit(task_id)
	else:
		editor.open_new(status)
