@tool
extends "res://addons/godoban/ui/modal_overlay.gd"

## epic_dialog.gd — "Epics": create, rename, recolor and delete a board's epics.
##
## Built like `tags_dialog.gd`, because the two answer the same question — a list of the things the
## tasks point at — and used to answer it two different ways. A row is a color square (click it for
## Godot's color picker), the epic's title, how many tasks are assigned to it, and the two things
## you can do to it: rename inline, or delete.
##
## There is no Save. An epic is a handful of fields, so each edit is applied the moment it's
## committed — Enter or the check on a rename, a picked color, Delete in the confirmation — and the
## footer's Close merely dismisses. That is why this dialog no longer stages drafts: a staged model
## means a row you deleted is still on the board until you Save, and a row you renamed reverts the
## moment the ✕ is pressed instead — two answers to "what does closing do", neither of them
## visible from the row you just edited. Every commit goes through an ordinary store mutator, so
## the board, the cards and the task editor's epic picker all follow through the store's `changed`.
##
## Deletion is the only thing that asks first, and only when it has a blast radius: an epic with
## tasks on it is confirmed, naming how many lose their assignment, while an unused one just goes.
##
## Also like the tags dialog, this one does NOT listen to `store.changed`: rebuilding on it would
## free the rows out from under a mounted rename field or an open color popup, mid-typing,
## mid-picking. Nothing else can touch the board while this modal is up, so there is nothing to
## miss.
##
## `changed(epic_id)` is emitted on every commit that alters what the task editor's epic picker
## lists — a new epic, a renamed one, a deleted one — so the picker follows along and a
## brand-new epic can be left selected there. A recolored epic doesn't emit it: the picker draws
## names, not colors.
##
## Chrome (backdrop, centered bordered panel, header ✕) comes from `modal_overlay.gd`; `T`, `I`
## and the shared row parts (`_icon_button`, `_tint_button_icon`, `_contain_label`,
## `_name_tooltip`) are inherited from it.

const Model = preload("res://addons/godoban/data/godoban_model.gd")
const ColorSwatch = preload("res://addons/godoban/ui/color_swatch.gd")

signal changed(epic_id: String)

## Wider than the base MODAL_W (400): a row is a color square plus a title plus a task count plus
## two buttons, and at 400 the title clips before the count even fits. The tags dialog came to the
## same number for the same reason, which is the point — the two popups should read as siblings.
const PANEL_W := 520.0
## The title a brand-new epic lands under, before its rename field takes over. Never blank: a
## board with an untitled epic draws a row with nothing to click.
const NEW_TITLE := "New epic"

var store: RefCounted

var _rows: VBoxContainer
var _head_count: Label
## The row currently swapped into rename mode, if any — ESC belongs to it, not to the popup.
var _editing_box: Control
## Id of an epic whose row should open straight into rename mode on the next rebuild. Set by
## "+ New epic", which creates the epic and then wants the user typing its real name.
var _focus_id := ""
var _confirm: PopupPanel
var _confirm_msg: Label
## The epic the confirmation is about — the confirm is one popup reused by every row, so which
## epic it deletes has to be remembered between opening it and pressing Delete.
var _confirm_pending := ""


func setup(p_store: RefCounted) -> void:
	store = p_store
	# Four rows or so before the list scrolls; the fit clamps it so the panel never outgrows the
	# editor window.
	list_min_h = 170.0
	list_max_h = 340.0
	_build()
	_on_rebuilt()


## Everything that follows `_build()` — run once at setup and again by `rebuild_for_theme`
## (see `modal_overlay.gd`), which is why none of it lives in `setup()`.
func _on_rebuilt() -> void:
	# After `_build`: the panel only exists once the base class has made it. `_build` hands it the
	# base MODAL_W, so this is also what re-widens it on a rebuild.
	panel.custom_minimum_size.x = PANEL_W
	_build_confirm()
	# The rows are gone, so any row that was in rename mode is too — and the confirmation is a new,
	# hidden popup, so what the old one was about is stale.
	_editing_box = null
	_confirm_pending = ""
	_rebuild_rows()


func _modal_icon() -> String:
	return "layers-2"


func _modal_title() -> String:
	return "Epics"


## The epic count sits just left of the ✕, where the task editor keeps its own header extras.
func _modal_header_extras() -> Control:
	_head_count = Label.new()
	_head_count.add_theme_color_override("font_color", T.TEXT_FAINT())
	_head_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return _head_count


