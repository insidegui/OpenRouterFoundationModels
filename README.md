# OpenRouterFoundationModels

Use OpenRouter models as server-side models for Apple's FoundationModels `LanguageModelSession` on iOS 27, macOS 27, Mac Catalyst 27, and visionOS 27.
> Disclaimer: most of the code in this repository was written by Codex, I have reviewed and tested it, but use it at your own risk.

```swift
import FoundationModels
import OpenRouterFoundationModels

let model = OpenRouterLanguageModel(
  id: "openai/gpt-5.2",
  auth: .apiKey(openRouterAPIKey),
  capabilities: .init(
    toolCalling: true,
    structuredOutput: true,
    reasoning: true,
    imageInput: true
  )
)

let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "Write one sentence about OpenRouter.")
```

## Model Capabilities

OpenRouter's model catalogue changes continuously, so this package does not hardcode model identifiers. You can construct an `OpenRouterModel` directly when you know the model's capabilities, or derive the capabilities from OpenRouter's `/models` metadata:

```swift
let catalog = OpenRouterModelCatalog(auth: .apiKey(openRouterAPIKey))
let models = try await catalog.languageModels()

let gpt = models.first { $0.id == "openai/gpt-5.2" }!
let languageModel = OpenRouterLanguageModel(model: gpt, auth: .apiKey(openRouterAPIKey))
```

The derived capabilities drive FoundationModels routing:

- `tools` or `tool_choice` -> `.toolCalling`
- `structured_outputs` or `response_format` -> `.guidedGeneration`
- `reasoning`, `include_reasoning`, or `reasoning_effort` -> `.reasoning`
- `image` input modality -> `.vision`

## Authentication

For prototypes and trusted environments, pass an OpenRouter API key:

```swift
OpenRouterLanguageModel(id: "anthropic/claude-sonnet-4.6", auth: .apiKey(key))
```

For production apps, route through your own proxy and let the proxy attach the real OpenRouter credential server-side:

```swift
OpenRouterLanguageModel(
  id: "anthropic/claude-sonnet-4.6",
  auth: .proxied(headers: ["X-App-Token": appToken]),
  baseURL: URL(string: "https://api.example.com/openrouter")!
)
```

Optional app attribution headers are supported:

```swift
let attribution = OpenRouterAppAttribution(
  httpReferer: URL(string: "https://example.com")!,
  title: "Example App",
  categories: ["productivity"]
)
```

## Supported FoundationModels Features

- Text prompts and multi-turn transcripts
- Image attachments for models that declare image input
- Client-side FoundationModels tools through OpenRouter function calling
- Structured output via `response_format: json_schema`
- Reasoning hints through OpenRouter's `reasoning` parameter
- Streaming response text, reasoning text, tool-call argument deltas, and usage
- API key and proxy-header authentication

The package uses Swift 6 language mode under SwiftPM and keeps networking behind an injectable, `Sendable` transport so the public API and executor paths are covered by unit tests without live OpenRouter calls.
