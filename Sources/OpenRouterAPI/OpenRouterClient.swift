import Foundation

package struct OpenRouterClient: Sendable {
  package let configuration: Configuration
  private let transport: any HTTPTransport

  package init(configuration: Configuration, session: URLSession = .shared) {
    self.init(
      configuration: configuration,
      transport: URLSessionTransport(session: session)
    )
  }

  package init(configuration: Configuration, transport: any HTTPTransport) {
    self.configuration = configuration
    self.transport = transport
  }

  package func send(
    _ request: ChatCompletionRequest,
    headers: [String: String] = [:]
  ) async throws -> ChatCompletionResponse {
    var body = request
    body.stream = false
    let (data, response) = try await transport.data(
      for: urlRequest(path: "chat/completions", method: "POST", body: body, headers: headers)
    )
    try Self.check(response, body: data)
    let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    if let error = decoded.error { throw error }
    return decoded
  }

  package func stream(
    _ request: ChatCompletionRequest,
    headers: [String: String] = [:]
  ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var body = request
          body.stream = true
          let (bytes, response) = try await transport.bytes(
            for: urlRequest(path: "chat/completions", method: "POST", body: body, headers: headers)
          )
          if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            try Self.check(response, body: body)
          }
          for try await event in SSEParser.events(from: bytes) {
            continuation.yield(event)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  package func listModels(headers: [String: String] = [:]) async throws -> ModelsResponse {
    let (data, response) = try await transport.data(
      for: urlRequest(path: "models", method: "GET", body: Optional<EmptyBody>.none, headers: headers)
    )
    try Self.check(response, body: data)
    return try JSONDecoder().decode(ModelsResponse.self, from: data)
  }

  private func urlRequest<Body: Encodable>(
    path: String,
    method: String,
    body: Body?,
    headers: [String: String]
  ) throws -> URLRequest {
    var request = URLRequest(url: configuration.baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "accept")
    request.setValue("OpenRouterFoundationModels/1", forHTTPHeaderField: "User-Agent")

    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "content-type")
    }

    switch configuration.auth {
    case .apiKey(let key):
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    case .none:
      break
    }

    if let attribution = configuration.attribution {
      if let httpReferer = attribution.httpReferer {
        request.setValue(httpReferer.absoluteString, forHTTPHeaderField: "HTTP-Referer")
      }
      if let title = attribution.title {
        request.setValue(title, forHTTPHeaderField: "X-OpenRouter-Title")
      }
      if !attribution.categories.isEmpty {
        request.setValue(
          attribution.categories.joined(separator: ","),
          forHTTPHeaderField: "X-OpenRouter-Categories"
        )
      }
    }

    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    if let body {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      request.httpBody = try encoder.encode(body)
    }

    return request
  }

  private static func check(_ response: URLResponse, body: Data) throws {
    guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }

    if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: body) {
      var error = envelope.error
      error.httpStatusCode = http.statusCode
      error.requestID =
        http.value(forHTTPHeaderField: "X-Request-ID")
        ?? http.value(forHTTPHeaderField: "X-Generation-Id")
      throw error
    }

    let maxBodyExcerpt = 512
    var excerpt = String(decoding: body.prefix(maxBodyExcerpt), as: UTF8.self)
    if body.count > maxBodyExcerpt {
      excerpt += "... [truncated, \(body.count) bytes total]"
    }
    throw APIError(
      code: .number(Double(http.statusCode)),
      message: "HTTP \(http.statusCode): \(excerpt)",
      httpStatusCode: http.statusCode,
      requestID: http.value(forHTTPHeaderField: "X-Request-ID")
        ?? http.value(forHTTPHeaderField: "X-Generation-Id")
    )
  }
}

private struct EmptyBody: Encodable {}
