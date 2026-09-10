@tool
extends PopupPanel

## board_switcher.gd — the "switch board" popup, opened from the board chip in the
## tab bar. Lists every known board (click to switch), and offers two actions:
## create a brand-new board, or import an existing board JSON from anywhere on disk.
## Modeled on the epics dialog: built once, rebuilt from fresh state on each open().

const T = preload("res://addons/godoban/ui/theme.gd")
const I = preload("res://addons/godoban/ui/icons.gd")
const GodobanStore = preload("res://addons/godoban/data/godoban_store.gd")

var store: RefCounted
var _import_dialog: FileDialog

var _rows: VBoxContainer
var _action_row: HBoxContainer
var _create_box: VBoxContainer
var _create_name: LineEdit
var _usage: Label


## `p_import_dialog` is owned by the main screen (not the popup) so it survives the
## popup closing on an outside click; the switcher only triggers it and consumes
## its result.
func setup(p_store: RefCounted, p_import_dialog: FileDialog) -> void:
	store = p_store
	_import_dialog = p_import_dialog
	_import_dialog.file_selected.connect(_import)
	# A board whose file is gone gets dropped from the registry by the store; keep the
	# visible list in sync so the user doesn't click the dead row again.
	store.board_missing.connect(_on_board_missing)
	_build()


func _build() -> void:
	title = "Boards"
	add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER_SOFT(), 10, 16, 16, 14, 14, 1))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(280, 0)
	add_child(v)

	v.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ~4 rows (~34px each + separation) before it scrolls; the panel auto-sizes to the
	# content minimum, so this minimum is what decides when the viewport starts scrolling.
	scroll.custom_minimum_size = Vector2(0, 160)
	v.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	var sep := HSeparator.new()
	v.add_child(sep)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	v.add_child(_action_row)
	_build_actions()

	_create_box = VBoxContainer.new()
	_create_box.add_theme_constant_override("separation", 8)
	_create_box.visible = false
	v.add_child(_create_box)
	_build_create()


func _build_header() -> Control:
	var h := HBoxContainer.new()
	var t := Label.new()
	t.text = "Boards"
	t.add_theme_font_size_override("font_size", 15)
	h.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	_usage = Label.new()
	_usage.add_theme_color_override("font_color", T.TEXT_FAINT())
	_usage.text = "click to switch"
	h.add_child(_usage)
	return h


func _build_actions() -> void:
	var new_btn := Button.new()
	new_btn.text = "New board"
	new_btn.icon = I.icon("plus", 16)
	_tint_icon(new_btn)
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.button(new_btn)
	new_btn.pressed.connect(_begin_create)
	_action_row.add_child(new_btn)

	var import_btn := Button.new()
	import_btn.text = "Import"
	import_btn.icon = I.icon("folder-open", 16)
	_tint_icon(import_btn)
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.button(import_btn)
	import_btn.pressed.connect(_open_import)
	_action_row.add_child(import_btn)


func _build_create() -> void:
	_create_name = LineEdit.new()
	_create_name.placeholder_text = "Board name"
	T.field(_create_name)
	_create_name.text_submitted.connect(func(_t): _create())
	_create_box.add_child(_create_name)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	_create_box.add_child(btns)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(spacer)

	var cancel := Button.new()
	cancel.text = "Cancel"
	T.button(cancel)
	cancel.pressed.connect(_cancel_create)
	btns.add_child(cancel)

	var create := Button.new()
	create.text = "Create"
	T.button(create, true)
	create.pressed.connect(_create)
	btns.add_child(create)


## Position the popup just below the chip and rebuild the rows from the current
## registry, so it always reflects the latest boards + current selection.
func open(anchor: Rect2i) -> void:
	_create_box.visible = false
	_action_row.visible = true
	_rebuild_rows()
	var pos := anchor.position + Vector2i(0, anchor.size.y)
	popup(Rect2i(pos.x, pos.y, 280, 0))


