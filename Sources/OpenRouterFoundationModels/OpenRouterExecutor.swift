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
    OpenRouterLog.executor.notice(
      "Executor respond started requestID=\(request.id.uuidString, privacy: .public) configuredModel=\(configuration.model.id, privacy: .public) sessionModel=\(model.model.id, privacy: .public)"
    )
    do {
      let built = try RequestBuilder.build(from: request, model: configuration.model)
      OpenRouterLog.executor.notice(
        "Executor built request requestID=\(request.id.uuidString, privacy: .public) wireTools=\(built.request.tools?.count ?? 0)"
      )
      try await stream(
        built.request,
        toolNameMapping: built.toolNameMapping,
        forwardsReasoning: built.forwardsReasoning,
        into: channel
      )
      OpenRouterLog.executor.notice(
        "Executor respond completed requestID=\(request.id.uuidString, privacy: .public)"
      )
    } catch {
      OpenRouterLog.executor.error(
        "Executor respond failed requestID=\(request.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
      )
      throw ErrorMapper.map(error)
    }
  }

  private func stream(
    _ request: ChatCompletionRequest,
    toolNameMapping: ToolNameMapping,
    forwardsReasoning: Bool,
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    OpenRouterLog.executor.notice(
      "Executor streaming request model=\(request.model, privacy: .public) mappedToolNames=\(toolNameMapping.wireToOriginalNames.count) forwardsReasoning=\(forwardsReasoning)"
    )
    try await EventTranslator(
      wireToolNames: toolNameMapping.wireToOriginalNames,
      forwardsReasoning: forwardsReasoning
    ).translate(
      client.stream(request, headers: try authHeaders()),
      into: channel
    )
    OpenRouterLog.executor.notice("Executor stream returned to respond")
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
