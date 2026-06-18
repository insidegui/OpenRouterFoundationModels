import Foundation
import FoundationModels
import OpenRouterAPI

enum RequestBuilder {
  struct Built {
    var request: ChatCompletionRequest
    var isStructured: Bool
    var toolNameMapping: ToolNameMapping
  }

  static func build(
    from request: LanguageModelExecutorGenerationRequest,
    model: OpenRouterModel
  ) throws -> Built {
    var messages: [ChatMessage] = []
    var systemParts: [String] = []
    let toolNameMapping = ToolNameMapping(toolNames: toolNames(in: request))

    OpenRouterLog.request.notice(
      "Building request id=\(request.id.uuidString, privacy: .public) model=\(model.id, privacy: .public) transcriptEntries=\(request.transcript.count) enabledTools=\(request.enabledToolDefinitions.count)"
    )

    for entry in request.transcript {
      switch entry {
      case .instructions(let instructions):
        let instructionText = text(of: instructions.segments)
        if !instructionText.isEmpty {
          systemParts.append(instructionText)
        }

      case .prompt(let prompt):
        messages.append(.user(try messageContent(from: prompt.segments)))

      case .response(let response):
        let responseText = text(of: response.segments)
        if !responseText.isEmpty {
          messages.append(.assistant(responseText))
        }

      case .toolCalls(let calls):
        messages.append(.assistant(toolCalls: calls.map { toolCall($0, mapping: toolNameMapping) }))

      case .toolOutput(let output):
        messages.append(
          .tool(
            id: output.id,
            name: toolNameMapping.wireName(for: output.toolName),
            content: text(of: output.segments)
          )
        )

      case .reasoning:
        // Chat Completions has no documented replay slot for prior reasoning.
        // Omitting it preserves turn replay without inventing unsupported fields.
        continue

      @unknown default:
        continue
      }
    }

    if !systemParts.isEmpty {
      messages.insert(.system(systemParts.joined(separator: "\n\n")), at: 0)
    }

    var chatRequest = ChatCompletionRequest(
      model: model.id,
      messages: messages,
      maxTokens: request.generationOptions.maximumResponseTokens
        ?? model.maximumResponseTokens,
      tools: request.enabledToolDefinitions.isEmpty
        ? nil
        : request.enabledToolDefinitions.map { toolDefinition($0, mapping: toolNameMapping) },
      toolChoice: toolChoice(for: request.generationOptions.toolCallingMode),
      reasoning: reasoning(for: request.contextOptions, model: model),
      includeReasoning: model.capabilities.reasoning ? true : nil,
      stream: true
    )

    for definition in request.enabledToolDefinitions {
      let wireName = toolNameMapping.wireName(for: definition.name)
      if wireName == definition.name {
        OpenRouterLog.request.debug(
          "Tool name accepted by provider original=\(definition.name, privacy: .public)"
        )
      } else {
        OpenRouterLog.request.notice(
          "Mapped FoundationModels tool name original=\(definition.name, privacy: .public) wire=\(wireName, privacy: .public)"
        )
      }
    }

    applySampling(request.generationOptions, to: &chatRequest)

    let isStructured = request.schema != nil
    if let schema = request.schema {
      guard model.capabilities.structuredOutput else {
        throw LanguageModelError.unsupportedGenerationGuide(
          .init(
            schemaName: nil,
            debugDescription:
              "\(model.id) does not declare OpenRouter structured output support."
          )
        )
      }
      chatRequest.responseFormat = .jsonSchema(
        name: "response",
        strict: true,
        schema: jsonSchema(from: schema)
      )
      if request.contextOptions.includeSchemaInPrompt ?? true {
        let hint = "Respond with a single JSON object matching the required schema."
        if let first = chatRequest.messages.first, first.role == .system {
          chatRequest.messages[0] = .system(
            "\(text(from: first.content))\n\n\(hint)"
          )
        } else {
          chatRequest.messages.insert(.system(hint), at: 0)
        }
      }
    }

    OpenRouterLog.request.notice(
      "Built request id=\(request.id.uuidString, privacy: .public) messages=\(chatRequest.messages.count) tools=\(chatRequest.tools?.count ?? 0) hasSchema=\(isStructured) hasReasoning=\(chatRequest.reasoning != nil) toolChoice=\(String(describing: chatRequest.toolChoice), privacy: .public)"
    )

    return Built(
      request: chatRequest,
      isStructured: isStructured,
      toolNameMapping: toolNameMapping
    )
  }

  static func jsonSchema(from schema: GenerationSchema) -> JSONValue {
    guard let value = JSONValue.encoded(schema) else {
      return .object(["type": .string("object")])
    }
    return sanitize(value)
  }

  private static let allowedSchemaKeys: Set<String> = [
    "$defs", "$ref", "additionalProperties", "allOf", "anyOf", "const",
    "definitions", "description", "enum", "format", "items", "oneOf",
    "properties", "required", "type",
  ]

