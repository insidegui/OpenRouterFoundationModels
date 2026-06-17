import Foundation
import Testing

@testable import OpenRouterFoundationModels

@Suite struct OpenRouterImageTests {
  @Test func `encodes CGImage as JPEG data URL content part`() throws {
    let image = try OpenRouterImage(cgImage: makeTestImage(), orientation: .up)

    #expect(image.mediaType == "image/jpeg")
    #expect(image.dataURL.hasPrefix("data:image/jpeg;base64,"))
    #expect(!image.data.isEmpty)
  }
}
