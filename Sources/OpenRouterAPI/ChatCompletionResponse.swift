import Foundation

package struct ChatCompletionResponse: Sendable, Hashable, Codable {
  package var id: String
  package var choices: [Choice]
  package var model: String?
  package var usage: Usage?
  package var error: APIError?

  package init(
    id: String,
    choices: [Choice],
    model: String? = nil,
    usage: Usage? = nil,
    error: APIError? = nil
  ) {
    self.id = id
    self.choices = choices
    self.model = model
    self.usage = usage
    self.error = error
  }

  package struct Choice: Sendable, Hashable, Codable {
    package var index: Int?
    package var finishReason: String?
    package var nativeFinishReason: String?
    package var message: Message?
    package var text: String?
    package var error: APIError?

    private enum CodingKeys: String, CodingKey {
      case index, message, text, error
      case finishReason = "finish_reason"
      case nativeFinishReason = "native_finish_reason"
    }
  }

  package struct Message: Sendable, Hashable, Codable {
    package var role: String?
    package var content: String?
    package var toolCalls: [ToolCall]?
    package var reasoning: String?

    private enum CodingKeys: String, CodingKey {
      case role, content, reasoning
      case reasoningContent = "reasoning_content"
      case toolCalls = "tool_calls"
    }

    package init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      role = try container.decodeIfPresent(String.self, forKey: .role)
      content = try container.decodeIfPresent(String.self, forKey: .content)
      toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
      reasoning =
        try container.decodeIfPresent(String.self, forKey: .reasoning)
        ?? container.decodeIfPresent(String.self, forKey: .reasoningContent)
    }

    package func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(role, forKey: .role)
      try container.encodeIfPresent(content, forKey: .content)
      try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
      try container.encodeIfPresent(reasoning, forKey: .reasoning)
    }
  }
}

package struct ChatCompletionChunk: Sendable, Hashable, Codable {
  package var id: String?
  package var choices: [StreamingChoice]
  package var model: String?
  package var usage: Usage?
  package var error: APIError?

  package init(
    id: String? = nil,
    choices: [StreamingChoice] = [],
    model: String? = nil,
    usage: Usage? = nil,
    error: APIError? = nil
  ) {
    self.id = id
    self.choices = choices
    self.model = model
    self.usage = usage
    self.error = error
  }
}

package struct StreamingChoice: Sendable, Hashable, Codable {
  package var index: Int?
  package var finishReason: String?
  package var nativeFinishReason: String?
  package var delta: Delta?
  package var error: APIError?

  private enum CodingKeys: String, CodingKey {
    case index, delta, error
    case finishReason = "finish_reason"
    case nativeFinishReason = "native_finish_reason"
  }
}

package struct Delta: Sendable, Hashable, Codable {
  package var role: String?
  package var content: String?
  package var reasoning: String?
  package var toolCalls: [ToolCall]?

  private enum CodingKeys: String, CodingKey {
    case role, content, reasoning
    case reasoningContent = "reasoning_content"
    case toolCalls = "tool_calls"
  }

  package init(
    role: String? = nil,
    content: String? = nil,
    reasoning: String? = nil,
    toolCalls: [ToolCall]? = nil
  ) {
    self.role = role
    self.content = content
    self.reasoning = reasoning
    self.toolCalls = toolCalls
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = try container.decodeIfPresent(String.self, forKey: .role)
    content = try container.decodeIfPresent(String.self, forKey: .content)
    reasoning =
      try container.decodeIfPresent(String.self, forKey: .reasoning)
      ?? container.decodeIfPresent(String.self, forKey: .reasoningContent)
    toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(role, forKey: .role)
    try container.encodeIfPresent(content, forKey: .content)
    try container.encodeIfPresent(reasoning, forKey: .reasoning)
    try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
  }
}

package struct Usage: Sendable, Hashable, Codable {
  package var promptTokens: Int
  package var completionTokens: Int
  package var totalTokens: Int
  package var promptTokensDetails: PromptTokensDetails?
  package var completionTokensDetails: CompletionTokensDetails?

  private enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case completionTokens = "completion_tokens"
    case totalTokens = "total_tokens"
    case promptTokensDetails = "prompt_tokens_details"
    case completionTokensDetails = "completion_tokens_details"
  }

  package init(
    promptTokens: Int,
    completionTokens: Int,
    totalTokens: Int,
    promptTokensDetails: PromptTokensDetails? = nil,
    completionTokensDetails: CompletionTokensDetails? = nil
  ) {
    self.promptTokens = promptTokens
    self.completionTokens = completionTokens
    self.totalTokens = totalTokens
    self.promptTokensDetails = promptTokensDetails
    self.completionTokensDetails = completionTokensDetails
  }
}

package struct PromptTokensDetails: Sendable, Hashable, Codable {
  package var cachedTokens: Int?
  package var cacheWriteTokens: Int?

  private enum CodingKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
    case cacheWriteTokens = "cache_write_tokens"
  }

  package init(cachedTokens: Int? = nil, cacheWriteTokens: Int? = nil) {
    self.cachedTokens = cachedTokens
    self.cacheWriteTokens = cacheWriteTokens
  }
}

package struct CompletionTokensDetails: Sendable, Hashable, Codable {
  package var reasoningTokens: Int?

  private enum CodingKeys: String, CodingKey {
    case reasoningTokens = "reasoning_tokens"
  }

  package init(reasoningTokens: Int? = nil) {
    self.reasoningTokens = reasoningTokens
  }
}
