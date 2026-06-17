import Foundation
import FoundationModels
import Testing

@testable import OpenRouterAPI
@testable import OpenRouterFoundationModels

@Suite struct ErrorMapperTests {
  @Test func `401 maps to missing credential`() {
    let mapped = ErrorMapper.map(APIError(message: "bad key", httpStatusCode: 401))
    #expect((mapped as? OpenRouterError) == .missingCredential)
  }

  @Test func `429 and 402 map to rate limited`() {
    guard
      case LanguageModelError.rateLimited(let payload) = ErrorMapper.map(
        APIError(message: "slow", httpStatusCode: 429)
      )
    else {
      Issue.record("expected rateLimited")
      return
    }
    #expect(payload.resetDate == nil)
  }

  @Test func `context messages map to contextSizeExceeded`() {
    guard
      case LanguageModelError.contextSizeExceeded = ErrorMapper.map(
        APIError(message: "maximum context length exceeded", httpStatusCode: 400)
      )
    else {
      Issue.record("expected contextSizeExceeded")
      return
    }
  }

  @Test func `timeouts map to LanguageModelError timeout`() {
    guard case LanguageModelError.timeout = ErrorMapper.map(URLError(.timedOut)) else {
      Issue.record("expected timeout")
      return
    }
  }

  @Test func `image errors map to unsupported transcript content`() {
    guard
      case LanguageModelError.unsupportedTranscriptContent(let payload) = ErrorMapper.map(
        OpenRouterImage.Error.tooLarge(byteCount: 42)
      )
    else {
      Issue.record("expected unsupportedTranscriptContent")
      return
    }
    #expect(payload.debugDescription.contains("42"))
  }
}
