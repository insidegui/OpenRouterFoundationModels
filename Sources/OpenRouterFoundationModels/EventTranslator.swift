import Foundation
import FoundationModels
import OpenRouterAPI

struct EventTranslator: Sendable {
  let responseEntryID: String
  let reasoningEntryID: String
  let toolCallsEntryID: String
  let wireToolNames: [String: String]
  let forwardsReasoning: Bool

  init(
    responseEntryID: String = UUID().uuidString,
    reasoningEntryID: String = UUID().uuidString,
    toolCallsEntryID: String = UUID().uuidString,
    wireToolNames: [String: String] = [:],
    forwardsReasoning: Bool = false
  ) {
    self.responseEntryID = responseEntryID
    self.reasoningEntryID = reasoningEntryID
    self.toolCallsEntryID = toolCallsEntryID
    self.wireToolNames = wireToolNames
    self.forwardsReasoning = forwardsReasoning
  }

  func translate(
    _ chunks: AsyncThrowingStream<ChatCompletionChunk, Error>,
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    var toolCallsByIndex: [Int: ToolCallState] = [:]
    var chunkCount = 0
    var usageTarget = UsageTarget.response

    OpenRouterLog.stream.notice(
      "Translator started responseEntryID=\(responseEntryID, privacy: .public) toolCallsEntryID=\(toolCallsEntryID, privacy: .public) mappedToolNames=\(wireToolNames.count) forwardsReasoning=\(forwardsReasoning)"
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
            usageTarget = .response
            await channel.send(
              .response(
                entryID: responseEntryID,
                action: .appendText(content, tokenCount: Self.deltaTokenCount)
              )
            )
          }

          if let reasoning = delta.reasoning, !reasoning.isEmpty, forwardsReasoning {
            OpenRouterLog.stream.debug(
              "Translator forwarding reasoning text bytes=\(reasoning.utf8.count)"
            )
            usageTarget = .reasoning
            await channel.send(
              .reasoning(
                entryID: reasoningEntryID,
                action: .appendText(reasoning, tokenCount: Self.deltaTokenCount)
              )
            )
          } else if let reasoning = delta.reasoning, !reasoning.isEmpty {
            OpenRouterLog.stream.debug(
              "Translator dropping unsolicited reasoning text bytes=\(reasoning.utf8.count)"
            )
          }

          for call in delta.toolCalls ?? [] {
            usageTarget = .toolCalls
            let index = call.index ?? 0
            var state = toolCallsByIndex[index] ?? ToolCallState()
            if let id = call.id {
              state.id = id
            }
            if let name = call.function.name {
              state.name = name
            }
            let argumentFragment = call.function.arguments
            state.arguments += argumentFragment
            if !argumentFragment.isEmpty {
              state.pendingArgumentFragments.append(argumentFragment)
            }
            toolCallsByIndex[index] = state
            await sendToolCallStartAndPendingIfPossible(
              at: index,
              in: &toolCallsByIndex,
              into: channel
            )
            let hasSentStart = toolCallsByIndex[index]?.hasSentStart ?? false
            OpenRouterLog.stream.notice(
              "Translator buffered tool delta index=\(index) id=\(state.id ?? "nil", privacy: .public) wireName=\(state.name ?? "nil", privacy: .public) fragmentBytes=\(argumentFragment.utf8.count) argumentBytes=\(state.arguments.utf8.count) started=\(hasSentStart)"
            )
          }
        }

