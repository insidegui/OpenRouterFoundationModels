import Foundation

public enum OpenRouterError: LocalizedError, Sendable, Equatable {
  case missingCredential

  public var errorDescription: String? {
    switch self {
    case .missingCredential:
      "No OpenRouter credential. Provide an API key or use a proxy that supplies one."
    }
  }
}
