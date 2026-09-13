@tool
extends RefCounted

## godoban_model.gd — pure data classes (Board / Task / Epic) plus JSON
## (de)serialization. No UI, no filesystem access here.

const STATUSES := ["backlog", "todo", "in_progress", "review", "done"]
const STATUS_TITLES := ["Backlog", "To Do", "In Progress", "Review", "Done"]
const PRIORITIES := ["low", "medium", "high", "critical"]
const PRIORITY_TITLES := ["Low", "Medium", "High", "Critical"]

## Maximum tag length. Tags are laid out to their own width everywhere they appear, so an
## over-long one stretches its chip past the popup and its card pill wider than its column —
## a layout break, not a cosmetic wart. 24 covers the compound names people actually write
## (`needs-design-review`, `regression-test-required`) and still fits the picker's grid cells.
const MAX_TAG_LEN := 24


## Trims a tag at the point it enters a task. Only the input path clamps: tags already on a
## board that exceed the limit (hand-edited JSON) are left as they are rather than silently
## rewritten, and stay legible through `tag_label`.
static func clamp_tag(tag: String) -> String:
	return tag.strip_edges().substr(0, MAX_TAG_LEN)


## A tag rendered where there may not be room for it whole. A no-op within the limit, so it
## only shortens tags predating `MAX_TAG_LEN`; callers pair the ellipsis with a tooltip.
static func tag_label(tag: String) -> String:
	if tag.length() <= MAX_TAG_LEN:
		return tag
	return tag.substr(0, MAX_TAG_LEN) + "…"


## The comparison key for a tag: trimmed, lowercased. Tags are stored as the user typed them and
## are only ever *compared* through this, so "AI" and "ai" are one tag for every question that
## matters — the vocabulary's dedup, a usage count, and the rename/delete sweep — while the
## stored spelling, which is what gets displayed, is never rewritten by a comparison.
##
## Delegates to the same-named static on `Board`, which is where it lives: an inner class can't
## reach the enclosing script's statics, and the vocabulary merge happens inside `Board`. One
## implementation, two ways in.
static func tag_key(tag: String) -> String:
	return Board.tag_key(tag)


static func status_title(status: String) -> String:
	var i := STATUSES.find(status)
	return STATUS_TITLES[i] if i != -1 else status


static func priority_title(priority: String) -> String:
	var i := PRIORITIES.find(priority)
	return PRIORITY_TITLES[i] if i != -1 else priority


static func format_date(ts: int) -> String:
	if ts == 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


class Epic:
	extends RefCounted

	const DEFAULT_COLOR := "#5e6ad2"

	var id: String
	var title: String
	var color: String

	func _init(p_id := "", p_title := "", p_color := DEFAULT_COLOR) -> void:
		id = p_id
		title = p_title
		color = p_color

	func to_dict() -> Dictionary:
		return {"id": id, "title": title, "color": color}

	static func from_dict(d: Dictionary) -> Epic:
		return Epic.new(
			str(d.get("id", "")),
			str(d.get("title", "")),
			str(d.get("color", DEFAULT_COLOR))
		)


class Task:
	extends RefCounted

	var id: String
	var title: String
	var description: String
	var status: String
	var priority: String
	var epic_id: String  # "" == no epic (serialized as null)
	var due_date: int  # Unix timestamp, 0 == none (serialized as null)
	## Tag NAMES, as the user typed them. The board's `tags` array is the vocabulary these are
	## drawn from (and the reason a tag can exist with no task on it); matching is always
	## case-insensitive, through `tag_key`.
	var tags: Array
	var created_at: int
	var updated_at: int

	func _init(p_id := "") -> void:
		id = p_id
		title = ""
		description = ""
		status = "backlog"
		priority = "medium"
		epic_id = ""
		due_date = 0
		tags = []
		created_at = 0
		updated_at = 0

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"title": title,
			"description": description,
			"status": status,
			"priority": priority,
			"epic_id": epic_id if epic_id != "" else null,
			"due_date": due_date if due_date != 0 else null,
			"tags": tags.duplicate(),
			"created_at": created_at,
			"updated_at": updated_at,
		}

	static func from_dict(d: Dictionary) -> Task:
		var t := Task.new(str(d.get("id", "")))
		t.title = str(d.get("title", ""))
		t.description = str(d.get("description", ""))
		t.status = str(d.get("status", "backlog"))
		t.priority = str(d.get("priority", "medium"))
		var epic = d.get("epic_id")
		t.epic_id = str(epic) if epic != null else ""
		var due = d.get("due_date")
		t.due_date = int(due) if due != null else 0
		for tag in d.get("tags", []):
			t.tags.append(str(tag))
		t.created_at = int(d.get("created_at", 0))
		t.updated_at = int(d.get("updated_at", 0))
		return t