func _build_body(v: VBoxContainer) -> void:
	var sub := Label.new()
	sub.text = "Create, edit, and organize the epics your tasks belong to."
	sub.add_theme_color_override("font_color", T.TEXT_DIM())
	sub.add_theme_font_size_override("font_size", 12)
	v.add_child(sub)

	list = ScrollContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, list_min_h)
	# The rows are one line each and never scroll sideways; a horizontal bar would only steal
	# height from the list.
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(list)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	list.add_child(_rows)

	# Creation is a button here rather than the tags dialog's "type a name into the search field":
	# a tag is a bare name so the field *is* the whole of it, while an epic needs a color decided
	# too — so the row is created first and the rename field that follows is where the name goes.
	v.add_child(_build_add_button())

	v.add_child(_build_footer())


## The create row, drawn like the tags dialog's "+ Create …" row (flat, accent text) so the two
## popups offer "make a new one" in the same place and the same shape.
func _build_add_button() -> Control:
	var b := Button.new()
	b.text = "+  New epic"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 12)
	T.flat_button(b)
	b.add_theme_color_override("font_color", T.ACCENT())
	b.add_theme_color_override("font_hover_color", T.ACCENT().lightened(0.15))
	b.pressed.connect(_create_epic)
	return b


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close := Button.new()
	close.text = "Close"
	T.button(close)
	close.pressed.connect(_cancel)
	footer.add_child(close)

	return footer


## Center the popup and start from a clean slate: fresh rows, no row in rename mode, no pending
## focus. The rows are read from the store here rather than held as drafts, so opening always
## shows the board as it actually is.
func open() -> void:
	_editing_box = null
	_focus_id = ""
	_rebuild_rows()
	_show_modal()


## A row in rename mode owns ESC — it backs out of the edit rather than dismissing the popup — and
## the delete confirmation owns it while it's up. `is_instance_valid` because committing a rename
## rebuilds, and frees, every row.
func _modal_escape_consumed() -> bool:
	if _confirm != null and _confirm.visible:
		return true
	return is_instance_valid(_editing_box) and _editing_box.visible


## ✕, ESC and a backdrop click all land here. There is nothing of the user's to throw away — every
## edit was applied as it was made — but the confirmation is a Window of its own and would outlive
## the popup if it weren't taken down with it.
func _cancel() -> void:
	if _confirm != null:
		_confirm.hide()
	hide()


# --- rows ---------------------------------------------------------------------


## Rebuild the list from the board's epics, in the board's own order — the epics array is the order
## the overview and the epic sub-boards read, so the popup shows it rather than imposing an
## alphabetical one the rest of the plugin doesn't use. Every `free()` here can be reached from a
## button that is still dispatching its own signal, which is why callers say `call_deferred`.
func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.free()
	# Read once and cleared: a fresh epic opens in rename mode on *this* rebuild, and must not
	# reopen on every rebuild after it.
	var focus := _focus_id
	_focus_id = ""
	var epics: Array = store.board.epics
	var n: int = epics.size()
	_head_count.text = "%d %s" % [n, "epic" if n == 1 else "epics"]
	if epics.is_empty():
		var empty := Label.new()
		empty.text = "No epics yet — press New epic."
		empty.add_theme_color_override("font_color", T.TEXT_FAINT())
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_rows.add_child(empty)
	else:
		for e in epics:
			_rows.add_child(_build_row(e, e.id == focus))
	_fit_to_view()