func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.free()
	var boards: Array = store.list_boards()
	if boards.is_empty():
		var empty := Label.new()
		empty.text = "No boards yet."
		empty.add_theme_color_override("font_color", T.TEXT_FAINT())
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_rows.add_child(empty)
		return
	for entry in boards:
		_rows.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var current: bool = String(entry["id"]) == store.current_board_id()
	var is_builtin := String(entry["path"]).begins_with(GodobanStore.BOARDS_DIR)

	var row := PanelContainer.new()
	var row_normal := T.row_surface()
	var row_hover := T.row_surface()
	row_hover.bg_color = T.BG_HOVER()
	# PanelContainer draws only its "panel" stylebox — no normal/hover states — so
	# the base surface goes there and hover is swapped in via mouse_entered/exited.
	row.add_theme_stylebox_override("panel", row_normal)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", row_hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", row_normal))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	# Children are mouse-Ignore so a click anywhere on the row reaches `row.gui_input`.
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	# Leading glyph: a check marks the current board; a kanban bar marks the rest.
	var marker := TextureRect.new()
	marker.custom_minimum_size = Vector2(16, 16)
	marker.texture = I.icon("check", 16) if current else I.icon("kanban", 16)
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker.modulate = T.ACCENT() if current else T.TEXT_FAINT()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(marker)

	var label := Label.new()
	label.text = String(entry["name"])
	label.add_theme_color_override("font_color", T.ACCENT() if current else T.TEXT())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(label)

	# Imports may live outside BOARDS_DIR — show their file name so it's clear
	# where the board's data actually is. Managed boards stay minimal.
	var sub: Label = null
	if not is_builtin:
		sub = Label.new()
		sub.text = String(entry["path"]).get_file()
		sub.add_theme_color_override("font_color", T.TEXT_FAINT())
		sub.add_theme_font_size_override("font_size", 11)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sub)

	# Inline rename is a swap: a read-only name label (interactive row) vs. an editable
	# group (LineEdit + green accept / red cancel). Only one is visible at a time; the
	# group starts hidden. Children keep their own mouse filter so the buttons receive
	# clicks while the row's switch handler stays quiet during editing (see `_on_row_input`).
	# All the nodes are created before their wiring so the lambdas below can close over them.
	var edit_box := HBoxContainer.new()
	edit_box.add_theme_constant_override("separation", 6)
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.visible = false

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Board name"
	T.field(name_edit)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var accept_btn := _icon_button("check", "Save name")
	# Green — a clear "commit" affordance, distinct from the neutral chrome around it.
	_tint_button_icon(accept_btn, Color("#3fae74"), Color("#3fae74").lightened(0.12))

	var cancel_btn := _icon_button("x", "Cancel")
	# Red — the same danger red used by the remove glyph, so cancel reads as "back out".
	_tint_button_icon(cancel_btn, T.OVERDUE, T.OVERDUE.lightened(0.12))

	# "Rename" (pencil) — before the remove glyph. Clicking it flips the row into edit mode.
	var pencil_btn := _icon_button("pencil", "Rename board")
	_tint_button_icon(pencil_btn, T.TEXT_FAINT(), T.ACCENT())

	# "Remove from list" — unregisters the board but leaves its file on disk (the user
	# deletes the file themselves). STOP filter so the click lands here, not on the row's
	# switch handler; hand cursor + red-on-hover mark it as a clickable remove control.
	var remove_btn := _icon_button("x", "Remove from list (file stays on disk)")
	_tint_remove_icon(remove_btn)

	# Toggle between view (label + actions) and edit (LineEdit + accept/cancel). When
	# entering edit, seed the field from the entry and focus it once it's mounted.
	# `sub` may be null for managed boards — guard the lookup.
	var set_edit := func(on: bool) -> void:
		edit_box.visible = on
		label.visible = not on
		pencil_btn.visible = not on
		remove_btn.visible = not on
		if sub != null:
			sub.visible = not on
		if on:
			name_edit.text = String(entry["name"])
			name_edit.call_deferred("grab_focus")

	var accept := func() -> void:
		var name: String = name_edit.text.strip_edges()
		if name == "" or name == String(entry["name"]):
			# Nothing to change — just leave edit mode.
			set_edit.call(false)
			return
		store.rename_board(String(entry["id"]), name)
		call_deferred("_rebuild_rows")

	# Lay out left→right: name area (label or edit group), then rename, then remove.
	edit_box.add_child(name_edit)
	edit_box.add_child(accept_btn)
	edit_box.add_child(cancel_btn)
	h.add_child(edit_box)
	h.add_child(pencil_btn)
	h.add_child(remove_btn)

	accept_btn.pressed.connect(accept)
	cancel_btn.pressed.connect(func(): set_edit.call(false))
	# Enter commits, Esc cancels — mirror the create-box behaviour.
	name_edit.text_submitted.connect(func(_t): accept.call())
	name_edit.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			set_edit.call(false))
	pencil_btn.pressed.connect(func(): set_edit.call(true))
	remove_btn.pressed.connect(func(): _remove(entry))

	row.gui_input.connect(func(e): _on_row_input(e, entry, edit_box))
	return row


