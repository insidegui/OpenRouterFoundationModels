import OSLog

enum OpenRouterAPILog {
  static let network = Logger(
    subsystem: "OpenRouterFoundationModels",
    category: "OpenRouterAPI.Network"
  )
}
