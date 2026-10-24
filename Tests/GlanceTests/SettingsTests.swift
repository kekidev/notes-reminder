import Foundation
import Testing

@testable import Glance

private func merged(_ existing: String?) throws -> NSDictionary {
  let data = try mergeClaudeConfig(
    existing.map { Data($0.utf8) }, command: "/app/glance-mcp", todoPath: "/t.md")
  return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private let glance: NSDictionary = ["command": "/app/glance-mcp", "args": ["/t.md"]]

struct ClaudeConfigTests {
  @Test func missingFileCreatesEntry() throws {
    #expect(try merged(nil) == ["mcpServers": ["glance": glance]])
  }

  @Test func otherServersAndKeysKept() throws {
    let out = try merged(#"{"theme": "x", "mcpServers": {"other": {"command": "o"}}}"#)
    #expect(out == ["theme": "x", "mcpServers": ["other": ["command": "o"], "glance": glance]])
  }

  @Test func existingGlanceReplaced() throws {
    let out = try merged(#"{"mcpServers": {"glance": {"command": "old", "env": {}}}}"#)
    #expect(out == ["mcpServers": ["glance": glance]])
  }

  @Test func invalidJSONThrows() {
    #expect(throws: (any Error).self) { try merged("{nope") }
    #expect(throws: (any Error).self) { try merged("[1]") }
  }
}
