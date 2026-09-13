@tool
extends "res://addons/godoban/ui/modal_overlay.gd"

## One-line notice in the standard modal chrome — currently only "that board is already on the
## list" after a refused import. Lives alongside the other dialogs rather than inside the board
## switcher, because it has to stay up after the switcher hides itself following the action that
## triggered it.
##
## Chrome (backdrop, centered bordered panel, header ✕) comes from `modal_overlay.gd`; `T` and `I`
## are inherited from it.

var _label: Label


func setup() -> void:
	_build()


func _modal_title() -> String:
	return "Notice"


func _build_body(v: VBoxContainer) -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wide enough for the message to read as a sentence rather than a column of words.
	_label.custom_minimum_size = Vector2(MODAL_W - 60.0, 0)
	v.add_child(_label)

	var ok := Button.new()
	ok.text = "OK"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	T.button(ok, true)
	ok.pressed.connect(_cancel)
	v.add_child(ok)


func show_text(text: String) -> void:
	_label.text = text
	_show_modal()
