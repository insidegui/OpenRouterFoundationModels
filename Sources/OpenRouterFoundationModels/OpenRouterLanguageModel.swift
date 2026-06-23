import Foundation
import FoundationModels

public struct OpenRouterLanguageModel: Sendable {
  public let model: OpenRouterModel
  public let baseURL: URL
  public let timeout: TimeInterval
  public let appAttribution: OpenRouterAppAttribution?
  let authMode: OpenRouterAuthMode

  public init(
    model: OpenRouterModel,
    auth: OpenRouterAuthMode,
    baseURL: URL = OpenRouterLanguageModel.defaultBaseURL,
    timeout: TimeInterval = 60,
    appAttribution: OpenRouterAppAttribution? = nil
  ) {
    self.model = model
    self.authMode = auth
    self.baseURL = baseURL
    self.timeout = timeout
    self.appAttribution = appAttribution
  }

  public init(
    id: String,
    auth: OpenRouterAuthMode,
    capabilities: OpenRouterModel.Capabilities = .text,
    baseURL: URL = OpenRouterLanguageModel.defaultBaseURL,
    timeout: TimeInterval = 60,
    appAttribution: OpenRouterAppAttribution? = nil
  ) {
    self.init(
      model: OpenRouterModel(id: id, capabilities: capabilities),
      auth: auth,
      baseURL: baseURL,
      timeout: timeout,
      appAttribution: appAttribution
    )
  }

  public func authenticateIfNeeded() async throws {}

  public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!
}

extension OpenRouterLanguageModel: LanguageModel {
  public typealias Executor = OpenRouterExecutor

  public var capabilities: LanguageModelCapabilities {
    var capabilities: [LanguageModelCapabilities.Capability] = []
    if model.capabilities.toolCalling {
      capabilities.append(.toolCalling)
    }
    if model.capabilities.structuredOutput {
      capabilities.append(.guidedGeneration)
    }
    if model.capabilities.reasoning {
      capabilities.append(.reasoning)
    }
    if model.capabilities.imageInput {
      capabilities.append(.vision)
    }
    return LanguageModelCapabilities(capabilities)
  }

  public var executorConfiguration: OpenRouterExecutor.Configuration {
    .init(
      model: model,
      baseURL: baseURL,
      authMode: authMode,
      timeout: timeout,
      appAttribution: appAttribution
    )
  }
}
