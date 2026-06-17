import Foundation

public struct OpenRouterModel: Sendable, Hashable {
  public var id: String
  public var capabilities: Capabilities
  public var maximumResponseTokens: Int?
  public var contextLength: Int?

  public init(
    id: String,
    capabilities: Capabilities = .text,
    maximumResponseTokens: Int? = nil,
    contextLength: Int? = nil
  ) {
    self.id = id
    self.capabilities = capabilities
    self.maximumResponseTokens = maximumResponseTokens
    self.contextLength = contextLength
  }

  public init(metadata: OpenRouterModelMetadata) {
    self.init(
      id: metadata.id,
      capabilities: Capabilities(metadata: metadata),
      maximumResponseTokens: metadata.maxCompletionTokens,
      contextLength: metadata.contextLength
    )
  }

  public struct Capabilities: Sendable, Hashable {
    public var toolCalling: Bool
    public var structuredOutput: Bool
    public var reasoning: Bool
    public var imageInput: Bool
    public var supportedParameters: Set<String>

    public init(
      toolCalling: Bool = false,
      structuredOutput: Bool = false,
      reasoning: Bool = false,
      imageInput: Bool = false,
      supportedParameters: Set<String> = []
    ) {
      self.toolCalling = toolCalling
      self.structuredOutput = structuredOutput
      self.reasoning = reasoning
      self.imageInput = imageInput
      self.supportedParameters = supportedParameters
    }

    public static let text = Capabilities()

    public init(metadata: OpenRouterModelMetadata) {
      let supported = metadata.supportedParameters
      let inputModalities = metadata.architecture?.inputModalities ?? []
      let modality = metadata.architecture?.modality?.lowercased() ?? ""

      self.init(
        toolCalling: supported.contains("tools") || supported.contains("tool_choice"),
        structuredOutput: supported.contains("structured_outputs")
          || supported.contains("response_format"),
        reasoning: supported.contains("reasoning")
          || supported.contains("include_reasoning")
          || supported.contains("reasoning_effort"),
        imageInput: inputModalities.contains("image") || modality.contains("image"),
        supportedParameters: supported
      )
    }
  }
}
