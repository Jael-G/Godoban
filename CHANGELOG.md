# Changelog

All notable changes to this project will be documented in this file.


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
