import Foundation

package protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse)
}

package struct URLSessionTransport: HTTPTransport {
  private let session: URLSession

  package init(session: URLSession = .shared) {
    self.session = session
  }

  package func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }

  package func bytes(for request: URLRequest) async throws -> (
    AsyncThrowingStream<UInt8, Error>, URLResponse
  ) {
    let (asyncBytes, response) = try await session.bytes(for: request)
    let stream = AsyncThrowingStream<UInt8, Error> { continuation in
      let task = Task {
        do {
          for try await byte in asyncBytes {
            continuation.yield(byte)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
    return (stream, response)
  }
}
