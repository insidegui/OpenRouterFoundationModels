import CoreGraphics
import Foundation
import FoundationModels
import Synchronization
import Testing

@testable import OpenRouterAPI
@testable import OpenRouterFoundationModels

func makeTestImage(width: Int = 4, height: Int = 4) -> CGImage {
  let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return context.makeImage()!
}

extension LanguageModelExecutorGenerationRequest {
  static func make(
    transcript: Transcript,
    enabledTools: [Transcript.ToolDefinition] = [],
    schema: GenerationSchema? = nil,
    generationOptions: GenerationOptions = GenerationOptions(),
    contextOptions: ContextOptions = ContextOptions()
  ) -> Self {
    Self(
      id: UUID(),
      transcript: transcript,
      enabledTools: enabledTools,
      schema: schema,
      generationOptions: generationOptions,
      contextOptions: contextOptions,
      metadata: [:]
    )
  }
}

enum RecordedEvent: Equatable {
  case responseText(entryID: String?, text: String, tokenCount: Int)
  case responseUsage(
    entryID: String?,
    inputTotal: Int,
    inputCached: Int,
    outputTotal: Int,
    outputReasoning: Int
  )
  case toolCallsUsage(
    entryID: String?,
    inputTotal: Int,
    inputCached: Int,
    outputTotal: Int,
    outputReasoning: Int
  )
  case reasoningText(entryID: String?, text: String, tokenCount: Int)
  case toolCallArguments(
    entryID: String?,
    id: String,
    name: String,
    arguments: String,
    tokenCount: Int
  )
  case other(String)

  init(_ event: any LanguageModelExecutorGenerationChannel.Event) {
    typealias Channel = LanguageModelExecutorGenerationChannel
    switch event {
    case let response as Channel.Response:
      switch response.action {
      case .appendText(let fragment):
        self = .responseText(
          entryID: response.entryID,
          text: fragment.content,
          tokenCount: fragment.tokenCount
        )
      case .updateUsage(let usage):
        self = .responseUsage(
          entryID: response.entryID,
          inputTotal: usage.input.totalTokenCount,
          inputCached: usage.input.cachedTokenCount,
          outputTotal: usage.output.totalTokenCount,
          outputReasoning: usage.output.reasoningTokenCount
        )
      default:
        self = .other(String(describing: response.action))
      }

    case let reasoning as Channel.Reasoning:
      switch reasoning.action {
      case .appendText(let fragment):
        self = .reasoningText(
          entryID: reasoning.entryID,
          text: fragment.content,
          tokenCount: fragment.tokenCount
        )
      default:
        self = .other(String(describing: reasoning.action))
      }

    case let toolCalls as Channel.ToolCalls:
      switch toolCalls.action {
      case .toolCall(let call):
        switch call.action {
        case .appendArguments(let fragment):
          self = .toolCallArguments(
            entryID: toolCalls.entryID,
            id: call.id,
            name: call.name,
            arguments: fragment.content,
            tokenCount: fragment.tokenCount
          )
        default:
          self = .other(String(describing: call.action))
        }
      case .updateUsage(let usage):
        self = .toolCallsUsage(
          entryID: toolCalls.entryID,
          inputTotal: usage.input.totalTokenCount,
          inputCached: usage.input.cachedTokenCount,
          outputTotal: usage.output.totalTokenCount,
          outputReasoning: usage.output.reasoningTokenCount
        )
      default:
        self = .other(String(describing: toolCalls.action))
      }

    default:
      self = .other(String(describing: event))
    }
  }
}

func recordedEvents(
  _ produce: @escaping @Sendable (LanguageModelExecutorGenerationChannel) async throws -> Void
) async throws -> [RecordedEvent] {
  let channel = LanguageModelExecutorGenerationChannel()
  let sentinelID = "test.sentinel"

  let producer = Task {
    let sentinel: LanguageModelExecutorGenerationChannel.Response = .response(
      entryID: sentinelID,
      action: .appendText("", tokenCount: 0)
    )
    do {
      try await produce(channel)
    } catch {
      await channel.send(sentinel)
      throw error
    }
    await channel.send(sentinel)
  }

  var events: [RecordedEvent] = []
  for try await event in channel {
    if let response = event as? LanguageModelExecutorGenerationChannel.Response,
      response.entryID == sentinelID
    {
      break
    }
    events.append(RecordedEvent(event))
  }
  try await producer.value
  return events
}

final class MockTransport: HTTPTransport {
  let status: Int
  let body: Data
  private let captured = Mutex<URLRequest?>(nil)

  init(status: Int = 200, body: Data) {
    self.status = status
    self.body = body
  }

  var lastRequest: URLRequest? {
    captured.withLock { $0 }
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    captured.withLock { $0 = request }
    return (body, response(for: request))
  }

  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
    captured.withLock { $0 = request }
    let body = self.body
    let stream = AsyncThrowingStream<UInt8, Error> { continuation in
      for byte in body {
        continuation.yield(byte)
      }
      continuation.finish()
    }
    return (stream, response(for: request))
  }

  private func response(for request: URLRequest) -> URLResponse {
    HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!
  }
}

func jsonObject(from data: Data) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func stream(chunks jsonChunks: [String]) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
  AsyncThrowingStream { continuation in
    do {
      for json in jsonChunks {
        continuation.yield(
          try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))
        )
      }
      continuation.finish()
    } catch {
      continuation.finish(throwing: error)
    }
  }
}
