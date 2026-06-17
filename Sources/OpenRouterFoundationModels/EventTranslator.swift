import Foundation
import FoundationModels
import OpenRouterAPI

struct EventTranslator: Sendable {
  let responseEntryID: String
  let reasoningEntryID: String
  let toolCallsEntryID: String

  init(
    responseEntryID: String = UUID().uuidString,
    reasoningEntryID: String = UUID().uuidString,
    toolCallsEntryID: String = UUID().uuidString
  ) {
    self.responseEntryID = responseEntryID
    self.reasoningEntryID = reasoningEntryID
    self.toolCallsEntryID = toolCallsEntryID
  }

  func translate(
    _ chunks: AsyncThrowingStream<ChatCompletionChunk, Error>,
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    var toolCallsByIndex: [Int: ToolCallState] = [:]

    for try await chunk in chunks {
      try Task.checkCancellation()

      if let usage = chunk.usage {
        await sendUsage(usage, to: channel)
      }

      for choice in chunk.choices {
        if let error = choice.error {
          throw error
        }

        if let delta = choice.delta {
          if let content = delta.content, !content.isEmpty {
            await channel.send(
              .response(
                entryID: responseEntryID,
                action: .appendText(content, tokenCount: Self.deltaTokenCount)
              )
            )
          }

          if let reasoning = delta.reasoning, !reasoning.isEmpty {
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
          }
        }

        if choice.finishReason == "tool_calls" {
          try await flushOpenToolCalls(&toolCallsByIndex, into: channel)
        }
      }
    }

    try await flushOpenToolCalls(&toolCallsByIndex, into: channel)
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
        throw APIError(message: "Incomplete streamed tool call from OpenRouter.")
      }

      await sendToolCall(
        id: id,
        name: name,
        arguments: state.arguments.isEmpty ? "{}" : state.arguments,
        tokenCount: Self.deltaTokenCount,
        to: channel
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
