@tool
extends RefCounted

## godoban_model.gd — pure data classes (Board / Task / Epic) plus JSON
## (de)serialization. No UI, no filesystem access here.

const STATUSES := ["backlog", "todo", "in_progress", "review", "done"]
const STATUS_TITLES := ["Backlog", "To Do", "In Progress", "Review", "Done"]
const PRIORITIES := ["low", "medium", "high", "critical"]
const PRIORITY_TITLES := ["Low", "Medium", "High", "Critical"]


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
	var tasks: Array = []

	func new_id(prefix: String) -> String:
		var result := "%s_%d" % [prefix, next_id]
		next_id += 1
		return result

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
		return b