  private static let mapValuedKeys: Set<String> = ["$defs", "definitions", "properties"]

  private static func sanitize(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let object):
      var output: [String: JSONValue] = [:]
      for (key, value) in object where allowedSchemaKeys.contains(key) {
        if mapValuedKeys.contains(key), case .object(let nested) = value {
          output[key] = .object(nested.mapValues(sanitize))
        } else {
          output[key] = sanitize(value)
        }
      }
      if output["type"] == .string("object"), output["additionalProperties"] == nil {
        output["additionalProperties"] = .bool(false)
      }
      return .object(output)
    case .array(let array):
      return .array(array.map(sanitize))
    default:
      return value
    }
  }

  private static func messageContent(from segments: [Transcript.Segment]) throws -> MessageContent {
    let parts = try contentParts(from: segments)
    if parts.count == 1, case .text(let text) = parts[0] {
      return .text(text)
    }
    return .parts(parts)
  }

  private static func contentParts(from segments: [Transcript.Segment]) throws -> [ContentPart] {
    var parts: [ContentPart] = []
    for segment in segments {
      switch segment {
      case .text(let text) where !text.content.isEmpty:
        parts.append(.text(text.content))
      case .text:
        break
      case .structure(let structure):
        parts.append(.text(structure.content.jsonString))
      case .attachment(let attachment):
        switch attachment.content {
        case .image(let image):
          parts.append(
            try OpenRouterImage(
              cgImage: image.cgImage,
              orientation: image.orientation
            ).contentPart
          )
        @unknown default:
          break
        }
      case .custom(let custom):
        let text = String(describing: custom)
        if !text.isEmpty {
          parts.append(.text(text))
        }
      @unknown default:
        break
      }
    }
    return parts.isEmpty ? [.text("")] : parts
  }

  private static func text(of segments: [Transcript.Segment]) -> String {
    segments.compactMap { segment in
      switch segment {
      case .text(let text):
        text.content
      case .structure(let structure):
        structure.content.jsonString
      case .custom(let custom):
        String(describing: custom)
      case .attachment:
        nil
      @unknown default:
        nil
      }
    }
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
  }

  private static func text(from content: MessageContent?) -> String {
    switch content {
    case .text(let text):
      text
    case .parts(let parts):
      parts.compactMap {
        if case .text(let text) = $0 { text } else { nil }
      }
      .joined(separator: "\n")
    case nil:
      ""
    }
  }

  private static func toolNames(in request: LanguageModelExecutorGenerationRequest) -> [String] {
    var names = request.enabledToolDefinitions.map(\.name)
    for entry in request.transcript {
      switch entry {
      case .toolCalls(let calls):
        names.append(contentsOf: calls.map(\.toolName))
      case .toolOutput(let output):
        names.append(output.toolName)
      case .instructions, .prompt, .reasoning, .response:
        break
      @unknown default:
        break
      }
    }
    return names
  }

  private static func toolDefinition(
    _ definition: Transcript.ToolDefinition,
    mapping: ToolNameMapping
  ) -> ToolDefinition {
    ToolDefinition(
      name: mapping.wireName(for: definition.name),
      description: definition.description,
      parameters: jsonSchema(from: definition.parameters)
    )
  }

  private static func toolCall(_ call: Transcript.ToolCall, mapping: ToolNameMapping) -> ToolCall {
    ToolCall(
      id: call.id,
      name: mapping.wireName(for: call.toolName),
      arguments: call.arguments.jsonString
    )
  }

  private static func toolChoice(
    for mode: GenerationOptions.ToolCallingMode?
  ) -> ToolChoice? {
    guard let mode else { return nil }
    switch mode.kind {
    case .allowed:
      return nil
    case .required:
      return .required
    case .disallowed:
      return ToolChoice.none
    @unknown default:
      return nil
    }
  }

  private static func reasoning(
    for options: ContextOptions,
    model: OpenRouterModel
  ) -> ReasoningConfig? {
    guard model.capabilities.reasoning, let level = options.reasoningLevel else { return nil }
    return ReasoningConfig(effort: effort(for: level), exclude: false)
  }

  private static func effort(for level: ContextOptions.ReasoningLevel) -> ReasoningConfig.Effort {
    switch level {
    case .light:
      .low
    case .moderate:
      .medium
    case .deep:
      .high
    case .custom(let value):
      ReasoningConfig.Effort(rawValue: value) ?? .medium
    @unknown default:
      .medium
    }
  }

  private static func applySampling(
    _ options: GenerationOptions,
    to request: inout ChatCompletionRequest
  ) {
    request.temperature = options.temperature
    switch options.samplingMode?.kind {
    case .greedy:
      request.temperature = 0
    case .top(let k, let seed):
      request.topK = k
      request.seed = seed
    case .nucleus(let threshold, let seed):
      request.topP = threshold
      request.seed = seed
    case nil:
      break
    @unknown default:
      break
    }
  }
}
