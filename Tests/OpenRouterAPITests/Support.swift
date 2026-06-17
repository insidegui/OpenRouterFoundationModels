import Foundation
import Synchronization
import Testing

@testable import OpenRouterAPI

final class MockTransport: HTTPTransport {
  let status: Int
  let headers: [String: String]
  let body: Data
  private let captured = Mutex<URLRequest?>(nil)

  init(status: Int = 200, headers: [String: String] = [:], body: Data) {
    self.status = status
    self.headers = headers
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
      headerFields: headers
    )!
  }
}

func byteStream(_ text: String) -> AsyncThrowingStream<UInt8, Error> {
  let data = Data(text.utf8)
  return AsyncThrowingStream { continuation in
    for byte in data {
      continuation.yield(byte)
    }
    continuation.finish()
  }
}

func jsonObject(from data: Data) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}
