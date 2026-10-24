# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-10-23

### Added
- A floating glass orb that shows how many lines are still open. Click it to open or close the panel, and drag it anywhere; it stays where you drop it.
- A notepad panel in which each page is one native text editor: Return continues a list, Tab and Shift-Tab indent, Backspace joins lines, ⌘Z undoes, and ↑/↓ move between lines.
- Checklist, bullet, heading, and plain lines, set with `[] `, `- `, `# `, ⇧⌘L, or the format bar.
- Pages that you add, rename, and delete right in the panel.
- A Completed tab: crossed-off lines move there, and you can restore, delete, or clear them. You can hide the tab.
- Liquid Glass with a transparency slider, a resizable panel, light and dark mode, and JetBrains Mono.
- Due-date notifications, with a tint on the orb when something is due.
- A local `glance-mcp` server (stdio only) for Claude Desktop: list, add, update, complete, and suggest tasks. A Settings button connects it.
- Launch at login, a menu bar icon, a ⌥Space global shortcut, and a quit button.

### Notes
- Notes live in `~/Documents/Glance/todo.md` as plain Markdown. Lines Glance doesn't recognise are kept exactly as they are.
- No network code, no telemetry.
