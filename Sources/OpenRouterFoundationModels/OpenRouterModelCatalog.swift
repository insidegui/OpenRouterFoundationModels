import Foundation
import OpenRouterAPI

public struct OpenRouterModelCatalog: Sendable {
  private let authMode: OpenRouterAuthMode
  private let client: OpenRouterClient

  public init(
    auth: OpenRouterAuthMode,
    baseURL: URL = OpenRouterLanguageModel.defaultBaseURL,
    timeout: TimeInterval = 60,
    appAttribution: OpenRouterAppAttribution? = nil
  ) {
    self.authMode = auth
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.timeoutIntervalForRequest = timeout
    let apiAuth: Configuration.Auth =
      switch auth {
      case .apiKey(let key) where !key.isEmpty: .apiKey(key)
      case .apiKey, .proxied: .none
      }
    self.client = OpenRouterClient(
      configuration: .init(
        auth: apiAuth,
        baseURL: baseURL,
        attribution: appAttribution?.apiValue
      ),
      session: URLSession(configuration: sessionConfiguration)
    )
  }

  init(auth: OpenRouterAuthMode, client: OpenRouterClient) {
    self.authMode = auth
    self.client = client
  }

  public func models() async throws -> [OpenRouterModelMetadata] {
    let response = try await client.listModels(headers: try authHeaders())
    return response.data.map(OpenRouterModelMetadata.init)
  }

  public func languageModels() async throws -> [OpenRouterModel] {
    try await models().map(OpenRouterModel.init(metadata:))
  }

  private func authHeaders() throws -> [String: String] {
    switch authMode {
    case .apiKey(let key):
      guard !key.isEmpty else { throw OpenRouterError.missingCredential }
      return [:]
    case .proxied(let headers):
      return headers
    }
  }
}
