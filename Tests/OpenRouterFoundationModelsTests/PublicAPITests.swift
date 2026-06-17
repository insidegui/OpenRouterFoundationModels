import Foundation
import FoundationModels
import Testing

@testable import OpenRouterAPI
@testable import OpenRouterFoundationModels

@Suite struct PublicAPITests {
  @Test func `metadata derives model capabilities`() throws {
    let metadata = try JSONDecoder().decode(
      OpenRouterModelMetadata.self,
      from: Data(
        #"""
        {"id":"openai/gpt-5.2","architecture":{"input_modalities":["text","image"],"modality":"text+image->text"},"supported_parameters":["tools","response_format","reasoning"],"context_length":128000,"top_provider":{"max_completion_tokens":8192}}
        """#.utf8
      )
    )

    let model = OpenRouterModel(metadata: metadata)

    #expect(model.id == "openai/gpt-5.2")
    #expect(model.capabilities.toolCalling)
    #expect(model.capabilities.structuredOutput)
    #expect(model.capabilities.reasoning)
    #expect(model.capabilities.imageInput)
    #expect(model.contextLength == 128000)
    #expect(model.maximumResponseTokens == 8192)
  }

  @Test func `language model reports FoundationModels capabilities from model capabilities`() {
    let languageModel = OpenRouterLanguageModel(
      id: "test/model",
      auth: .apiKey("sk"),
      capabilities: .init(
        toolCalling: true,
        structuredOutput: true,
        reasoning: true,
        imageInput: true
      )
    )

    #expect(languageModel.capabilities.contains(.toolCalling))
    #expect(languageModel.capabilities.contains(.guidedGeneration))
    #expect(languageModel.capabilities.contains(.reasoning))
    #expect(languageModel.capabilities.contains(.vision))
  }

  @Test func `executor configuration preserves public init values`() {
    let attribution = OpenRouterAppAttribution(
      httpReferer: URL(string: "https://example.com")!,
      title: "App"
    )
    let model = OpenRouterModel(id: "test/model", capabilities: .text)
    let languageModel = OpenRouterLanguageModel(
      model: model,
      auth: .proxied(headers: ["X-App": "1"]),
      baseURL: URL(string: "https://proxy.test/api/v1")!,
      timeout: 12,
      appAttribution: attribution
    )

    #expect(languageModel.executorConfiguration.model == model)
    #expect(languageModel.executorConfiguration.baseURL.absoluteString == "https://proxy.test/api/v1")
    #expect(languageModel.executorConfiguration.authMode == .proxied(headers: ["X-App": "1"]))
    #expect(languageModel.executorConfiguration.timeout == 12)
    #expect(languageModel.executorConfiguration.appAttribution == attribution)
  }

  @Test func `catalog maps API metadata to public metadata and models`() async throws {
    let transport = MockTransport(
      body: Data(
        #"""
        {"data":[{"id":"anthropic/claude-sonnet-4.6","architecture":{"input_modalities":["text"],"modality":"text->text"},"supported_parameters":["tools","structured_outputs"],"top_provider":{"max_completion_tokens":4096}}]}
        """#.utf8
      )
    )
    let client = OpenRouterClient(
      configuration: .init(auth: .apiKey("sk"), baseURL: URL(string: "https://proxy.test/api/v1")!),
      transport: transport
    )
    let catalog = OpenRouterModelCatalog(auth: .apiKey("sk"), client: client)

    let metadata = try await catalog.models()
    let models = try await catalog.languageModels()

    #expect(metadata[0].id == "anthropic/claude-sonnet-4.6")
    #expect(models[0].capabilities.toolCalling)
    #expect(models[0].capabilities.structuredOutput)
    #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer sk")
  }

  @Test func `catalog proxy auth forwards proxy headers`() async throws {
    let transport = MockTransport(body: Data(#"{"data":[]}"#.utf8))
    let client = OpenRouterClient(
      configuration: .init(auth: .none, baseURL: URL(string: "https://proxy.test/api/v1")!),
      transport: transport
    )
    let catalog = OpenRouterModelCatalog(
      auth: .proxied(headers: ["X-App-Token": "abc"]),
      client: client
    )

    _ = try await catalog.models()

    #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(transport.lastRequest?.value(forHTTPHeaderField: "X-App-Token") == "abc")
  }

  @Test func `empty catalog API key fails before request`() async throws {
    let transport = MockTransport(body: Data(#"{"data":[]}"#.utf8))
    let client = OpenRouterClient(configuration: .init(auth: .none), transport: transport)
    let catalog = OpenRouterModelCatalog(auth: .apiKey(""), client: client)

    let error = try await #require(throws: OpenRouterError.self) {
      _ = try await catalog.models()
    }
    #expect(error == .missingCredential)
    #expect(transport.lastRequest == nil)
  }
}
