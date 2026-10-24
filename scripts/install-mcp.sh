#!/usr/bin/env bash
# Register glance-mcp in Claude Desktop's config. Shows a diff first and backs up the old file.
set -euo pipefail
cd "$(dirname "$0")/.."

config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
todo="$HOME/Documents/Glance/todo.md"
legacy="$HOME/workspace/notes-reminder/data/todo.md"
[ -f "$legacy" ] && todo="$legacy"
app=/Applications/Glance.app
yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) config="${2:?--config needs a path}"; shift 2 ;;
    --app) app="${2:?--app needs a path}"; shift 2 ;;
    --yes) yes=1; shift ;;
    *) echo "usage: $0 [--config PATH] [--app PATH] [--yes]" >&2; exit 64 ;;
  esac
done

new=$(/usr/bin/python3 -I scripts/merge_mcp_config.py "$config" \
  "$app/Contents/MacOS/glance-mcp" "$todo")

old=/dev/null
[ -f "$config" ] && old=$config
diff -u "$old" <(printf '%s\n' "$new") || true

if [ "$yes" -eq 0 ]; then
  read -r -p "Apply? [y/N] " answer
  [ "$answer" = y ] || { echo "Aborted."; exit 1; }
fi

mkdir -p "$(dirname "$config")"
[ -f "$config" ] && cp "$config" "$config.bak.$(date +%Y%m%d%H%M%S)"
printf '%s\n' "$new" > "$config"
echo "Restart Claude Desktop to load Glance."
