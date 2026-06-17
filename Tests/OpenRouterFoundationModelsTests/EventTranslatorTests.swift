import Foundation
import Testing

@testable import OpenRouterAPI
@testable import OpenRouterFoundationModels

@Suite struct EventTranslatorTests {
  @Test func `translates text reasoning usage and tool call deltas`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(
        responseEntryID: "response",
        reasoningEntryID: "reasoning",
        toolCallsEntryID: "tools"
      ).translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"content":"Hi","reasoning":"Think"}}]}"#,
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":""}}]}}]}"#,
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"arguments":"{\"q\":\"SF\"}"}}]}}]}"#,
          #"{"id":"gen","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15,"prompt_tokens_details":{"cached_tokens":3},"completion_tokens_details":{"reasoning_tokens":2}}}"#,
        ]),
        into: channel
      )
    }

    #expect(events.contains(.responseText(entryID: "response", text: "Hi", tokenCount: 1)))
    #expect(events.contains(.reasoningText(entryID: "reasoning", text: "Think", tokenCount: 1)))
    #expect(events.contains(.toolCallArguments(entryID: "tools", id: "call_1", name: "lookup", arguments: "", tokenCount: 0)))
    #expect(events.contains(.toolCallArguments(entryID: "tools", id: "call_1", name: "lookup", arguments: #"{"q":"SF"}"#, tokenCount: 1)))
    #expect(events.contains(.responseUsage(entryID: "response", inputTotal: 10, inputCached: 3, outputTotal: 5, outputReasoning: 2)))
  }

  @Test func `throws choice errors`() async throws {
    let error = try await #require(throws: APIError.self) {
      _ = try await recordedEvents { channel in
        try await EventTranslator().translate(
          stream(chunks: [
            #"{"id":"gen","choices":[{"error":{"code":"server_error","message":"broken"}}]}"#
          ]),
          into: channel
        )
      }
    }

    #expect(error.message == "broken")
  }
}