class Board:
	extends RefCounted

	var name := ""
	var next_id := 1
	var epics: Array = []
	## The board's tag vocabulary: tag NAMES (the same strings `Task.tags` carries). It exists
	## independently of the tasks so a tag can be created before anything uses it — a tag has no
	## other identity to hang off, so "a tag that isn't on a task" is only representable here.
	## Tasks stay the source of what's *used*; this is the source of what *exists*. The store's
	## tag mutators keep the two in step, and any name that only a task carries is folded in on
	## load, so this is always a superset of what the tasks use.
	var tags: Array = []
	var tasks: Array = []

	func new_id(prefix: String) -> String:
		var result := "%s_%d" % [prefix, next_id]
		next_id += 1
		return result

	## The comparison key for a tag: trimmed, lowercased — see the identical static on the
	## enclosing script, which delegates here. It lives on `Board` because the vocabulary merge
	## below needs it and an inner class can't see the outer script's statics.
	static func tag_key(tag: String) -> String:
		return tag.strip_edges().to_lower()

	func get_task(id: String) -> Task:
		for t in tasks:
			if t.id == id:
				return t
		return null

	func get_epic(id: String) -> Epic:
		for e in epics:
			if e.id == id:
				return e
		return null

	func tasks_in_status(status: String) -> Array:
		var result: Array = []
		for t in tasks:
			if t.status == status:
				result.append(t)
		return result

	func add_task(t: Task) -> void:
		tasks.append(t)

	func remove_task(t: Task) -> void:
		tasks.erase(t)

	## Move `t` to sit immediately before the task with `before_id` in the board's task
	## array. That array IS the manual order, and a column's order is just the array
	## filtered by status (see `tasks_in_status`), so one array carries the order of all
	## five columns — and of every per-epic sub-board — at once: removing and re-inserting
	## a single element never changes the relative order of any other pair.
	##
	## The element is removed FIRST and the anchor looked up in the already-shortened
	## array, so no index adjustment is ever needed. `before_id` may be "" (move to the
	## end) or stale (also the end — a drop must always land somewhere). Returns true if
	## the array actually changed.
	func reorder_before(t: Task, before_id: String) -> bool:
		var from := tasks.find(t)
		if from == -1 or before_id == t.id:
			# Not ours, or "before itself": a no-op, NOT a jump to the end. Without this
			# guard the anchor has just been erased below, the lookup misses, and the
			# task silently lands last.
			return false
		tasks.remove_at(from)
		var to := tasks.size()
		if before_id != "":
			for i in tasks.size():
				if tasks[i].id == before_id:
					to = i
					break
		tasks.insert(to, t)
		return to != from

	func add_epic(e: Epic) -> void:
		epics.append(e)

	func remove_epic(e: Epic) -> void:
		epics.erase(e)
		for t in tasks:
			if t.epic_id == e.id:
				t.epic_id = ""

	func to_dict() -> Dictionary:
		var epic_arr: Array = []
		for e in epics:
			epic_arr.append(e.to_dict())
		var task_arr: Array = []
		for t in tasks:
			task_arr.append(t.to_dict())
		return {
			"name": name,
			"next_id": next_id,
			"tags": tags.duplicate(),
			"epics": epic_arr,
			"tasks": task_arr,
		}

	static func from_dict(d: Dictionary) -> Board:
		var b := Board.new()
		b.name = str(d.get("name", "My Board"))
		b.next_id = int(d.get("next_id", 1))
		for e in d.get("epics", []):
			if e is Dictionary:
				b.epics.append(Epic.from_dict(e))
		for t in d.get("tasks", []):
			if t is Dictionary:
				b.tasks.append(Task.from_dict(t))
		# After the tasks, because the vocabulary is read together with what they carry. A board
		# that predates the vocabulary has no `tags` key at all and simply gets the tags in use.
		b.tags = _merge_tag_names(d.get("tags", []), b.tasks)
		return b


	## The tag vocabulary as loaded: the board's own `listed` entries first, then any name a task
	## carries that the list didn't mention (a board written before the vocabulary existed, or one
	## edited by hand). Names are deduped case-insensitively and the first spelling wins, so the
	## first-encountered form is the one that gets displayed and saved.
	##
	## Deliberately a *union* rather than a straight read: it makes the field additive — old files
	## load unchanged, no migration step and no version gate is needed, and running it over an
	## already-migrated board is a no-op.
	static func _merge_tag_names(listed: Variant, tasks: Array) -> Array:
		var out: Array = []
		var seen := {}
		if listed is Array:
			for raw in listed:
				_append_tag_name(out, seen, str(raw))
		for t in tasks:
			for raw in t.tags:
				_append_tag_name(out, seen, str(raw))
		return out


	## Append `name` to a vocabulary being built unless a case variant is already in it. Blank
	## names are dropped: an empty tag is not a tag.
	static func _append_tag_name(out: Array, seen: Dictionary, name: String) -> void:
		var key := Board.tag_key(name)
		if key == "" or seen.has(key):
			return
		seen[key] = true
		out.append(name.strip_edges())
