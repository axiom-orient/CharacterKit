import SwiftUI

@main
struct CharacterHostDemoApp: App {
  var body: some Scene {
    WindowGroup {
      HostDemoView()
    }
    Window("All characters", id: "all-characters") {
      CharacterShowcaseView()
    }
    .defaultSize(width: 1144, height: 746)
  }
}
