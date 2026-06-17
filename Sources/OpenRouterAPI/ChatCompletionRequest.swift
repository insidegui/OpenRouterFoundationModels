import Foundation

package struct ChatCompletionRequest: Sendable, Hashable, Codable {
  package var model: String
  package var messages: [ChatMessage]
  package var maxTokens: Int?
  package var temperature: Double?
  package var topP: Double?
  package var topK: Int?
  package var seed: UInt64?
  package var tools: [ToolDefinition]?
  package var toolChoice: ToolChoice?
  package var responseFormat: ResponseFormat?
  package var reasoning: ReasoningConfig?
  package var includeReasoning: Bool?
  package var stream: Bool

  package init(
    model: String,
    messages: [ChatMessage],
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    seed: UInt64? = nil,
    tools: [ToolDefinition]? = nil,
    toolChoice: ToolChoice? = nil,
    responseFormat: ResponseFormat? = nil,
    reasoning: ReasoningConfig? = nil,
    includeReasoning: Bool? = nil,
    stream: Bool = false
  ) {
    self.model = model
    self.messages = messages
    self.maxTokens = maxTokens
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.seed = seed
    self.tools = tools
    self.toolChoice = toolChoice
    self.responseFormat = responseFormat
    self.reasoning = reasoning
    self.includeReasoning = includeReasoning
    self.stream = stream
  }

  private enum CodingKeys: String, CodingKey {
    case model, messages, temperature, seed, tools, stream, reasoning
    case maxTokens = "max_tokens"
    case topP = "top_p"
    case topK = "top_k"
    case toolChoice = "tool_choice"
    case responseFormat = "response_format"
    case includeReasoning = "include_reasoning"
  }
}

package struct ChatMessage: Sendable, Hashable, Codable {
  package enum Role: String, Sendable, Hashable, Codable {
    case system
    case user
    case assistant
    case tool
  }

  package var role: Role
  package var content: MessageContent?
  package var toolCalls: [ToolCall]?
  package var toolCallID: String?
  package var name: String?

  package init(
    role: Role,
    content: MessageContent? = nil,
    toolCalls: [ToolCall]? = nil,
    toolCallID: String? = nil,
    name: String? = nil
  ) {
    self.role = role
    self.content = content
    self.toolCalls = toolCalls
    self.toolCallID = toolCallID
    self.name = name
  }

  package static func system(_ text: String) -> ChatMessage {
    ChatMessage(role: .system, content: .text(text))
  }

  package static func user(_ content: MessageContent) -> ChatMessage {
    ChatMessage(role: .user, content: content)
  }

  package static func assistant(_ text: String) -> ChatMessage {
    ChatMessage(role: .assistant, content: .text(text))
  }

  package static func assistant(toolCalls: [ToolCall]) -> ChatMessage {
    ChatMessage(role: .assistant, content: nil, toolCalls: toolCalls)
  }

  package static func tool(id: String, name: String?, content: String) -> ChatMessage {
    ChatMessage(role: .tool, content: .text(content), toolCallID: id, name: name)
  }

  private enum CodingKeys: String, CodingKey {
    case role, content, name
    case toolCalls = "tool_calls"
    case toolCallID = "tool_call_id"
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = try container.decode(Role.self, forKey: .role)
    content = try container.decodeIfPresent(MessageContent.self, forKey: .content)
    toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
    toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
    name = try container.decodeIfPresent(String.self, forKey: .name)
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(role, forKey: .role)
    if let content {
      try container.encode(content, forKey: .content)
    } else if role == .assistant {
      try container.encodeNil(forKey: .content)
    }
    try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
    try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    try container.encodeIfPresent(name, forKey: .name)
  }
}

package enum MessageContent: Sendable, Hashable, Codable {
  case text(String)
  case parts([ContentPart])

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      self = .text(text)
    } else {
      self = .parts(try container.decode([ContentPart].self))
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .text(let text):
      try container.encode(text)
    case .parts(let parts):
      try container.encode(parts)
    }
  }
}

package enum ContentPart: Sendable, Hashable, Codable {
  case text(String)
  case imageURL(url: String, detail: ImageDetail?)

  package enum ImageDetail: String, Sendable, Hashable, Codable {
    case auto
    case low
    case high
  }

  private enum CodingKeys: String, CodingKey {
    case type, text
    case imageURL = "image_url"
  }

  private enum ImageURLCodingKeys: String, CodingKey {
    case url, detail
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .type) {
    case "text":
      self = .text(try container.decode(String.self, forKey: .text))
    case "image_url":
      let image = try container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
      self = .imageURL(
        url: try image.decode(String.self, forKey: .url),
        detail: try image.decodeIfPresent(ImageDetail.self, forKey: .detail)
      )
    case let type:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown content part type '\(type)'"
      )
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
    case .imageURL(let url, let detail):
      try container.encode("image_url", forKey: .type)
      var image = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
      try image.encode(url, forKey: .url)
      try image.encodeIfPresent(detail, forKey: .detail)
    }
  }
}

