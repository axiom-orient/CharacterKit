// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CharacterHostDemo",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "CharacterHostDemo",
      dependencies: [
        .product(name: "ReactiveCharacterKit", package: "CharacterKit"),
        .product(name: "CharacterChat", package: "CharacterKit"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
