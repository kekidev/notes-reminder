import Foundation
import GlanceCore
import GlanceMCP
import MCP

// stdout carries the MCP protocol, so every message for humans goes to stderr.
func log(_ message: String) {
  FileHandle.standardError.write(Data("glance-mcp: \(message)\n".utf8))
}

guard CommandLine.arguments.count == 2 else {
  log("usage: glance-mcp <path-to-todo.md>")
  exit(64)
}
let path = CommandLine.arguments[1]
let store = FileStore(url: URL(filePath: path))
let resourceURI = "glance://tasks"

let server = Server(
  name: "glance", version: "0.1.0",
  capabilities: .init(prompts: .init(), resources: .init(), tools: .init()))

await server.withMethodHandler(ListTools.self) { _ in .init(tools: GlanceTools.all) }
await server.withMethodHandler(CallTool.self) { params in
  GlanceTools.handle(params.name, params.arguments, store: store, now: Date())
}

await server.withMethodHandler(ListResources.self) { _ in
  .init(resources: [
    Resource(
      name: "Glance tasks", uri: resourceURI, description: "The user's to-do list file",
      mimeType: "text/markdown")
  ])
}
await server.withMethodHandler(ReadResource.self) { params in
  guard params.uri == resourceURI else {
    throw MCPError.invalidParams("Unknown resource \(params.uri)")
  }
  let text = MarkdownSerializer.serialize(try store.read().0)
  return .init(contents: [.text(text, uri: resourceURI, mimeType: "text/markdown")])
}

let extractTasks = """
  Scan this conversation for action items: things I said I need to do, with any due dates. \
  Call list_tasks to see what is already on my list. Then call suggest_tasks once with the new \
  items, giving a short reason for each. Do not call add_task.
  """
await server.withMethodHandler(ListPrompts.self) { _ in
  .init(prompts: [
    Prompt(name: "extract_tasks", description: "Suggest to-dos found in this conversation")
  ])
}
await server.withMethodHandler(GetPrompt.self) { params in
  guard params.name == "extract_tasks" else {
    throw MCPError.invalidParams("Unknown prompt \(params.name)")
  }
  return .init(
    description: "Suggest to-dos found in this conversation",
    messages: [.user(.text(text: extractTasks))])
}

try await server.start(transport: StdioTransport())
log("serving \(path)")
await server.waitUntilCompleted()
