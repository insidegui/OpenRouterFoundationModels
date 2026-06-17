import Foundation
import FoundationModels
import OpenRouterAPI
import Testing

@testable import OpenRouterFoundationModels

@Suite struct RequestBuilderTests {
  @Test func `instructions become a system message`() throws {
    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [
        .instructions(.init(segments: [.text(.init(content: "Be concise."))], toolDefinitions: [])),
        .prompt(.init(segments: [.text(.init(content: "Hello"))])),
      ])
    )

    let built = try RequestBuilder.build(from: request, model: .init(id: "test/model"))

    #expect(built.request.messages.count == 2)
    #expect(built.request.messages[0].role == .system)
    #expect(built.request.messages[0].content == .text("Be concise."))
    #expect(built.request.messages[1].role == .user)
  }

  @Test func `image attachments become image_url content parts`() throws {
    let image = Transcript.ImageAttachment(makeTestImage())
    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [
        .prompt(
          .init(segments: [
            .text(.init(content: "What is this?")),
            .attachment(.init(content: .image(image), label: "sample")),
          ])
        )
      ])
    )

    let built = try RequestBuilder.build(from: request, model: .init(id: "test/model"))

    guard case .parts(let parts) = built.request.messages[0].content else {
      Issue.record("expected content parts")
      return
    }
    #expect(parts.count == 2)
    guard case .imageURL(let url, let detail) = parts[1] else {
      Issue.record("expected image url")
      return
    }
    #expect(url.hasPrefix("data:image/jpeg;base64,"))
    #expect(detail == .auto)
  }

  @Test func `tool calls and tool outputs map to OpenAI chat messages`() throws {
    let transcript = Transcript(entries: [
      .prompt(.init(segments: [.text(.init(content: "Weather?"))])),
      .toolCalls(
        .init([
          .init(
            id: "call_1",
            toolName: "weather",
            arguments: try GeneratedContent(json: #"{"city":"SF"}"#)
          )
        ])
      ),
      .toolOutput(.init(id: "call_1", toolName: "weather", segments: [.text(.init(content: "72F"))])),
    ])

    let built = try RequestBuilder.build(
      from: .make(transcript: transcript),
      model: .init(id: "test/model")
    )

    #expect(built.request.messages.map(\.role) == [.user, .assistant, .tool])
    #expect(built.request.messages[1].toolCalls?[0].id == "call_1")
    #expect(built.request.messages[1].toolCalls?[0].function.name == "weather")
    #expect(built.request.messages[2].toolCallID == "call_1")
    #expect(built.request.messages[2].content == .text("72F"))
  }

  @Test func `enabled tools and required mode become tools and required tool choice`() throws {
    var options = GenerationOptions()
    options.toolCallingMode = .required
    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Hi"))]))]),
      enabledTools: [
        .init(name: "weather", description: "Weather", parameters: TestArgs.generationSchema)
      ],
      generationOptions: options
    )

    let built = try RequestBuilder.build(from: request, model: .init(id: "test/model"))

    #expect(built.request.tools?.count == 1)
    #expect(built.request.tools?[0].function.name == "weather")
    #expect(built.request.toolChoice == .required)
  }

  @Test func `tool names are sanitized for OpenAI compatible providers`() throws {
    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [
        .prompt(.init(segments: [.text(.init(content: "Hi"))])),
        .toolCalls(
          .init([
            .init(
              id: "call_1",
              toolName: "Email Search",
              arguments: try GeneratedContent(json: #"{"query":"John"}"#)
            )
          ])
        ),
        .toolOutput(
          .init(
            id: "call_1",
            toolName: "Email Search",
            segments: [.text(.init(content: "Found John"))]
          )
        ),
      ]),
      enabledTools: [
        .init(name: "Email Search", description: "Search mail", parameters: TestArgs.generationSchema)
      ]
    )

    let built = try RequestBuilder.build(from: request, model: .init(id: "test/model"))

    #expect(built.request.tools?[0].function.name == "Email_Search")
    #expect(built.request.messages[1].toolCalls?[0].function.name == "Email_Search")
    #expect(built.request.messages[2].name == "Email_Search")
    #expect(built.toolNameMapping.wireToOriginalNames["Email_Search"] == "Email Search")
  }

  @Test func `tool name sanitization resolves collisions deterministically`() throws {
    let mapping = ToolNameMapping(toolNames: ["Email Search", "Email_Search"])

    #expect(mapping.wireName(for: "Email Search") == "Email_Search")
    #expect(mapping.wireName(for: "Email_Search") == "Email_Search_2")
    #expect(mapping.wireToOriginalNames["Email_Search"] == "Email Search")
    #expect(mapping.wireToOriginalNames["Email_Search_2"] == "Email_Search")
  }

  @Test func `structured schema becomes strict response_format`() throws {
    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Plan"))]))]),
      schema: TestArgs.generationSchema
    )

    let built = try RequestBuilder.build(
      from: request,
      model: .init(id: "test/model", capabilities: .init(structuredOutput: true))
    )

    #expect(built.isStructured)
    guard case .jsonSchema(let name, let strict, let schema)? = built.request.responseFormat else {
      Issue.record("expected json_schema response format")
      return
    }
    #expect(name == "response")
    #expect(strict)
    guard case .object(let object) = schema else {
      Issue.record("expected object schema")
      return
    }
    #expect(object["x-order"] == nil)
    #expect(object["title"] == nil)
    #expect(object["additionalProperties"] == .bool(false))
  }

  @Test func `schema on model without structured output throws`() {
    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Plan"))]))]),
      schema: TestArgs.generationSchema
    )

    #expect(throws: LanguageModelError.self) {
      try RequestBuilder.build(from: request, model: .init(id: "test/model"))
    }
  }

  @Test func `reasoning and sampling options map to OpenRouter fields`() throws {
    var generationOptions = GenerationOptions()
    generationOptions.temperature = 0.7
    generationOptions.samplingMode = .random(probabilityThreshold: 0.8, seed: 9)
    generationOptions.maximumResponseTokens = 321

    var contextOptions = ContextOptions()
    contextOptions.reasoningLevel = .deep

    let request = LanguageModelExecutorGenerationRequest.make(
      transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Hi"))]))]),
      generationOptions: generationOptions,
      contextOptions: contextOptions
    )

    let built = try RequestBuilder.build(
      from: request,
      model: .init(id: "test/model", capabilities: .init(reasoning: true))
    )

    #expect(built.request.maxTokens == 321)
    #expect(built.request.temperature == 0.7)
    #expect(built.request.topP == 0.8)
    #expect(built.request.seed == 9)
    #expect(built.request.reasoning?.effort == .high)
    #expect(built.request.includeReasoning == true)
  }
}

@Generable
private struct TestArgs {
  var city: String
}
