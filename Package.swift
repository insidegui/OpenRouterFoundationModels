// swift-tools-version: 6.4
import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6)
]

let package = Package(
  name: "OpenRouterFoundationModels",
  platforms: [
    .iOS("27.0"),
    .macOS("27.0"),
    .macCatalyst("27.0"),
    .visionOS("27.0"),
  ],
  products: [
    .library(
      name: "OpenRouterFoundationModels",
      targets: ["OpenRouterFoundationModels"]
    )
  ],
  targets: [
    .target(
      name: "OpenRouterAPI",
      swiftSettings: strictSwiftSettings
    ),
    .target(
      name: "OpenRouterFoundationModels",
      dependencies: ["OpenRouterAPI"],
      swiftSettings: strictSwiftSettings
    ),
    .executableTarget(
      name: "OpenRouterExample",
      dependencies: ["OpenRouterFoundationModels"],
      path: "Examples/OpenRouterExample",
      swiftSettings: strictSwiftSettings
    ),
    .testTarget(
      name: "OpenRouterAPITests",
      dependencies: ["OpenRouterAPI"],
      swiftSettings: strictSwiftSettings
    ),
    .testTarget(
      name: "OpenRouterFoundationModelsTests",
      dependencies: ["OpenRouterFoundationModels", "OpenRouterAPI"],
      swiftSettings: strictSwiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
