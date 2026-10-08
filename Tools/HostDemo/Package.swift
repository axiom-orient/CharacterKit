// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CharacterHostDemo",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(name: "CharacterKit", path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "CharacterHostDemo",
      dependencies: [
        .product(name: "ReactiveCharacterKit", package: "CharacterKit"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
