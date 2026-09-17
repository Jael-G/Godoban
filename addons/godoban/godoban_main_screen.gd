@tool
extends Control

## Root control for the Godoban main-screen tab. Owns the store and composes a
## two-tab layout (Board / Overview), each full width: the board tab holds the
## toolbar (view mode, epics, filters, New Task) + the board; the overview tab
## holds the full-page stats. Task editor overlays both tabs.

const GodobanStore = preload("res://addons/godoban/data/godoban_store.gd")
const Board = preload("res://addons/godoban/ui/board.gd")
const TaskEditor = preload("res://addons/godoban/ui/task_editor.gd")
const TaskView = preload("res://addons/godoban/ui/task_view.gd")
const EpicDialog = preload("res://addons/godoban/ui/epic_dialog.gd")
const TagsDialog = preload("res://addons/godoban/ui/tags_dialog.gd")
const FiltersBar = preload("res://addons/godoban/ui/filters_bar.gd")
const Overview = preload("res://addons/godoban/ui/overview.gd")
const BoardSwitcher = preload("res://addons/godoban/ui/board_switcher.gd")
const MessageDialog = preload("res://addons/godoban/ui/message_dialog.gd")
const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")

## How much of the board name the toolbar chip shows before it's elided. Kept small: the
## chip shares the bar with the view tabs, so its width is a budget, not a preference.
const CHIP_NAME_MAX_CHARS := 20

## Entries of a card's context menu (`_open_card_menu`). Ids rather than item indices, so the
## handler and the menu don't have to agree on an order.
const MENU_EDIT := 0
const MENU_DELETE := 1

var store: GodobanStore
var board: Board
var editor: TaskEditor
var task_view: TaskView
var epic_dialog: EpicDialog
var tags_dialog: TagsDialog
var filters_bar: FiltersBar
var overview: Overview
var board_switcher: BoardSwitcher
var _import_dialog: FileDialog
var _message_box: MessageDialog
## Held between `show_message` and the deferred pop, which exists so the popup isn't opened from
## inside a `gui_input` handler (see `show_message`).
var _message_text := ""
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
## The card context menu that is up, or `null` when none is — never more than one at a time. Its
## counterpart `_card_menu_task` is the task it is *for*, which is what tells a right-click on the
## card the menu is already on from a right-click somewhere else. It outlives the menu (a dismissed
## menu still has to say which card it was about — see `_move_card_menu_to`), so it is only ever
## rewritten by `_open_card_menu`.
var _card_menu: PopupMenu = null
var _card_menu_task := ""
## A card menu was taken down and the click that took it down has not been accounted for yet: armed
## in `_on_card_menu_hidden`, disarmed by any right-press we see. A right-release that arrives while
## it is armed is the tail of that very click — see `_input`, which is where the editor's default,
## windowed popups leave us no other half of it to work with.
var _menu_dismissed := false
## Right-button state as of the end of the last frame, and whether a card menu was up then. `_process`
## reads the situation as it was a frame ago rather than from the live objects, which at that moment
## may already be mid-collapse at the hand of the press it is reacting to.
var _right_was_down := false
var _card_menu_was_up := false

func _ready() -> void:
	store = GodobanStore.new()
	store.load()
	# Apply the shared theme (Geist default font) to the whole tab; children inherit it.
	theme = T.theme()
	_build_ui()
	_build_overlays()
	# `_process` and `_input` are what move the card menu between cards, and they have to be watching
	# before the first right-click rather than woken by it. Both start on: the node is alive for as
	# long as the tab is.
	set_process(true)
	set_process_input(true)


## Builds the task view, the task editor + dialogs once; they persist across chrome rebuilds so an
## open edit survives a theme change (they restyle themselves instead — see `_rebuild_chrome`).
## Added after the chrome so they layer on top, and in this order — each one added later covers the
## ones before it: editor < view < epics < boards < message.
func _build_overlays() -> void:
	if editor != null:
		return
	# Full-rect overlays; all of them anchor and center themselves. The dialogs share their chrome
	# through `modal_overlay.gd`; the editor predates it and carries its own copy of the layout.
	editor = TaskEditor.new()
	editor.setup(store)
	editor.visible = false
	add_child(editor)

	# Directly above the editor and nowhere else: the only two overlays that are never up at the
	# same time are these two (Edit puts one down and the other up), so the pair has to keep its
	# relative order for `owns_escape` to answer "who owns ESC" correctly.
	task_view = TaskView.new()
	task_view.setup(store)
	add_child(task_view)
	task_view.edit_requested.connect(func(id): editor.open_edit(id))

	epic_dialog = EpicDialog.new()
	epic_dialog.setup(store)
	add_child(epic_dialog)
	epic_dialog.changed.connect(func(id): editor.refresh_epics(id))
	editor.new_epic_requested.connect(func(): epic_dialog.open())

	tags_dialog = TagsDialog.new()
	tags_dialog.setup(store)
	add_child(tags_dialog)

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


