// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CharacterPreview",
  platforms: [.macOS(.v13)],
  dependencies: [.package(name: "CharacterKit", path: "../..")],
  targets: [.executableTarget(
    name: "CharacterPreview",
    dependencies: [.product(name: "ReactiveCharacterKit", package: "CharacterKit")]
  )],
  swiftLanguageModes: [.v6]
)
