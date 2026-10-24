// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Glance",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "GlanceCore", targets: ["GlanceCore"]),
    .executable(name: "glance-mcp", targets: ["glance-mcp"]),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1")
  ],
  targets: [
    .target(name: "GlanceCore"),
    // Tool logic lives in a library so tests can call it without the stdio transport.
    .target(
      name: "GlanceMCP",
      dependencies: ["GlanceCore", .product(name: "MCP", package: "swift-sdk")]
    ),
    .executableTarget(
      name: "glance-mcp",
      dependencies: ["GlanceCore", "GlanceMCP", .product(name: "MCP", package: "swift-sdk")]
    ),
    .testTarget(
      name: "GlanceCoreTests",
      dependencies: ["GlanceCore"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "GlanceMCPTests", dependencies: ["GlanceMCP"]),
  ]
)
