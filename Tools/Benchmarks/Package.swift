// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CharacterBenchmarks",
  platforms: [.macOS(.v13)],
  dependencies: [.package(path: "../..")],
  targets: [.executableTarget(
    name: "CharacterBenchmark",
    dependencies: [.product(name: "ReactiveCharacterKit", package: "CharacterKit")])],
  swiftLanguageModes: [.v6]
)
