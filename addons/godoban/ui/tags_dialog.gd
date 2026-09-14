@tool
extends "res://addons/godoban/ui/modal_overlay.gd"

## tags_dialog.gd — "Manage Tags": create, rename and delete the tags used across a board.
##
## This is the only place a tag can be created without a task. `all_tags()` reads the board's
## *vocabulary* (`Board.tags`) rather than scanning the tasks, so a tag made here exists from the
## moment it's typed — it shows up in the task editor's picker straight away with "0 tasks", ready
## to be assigned. Renaming rewrites the name on every task that carried the old one; deleting
## strips it from every task. Both are ordinary store mutators, so the board, the picker and the
## tag filter all follow through the store's `changed`.
##
## There is no Save. A tag is a single field, so each edit is applied the moment it's committed —
## Enter or the check on a rename, the Create row, Delete in the confirmation — and the footer's
## Close merely dismisses. That is also why this dialog does NOT listen to `store.changed`:
## rebuilding on it would free the rows out from under a mounted rename field, mid-typing.
## Nothing else can touch the board while this modal is up, so there is nothing to miss.
##
## Chrome (backdrop, centered bordered panel, header ✕) comes from `modal_overlay.gd`; `T`, `I`
## and the shared row parts (`_icon_button`, `_tint_button_icon`, `_contain_label`) are inherited
## from it.

const Model = preload("res://addons/godoban/data/godoban_model.gd")

## Wider than the base MODAL_W (400): a row is a name plus a task count plus two buttons, and at
## 400 the name clips before the count even fits. Narrower than the task editor's 660, which holds
## a two-column form this popup has nothing like.
const PANEL_W := 520.0

var store: RefCounted

var _rows: VBoxContainer
var _search: LineEdit
## The live `n/24` length counter beside the field — see `_refresh_count`.
var _count: Label
var _footer_count: Label
## The row currently swapped into rename mode, if any — ESC belongs to it, not to the popup.
var _editing_box: Control
var _confirm: PopupPanel
var _confirm_msg: Label
## The tag the confirmation is about — the confirm is one popup reused by every row, so which tag
## it deletes has to be remembered between opening it and pressing Delete.
var _confirm_pending := ""
## The filter text, held across a theme rebuild — the field is both the filter and how a tag gets
## created, so losing what was typed there would lose the user's work. See `_before_rebuild`.
var _query_cache := ""


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
	# Signals blocked around it, exactly as `open()` does: the field's own `text_changed` would
	# otherwise rebuild the rows a second time.
	_search.set_block_signals(true)
	_search.text = _query_cache
	_search.set_block_signals(false)
	_refresh_count()
	_rebuild_rows()


## Read before the children are freed by `rebuild_for_theme`: the filter text lives only in the
## field, and `_on_rebuilt` has no way back to it once the field is gone.
func _before_rebuild() -> void:
	_query_cache = _search.text if is_instance_valid(_search) else ""


func _modal_icon() -> String:
	return "tag"


func _modal_title() -> String:
	return "Manage Tags"


func _build_body(v: VBoxContainer) -> void:
	var sub := Label.new()
	sub.text = "Create, edit, and organize tags used across your tasks."
	sub.add_theme_color_override("font_color", T.TEXT_DIM())
	sub.add_theme_font_size_override("font_size", 12)
	v.add_child(sub)

	v.add_child(_build_search_row())

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

	v.add_child(_build_footer())


## The field and its length counter share a row; the counter sits outside the field's box because
## `clear_button_enabled` already owns the right-hand slot inside a LineEdit.
func _build_search_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var field := _build_search_field()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Width reserved so the field doesn't twitch as the count goes from one digit to two.
	_count.custom_minimum_size.x = 42
	_count.visible = false
	row.add_child(_count)

	return row


## The one field in the popup, and it does double duty: it filters the list, and it is how a tag
## gets created. Typing a name the board doesn't have puts a `+ Create "…"` row at the top of the
## list (`_refresh_create_row`), exactly as the task editor's picker does — same case-insensitive
## "don't duplicate a tag you already have" rule, same cap, same counter, and the same refusal to
## treat a comma as anything but part of the name.
##
## A field with the magnifier inside its left edge. LineEdit has no left-icon slot, and
## `clear_button_enabled` already owns the right one, so this is a composite — a field-styled panel
## carrying the border, with a chrome-less LineEdit and the glyph inside it. The wrapper owning the
## border is why focus has to be repainted onto it by hand.
func _build_search_field() -> Control:
	var box := PanelContainer.new()
	var border := func(focused: bool) -> StyleBoxFlat:
		return T.panel(T.BG_INPUT(), T.ACCENT() if focused else T.BORDER(), 6, 9, 9, 5, 5, 1)
	box.add_theme_stylebox_override("panel", border.call(false))
	# Clicking the field's own padding should land the caret, not fall through to the panel.
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_search.grab_focus())

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

	_search = LineEdit.new()
	_search.placeholder_text = "Search tags…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Capped at the source rather than trimmed afterwards: the field stops accepting input (paste
	# included), so nothing is silently cut. `create_tag` still guards the commit path.
	_search.max_length = Model.MAX_TAG_LEN
	# Bare inside the wrapper — two borders on one field reads as a mistake.
	for s in ["normal", "hover", "pressed", "focus"]:
		_search.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _on_query_changed())
	# Enter commits whatever is typed, when it's a name the board doesn't have.
	_search.text_submitted.connect(func(_t): _commit_query())
	_search.focus_entered.connect(func(): box.add_theme_stylebox_override("panel", border.call(true)))
	_search.focus_exited.connect(func(): box.add_theme_stylebox_override("panel", border.call(false)))
	row.add_child(_search)

	return box


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)

	_footer_count = Label.new()
	_footer_count.add_theme_color_override("font_color", T.TEXT_FAINT())
	_footer_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_footer_count)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close := Button.new()
	close.text = "Close"
	T.button(close)
	close.pressed.connect(_cancel)
	footer.add_child(close)

	return footer


