import OSLog

enum OpenRouterLog {
  static let executor = Logger(
    subsystem: "OpenRouterFoundationModels",
    category: "Executor"
  )

  static let request = Logger(
    subsystem: "OpenRouterFoundationModels",
    category: "RequestBuilder"
  )

  static let stream = Logger(
    subsystem: "OpenRouterFoundationModels",
    category: "EventTranslator"
  )
}
