#!/usr/bin/env python3
"""Print config.json with mcpServers.glance set. Usage: merge_mcp_config.py <config.json> <command> <todo-path>"""
import json, os, sys, tempfile


def merge(path, command, todo):
    try:
        text = open(path).read().strip()
    except FileNotFoundError:
        text = ""
    cfg = json.loads(text) if text else {}
    cfg.setdefault("mcpServers", {})["glance"] = {"command": command, "args": [todo]}
    return json.dumps(cfg, indent=2, sort_keys=False)


def self_test():
    d = tempfile.mkdtemp()
    p = os.path.join(d, "c.json")
    want = {"command": "/app/glance-mcp", "args": ["/t.md"]}
    # (a) missing file
    assert json.loads(merge(p, "/app/glance-mcp", "/t.md")) == {"mcpServers": {"glance": want}}
    # (b) other server kept
    open(p, "w").write('{"theme": "x", "mcpServers": {"other": {"command": "o"}}}')
    out = json.loads(merge(p, "/app/glance-mcp", "/t.md"))
    assert out == {"theme": "x", "mcpServers": {"other": {"command": "o"}, "glance": want}}
    # (c) existing glance replaced
    open(p, "w").write('{"mcpServers": {"glance": {"command": "old", "args": [], "env": {}}}}')
    assert json.loads(merge(p, "/app/glance-mcp", "/t.md")) == {"mcpServers": {"glance": want}}
    print("self-test ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 4:
        print(merge(*sys.argv[1:]))
    else:
        sys.exit(__doc__)
