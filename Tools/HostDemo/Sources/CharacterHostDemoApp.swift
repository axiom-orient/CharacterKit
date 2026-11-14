import SwiftUI

@main
struct CharacterHostDemoApp: App {
  var body: some Scene {
    WindowGroup("CharacterKit · 채팅 스튜디오") {
      CharacterChatView()
    }
    .defaultSize(width: 1000, height: 760)
    Window("Input inspector", id: "host-inspector") { HostDemoView() }
    Window("All characters", id: "all-characters") {
      CharacterShowcaseView()
    }
    .defaultSize(width: 1144, height: 746)
  }
}
