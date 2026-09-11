# Changelog

All notable changes to this project will be documented in this file.


## [1.2.0] - 2026-09-11

### Added

- **Manual order, and it is now the default.** Columns are no longer sorted out of the box, so the
  arrangement you drag out is the arrangement you see. A new **Manual** sort mode sits first in the
  sort dropdown; picking one of the other six sorts still works exactly as before, and your manual
  arrangement is kept underneath it — switch back to Manual and it is there untouched.
- **Drop a card exactly where you want it.** Releasing a card between two others inserts it there
  (release between the 3rd and 4th and it becomes the 4th), instead of only changing its status.
  The order is saved per column and survives editor restarts. A thin line shows the slot the card
  will land in while you drag — drawn in the dragged card's priority colour, matching the border on
  the card under your cursor. Cards can also be dropped into empty columns now.

### Changed

- Reordering a card no longer counts as an edit: it leaves `updated_at` alone, so dragging a card
  into place does not jump it to the top of the **Latest edited** sort. Changing a card's *status*
  still counts as an edit.
- Changing a task's status in the task editor now moves it to the end of its new column, the same
  place a drag into empty space puts it, rather than leaving it at an arbitrary spot.


## [1.1.1] - 2026-09-09

### Fixed

- **Very long board names no longer take over the UI.** The toolbar chip shortens the name to a fixed
  character budget (the full name moves to the chip's tooltip) instead of stretching until it pushes
  the view tabs off the bar, and board-switcher rows clip their name with an ellipsis instead of
  widening the row until the switch / rename / remove buttons leave the popup.

### Changed

- Board switcher rows are name-only: the file-name label under imported boards is gone (where a board's
  file lives is registry detail, not how you pick one — a missing file is still reported on switch),
  and a row's tooltip now carries the full name whenever the row had to trim it.
- Added more spacing between the board chip and the Board / Overview tabs.

## [1.1.0] - 2026-09-09

### Added

- **Multiple boards**: keep any number of boards and switch between them from a clickable board chip in the toolbar.
- Each board is its own named JSON file under `res://godoban_boards/`, indexed by a `boards.json` registry (id → name → path, plus which board is current).
- A **board switcher** popup lists every known board (click to switch) with actions to **New board** and **Import board** (pick any JSON on disk).
- Boards are **imported by reference** — an imported file stays where it is and is never copied into the folder.

### Changed

- Data now lives under `res://godoban_boards/` (one JSON per board + a registry) instead of a single `res://godoban_data.json`.
- The active board's title is shown bold, letter-spaced, with a click-chevron so it reads as a control.
- Adopted Semantic Versioning strictly: major for breaking changes, minor for features, patch for fixes.
  Previous version bumps did not follow this and are left unchanged.

## [1.0.2] - 2026-09-06

### Changed

- Replaced the default editor plugin icon with a bespoke Kanban logo (`icon.svg`).

## [1.0.1] - 2026-09-06

### Changed

- The board now uses Godot's editor theme colors instead of its own hard-coded palette, so it follows the editor in both dark and light themes. Only semantic colors (status, priority, overdue, and per-epic accents) remain custom.
