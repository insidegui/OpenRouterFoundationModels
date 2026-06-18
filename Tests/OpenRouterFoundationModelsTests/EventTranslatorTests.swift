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
        toolCallsEntryID: "tools",
        forwardsReasoning: true
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
    #expect(events.contains(.toolCallsUsage(entryID: "tools", inputTotal: 10, inputCached: 3, outputTotal: 5, outputReasoning: 2)))
  }

  @Test func `routes text only usage to the response entry`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(responseEntryID: "response").translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"content":"Hi"}}]}"#,
          #"{"id":"gen","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#,
        ]),
        into: channel
      )
    }

    #expect(events.contains(.responseUsage(entryID: "response", inputTotal: 10, inputCached: 0, outputTotal: 5, outputReasoning: 0)))
  }

  @Test func `drops reasoning deltas when reasoning was not requested`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(responseEntryID: "response").translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"reasoning":"I should call a tool."}}]}"#,
          #"{"id":"gen","choices":[{"delta":{"content":"Visible"}}]}"#,
        ]),
        into: channel
      )
    }

    #expect(events == [.responseText(entryID: "response", text: "Visible", tokenCount: 1)])
  }

  @Test func `buffers tool arguments that arrive before id and name`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(toolCallsEntryID: "tools").translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"arguments":"{\"q\""}}]}}]}"#,
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":":\"SF\"}"}}]},"finish_reason":"tool_calls"}]}"#,
        ]),
        into: channel
      )
    }

    #expect(events.contains(.toolCallArguments(entryID: "tools", id: "call_1", name: "lookup", arguments: "", tokenCount: 0)))
    #expect(events == [
      .toolCallArguments(entryID: "tools", id: "call_1", name: "lookup", arguments: "", tokenCount: 0),
      .toolCallArguments(entryID: "tools", id: "call_1", name: "lookup", arguments: #"{"q""#, tokenCount: 1),
      .toolCallArguments(entryID: "tools", id: "call_1", name: "lookup", arguments: #":"SF"}"#, tokenCount: 1),
    ])
  }

  @Test func `empty argument tool calls are finalized as empty JSON objects`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(toolCallsEntryID: "tools").translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"refresh"}}]},"finish_reason":"tool_calls"}]}"#
        ]),
        into: channel
      )
    }

    #expect(events.contains(.toolCallArguments(entryID: "tools", id: "call_1", name: "refresh", arguments: "", tokenCount: 0)))
    #expect(events.contains(.toolCallArguments(entryID: "tools", id: "call_1", name: "refresh", arguments: "{}", tokenCount: 1)))
  }

  @Test func `streams tool call argument fragments without replaying the full payload`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(toolCallsEntryID: "tools").translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"spotlight_search","arguments":"{\"query\":\""}}]}}]}"#,
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"type":"function","function":{"arguments":"Documents\"}"}}]},"finish_reason":"tool_calls"}]}"#,
        ]),
        into: channel
      )
    }

    #expect(events == [
      .toolCallArguments(
        entryID: "tools",
        id: "call_1",
        name: "spotlight_search",
        arguments: "",
        tokenCount: 0
      ),
      .toolCallArguments(
        entryID: "tools",
        id: "call_1",
        name: "spotlight_search",
        arguments: #"{"query":""#,
        tokenCount: 1
      ),
      .toolCallArguments(
        entryID: "tools",
        id: "call_1",
        name: "spotlight_search",
        arguments: #"Documents"}"#,
        tokenCount: 1
      )
    ])
  }

  @Test func `maps wire tool names back to original FoundationModels names`() async throws {
    let events = try await recordedEvents { channel in
      try await EventTranslator(
        toolCallsEntryID: "tools",
        wireToolNames: ["Email_Search": "Email Search"]
      ).translate(
        stream(chunks: [
          #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"Email_Search","arguments":"{\"query\":\"John\"}"}}]},"finish_reason":"tool_calls"}]}"#
        ]),
        into: channel
      )
    }

    #expect(events == [
      .toolCallArguments(
        entryID: "tools",
        id: "call_1",
        name: "Email Search",
        arguments: "",
        tokenCount: 0
      ),
      .toolCallArguments(
        entryID: "tools",
        id: "call_1",
        name: "Email Search",
        arguments: #"{"query":"John"}"#,
        tokenCount: 1
      )
    ])
  }

  @Test func `throws invalid tool argument JSON at finish`() async throws {
    let error = try await #require(throws: APIError.self) {
      _ = try await recordedEvents { channel in
        try await EventTranslator(toolCallsEntryID: "tools").translate(
          stream(chunks: [
            #"{"id":"gen","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\"q\""}}]},"finish_reason":"tool_calls"}]}"#
          ]),
          into: channel
        )
      }
    }

    #expect(error.message == "OpenRouter streamed invalid JSON tool arguments.")
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
