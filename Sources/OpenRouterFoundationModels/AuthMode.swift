import Foundation

public enum OpenRouterAuthMode: Hashable, Sendable {
  case apiKey(String)
  case proxied(headers: [String: String])
}
