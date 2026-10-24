import SwiftUI
import UserNotifications

@main
struct GlanceApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @Environment(\.openSettings) private var openSettings

  // The ball and list are panels made at launch; the menu bar and Settings are the only scenes.
  var body: some Scene {
    MenuBarExtra("Glance", systemImage: "checklist") {
      Button(delegate.windows?.hidden == true ? "Show Glance" : "Hide Glance") {
        delegate.windows?.toggleVisible()
      }
      Button("Open List") { delegate.windows?.summon() }
      LaunchAtLoginToggle()
      Button("Settings…") {
        NSApp.activate()
        openSettings()
      }
      Button("Quit Glance") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    Settings { SettingsView() }
  }
}

@Observable
final class AppDelegate: NSObject, NSApplicationDelegate,
  UNUserNotificationCenterDelegate
{
  private(set) var windows: WindowController?
  private var hotKey: HotKey?
  @ObservationIgnored private let reminders = Reminders()
  @ObservationIgnored private var notificationsEnabled = true

  func applicationDidFinishLaunching(_ notification: Notification) {
    // The test host launches the app too. It must not open the real list, show panels, or take
    // ⌥Space, or a test run edits the owner's file behind their back.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    let state = AppState()
    let windows = WindowController(state: state)
    self.windows = windows
    hotKey = HotKey { windows.summon() }
    UNUserNotificationCenter.current().delegate = self
    trackReminders(state)
    NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        let enabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard let self, enabled != self.notificationsEnabled else { return }
        self.notificationsEnabled = enabled
        self.reminders.reschedule(state.document)
      }
    }
  }

  /// Reschedules now and again after every change to the document.
  private func trackReminders(_ state: AppState) {
    withObservationTracking {
      reminders.reschedule(state.document)
    } onChange: { [weak self] in
      // onChange runs before the new value lands; the hop reads it.
      Task { @MainActor in self?.trackReminders(state) }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    windows?.summon()
  }
}
