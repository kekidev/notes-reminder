import SwiftUI

struct SettingsView: View {
  @AppStorage("notificationsEnabled") private var notificationsEnabled = true
  @AppStorage("showCompleted") private var showCompleted = true
  @State private var connecting = false

  var body: some View {
    Form {
      Toggle("Notifications", isOn: $notificationsEnabled)
      Toggle("Show Completed tab", isOn: $showCompleted)
      LaunchAtLoginToggle()
      // shortcut: read-only, rebinding the hot key is out of scope until someone asks.
      LabeledContent("Shortcut", value: "Open list: ⌥Space")
      Button("Connect Claude Desktop…") { connecting = true }
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .sheet(isPresented: $connecting) { ConnectClaudeSheet() }
  }
}

private struct ConnectClaudeSheet: View {
  private static let url = URL.homeDirectory.appending(
    path: "Library/Application Support/Claude/claude_desktop_config.json")
  @Environment(\.dismiss) private var dismiss
  @State private var before: Data?
  @State private var after: Data?
  @State private var message: String?
  @State private var failed = false
  @State private var applied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect Claude Desktop").font(.headline)
      HStack(alignment: .top) {
        pane("Before", before.map { String(bytes: $0, encoding: .utf8) ?? "" } ?? "(no file)")
        pane("After", after.flatMap { String(bytes: $0, encoding: .utf8) } ?? "")
      }
      if let message {
        Text(message).foregroundStyle(failed ? .red : .secondary)
      }
      HStack {
        Spacer()
        Button(applied ? "Done" : "Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Apply") { apply() }
          .keyboardShortcut(.defaultAction)
          .disabled(after == nil || applied)
      }
    }
    .padding()
    .frame(width: 640, height: 400)
    .onAppear { load() }
  }

  private func pane(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      ScrollView { Text(text).font(.mono(11)).frame(maxWidth: .infinity, alignment: .leading) }
    }
  }

  private func load() {
    before = try? Data(contentsOf: Self.url)
    do {
      after = try mergeClaudeConfig(
        before,
        command: Bundle.main.bundleURL.appending(path: "Contents/MacOS/glance-mcp").path,
        todoPath: AppState.defaultURL.path)
    } catch {
      after = nil
      failed = true
      message =
        "Existing config is not valid JSON; nothing will be written. \(error.localizedDescription)"
    }
  }

  private func apply() {
    guard let after else { return }
    do {
      if FileManager.default.fileExists(atPath: Self.url.path) {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMddHHmmss"
        let backup = URL(filePath: Self.url.path + ".bak." + stamp.string(from: .now))
        try FileManager.default.copyItem(at: Self.url, to: backup)
      }
      try after.write(to: Self.url, options: .atomic)
      applied = true
      failed = false
      message = "Restart Claude Desktop to load Glance."
    } catch {
      failed = true
      message = error.localizedDescription
    }
  }
}