## Rebuilds the theme-colored chrome when the editor theme changes. Colors resolve through
## the editor theme, so re-applying them repaints every surface.
##
## The overlays are skipped because they rebuild *themselves* (see
## `modal_overlay.rebuild_for_theme` and `task_editor._rebuild_for_theme`), each carrying its own
## state across — that's what lets an open edit survive a theme change. Freeing them here would
## throw that state away, and rebuilding them twice in one frame would be wasted work.
func _rebuild_chrome() -> void:
	for c in get_children():
		if c == editor or c == task_view or c == epic_dialog or c == tags_dialog or c == board_switcher or c == _import_dialog or c == _message_box:
			continue
		remove_child(c)
		c.free()
	_pages.clear()
	_tabs.clear()
	_chip_name_label = null
	_build_ui()
	# Overlays were added before the chrome, so raise them back to the top — in the same order
	# `_build_overlays` added them, or `owns_escape` would hand ESC to the wrong overlay.
	if editor != null:
		move_child(editor, get_child_count() - 1)
	if task_view != null:
		move_child(task_view, get_child_count() - 1)
	if epic_dialog != null:
		move_child(epic_dialog, get_child_count() - 1)
	if tags_dialog != null:
		move_child(tags_dialog, get_child_count() - 1)
	if board_switcher != null:
		move_child(board_switcher, get_child_count() - 1)
	if _message_box != null:
		move_child(_message_box, get_child_count() - 1)
	if _import_dialog != null:
		move_child(_import_dialog, get_child_count() - 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and editor != null:
		# Defer so we don't free the child tree mid-notification walk.
		call_deferred("_rebuild_chrome")


## Watches for the right-click that lands while a card menu is up, so one click is enough to move the
## menu to the card that click was aimed at — no click spent dismissing the open one first.
##
## The click that *opens* a card menu is the card's own (`card.gd` -> `board.gd` -> `_open_card_menu`);
## the click that should move it is one the card usually never hears about, because the open menu is a
## popup and a popup owns the pointer. What is left of that click to work with depends on *Single
## Window Mode*, and both cases are read here (each verified against the editor on Godot 4.7, with real
## clicks on a card while another card's menu was up):
##
## * **On** — the popup embeds, as popups always do in a game. It takes the viewport's subwindow focus,
##   `viewport.cpp` `_sub_windows_forward_input` hands it the pointer events and returns, and the card
##   is never asked — but the press does reach `Input`, so the poll below sees it while the menu is
##   still up, closes the menu, and `_on_card_menu_hidden` opens its replacement.
## * **Off** — the default, and a real OS window with the pointer grabbed. The press reaches neither
##   the card nor `Input` (and by the time Godot lets the grab go the button is up again), so the
##   *release* — replayed to the window under the pointer once the menu is gone — is the only half of
##   the click that arrives, and `_input` takes it.
##
## Either way the move itself is `_move_card_menu_to`, which is idempotent on purpose: both paths can
## see the same click, in either order, and one menu is still all that is left standing.
func _process(_delta: float) -> void:
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if down and not _right_was_down:
		_move_card_menu_from_polled_press()
	_right_was_down = down
	# Recorded last, so it describes the end of the frame — what the *next* frame's press finds in
	# front of it. Cheap enough to keep as a bool: this runs on every frame of the editor's life.
	_card_menu_was_up = is_instance_valid(_card_menu) and _card_menu.visible


## The embedded popup's half of the gesture (see `_process`): a right-press the menu swallowed before
## the card could see it, landing — or not — on the menu itself.
func _move_card_menu_from_polled_press() -> void:
	# No menu for the click to have landed on: it was an ordinary first right-click on a card, whose
	# own `_open_card_menu` is already running by the time this frame's `_process` gets here. Reading
	# last frame's state rather than this one is what makes that true.
	if not _card_menu_was_up or not is_instance_valid(_card_menu) or not _card_menu.visible:
		return
	var at := get_viewport().get_mouse_position()
	# A press on the menu itself is the menu's business — it stays up, as it should. Measured against
	# the whole window rect rather than the panel's: the sliver between the two is the panel's shadow,
	# and a click landing there closes the menu with nothing in its place, which is what a click on a
	# menu's edge should do anyway.
	if Rect2(Vector2(_card_menu.position), Vector2(_card_menu.size)).has_point(at):
		return
	# The menu opens at the pointer, which is over the card it is for, so "the card under the pointer
	# is the one this menu belongs to" is another way of saying the pointer never left it.
	if board.card_at(at) == _card_menu_task:
		return
	_card_menu.hide()


## The windowed popup's half of the gesture (see `_process`): of the click that dismissed the menu,
## only the release reaches this window, and it is the one thing left that says where that click was
## aimed — the card it should have opened for.
##
## A right-press we can see is a press a card can see, so it cancels the wait outright: that click is
## the card's to answer, and `_open_card_menu` runs from `card.gd` as usual.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if mb.pressed:
		_menu_dismissed = false
		return
	# Nothing says this release is the tail of a click that dismissed a card menu — except the menu
	# having been dismissed (the usual order: the popup goes on the press, this arrives on the release)
	# or still being up a frame ago, which is the same click arriving ahead of its own dismissal.
	if not (_menu_dismissed or _card_menu_was_up):
		return
	_menu_dismissed = false
	# `mb.position` is already in viewport pixels, the space `board.card_at` measures in.
	_move_card_menu_to(mb.position)


## A card menu went away — we closed it above, or Godot dismissed it on the click that was meant for
## another card. Both are the same thing to the click that did it, which is owed a menu for whatever
## card it landed on: the two paths above collect on that, and this is where the debt is recorded.
##
## The embedded case is also served from here, one frame later, because the menu being torn down has to
## be gone — off screen, unfocused, and out of the viewport's subwindow list — before the next one is
## built, or the new popup is caught up in the teardown and never appears, which looks exactly like the
## click having done nothing.
func _on_card_menu_hidden(menu: PopupMenu, task_id: String) -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	if _card_menu == menu:
		_card_menu = null
	# `_card_menu_task` deliberately stays as it was: the menu is gone, but which card it was for is
	# still what says whether the click that dismissed it asked for that same card back — see
	# `_move_card_menu_to`.
	_menu_dismissed = true
	if not is_inside_tree():
		return
	# The button being held is what separates a dismissal by a click from one by ESC or a menu entry
	# being chosen — a menu chosen from is closed by a left-click, and a menu dismissed by ESC by no
	# button at all. Only the embedded case ever gets here with the button still down.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	# Held as of the click, not re-read a frame later: this is where the press landed.
	var at := get_viewport().get_mouse_position()
	await get_tree().process_frame
	if not is_inside_tree() or not _menu_dismissed:
		return
	_menu_dismissed = false
	_move_card_menu_to(at)


## Puts the card menu on the card at `at` — a point in viewport pixels — replacing whatever card menu
## is up. Nothing happens when the click asked for the card whose menu it just dismissed (a dismissal
## and little more, which is what a right-click on the same card does everywhere else) or for no card
## at all (a column gutter, the space below a short column, the margin).
##
## Idempotent, and deliberately so: the polled and the windowed halves of one click can both end up
## here, in either order, and the checks below are what leave exactly one menu standing.
func _move_card_menu_to(at: Vector2) -> void:
	var task_id := board.card_at(at)
	if task_id == "" or task_id == _card_menu_task:
		return
	# The card heard the click after all and opened its own menu (`board.gd` -> `_open_card_menu`):
	# nothing to move, and opening a second one here would fight it.
	if is_instance_valid(_card_menu) and _card_menu.visible:
		return
	_open_card_menu(task_id, at)


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

	# Hold the board in from the window's left/right/bottom edges so the
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
	board.open_requested.connect(_open_task_view)
	board.context_requested.connect(_open_card_menu)
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
		_set_chip_name()


## Write the current board's name into the chip, elided to a fixed character budget and
## with the untruncated name parked in the tooltip. The chip is a fixed affordance in the
## toolbar — without a cap a long name stretches the pill across the bar and pushes the
## view tabs out of reach.
func _set_chip_name() -> void:
	var full_name: String = store.board_name if store.board_name != "" else "Board"
	_chip_name_label.text = T.elide(full_name, CHIP_NAME_MAX_CHARS)
	# Only worth a tooltip when it's actually hiding something; otherwise keep the
	# "Switch board" hint that explains what the chip does.
	_board_chip.tooltip_text = full_name if _chip_name_label.text != full_name else "Switch board"


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

	# The three board-wide actions. Each leads with the same Lucide glyph its own popup wears in
	# the header (plus / layers-2 / tag), so the button and the panel it opens read as one thing.
	# The glyph replaces the "+" that used to be typed into the label — a real icon lines up with
	# the text baseline and the other two buttons' icons, which a bare ASCII "+" never did.
	var new_btn := Button.new()
	new_btn.text = "New Task"
	new_btn.icon = I.icon("plus", 16)
	T.button(new_btn, true)
	new_btn.pressed.connect(func(): _open_editor("", "backlog"))
	actions.add_child(new_btn)

	var epics_btn := Button.new()
	epics_btn.text = "Epics"
	epics_btn.icon = I.icon("layers-2", 16)
	epics_btn.tooltip_text = "Manage epics"
	T.button(epics_btn, true)
	epics_btn.pressed.connect(func(): epic_dialog.open())
	actions.add_child(epics_btn)

	# Tags sit beside Epics as the other board-wide vocabulary; both open a management popup
	# rather than creating something here.
	var tags_btn := Button.new()
	tags_btn.text = "Tags"
	tags_btn.icon = I.icon("tag", 16)
	tags_btn.tooltip_text = "Manage tags"
	T.button(tags_btn, true)
	tags_btn.pressed.connect(_open_tags)
	actions.add_child(tags_btn)

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

	# Extra air between the chip and the view tabs — the bar's own 4px makes them read as one
	# cluster, and they're two different kinds of control (which board vs. which page). Fixed
	# width, so only the chip→tabs gap widens; the tabs keep their tight 4px pairing.
	# Net gap is this plus the bar's separation on either side.
	var chip_gap := Control.new()
	chip_gap.custom_minimum_size = Vector2(8, 0)
	h.add_child(chip_gap)

	_tabs["board"] = _add_tab(h, "Board")
	_tabs["overview"] = _add_tab(h, "Overview")
	return bar


## A clickable chip showing the current board's name with a chevron hint + hover
## highlight. Built as a PanelContainer (not a Button) so it can freely lay out
## icon + label + chevron while the whole surface stays one click target; the
## children are mouse-Ignore so clicks land on the chip itself.
func _build_board_chip() -> Control:
	var chip := PanelContainer.new()
	# Assigned before the label is built so `_set_chip_name` can reach the chip's tooltip.
	_board_chip = chip
	# PanelContainer draws only the "panel" stylebox (it has no normal/hover/pressed
	# Button states), so the border + fill live there; hover is wired manually.
	var panel_normal := T.panel(T.BG_INPUT(), T.BORDER_STRONG(), 10, 11, 11, 5, 5, 1)
	var panel_hover := T.panel(T.BG_HOVER(), T.BORDER_STRONG(), 10, 11, 11, 5, 5, 1)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", panel_normal)
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# tooltip_text is owned by `_set_chip_name` (below): it shows the full board name when
	# the chip had to elide it, and the "Switch board" hint otherwise.
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
	_set_chip_name()
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
	if board_switcher == null:
		return
	board_switcher.open()


## The toolbar is built before the overlays exist, so the guard isn't decorative.
func _open_tags() -> void:
	if tags_dialog == null:
		return
	tags_dialog.open()


## A board was just switched (or the last one removed): repaint the whole state — chip,
## view tabs, and content vs. empty state — and clear any open task editor, so a lingering
## "Save" can't write a stale task into the new board.
func _on_board_switched(_id: String) -> void:
	_apply_board_state()
	if editor != null:
		editor.hide()
	if task_view != null:
		# It is showing the *old* board's task.
		task_view.hide()
	if tags_dialog != null:
		# Its rows name the *old* board's tags; the popup is rebuilt on open, so it only has to
		# come down — leaving it up would offer renames into a board that's no longer on screen.
		tags_dialog.hide()
	if epic_dialog != null:
		# Same, for the old board's epics.
		epic_dialog.hide()
	if filters_bar != null:
		filters_bar.reset_scope()


## The current board was renamed in-place (no switch): repaint just the chip label.
func _on_board_renamed(board_id: String, _board_name: String) -> void:
	if board_id != store.current_board_id():
		return
	if _chip_name_label != null:
		# Through the same elide path as every other chip repaint — a rename is exactly how
		# an over-long name gets in here in the first place.
		_set_chip_name()


## Show a small centered message popup (currently: a refused duplicate import). Owned
## here — not by the board switcher — so it stays up after the switcher hides
## itself following the action that triggered the message. Deferred: we may be inside a
## gui_input signal handler (a board row click), and the modal that opens this frame would
## rebuild the row that is still dispatching; show it on the next idle frame instead.
func show_message(text: String) -> void:
	if _message_box == null:
		_build_message_box()
	_message_text = text
	call_deferred("_popup_message")


func _popup_message() -> void:
	_message_box.show_text(_message_text)


func _build_message_box() -> void:
	_message_box = MessageDialog.new()
	_message_box.setup()
	add_child(_message_box)


func _open_editor(task_id: String, status: String) -> void:
	if task_id != "":
		editor.open_edit(task_id)
	else:
		editor.open_new(status)


## A card was clicked: read it, don't edit it. The editor is still one Edit button away, and the
## board's `+` buttons still open it directly for a new task.
func _open_task_view(task_id: String) -> void:
	if task_view == null:
		return
	task_view.open(task_id)


## A card was right-clicked: offer the two things a card can do to itself, at the pointer.
##
## This is Godot's own `PopupMenu` rather than a hand-drawn menu, for everything it already
## brings: hover highlighting, arrow-key navigation, and dismissal on ESC or a click outside.
## Two measured details make it fit here. Its chrome is a plain stylebox override, which a
## `PopupMenu` accepts directly (no `Theme` resource to build, the same `add_theme_stylebox_override`
## the rest of the UI uses); and as a `Popup` it is borderless with a transparent background, so a
## rounded panel draws cleanly with the board showing through the corners rather than wedging them
## the way the opaque `embedded_border` frame did for the modals `modal_overlay.gd` replaced.
## And `popup(Rect2i)` places a window in *viewport* pixels — measured the same whether the popup
## ends up embedded or, as in the default editor, a window of its own — which is the space the card
## reports its right-click in; screen coordinates would put the menu under the wrong point.
##
## Built per right-click and freed when it closes, rather than kept around: nothing here holds a
## palette it was built in, so a theme switch while the menu is shut is a non-issue, and a menu
## owned by the card would be freed by the very rebuild its own Delete entry triggers.
func _open_card_menu(task_id: String, at: Vector2) -> void:
	var menu := PopupMenu.new()
	# A `Window` keeps its own theme and doesn't inherit this screen's, so hand it the shared one
	# (Geist) directly; every color still falls through to the editor theme as usual.
	menu.theme = T.theme()
	menu.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER(), 6, 4, 4, 4, 4, 1))
	# The same lighter-surface hover the cards and the buttons use — accent stays reserved for the
	# selected/active state (tab buttons, tag chips), which a hovered menu entry is not.
	menu.add_theme_stylebox_override("hover",
		T.panel(T.BG_HOVER(), Color(0, 0, 0, 0), 4, 0, 0, 0, 0, 0))
	menu.add_theme_color_override("font_color", T.TEXT())
	menu.add_theme_color_override("font_hover_color", T.TEXT())
	# The glyphs are baked white (`icons.gd`) and a `PopupMenu` has no icon color in its theme, so
	# each item carries its own tint — the same trick as the flat icon buttons. That per-item
	# modulate is also the only way to color an entry: it has no per-item text color, so the trash
	# glyph is what marks Delete as the destructive one.
	menu.add_icon_item(I.icon("pencil", 14), "Edit", MENU_EDIT)
	menu.add_icon_item(I.icon("trash-2", 14), "Delete", MENU_DELETE)
	menu.set_item_icon_modulate(1, T.OVERDUE)
	menu.id_pressed.connect(func(id: int):
		if id == MENU_EDIT:
			editor.open_edit(task_id)
		elif id == MENU_DELETE:
			# The editor's own confirmation, raised on a task it isn't holding: see
			# `task_editor.confirm_delete`.
			editor.confirm_delete(task_id))
	# `_on_card_menu_hidden` is where this menu is freed, and where the click that takes it down is
	# recorded as a click still owed a menu — so the two are one connection, not two.
	menu.popup_hide.connect(_on_card_menu_hidden.bind(menu, task_id))
	# The menu this one replaces, if any — the paths that move a menu have usually closed it already
	# and this finds nothing, but `_move_card_menu_to` is the one caller that can arrive while the menu
	# it replaces is still up. Either way only one card menu ends up on screen.
	if is_instance_valid(_card_menu):
		_card_menu.hide()
	_card_menu = menu
	_card_menu_task = task_id
	add_child(menu)
	menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