## Center the popup and start from a clean slate: no filter, no row in rename mode, fresh rows.
func open() -> void:
	_editing_box = null
	_search.set_block_signals(true)
	_search.clear()
	_search.set_block_signals(false)
	_refresh_count()
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


func _on_query_changed() -> void:
	_refresh_count()
	_rebuild_rows()


## Rebuild the list from the current vocabulary and filter. The Create row is part of the list
## (it sits above it), so it's rebuilt with it; every `free()` here can be reached from a button
## that is still dispatching its own signal, which is why callers say `call_deferred`.
func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.free()
	var tags: Array = _visible_tags()
	_refresh_create_row()
	if tags.is_empty():
		var empty := Label.new()
		empty.text = ("No tag matches \"%s\"." % _query()) if _query() != "" else "No tags yet — type a name above to create one."
		empty.add_theme_color_override("font_color", T.TEXT_FAINT())
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_rows.add_child(empty)
	else:
		for name in tags:
			_rows.add_child(_build_row(String(name)))
	_refresh_footer(tags.size())
	_fit_to_view()


## The vocabulary matching the filter; everything shows when nothing is typed, so the list doubles
## as a browse of what the board has. Alphabetical, and there is no other order: the popup has no
## sort control.
func _visible_tags() -> Array:
	var q := _query()
	var out: Array = []
	for name in store.all_tags():
		if q == "" or String(name).to_lower().contains(q):
			out.append(name)
	return out


func _query() -> String:
	return _search.text.strip_edges()


## Whether the typed text is a tag the board doesn't have yet, and so worth offering to create.
## Comma-bearing input is excluded — the task editor's field reads a comma as a batch separator,
## so a tag containing one could never be typed back into a task, and `create_tag` refuses them
## for the same reason.
func _query_is_new() -> bool:
	var q := _query()
	if q == "" or q.contains(","):
		return false
	return store.find_tag(q) == ""


## The create row, as the list's first entry when the typed name is new.
func _refresh_create_row() -> void:
	if not _query_is_new():
		return
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 12)
	T.flat_button(b)
	b.add_theme_color_override("font_color", T.ACCENT())
	# Shows the name as it will be stored, so the cap is visible where it applies.
	b.text = "+ Create \"%s\"" % Model.clamp_tag(_search.text)
	b.pressed.connect(_commit_query)
	_rows.add_child(b)


## Commit the typed name as a tag: the Create row, or Enter in the field. An existing tag is never
## made twice — `create_tag` hands back the spelling the board already uses — and the field always
## clears, so the next name can just be typed.
func _commit_query() -> void:
	if not _query_is_new():
		return
	if store.create_tag(_search.text) == "":
		return
	_search.set_block_signals(true)
	_search.clear()
	_search.set_block_signals(false)
	_refresh_count()
	# Deferred: this runs from the Create button's own `pressed`, and the rebuild frees that button.
	call_deferred("_rebuild_rows")


## The length indicator beside the field. It counts the raw field text — the string the cap counts
## — and turns danger red *at* the cap, where the field stops accepting input.
func _refresh_count() -> void:
	var n := _search.text.length()
	_count.visible = n > 0
	if not _count.visible:
		return
	_count.text = "%d/%d" % [n, Model.MAX_TAG_LEN]
	_count.add_theme_color_override("font_color",
			T.OVERDUE if n >= Model.MAX_TAG_LEN else T.TEXT_FAINT())


func _refresh_footer(shown: int) -> void:
	var total: int = store.all_tags().size()
	if shown != total:
		_footer_count.text = "%d of %d tags" % [shown, total]
	else:
		_footer_count.text = "%d %s" % [total, "tag" if total == 1 else "tags"]


