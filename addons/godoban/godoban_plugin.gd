@tool
extends EditorPlugin

const MainScreen = preload("res://addons/godoban/godoban_main_screen.tscn")

var screen: Control

func _store() -> Variant:
	return screen.get("store") if screen else null

func _enter_tree() -> void:
	screen = MainScreen.instantiate()
	EditorInterface.get_editor_main_screen().add_child(screen)
	_make_visible(false)

func _exit_tree() -> void:
	if screen:
		var s = _store()
		if s:
			s.save_now()
		screen.queue_free()
		screen = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if screen:
		screen.visible = visible

func _get_plugin_name() -> String:
	return "Godoban"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Edit", "EditorIcons")

func _apply_changes() -> void:
	var s = _store()
	if s:
		s.save_now()
