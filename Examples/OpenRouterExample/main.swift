import Foundation
import FoundationModels
import OpenRouterFoundationModels

@main
struct OpenRouterExample {
  static func main() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] else {
      print("Set OPENROUTER_API_KEY to run the example.")
      return
    }

    let model = OpenRouterLanguageModel(
      id: "openai/gpt-5.2",
      auth: .apiKey(apiKey),
      capabilities: .init(
        toolCalling: true,
        structuredOutput: true,
        reasoning: true,
        imageInput: true
      )
    )
    let session = LanguageModelSession(model: model)
    let response = try await session.respond(to: "Write one sentence about OpenRouter.")
    print(response.content)
  }
}
