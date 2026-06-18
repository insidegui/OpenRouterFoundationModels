import Foundation
import FoundationModels
import OpenRouterAPI

struct EventTranslator: Sendable {
  let responseEntryID: String
  let reasoningEntryID: String
  let toolCallsEntryID: String
  let wireToolNames: [String: String]

  init(
    responseEntryID: String = UUID().uuidString,
    reasoningEntryID: String = UUID().uuidString,
    toolCallsEntryID: String = UUID().uuidString,
    wireToolNames: [String: String] = [:]
  ) {
    self.responseEntryID = responseEntryID
    self.reasoningEntryID = reasoningEntryID
    self.toolCallsEntryID = toolCallsEntryID
    self.wireToolNames = wireToolNames
  }

  func translate(
    _ chunks: AsyncThrowingStream<ChatCompletionChunk, Error>,
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    var toolCallsByIndex: [Int: ToolCallState] = [:]
    var chunkCount = 0

    OpenRouterLog.stream.notice(
      "Translator started responseEntryID=\(responseEntryID, privacy: .public) toolCallsEntryID=\(toolCallsEntryID, privacy: .public) mappedToolNames=\(wireToolNames.count)"
    )

    for try await chunk in chunks {
      try Task.checkCancellation()
      chunkCount += 1

      OpenRouterLog.stream.debug(
        "Translator received chunk index=\(chunkCount) choices=\(chunk.choices.count) hasUsage=\(chunk.usage != nil)"
      )

      if let usage = chunk.usage {
        OpenRouterLog.stream.notice(
          "Translator received usage promptTokens=\(usage.promptTokens) completionTokens=\(usage.completionTokens) reasoningTokens=\(usage.completionTokensDetails?.reasoningTokens ?? 0)"
        )
        await sendUsage(usage, to: channel)
      }

      for choice in chunk.choices {
        if let error = choice.error {
          OpenRouterLog.stream.error(
            "Translator received choice error: \(String(describing: error), privacy: .public)"
          )
          throw error
        }

        if let finishReason = choice.finishReason {
          OpenRouterLog.stream.notice(
            "Translator received finishReason=\(finishReason, privacy: .public) pendingToolCalls=\(toolCallsByIndex.count)"
          )
        }

        if let delta = choice.delta {
          if let content = delta.content, !content.isEmpty {
            OpenRouterLog.stream.debug(
              "Translator forwarding response text bytes=\(content.utf8.count)"
            )
            await channel.send(
              .response(
                entryID: responseEntryID,
                action: .appendText(content, tokenCount: Self.deltaTokenCount)
              )
            )
          }

          if let reasoning = delta.reasoning, !reasoning.isEmpty {
            OpenRouterLog.stream.debug(
              "Translator forwarding reasoning text bytes=\(reasoning.utf8.count)"
            )
            await channel.send(
              .reasoning(
                entryID: reasoningEntryID,
                action: .appendText(reasoning, tokenCount: Self.deltaTokenCount)
              )
            )
          }

          for call in delta.toolCalls ?? [] {
            let index = call.index ?? 0
            var state = toolCallsByIndex[index] ?? ToolCallState()
            if let id = call.id {
              state.id = id
            }
            if let name = call.function.name {
              state.name = name
            }
            state.arguments += call.function.arguments
            toolCallsByIndex[index] = state
            OpenRouterLog.stream.notice(
              "Translator buffered tool delta index=\(index) id=\(state.id ?? "nil", privacy: .public) wireName=\(state.name ?? "nil", privacy: .public) argumentBytes=\(state.arguments.utf8.count)"
            )
          }
        }

        if choice.finishReason == "tool_calls" {
          try await flushOpenToolCalls(&toolCallsByIndex, into: channel)
        }
      }
    }

    try await flushOpenToolCalls(&toolCallsByIndex, into: channel)
    OpenRouterLog.stream.notice(
      "Translator completed chunks=\(chunkCount) pendingToolCalls=\(toolCallsByIndex.count)"
    )
  }

  private static let deltaTokenCount = 1

  private func sendUsage(
    _ usage: Usage,
    to channel: LanguageModelExecutorGenerationChannel
  ) async {
    await channel.send(
      .response(
        entryID: responseEntryID,
        action: .updateUsage(
          input: .init(
            totalTokenCount: usage.promptTokens,
            cachedTokenCount: usage.promptTokensDetails?.cachedTokens ?? 0
          ),
          output: .init(
            totalTokenCount: usage.completionTokens,
            reasoningTokenCount: usage.completionTokensDetails?.reasoningTokens ?? 0
          )
        )
      )
    )
  }

  private struct ToolCallState: Sendable {
    var id: String?
    var name: String?
    var arguments = ""
  }

  private func flushOpenToolCalls(
    _ toolCallsByIndex: inout [Int: ToolCallState],
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    for index in toolCallsByIndex.keys.sorted() {
      guard let state = toolCallsByIndex[index] else { continue }
      guard let id = state.id, let name = state.name else {
        OpenRouterLog.stream.error(
          "Translator cannot flush incomplete tool call index=\(index) id=\(state.id ?? "nil", privacy: .public) wireName=\(state.name ?? "nil", privacy: .public) argumentBytes=\(state.arguments.utf8.count)"
        )
        throw APIError(message: "Incomplete streamed tool call from OpenRouter.")
      }

      let originalName = wireToolNames[name] ?? name
      let arguments = state.arguments.isEmpty ? "{}" : state.arguments
      OpenRouterLog.stream.notice(
        "Translator sending tool call to FoundationModels index=\(index) id=\(id, privacy: .public) wireName=\(name, privacy: .public) originalName=\(originalName, privacy: .public) argumentBytes=\(arguments.utf8.count)"
      )
      await sendToolCall(
        id: id,
        name: originalName,
        arguments: arguments,
        tokenCount: Self.deltaTokenCount,
        to: channel
      )
      OpenRouterLog.stream.notice(
        "Translator sent tool call to channel id=\(id, privacy: .public) originalName=\(originalName, privacy: .public)"
      )
      toolCallsByIndex.removeValue(forKey: index)
    }
  }

  private func sendToolCall(
    id: String,
    name: String,
    arguments: String,
    tokenCount: Int,
    to channel: LanguageModelExecutorGenerationChannel
  ) async {
    await channel.send(
      .toolCalls(
        entryID: toolCallsEntryID,
        action: .toolCall(
          id: id,
          name: name,
          action: .appendArguments(arguments, tokenCount: tokenCount)
        )
      )
    )
  }
}
