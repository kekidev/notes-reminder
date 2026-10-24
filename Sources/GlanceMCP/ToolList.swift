import GlanceCore
import MCP

extension GlanceTools {
  public static let all: [Tool] = [
    Tool(
      name: "list_tasks",
      description: """
        List tasks in the user's Glance to-do list. Filters combine. due: "today" is open tasks \
        due today or overdue, "upcoming" is due after today, "none" is no due date.
        """,
      inputSchema: schema([
        "status": statusSchema,
        "category": ["type": "string", "description": "Category name"],
        "due": ["type": "string", "enum": ["today", "upcoming", "none"]],
      ])),
    Tool(
      name: "get_summary",
      description:
        "The number of open to-do tasks, and the open tasks due today or overdue.",
      inputSchema: schema([:])),
    Tool(
      name: "add_task",
      description: """
        Add a task to the user's list. Use this ONLY when the user explicitly asks to add \
        something. Otherwise use suggest_tasks, so the user can accept or dismiss it.
        """,
      inputSchema: schema(
        [
          "text": ["type": "string"],
          "category": [
            "type": "string",
            "description": "Category name; created if missing. Defaults to the first category.",
          ],
          "due": dueSchema,
        ], required: ["text"])),
    Tool(
      name: "suggest_tasks",
      description: """
        Propose tasks the user mentioned. They land in the Suggested section, where the user \
        accepts or dismisses each one. Tasks matching an open task are skipped and reported.
        """,
      inputSchema: schema(
        [
          "tasks": [
            "type": "array",
            "items": schema(
              [
                "text": ["type": "string"],
                "due": dueSchema,
                "reason": ["type": "string", "description": "Why you suggest it; saved as notes"],
              ], required: ["text"]),
          ],
          "source": [
            "type": "string", "description": "One word naming you; default claude-desktop",
          ],
        ], required: ["tasks"])),
    Tool(
      name: "update_task",
      description: """
        Edit a task by id from list_tasks. A new category moves the task. due or notes set to \
        "" or null clears them. Returns the task with its new id, which changes with text or category.
        """,
      inputSchema: schema(
        [
          "id": ["type": "string"],
          "text": ["type": "string"],
          "status": statusSchema,
          "category": ["type": "string", "description": "An existing category name"],
          "due": ["type": ["string", "null"], "description": .string(dueFormat)],
          "notes": ["type": ["string", "null"]],
        ], required: ["id"])),
    Tool(
      name: "complete_task", description: "Mark a task completed.",
      inputSchema: schema(["id": ["type": "string"]], required: ["id"])),
    Tool(
      name: "cancel_task", description: "Mark a task cancelled.",
      inputSchema: schema(["id": ["type": "string"]], required: ["id"])),
    Tool(
      name: "list_categories", description: "List category names in file order.",
      inputSchema: schema([:])),
    Tool(
      name: "add_category", description: "Add a category. Returns every category name.",
      inputSchema: schema(["name": ["type": "string"]], required: ["name"])),
  ]

  // MARK: - Schemas

  private static let statusSchema: Value = [
    "type": "string", "enum": .array(TaskStatus.allCases.map { .string("\($0)") }),
  ]

  private static let dueFormat = "\"YYYY-MM-DD\" or \"YYYY-MM-DD HH:mm\" (24-hour, local time)"
  private static let dueSchema: Value = ["type": "string", "description": .string(dueFormat)]

  private static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
    [
      "type": "object", "properties": .object(properties),
      "required": .array(required.map(Value.string)),
    ]
  }
}
