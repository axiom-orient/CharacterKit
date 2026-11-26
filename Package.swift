// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CharacterKit",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "ReactiveCharacterKit",
      targets: ["ReactiveCharacterKit"]
    ),
  ],
  targets: [
    .target(
      name: "ReactiveCharacterKit",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "ReactiveCharacterKitTests",
      dependencies: ["ReactiveCharacterKit"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
