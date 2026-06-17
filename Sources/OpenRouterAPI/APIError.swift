import Foundation

package struct APIError: Error, Sendable, Hashable, Codable {
  package var code: JSONValue?
  package var message: String
  package var metadata: JSONValue?
  package var httpStatusCode: Int?
  package var requestID: String?

  package init(
    code: JSONValue? = nil,
    message: String,
    metadata: JSONValue? = nil,
    httpStatusCode: Int? = nil,
    requestID: String? = nil
  ) {
    self.code = code
    self.message = message
    self.metadata = metadata
    self.httpStatusCode = httpStatusCode
    self.requestID = requestID
  }
}

extension APIError: LocalizedError {
  package var errorDescription: String? {
    var components = [message]
    if let code {
      components.append("code: \(code.jsonString)")
    }
    if let httpStatusCode {
      components.append("HTTP \(httpStatusCode)")
    }
    if let requestID {
      components.append("request_id: \(requestID)")
    }
    return components.joined(separator: " (") + String(repeating: ")", count: components.count - 1)
  }
}

package struct APIErrorEnvelope: Decodable {
  package var error: APIError

  package init(error: APIError) {
    self.error = error
  }
}
