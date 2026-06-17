import Foundation
import OpenRouterAPI

public struct OpenRouterModelMetadata: Hashable, Sendable, Decodable {
  public var id: String
  public var name: String?
  public var description: String?
  public var architecture: Architecture?
  public var supportedParameters: Set<String>
  public var contextLength: Int?
  public var maxCompletionTokens: Int?

  public init(
    id: String,
    name: String? = nil,
    description: String? = nil,
    architecture: Architecture? = nil,
    supportedParameters: Set<String> = [],
    contextLength: Int? = nil,
    maxCompletionTokens: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.architecture = architecture
    self.supportedParameters = supportedParameters
    self.contextLength = contextLength
    self.maxCompletionTokens = maxCompletionTokens
  }

  public struct Architecture: Hashable, Sendable, Decodable {
    public var inputModalities: Set<String>
    public var outputModalities: Set<String>
    public var modality: String?
    public var tokenizer: String?

    public init(
      inputModalities: Set<String> = [],
      outputModalities: Set<String> = [],
      modality: String? = nil,
      tokenizer: String? = nil
    ) {
      self.inputModalities = inputModalities
      self.outputModalities = outputModalities
      self.modality = modality
      self.tokenizer = tokenizer
    }

    private enum CodingKeys: String, CodingKey {
      case modality, tokenizer
      case inputModalities = "input_modalities"
      case outputModalities = "output_modalities"
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      inputModalities = Set(
        try container.decodeIfPresent([String].self, forKey: .inputModalities) ?? []
      )
      outputModalities = Set(
        try container.decodeIfPresent([String].self, forKey: .outputModalities) ?? []
      )
      modality = try container.decodeIfPresent(String.self, forKey: .modality)
      tokenizer = try container.decodeIfPresent(String.self, forKey: .tokenizer)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, description, architecture
    case supportedParameters = "supported_parameters"
    case contextLength = "context_length"
    case topProvider = "top_provider"
  }

  private enum TopProviderCodingKeys: String, CodingKey {
    case maxCompletionTokens = "max_completion_tokens"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    architecture = try container.decodeIfPresent(Architecture.self, forKey: .architecture)
    supportedParameters = Set(
      try container.decodeIfPresent([String].self, forKey: .supportedParameters) ?? []
    )
    contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
    if let topProvider = try? container.nestedContainer(
      keyedBy: TopProviderCodingKeys.self,
      forKey: .topProvider
    ) {
      maxCompletionTokens = try topProvider.decodeIfPresent(Int.self, forKey: .maxCompletionTokens)
    } else {
      maxCompletionTokens = nil
    }
  }

  init(_ info: ModelInfo) {
    id = info.id
    name = info.name
    description = info.description
    architecture = info.architecture.map {
      Architecture(
        inputModalities: Set($0.inputModalities ?? []),
        outputModalities: Set($0.outputModalities ?? []),
        modality: $0.modality,
        tokenizer: $0.tokenizer
      )
    }
    supportedParameters = Set(info.supportedParameters ?? [])
    contextLength = info.contextLength
    maxCompletionTokens = info.topProvider?.maxCompletionTokens
  }
}
