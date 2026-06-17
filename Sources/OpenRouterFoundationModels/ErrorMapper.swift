import Foundation
import FoundationModels
import OpenRouterAPI

enum ErrorMapper {
  static func map(_ error: any Error) -> any Error {
    if let apiError = error as? APIError {
      return map(apiError)
    }
    if let urlError = error as? URLError, urlError.code == .timedOut {
      return LanguageModelError.timeout(.init(debugDescription: urlError.localizedDescription))
    }
    if let imageError = error as? OpenRouterImage.Error {
      return LanguageModelError.unsupportedTranscriptContent(
        .init(
          unsupportedContent: [],
          debugDescription: imageError.errorDescription ?? "Image could not be prepared."
        )
      )
    }
    return error
  }

  static func map(_ error: APIError) -> any Error {
    let detail = error.errorDescription ?? error.message
    let status = error.httpStatusCode
    let lowercasedMessage = error.message.lowercased()

    if status == 401 {
      return OpenRouterError.missingCredential
    }
    if status == 402 || status == 429 {
      return LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: detail))
    }
    if lowercasedMessage.contains("context") || lowercasedMessage.contains("maximum context") {
      return LanguageModelError.contextSizeExceeded(
        .init(contextSize: 0, tokenCount: 0, debugDescription: detail)
      )
    }
    if lowercasedMessage.contains("moderation") || lowercasedMessage.contains("content filter") {
      return LanguageModelError.guardrailViolation(.init(debugDescription: detail))
    }
    return error
  }
}
