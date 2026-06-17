import Foundation
import FoundationModels
import Testing

@testable import OpenRouterFoundationModels

@Suite struct OpenRouterExecutorTests {
  @Test func `api key auth sends bearer token`() async throws {
    let transport = MockTransport(body: okStream)
    let executor = OpenRouterExecutor(configuration: config(.apiKey("sk-test")), transport: transport)

    _ = try await recordedEvents { channel in
      try await executor.respond(to: prompt(), model: model(.apiKey("sk-test")), streamingInto: channel)
    }

    #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
  }

  @Test func `proxied auth sends proxy headers and no bearer token`() async throws {
    let auth = OpenRouterAuthMode.proxied(headers: ["X-App-Token": "abc"])
    let transport = MockTransport(body: okStream)
    let executor = OpenRouterExecutor(configuration: config(auth), transport: transport)

    _ = try await recordedEvents { channel in
      try await executor.respond(to: prompt(), model: model(auth), streamingInto: channel)
    }

    #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(transport.lastRequest?.value(forHTTPHeaderField: "X-App-Token") == "abc")
  }

  @Test func `empty API key fails before request`() async throws {
    let transport = MockTransport(body: okStream)
    let executor = OpenRouterExecutor(configuration: config(.apiKey("")), transport: transport)

    let error = try await #require(throws: OpenRouterError.self) {
      _ = try await recordedEvents { channel in
        try await executor.respond(to: prompt(), model: model(.apiKey("")), streamingInto: channel)
      }
    }

    #expect(error == .missingCredential)
    #expect(transport.lastRequest == nil)
  }

  @Test func `streamed text reaches the generation channel`() async throws {
    let transport = MockTransport(body: okStream)
    let executor = OpenRouterExecutor(configuration: config(.apiKey("sk-test")), transport: transport)

    let events = try await recordedEvents { channel in
      try await executor.respond(to: prompt(), model: model(.apiKey("sk-test")), streamingInto: channel)
    }

    #expect(events.contains(.responseText(entryID: nil, text: "Hi", tokenCount: 1)) == false)
    #expect(events.contains { event in
      if case .responseText(_, "Hi", 1) = event { true } else { false }
    })
  }

  @Test func `HTTP API errors are mapped`() async throws {
    let transport = MockTransport(
      status: 429,
      body: Data(#"{"error":{"code":429,"message":"rate limit"}}"#.utf8)
    )
    let executor = OpenRouterExecutor(configuration: config(.apiKey("sk-test")), transport: transport)

    let error = try await #require(throws: LanguageModelError.self) {
      _ = try await recordedEvents { channel in
        try await executor.respond(to: prompt(), model: model(.apiKey("sk-test")), streamingInto: channel)
      }
    }

    guard case .rateLimited = error else {
      Issue.record("expected rateLimited")
      return
    }
  }

  private func config(_ auth: OpenRouterAuthMode) -> OpenRouterExecutor.Configuration {
    .init(
      model: OpenRouterModel(id: "test/model"),
      baseURL: URL(string: "https://proxy.test/api/v1")!,
      authMode: auth,
      timeout: 60
    )
  }

  private func model(_ auth: OpenRouterAuthMode) -> OpenRouterLanguageModel {
    OpenRouterLanguageModel(id: "test/model", auth: auth)
  }

  private func prompt() -> LanguageModelExecutorGenerationRequest {
    .make(
      transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "hi"))]))])
    )
  }

  private let okStream = Data(
    [
      #"data: {"id":"gen","choices":[{"delta":{"content":"Hi"}}]}"#,
      #"data: {"id":"gen","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#,
      "data: [DONE]",
    ]
    .map { $0 + "\n\n" }
    .joined()
    .utf8
  )
}
