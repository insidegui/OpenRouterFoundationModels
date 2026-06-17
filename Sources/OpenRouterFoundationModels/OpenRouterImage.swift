import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import OpenRouterAPI

struct OpenRouterImage: Sendable {
  enum Error: LocalizedError, Sendable, Equatable {
    case encodingFailed
    case tooLarge(byteCount: Int)

    var errorDescription: String? {
      switch self {
      case .encodingFailed:
        "Image could not be encoded as JPEG."
      case .tooLarge(let byteCount):
        "Encoded image is too large for an inline OpenRouter image payload (\(byteCount) bytes)."
      }
    }
  }

  static let maximumInlineBytes = 20 * 1024 * 1024

  let mediaType: String
  let data: Data

  init(cgImage: CGImage, orientation: CGImagePropertyOrientation) throws {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        "public.jpeg" as CFString,
        1,
        nil
      )
    else {
      throw Error.encodingFailed
    }

    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: 0.9,
      kCGImagePropertyOrientation: orientation.rawValue,
    ]
    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw Error.encodingFailed
    }

    let encoded = data as Data
    guard encoded.count <= Self.maximumInlineBytes else {
      throw Error.tooLarge(byteCount: encoded.count)
    }

    self.mediaType = "image/jpeg"
    self.data = encoded
  }

  var contentPart: ContentPart {
    .imageURL(url: dataURL, detail: .auto)
  }

  var dataURL: String {
    "data:\(mediaType);base64,\(data.base64EncodedString())"
  }
}
