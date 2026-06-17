import Foundation

package enum SSEParser {
  package static func events(
    from bytes: AsyncThrowingStream<UInt8, Error>
  ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let decoder = JSONDecoder()
          var data = ""

          func flush() throws {
            guard !data.isEmpty else { return }
            try emit(data, decoder: decoder, to: continuation)
            data = ""
          }

          func handle(_ line: String) throws {
            if line.isEmpty {
              try flush()
            } else if line.hasPrefix("data:") {
              let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
              data += data.isEmpty ? payload : "\n" + payload
            }
          }

          var line: [UInt8] = []
          var previousByteWasCR = false
          for try await byte in bytes {
            switch byte {
            case UInt8(ascii: "\n") where previousByteWasCR:
              previousByteWasCR = false
            case UInt8(ascii: "\n"), UInt8(ascii: "\r"):
              previousByteWasCR = byte == UInt8(ascii: "\r")
              try handle(String(decoding: line, as: UTF8.self))
              line.removeAll(keepingCapacity: true)
            default:
              previousByteWasCR = false
              line.append(byte)
            }
          }
          if !line.isEmpty {
            try handle(String(decoding: line, as: UTF8.self))
          }
          try flush()
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func emit(
    _ json: String,
    decoder: JSONDecoder,
    to continuation: AsyncThrowingStream<ChatCompletionChunk, Error>.Continuation
  ) throws {
    guard json != "[DONE]" else { return }
    let chunk = try decoder.decode(ChatCompletionChunk.self, from: Data(json.utf8))
    if let error = chunk.error {
      throw error
    }
    continuation.yield(chunk)
  }
}