package struct ToolDefinition: Sendable, Hashable, Codable {
  package var function: FunctionDescription

  package init(name: String, description: String, parameters: JSONValue) {
    self.function = FunctionDescription(
      name: name,
      description: description,
      parameters: parameters
    )
  }

  private enum CodingKeys: String, CodingKey {
    case type, function
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(String.self, forKey: .type)
    function = try container.decode(FunctionDescription.self, forKey: .function)
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("function", forKey: .type)
    try container.encode(function, forKey: .function)
  }
}

package struct FunctionDescription: Sendable, Hashable, Codable {
  package var name: String
  package var description: String?
  package var parameters: JSONValue

  package init(name: String, description: String? = nil, parameters: JSONValue) {
    self.name = name
    self.description = description
    self.parameters = parameters
  }
}

package enum ToolChoice: Sendable, Hashable, Codable {
  case auto
  case none
  case required
  case tool(name: String)

  private enum CodingKeys: String, CodingKey { case type, function }
  private enum FunctionCodingKeys: String, CodingKey { case name }

  package init(from decoder: Decoder) throws {
    let single = try decoder.singleValueContainer()
    if let raw = try? single.decode(String.self) {
      switch raw {
      case "auto": self = .auto
      case "none": self = .none
      case "required": self = .required
      default:
        throw DecodingError.dataCorruptedError(
          in: single,
          debugDescription: "Unknown tool_choice '\(raw)'"
        )
      }
      return
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode(String.self, forKey: .type)
    let function = try container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
    self = .tool(name: try function.decode(String.self, forKey: .name))
  }

  package func encode(to encoder: Encoder) throws {
    switch self {
    case .auto:
      var container = encoder.singleValueContainer()
      try container.encode("auto")
    case .none:
      var container = encoder.singleValueContainer()
      try container.encode("none")
    case .required:
      var container = encoder.singleValueContainer()
      try container.encode("required")
    case .tool(let name):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("function", forKey: .type)
      var function = container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
      try function.encode(name, forKey: .name)
    }
  }
}

package struct ToolCall: Sendable, Hashable, Codable {
  package var index: Int?
  package var id: String?
  package var function: FunctionCall

  package init(index: Int? = nil, id: String? = nil, name: String? = nil, arguments: String) {
    self.index = index
    self.id = id
    self.function = FunctionCall(name: name, arguments: arguments)
  }

  private enum CodingKeys: String, CodingKey {
    case index, id, type, function
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    index = try container.decodeIfPresent(Int.self, forKey: .index)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    function = try container.decode(FunctionCall.self, forKey: .function)
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(index, forKey: .index)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encode("function", forKey: .type)
    try container.encode(function, forKey: .function)
  }
}

package struct FunctionCall: Sendable, Hashable, Codable {
  package var name: String?
  package var arguments: String

  package init(name: String? = nil, arguments: String = "") {
    self.name = name
    self.arguments = arguments
  }

  private enum CodingKeys: String, CodingKey {
    case name, arguments
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encode(arguments, forKey: .arguments)
  }
}

package enum ResponseFormat: Sendable, Hashable, Codable {
  case jsonObject
  case jsonSchema(name: String, strict: Bool, schema: JSONValue)

  private enum CodingKeys: String, CodingKey {
    case type
    case jsonSchema = "json_schema"
  }

  private enum JSONSchemaCodingKeys: String, CodingKey {
    case name, strict, schema
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .type) {
    case "json_object":
      self = .jsonObject
    case "json_schema":
      let schema = try container.nestedContainer(
        keyedBy: JSONSchemaCodingKeys.self,
        forKey: .jsonSchema
      )
      self = .jsonSchema(
        name: try schema.decode(String.self, forKey: .name),
        strict: try schema.decodeIfPresent(Bool.self, forKey: .strict) ?? false,
        schema: try schema.decode(JSONValue.self, forKey: .schema)
      )
    case let type:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown response_format '\(type)'"
      )
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .jsonObject:
      try container.encode("json_object", forKey: .type)
    case .jsonSchema(let name, let strict, let schema):
      try container.encode("json_schema", forKey: .type)
      var jsonSchema = container.nestedContainer(
        keyedBy: JSONSchemaCodingKeys.self,
        forKey: .jsonSchema
      )
      try jsonSchema.encode(name, forKey: .name)
      try jsonSchema.encode(strict, forKey: .strict)
      try jsonSchema.encode(schema, forKey: .schema)
    }
  }
}

package struct ReasoningConfig: Sendable, Hashable, Codable {
  package var effort: Effort?
  package var maxTokens: Int?
  package var exclude: Bool?

  package init(effort: Effort? = nil, maxTokens: Int? = nil, exclude: Bool? = nil) {
    self.effort = effort
    self.maxTokens = maxTokens
    self.exclude = exclude
  }

  private enum CodingKeys: String, CodingKey {
    case effort, exclude
    case maxTokens = "max_tokens"
  }

  package enum Effort: String, Sendable, Hashable, Codable {
    case xhigh
    case high
    case medium
    case low
    case minimal
    case none
  }
}