        if choice.finishReason == "tool_calls" {
          try await flushOpenToolCalls(&toolCallsByIndex, into: channel)
        }
      }

      if let usage = chunk.usage {
        await sendUsage(usage, target: usageTarget, to: channel)
      }
    }

    try await flushOpenToolCalls(&toolCallsByIndex, into: channel)
    OpenRouterLog.stream.notice(
      "Translator completed chunks=\(chunkCount) pendingToolCalls=\(toolCallsByIndex.count)"
    )
  }

  private static let deltaTokenCount = 1

  private enum UsageTarget: String, Sendable {
    case response
    case reasoning
    case toolCalls
  }

  private func sendUsage(
    _ usage: Usage,
    target: UsageTarget,
    to channel: LanguageModelExecutorGenerationChannel
  ) async {
    let channelUsage = LanguageModelExecutorGenerationChannel.Usage(
      input: .init(
        totalTokenCount: usage.promptTokens,
        cachedTokenCount: usage.promptTokensDetails?.cachedTokens ?? 0
      ),
      output: .init(
        totalTokenCount: usage.completionTokens,
        reasoningTokenCount: usage.completionTokensDetails?.reasoningTokens ?? 0
      )
    )

    OpenRouterLog.stream.notice(
      "Translator forwarding usage target=\(target.rawValue, privacy: .public)"
    )

    switch target {
    case .response:
      await channel.send(
        .response(
          entryID: responseEntryID,
          action: .updateUsage(channelUsage)
        )
      )
    case .reasoning:
      await channel.send(
        .reasoning(
          entryID: reasoningEntryID,
          action: .updateUsage(channelUsage)
        )
      )
    case .toolCalls:
      await channel.send(
        .toolCalls(
          entryID: toolCallsEntryID,
          action: .updateUsage(channelUsage)
        )
      )
    }
  }

  private struct ToolCallState: Sendable {
    var id: String?
    var name: String?
    var arguments = ""
    var pendingArgumentFragments: [String] = []
    var hasSentStart = false
    var hasSentArguments = false
  }

  private func sendToolCallStartAndPendingIfPossible(
    at index: Int,
    in toolCallsByIndex: inout [Int: ToolCallState],
    into channel: LanguageModelExecutorGenerationChannel
  ) async {
    guard var state = toolCallsByIndex[index],
      let id = state.id,
      let name = state.name
    else {
      return
    }

    let originalName = wireToolNames[name] ?? name
    if !state.hasSentStart {
      OpenRouterLog.stream.notice(
        "Translator starting tool call for FoundationModels index=\(index) id=\(id, privacy: .public) wireName=\(name, privacy: .public) originalName=\(originalName, privacy: .public)"
      )
      await sendToolCall(
        id: id,
        name: originalName,
        arguments: "",
        tokenCount: 0,
        to: channel
      )
      state.hasSentStart = true
    }

    for fragment in state.pendingArgumentFragments {
      OpenRouterLog.stream.debug(
        "Translator forwarding tool argument fragment index=\(index) id=\(id, privacy: .public) originalName=\(originalName, privacy: .public) fragmentBytes=\(fragment.utf8.count)"
      )
      await sendToolCall(
        id: id,
        name: originalName,
        arguments: fragment,
        tokenCount: Self.deltaTokenCount,
        to: channel
      )
      state.hasSentArguments = true
    }
    state.pendingArgumentFragments.removeAll()
    toolCallsByIndex[index] = state
  }

  private func flushOpenToolCalls(
    _ toolCallsByIndex: inout [Int: ToolCallState],
    into channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    for index in toolCallsByIndex.keys.sorted() {
      await sendToolCallStartAndPendingIfPossible(at: index, in: &toolCallsByIndex, into: channel)
      guard let state = toolCallsByIndex[index] else { continue }
      guard let id = state.id, let name = state.name else {
        OpenRouterLog.stream.error(
          "Translator cannot flush incomplete tool call index=\(index) id=\(state.id ?? "nil", privacy: .public) wireName=\(state.name ?? "nil", privacy: .public) argumentBytes=\(state.arguments.utf8.count)"
        )
        throw APIError(message: "Incomplete streamed tool call from OpenRouter.")
      }

      let originalName = wireToolNames[name] ?? name
      try validateArguments(state.arguments, index: index, id: id, name: originalName)
      if state.arguments.isEmpty && !state.hasSentArguments {
        OpenRouterLog.stream.notice(
          "Translator finalizing empty tool arguments as empty JSON object index=\(index) id=\(id, privacy: .public) originalName=\(originalName, privacy: .public)"
        )
        await sendToolCall(
          id: id,
          name: originalName,
          arguments: "{}",
          tokenCount: Self.deltaTokenCount,
          to: channel
        )
      }
      OpenRouterLog.stream.notice(
        "Translator finalized tool call id=\(id, privacy: .public) originalName=\(originalName, privacy: .public) argumentBytes=\(state.arguments.utf8.count)"
      )
      toolCallsByIndex.removeValue(forKey: index)
    }
  }

  private func validateArguments(
    _ arguments: String,
    index: Int,
    id: String,
    name: String
  ) throws {
    guard !arguments.isEmpty else { return }
    guard let data = arguments.data(using: .utf8) else {
      OpenRouterLog.stream.error(
        "Translator received non-UTF8 tool arguments index=\(index) id=\(id, privacy: .public) originalName=\(name, privacy: .public)"
      )
      throw APIError(message: "OpenRouter streamed non-UTF8 tool arguments.")
    }
    do {
      _ = try JSONSerialization.jsonObject(with: data)
      OpenRouterLog.stream.debug(
        "Translator validated tool arguments JSON index=\(index) id=\(id, privacy: .public) originalName=\(name, privacy: .public) argumentBytes=\(arguments.utf8.count)"
      )
    } catch {
      OpenRouterLog.stream.error(
        "Translator received invalid JSON tool arguments index=\(index) id=\(id, privacy: .public) originalName=\(name, privacy: .public) argumentBytes=\(arguments.utf8.count): \(String(describing: error), privacy: .public)"
      )
      throw APIError(message: "OpenRouter streamed invalid JSON tool arguments.")
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
