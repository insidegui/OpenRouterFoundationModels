import Foundation
import Testing

@testable import OpenRouterAPI

@Suite struct SSEParserTests {
  @Test func `parses SSE data frames and ignores comments and done marker`() async throws {
    let sse = [
      ": OPENROUTER PROCESSING\n",
      #"data: {"id":"gen","choices":[{"delta":{"content":"Hi"}}]}"# + "\n\n",
      "data: [DONE]\n\n",
    ].joined()

    var chunks: [ChatCompletionChunk] = []
    for try await chunk in SSEParser.events(from: byteStream(sse)) {
      chunks.append(chunk)
    }

    #expect(chunks.count == 1)
    #expect(chunks[0].choices[0].delta?.content == "Hi")
  }

  @Test func `throws top-level OpenRouter stream errors`() async throws {
    let sse = #"data: {"error":{"code":"server_error","message":"provider down"},"choices":[]}"# + "\n\n"

    let error = try await #require(throws: APIError.self) {
      for try await _ in SSEParser.events(from: byteStream(sse)) {}
    }
    #expect(error.message == "provider down")
  }
}
