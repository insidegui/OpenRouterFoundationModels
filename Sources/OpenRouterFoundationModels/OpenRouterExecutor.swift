import Foundation
import FoundationModels
import OpenRouterAPI

public struct OpenRouterExecutor: LanguageModelExecutor {
  public typealias Model = OpenRouterLanguageModel

  public struct Configuration: Hashable, Sendable {
    public let model: OpenRouterModel
    public let baseURL: URL
    public let authMode: OpenRouterAuthMode
    public let timeout: TimeInterval
    public let appAttribution: OpenRouterAppAttribution?

    public init(
      model: OpenRouterModel,
      baseURL: URL,
      authMode: OpenRouterAuthMode,
      timeout: TimeInterval,
      appAttribution: OpenRouterAppAttribution? = nil
    ) {
      self.model = model
      self.baseURL = baseURL
      self.authMode = authMode
      self.timeout = timeout
      self.appAttribution = appAttribution
    }
  }

  private let configuration: Configuration
  private let client: OpenRouterClient

  public init(configuration: Configuration) throws {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
    self.init(
      configuration: configuration,
      transport: URLSessionTransport(session: URLSession(configuration: sessionConfiguration))
    )
  }

  init(configuration: Configuration, transport: any HTTPTransport) {
    self.configuration = configuration

    let auth: ConfigurationAuth =
      switch configuration.authMode {
      case .apiKey(let key) where !key.isEmpty:
        .apiKey(key)
      case .apiKey, .proxied:
        .none
      }

    self.client = OpenRouterClient(
      configuration: .init(
        auth: auth.apiValue,
        baseURL: configuration.baseURL,
        attribution: configuration.appAttribution?.apiValue
      ),
      transport: transport
    )
  }

  public func respond(
    to request: LanguageModelExecutorGenerationRequest,
    model: OpenRouterLanguageModel,
    streamingInto channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    do {
      let built = try RequestBuilder.build(from: request, model: configuration.model)
      try await stream(built.request, toolNameMapping: built.toolNameMapping, into: channel)
    } catch {
      throw ErrorMapper.map(error)
    }
  }

  private func stream(
    _ request: ChatCompletionRequest,
    toolNameMapping: ToolNameMapping,
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    try await EventTranslator(wireToolNames: toolNameMapping.wireToOriginalNames).translate(
      client.stream(request, headers: try authHeaders()),
      into: channel
    )
  }

  private func authHeaders() throws -> [String: String] {
    switch configuration.authMode {
    case .apiKey(let key):
      guard !key.isEmpty else { throw OpenRouterError.missingCredential }
      return [:]
    case .proxied(let headers):
      return headers
    }
  }
}

private enum ConfigurationAuth {
  case apiKey(String)
  case none

  var apiValue: OpenRouterAPI.Configuration.Auth {
    switch self {
    case .apiKey(let key):
      .apiKey(key)
    case .none:
      .none
    }
  }
}