func _on_row_input(e: InputEvent, entry: Dictionary, edit_box: Control = null) -> void:
	# While a row is being renamed, a stray click on the row must not switch boards.
	if edit_box != null and edit_box.visible:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		# If the board's file is gone the store won't switch and keeps us open, so the
		# user sees the refreshed list + the "removed" message from the main screen.
		if store.switch_board(String(entry["id"])):
			hide()


func _remove(entry: Dictionary) -> void:
	store.remove_board(String(entry["id"]))
	# Defer: free() can't run while this row's button is still emitting its `pressed` signal.
	call_deferred("_rebuild_rows")


## A small flat icon-only button: no background/border, a hand cursor, and a tooltip.
## The glyph is tinted separately via `_tint_button_icon` / `_tint_remove_icon`.
func _icon_button(kind: String, tooltip: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.icon = I.icon(kind, 16)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(16, 16)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	return b


## Tint an icon button's glyph: `base` while idle/focused/pressed, `hover` while the
## pointer is over it. Lets two icons in the same row read as distinct (pencil, remove).
func _tint_button_icon(btn: Button, base: Color, hover: Color) -> void:
	for s in ["icon_normal_color", "icon_focus_color", "icon_pressed_color"]:
		btn.add_theme_color_override(s, base)
	btn.add_theme_color_override("icon_hover_color", hover)
	btn.add_theme_color_override("icon_hover_pressed_color", hover)


## Faint "×" glyph, tinted to the danger red only on hover — a quiet cue that this removes
## the board from the list (it never deletes the file on disk).
func _tint_remove_icon(btn: Button) -> void:
	_tint_button_icon(btn, T.TEXT_FAINT(), T.OVERDUE)


func _begin_create() -> void:
	_action_row.visible = false
	_create_box.visible = true
	_create_name.text = ""
	# Defer so the box is mounted before grabbing focus.
	call_deferred("_focus_create")


func _focus_create() -> void:
	if _create_name != null and _create_name.is_inside_tree():
		_create_name.grab_focus()


func _cancel_create() -> void:
	_create_box.visible = false
	_action_row.visible = true


func _create() -> void:
	var name := _create_name.text.strip_edges()
	if name == "":
		return
	store.create_board(name)
	hide()


func _open_import() -> void:
	if _import_dialog == null:
		return
	_import_dialog.popup_centered_ratio(0.5)


func _import(path: String) -> void:
	# A duplicate import is refused: the store emits `board_import_rejected` and the
	# main screen shows "already on the list". Keep the switcher as-is on that path.
	if store.import_board(path) == "":
		return
	hide()


## A board's file went missing while switching; the store dropped it from the registry
## and the main screen showed the user. If the switcher is open, scrub the dead row.
## Deferred: `free()` on the clicked row can't run while it's still dispatching its
## own gui_input signal (the object is "locked"), so wait for the next idle frame.
func _on_board_missing(_id: String, _name: String) -> void:
	if is_visible():
		call_deferred("_rebuild_rows")


func _tint_icon(btn: Button) -> void:
	var c := T.TEXT()
	for s in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_hover_pressed_color", "icon_focus_color"]:
		btn.add_theme_color_override(s, c)