## One epic: its color, title, task count, and the two things you can do to it. The row is a column
## so a refused rename can explain itself underneath without widening anything. `start_edit` is the
## "+ New epic" handoff — the row is built already in rename mode.
func _build_row(e: Model.Epic, start_edit: bool) -> Control:
	var row := PanelContainer.new()
	var row_normal := T.row_surface()
	var row_hover := T.row_surface()
	row_hover.bg_color = T.BG_HOVER()
	# PanelContainer draws only its "panel" stylebox — no normal/hover states — so the base surface
	# goes there and hover is swapped in by hand, as on the board switcher's rows.
	row.add_theme_stylebox_override("panel", row_normal)
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", row_hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", row_normal))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	col.add_child(h)

	# Outside the view/edit swap: the color is not part of the name, and keeping the square put
	# means the title and the field it swaps with start at the same x. Clicking it opens Godot's
	# picker, and every color it emits lands on the board immediately — a live preview of the
	# epic's accents, with `mark_dirty`'s debounce collapsing the drag into one file write.
	#
	# The pipette beside it is the affordance: a colored square reads as a label, not a button, and
	# nothing else in the row says the color is editable. It opens the same picker, so the hint and
	# the thing it hints at are one target. The two sit in a nested box with a hairline gap —
	# separated by the row's own 8 they'd read as two unrelated widgets.
	var color_box := HBoxContainer.new()
	color_box.add_theme_constant_override("separation", 2)
	h.add_child(color_box)

	var sw := ColorSwatch.new()
	sw.set_color(Color(e.color))
	sw.tooltip_text = "Click to change color"
	sw.color_changed.connect(func(c): _commit_color(e, c))
	color_box.add_child(sw)

	var pipette := _icon_button("pipette", "Click to change color")
	# Faint by default so it doesn't compete with the title, accent on hover — the same "quiet
	# until you point at it" treatment the row's pencil and trash get.
	_tint_button_icon(pipette, T.TEXT_FAINT(), T.ACCENT())
	pipette.pressed.connect(func(): sw.open_picker())
	color_box.add_child(pipette)

	var label := Label.new()
	# Titles are free text and can be long; the label clips with an ellipsis rather than stretching
	# the row until the buttons leave the panel, and the untruncated title stays in the tooltip.
	label.text = e.title
	label.add_theme_color_override("font_color", T.TEXT())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contain_label(label)
	h.add_child(label)
	# Re-evaluated on every resize, since whether the title is trimmed depends on the width, not
	# the text. On the *row*, not the label: Godot skips mouse-Ignore controls when hunting for a
	# tooltip.
	label.resized.connect(func(): row.tooltip_text = _name_tooltip(label))
	row.tooltip_text = _name_tooltip(label)

	var usage := Label.new()
	var n: int = store.epic_usage(e.id)
	usage.text = "%d %s" % [n, "task" if n == 1 else "tasks"]
	usage.add_theme_color_override("font_color", T.TEXT_FAINT())
	usage.add_theme_font_size_override("font_size", 12)
	usage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	usage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(usage)

	# Inline rename is a swap: a read-only title + its actions, or an editable group (LineEdit +
	# green accept / red cancel). Only one is ever visible. All the nodes are created before their
	# wiring so the lambdas below can close over them.
	var edit_box := HBoxContainer.new()
	edit_box.add_theme_constant_override("separation", 6)
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.visible = false

	var field := LineEdit.new()
	field.placeholder_text = "Epic title"
	T.field(field)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var accept_btn := _icon_button("check", "Save title")
	# Green — a clear "commit" affordance, distinct from the neutral chrome around it.
	_tint_button_icon(accept_btn, Color("#3fae74"), Color("#3fae74").lightened(0.12))

	var cancel_btn := _icon_button("x", "Cancel")
	_tint_button_icon(cancel_btn, T.OVERDUE, T.OVERDUE.lightened(0.12))

	var pencil_btn := _icon_button("pencil", "Rename epic")
	_tint_button_icon(pencil_btn, T.TEXT_FAINT(), T.ACCENT())

	var remove_btn := _icon_button("trash-2", "Delete epic")
	_tint_button_icon(remove_btn, T.TEXT_FAINT(), T.OVERDUE)

	# Why a rename was refused, in the user's terms, under the field that was refused.
	var err := Label.new()
	err.add_theme_font_size_override("font_size", 11)
	err.add_theme_color_override("font_color", T.OVERDUE)
	err.visible = false
	err.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(err)

	# Toggle between view and edit. Entering seeds the field from the epic and focuses it once it's
	# mounted.
	var set_edit := func(on: bool) -> void:
		edit_box.visible = on
		label.visible = not on
		usage.visible = not on
		pencil_btn.visible = not on
		remove_btn.visible = not on
		err.visible = false
		# While this row is in edit mode it is what ESC talks to (see `_modal_escape_consumed`).
		_editing_box = edit_box if on else null
		if on:
			field.text = e.title
			field.call_deferred("grab_focus")
			field.call_deferred("select_all")
		_fit_to_view()

	var accept := func() -> void:
		var typed := field.text.strip_edges()
		if typed == e.title:
			set_edit.call(false)  # nothing to change — just leave edit mode
			return
		if typed == "":
			# An untitled epic is not a thing the user can mean: the row would draw a color square
			# and an empty line, with nothing to click to name it. Keep the field open with the text
			# as it was and say why.
			err.text = "An epic needs a title."
			err.visible = true
			_fit_to_view()
			return
		store.upsert_epic(e.id, typed, e.color)
		changed.emit(e.id)
		call_deferred("_rebuild_rows")

	edit_box.add_child(field)
	edit_box.add_child(accept_btn)
	edit_box.add_child(cancel_btn)
	h.add_child(edit_box)
	h.add_child(pencil_btn)
	h.add_child(remove_btn)

	accept_btn.pressed.connect(accept)
	cancel_btn.pressed.connect(func(): set_edit.call(false))
	# Enter commits, Esc backs out of the edit — the tags dialog's rename behaves the same way.
	field.text_submitted.connect(func(_t): accept.call())
	field.gui_input.connect(func(ev):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			set_edit.call(false))
	pencil_btn.pressed.connect(func(): set_edit.call(true))
	remove_btn.pressed.connect(func(): _ask_delete(e))

	# The "+ New epic" handoff, last so the row is fully wired before the field is asked to take
	# focus — `set_edit` mounts and focuses it.
	if start_edit:
		set_edit.call(true)

	return row


