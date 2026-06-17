import Foundation
import Testing

@testable import OpenRouterAPI

@Suite struct OpenRouterClientTests {
  @Test func `send uses bearer auth attribution headers and chat completions path`() async throws {
    let transport = MockTransport(body: Data(responseBody.utf8))
    let client = OpenRouterClient(
      configuration: .init(
        auth: .apiKey("sk-test"),
        baseURL: URL(string: "https://proxy.test/api/v1")!,
        attribution: .init(
          httpReferer: URL(string: "https://example.com")!,
          title: "Example App",
          categories: ["productivity", "developer"]
        )
      ),
      transport: transport
    )

    _ = try await client.send(
      .init(model: "openai/gpt-5.2", messages: [.user(.text("hi"))])
    )

    let request = try #require(transport.lastRequest)
    #expect(request.url?.absoluteString == "https://proxy.test/api/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://example.com")
    #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Title") == "Example App")
    #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Categories") == "productivity,developer")

    let body = try jsonObject(from: try #require(request.httpBody))
    #expect(body["stream"] as? Bool == false)
  }

  @Test func `per-request headers override configured headers for proxy use`() async throws {
    let transport = MockTransport(body: Data(responseBody.utf8))
    let client = OpenRouterClient(
      configuration: .init(auth: .none, baseURL: URL(string: "https://proxy.test/api/v1")!),
      transport: transport
    )

    _ = try await client.send(
      .init(model: "openai/gpt-5.2", messages: [.user(.text("hi"))]),
      headers: ["X-App-Token": "abc"]
    )

    let request = try #require(transport.lastRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "X-App-Token") == "abc")
  }

  @Test func `HTTP errors decode OpenRouter error envelopes`() async throws {
    let transport = MockTransport(
      status: 401,
      headers: ["X-Generation-Id": "gen_123"],
      body: Data(#"{"error":{"code":401,"message":"invalid key"}}"#.utf8)
    )
    let client = OpenRouterClient(configuration: .init(auth: .none), transport: transport)

    let error = try await #require(throws: APIError.self) {
      _ = try await client.send(.init(model: "openai/gpt-5.2", messages: [.user(.text("hi"))]))
    }
    #expect(error.httpStatusCode == 401)
    #expect(error.requestID == "gen_123")
    #expect(error.message == "invalid key")
  }

  @Test func `list models decodes model metadata`() async throws {
    let transport = MockTransport(
      body: Data(
        #"""
        {"data":[{"id":"openai/gpt-5.2","name":"GPT","architecture":{"input_modalities":["text","image"],"output_modalities":["text"],"modality":"text+image->text"},"supported_parameters":["tools","response_format"],"context_length":128000,"top_provider":{"max_completion_tokens":8192}}]}
        """#.utf8
      )
    )
    let client = OpenRouterClient(configuration: .init(auth: .none), transport: transport)

    let models = try await client.listModels().data

    #expect(models.count == 1)
    #expect(models[0].id == "openai/gpt-5.2")
    #expect(models[0].architecture?.inputModalities == ["text", "image"])
    #expect(models[0].supportedParameters == ["tools", "response_format"])
    #expect(models[0].topProvider?.maxCompletionTokens == 8192)

    let request = try #require(transport.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models")
  }

  private let responseBody = #"""
  {"id":"gen","choices":[{"message":{"role":"assistant","content":"ok"}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
  """#
}
