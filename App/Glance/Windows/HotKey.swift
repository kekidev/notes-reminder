import Carbon.HIToolbox
import os

/// A global ⌥Space shortcut. Carbon hot keys need no Accessibility permission.
final class HotKey {
  private static let log = Logger(subsystem: "app.glance.Glance", category: "hotkey")
  private var ref: EventHotKeyRef?
  private let onPress: () -> Void

  init(onPress: @escaping () -> Void) {
    self.onPress = onPress
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { hotKey.onPress() }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    let id = EventHotKeyID(signature: OSType(0x676C_6E63), id: 1)  // 'glnc'
    let status =
      installed == noErr
      ? RegisterEventHotKey(
        UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
      : installed
    // Another app may own ⌥Space; the menu's Open List still works.
    if status != noErr { Self.log.error("⌥Space not registered: OSStatus \(status)") }
  }
}