## A color was picked. Applied on the spot, and deliberately *without* rebuilding the rows: the
## picker that just emitted this is a child of the swatch in this very row, so a rebuild would free
## the popup the user is still dragging in. Nothing else on the row depends on the color.
func _commit_color(e: Model.Epic, c: Color) -> void:
	store.upsert_epic(e.id, e.title, c.to_html(false))


## "+ New epic": create it for real, then drop its row straight into rename mode so the name is
## typed in place — the same shape as the tags dialog's create row, where the epic exists from the
## moment it's made. Backing out of that field (Esc, or the red ✕) leaves it called "New epic",
## which the trash button beside it can undo.
func _create_epic() -> void:
	var id: String = store.board.new_id("epic")
	store.upsert_epic(id, NEW_TITLE, T.ACCENT().to_html(false))
	_focus_id = id
	changed.emit(id)
	# Deferred: the rebuild frees and remounts the rows the focus target is looked up in.
	call_deferred("_rebuild_rows")


# --- delete -------------------------------------------------------------------


## Deleting an epic also unassigns every task pointing at it, so it asks first and names the blast
## radius. An epic nothing uses needs no ceremony.
func _ask_delete(e: Model.Epic) -> void:
	var n: int = store.epic_usage(e.id)
	if n == 0:
		_do_delete(e.id)
		return
	_confirm_pending = e.id
	_confirm_msg.text = "Delete \"%s\"? It will be unassigned from %d %s. This cannot be undone." % [
		e.title, n, "task" if n == 1 else "tasks"]
	_confirm.popup_centered()


func _do_delete(id: String) -> void:
	_confirm_pending = ""
	store.delete_epic(id)
	_confirm.hide()
	changed.emit(id)
	# Deferred: this runs from the row's own trash button (or the confirm's), and the rebuild frees
	# the row that is still dispatching.
	call_deferred("_rebuild_rows")


## Built like the tags dialog's delete confirmation, corner radius 0 included: this is a Godot
## `Window`, and an embedded window paints an opaque square `embedded_border` frame behind its
## panel stylebox — which is what shows as black wedges in rounded corners.
func _build_confirm() -> void:
	_confirm = PopupPanel.new()
	_confirm.add_theme_stylebox_override("panel", T.panel(T.BG_PANEL(), T.BORDER(), 0, 24, 24, 24, 24, 2))
	_confirm.min_size = Vector2i(420, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	_confirm.add_child(cv)
	var title_msg := Label.new()
	title_msg.text = "Delete epic"
	title_msg.add_theme_font_size_override("font_size", 18)
	cv.add_child(title_msg)
	_confirm_msg = Label.new()
	_confirm_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_msg.add_theme_font_size_override("font_size", 14)
	_confirm_msg.add_theme_color_override("font_color", T.TEXT_DIM())
	_confirm_msg.custom_minimum_size.x = 360
	cv.add_child(_confirm_msg)
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
	T.button(c_del, true)
	c_del.pressed.connect(func(): _do_delete(_confirm_pending))
	crow.add_child(c_del)
	cv.add_child(crow)
	add_child(_confirm)
