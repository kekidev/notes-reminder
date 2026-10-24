import Foundation

struct ClaudeConfigError: LocalizedError {
  let errorDescription: String?
}

/// `existing` with `mcpServers.glance` set; every other key is kept. Nil or empty means a new file.
func mergeClaudeConfig(_ existing: Data?, command: String, todoPath: String) throws -> Data {
  var config: [String: Any] = [:]
  if let existing, !existing.isEmpty {
    guard let object = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
      throw ClaudeConfigError(errorDescription: "The config is not a JSON object.")
    }
    config = object
  }
  var servers = config["mcpServers"] as? [String: Any] ?? [:]
  servers["glance"] = ["command": command, "args": [todoPath]]
  config["mcpServers"] = servers
  return try JSONSerialization.data(
    withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}
