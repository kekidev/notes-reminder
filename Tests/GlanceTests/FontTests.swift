import AppKit
import Testing

@Test(arguments: ["JetBrainsMono-Regular", "JetBrainsMono-Bold"])
func bundledFontLoads(_ name: String) {
  #expect(NSFont(name: name, size: 13) != nil)
}
