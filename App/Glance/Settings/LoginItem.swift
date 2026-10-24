import ServiceManagement
import SwiftUI

/// Launch at login, backed by `SMAppService.mainApp`.
enum LoginItem {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func set(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}

/// The toggle in the menu bar and in Settings; a failed change shows in the label.
struct LaunchAtLoginToggle: View {
  @State private var enabled = LoginItem.isEnabled
  @State private var error: String?

  var body: some View {
    Toggle(
      error ?? "Launch at Login",
      isOn: Binding(
        get: { enabled },
        set: { wanted in
          do {
            try LoginItem.set(wanted)
            error = nil
          } catch {
            self.error = error.localizedDescription
          }
          enabled = LoginItem.isEnabled
        }))
  }
}
