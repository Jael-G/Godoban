@tool
extends RefCounted

## godoban_settings.gd — the plugin's own preferences, and the one place they are read from.
##
## Kept in the editor's settings rather than in the project, unlike the boards: a font size is a
## personal reading preference, not board data. Under `res://` it would ride along in the user's
## commits and impose one person's taste on every collaborator.

## The size the UI was authored against. Every font literal is a *design* size at this base, and
## `Theme.fs()` restates it at the base in force.
const BASE := 13

## How far the stepper reaches either side of the editor's own size, in pixels of font size.
const OFFSET_SPAN := 10

## Fallback for an editor whose font size can't be read — Godot's own default.
const DEFAULT_EDITOR_FONT := 14

## The editor's UI font size setting, newest spelling first: 4.7 moved it under `fonts/`, and the
## older key is still answered there as an alias, so this works on either without a version check.
const _EDITOR_SIZE_KEYS := [
	"interface/editor/fonts/main_font_size",
	"interface/editor/main_font_size",
]

const _KEY_OFFSET := "godoban/settings/font_offset"


## Registers the offset with the editor, once, from the plugin's `_enter_tree`.
##
## The three calls have to stay in this order, and each needs the one before it: `set_setting` is
## what creates the value, `set_initial_value` (the editor's revert arrow) refuses a name it hasn't
## seen a value for, and `add_property_info` last is what gives the key its type and range in Editor
## Settings. There is no single `add_setting` that does all three.
static func register() -> void:
	var es := _settings()
	if es == null:
		return
	if not es.has_setting(_KEY_OFFSET):
		es.set_setting(_KEY_OFFSET, 0)
	es.set_initial_value(_KEY_OFFSET, 0, false)
	es.add_property_info({
		"name": _KEY_OFFSET,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "%d,%d,1" % [-OFFSET_SPAN, OFFSET_SPAN],
	})


## The base font size the UI is drawn at: the editor's own, moved by however far the stepper has
## walked away from it. Zero offset is the default, so every install starts at the editor's size.
static func font_size() -> int:
	return maxi(1, editor_font_size() + font_offset())


## How far the stepper sits from its centre. Zero means the editor's size, untouched.
static func font_offset() -> int:
	return clampi(_get_int(_KEY_OFFSET, 0), -OFFSET_SPAN, OFFSET_SPAN)


static func set_font_offset(offset: int) -> void:
	var es := _settings()
	if es != null:
		es.set_setting(_KEY_OFFSET, clampi(offset, -OFFSET_SPAN, OFFSET_SPAN))


## The editor's own UI font size — the centre the stepper walks away from.
##
## Read off the editor *theme* rather than the setting, because `default_font_size` is what the
## editor's controls are actually drawing with: it has the interface display scale folded in (28
## rather than 14 at scale 2.0), which is the size a user comparing the two is looking at. The
## setting is the fallback for when the theme can't be reached.
static func editor_font_size() -> int:
	if Engine.is_editor_hint():
		var t := EditorInterface.get_editor_theme()
		if t != null and t.default_font_size > 0:
			return t.default_font_size
	return _editor_font_size_setting()


static func _editor_font_size_setting() -> int:
	var es := _settings()
	if es == null:
		return DEFAULT_EDITOR_FONT
	for key in _EDITOR_SIZE_KEYS:
		if not es.has_setting(key):
			continue
		var v = es.get_setting(key)
		if v is int and v > 0:
			return v
	return DEFAULT_EDITOR_FONT


## The editor's settings, or null outside the editor.
static func _settings() -> EditorSettings:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_settings()


## Read a registered int. The `is int` guard covers a key that exists but has no value behind it —
## the state a freshly registered key is in until `register` fills it.
static func _get_int(key: String, fallback: int) -> int:
	var es := _settings()
	if es == null or not es.has_setting(key):
		return fallback
	var v = es.get_setting(key)
	return v if v is int else fallback