## One tag: its name, how many tasks carry it, and the two things you can do to it. The row is a
## column so a refused rename can explain itself underneath without widening anything.
func _build_row(name: String) -> Control:
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

	var label := Label.new()
	# Tags are capped on the way in, but a board edited by hand can hold a longer name; the label
	# clips with an ellipsis rather than stretching the row until the buttons leave the panel, and
	# the untruncated name stays in the row's tooltip.
	label.text = name
	label.add_theme_color_override("font_color", T.TEXT())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contain_label(label)
	h.add_child(label)
	# Re-evaluated on every resize, since whether the name is trimmed depends on the width, not
	# the text. On the *row*, not the label: Godot skips mouse-Ignore controls when hunting for a
	# tooltip. `Model.tag_label` only bites on a name predating the cap, so pair the two.
	label.resized.connect(func(): row.tooltip_text = _name_tooltip(label))
	row.tooltip_text = _name_tooltip(label)

	var usage := Label.new()
	var n: int = store.tag_usage(name)
	usage.text = "%d %s" % [n, "task" if n == 1 else "tasks"]
	usage.add_theme_color_override("font_color", T.TEXT_FAINT())
	usage.add_theme_font_size_override("font_size", 12)
	usage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	usage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(usage)

	# Inline rename is a swap: a read-only name + its actions, or an editable group (LineEdit +
	# green accept / red cancel). Only one is ever visible. All the nodes are created before their
	# wiring so the lambdas below can close over them.
	var edit_box := HBoxContainer.new()
	edit_box.add_theme_constant_override("separation", 6)
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.visible = false

	var field := LineEdit.new()
	field.placeholder_text = "Tag name"
	# Never shorter than the name already in the field: a board edited by hand can hold a name past
	# the cap, and seeding the field with one under a 24-char limit would truncate it on sight.
	field.max_length = maxi(Model.MAX_TAG_LEN, name.length())
	T.field(field)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var accept_btn := _icon_button("check", "Save name")
	# Green — a clear "commit" affordance, distinct from the neutral chrome around it.
	_tint_button_icon(accept_btn, Color("#3fae74"), Color("#3fae74").lightened(0.12))

	var cancel_btn := _icon_button("x", "Cancel")
	_tint_button_icon(cancel_btn, T.OVERDUE, T.OVERDUE.lightened(0.12))

	var pencil_btn := _icon_button("pencil", "Rename tag")
	_tint_button_icon(pencil_btn, T.TEXT_FAINT(), T.ACCENT())

	var remove_btn := _icon_button("trash-2", "Delete tag")
	_tint_button_icon(remove_btn, T.TEXT_FAINT(), T.OVERDUE)

	# Why a rename was refused, in the user's terms, under the field that was refused.
	var err := Label.new()
	err.add_theme_font_size_override("font_size", 11)
	err.add_theme_color_override("font_color", T.OVERDUE)
	err.visible = false
	err.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(err)

	# Toggle between view and edit. Entering seeds the field from the tag and focuses it once it's
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
			field.text = name
			field.call_deferred("grab_focus")
			field.call_deferred("select_all")
		_fit_to_view()

	var accept := func() -> void:
		var typed := field.text.strip_edges()
		if typed == "" or typed == name:
			set_edit.call(false)  # nothing to change — just leave edit mode
			return
		if not store.rename_tag(name, typed):
			# Refused: the name is unusable, or another tag already answers to it. Say which and
			# keep the field open with the text intact so it can be corrected.
			err.text = _rename_error(typed, name)
			err.visible = true
			_fit_to_view()
			return
		call_deferred("_rebuild_rows")

	edit_box.add_child(field)
	edit_box.add_child(accept_btn)
	edit_box.add_child(cancel_btn)
	h.add_child(edit_box)
	h.add_child(pencil_btn)
	h.add_child(remove_btn)

	accept_btn.pressed.connect(accept)
	cancel_btn.pressed.connect(func(): set_edit.call(false))
	# Enter commits, Esc backs out of the edit — the board switcher's rename behaves the same way.
	field.text_submitted.connect(func(_t): accept.call())
	field.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			set_edit.call(false))
	pencil_btn.pressed.connect(func(): set_edit.call(true))
	remove_btn.pressed.connect(func(): _ask_delete(name))

	return row


## Why `rename_tag` refused, in the user's terms. Only the collision has a cause worth naming; the
## rest (blank, comma-bearing, unchanged) are all "that name won't do".
func _rename_error(typed: String, current: String) -> String:
	var existing: String = store.find_tag(typed)
	if existing != "" and existing != current:
		return "A tag named \"%s\" already exists." % existing
	return "That name can't be used."


# --- delete -------------------------------------------------------------------


## Deleting a tag also strips it from every task that carries it, so it asks first and names the
## blast radius. A tag nothing uses needs no ceremony.
func _ask_delete(name: String) -> void:
	var n: int = store.tag_usage(name)
	if n == 0:
		_do_delete(name)
		return
	_confirm_pending = name
	_confirm_msg.text = "Delete \"%s\"? It will be removed from %d %s. This cannot be undone." % [
		name, n, "task" if n == 1 else "tasks"]
	_confirm.popup_centered()


func _do_delete(name: String) -> void:
	_confirm_pending = ""
	store.delete_tag(name)
	_confirm.hide()
	# Deferred: this runs from the row's own trash button (or the confirm's), and the rebuild frees
	# the row that is still dispatching.
	call_deferred("_rebuild_rows")


## Built like the task editor's delete confirmation, corner radius 0 included: this is a Godot
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
	title_msg.text = "Delete tag"
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
