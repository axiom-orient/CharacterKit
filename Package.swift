// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CharacterKit",
  platforms: [
    .iOS(.v16),
    .macOS(.v11),
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
      resources: [
        .process("Resources")
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "ReactiveCharacterKitTests",
      dependencies: ["ReactiveCharacterKit"],
      resources: [
        .process("Resources")
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
