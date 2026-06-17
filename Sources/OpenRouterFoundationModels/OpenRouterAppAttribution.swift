import Foundation
import OpenRouterAPI

public struct OpenRouterAppAttribution: Hashable, Sendable {
  public var httpReferer: URL?
  public var title: String?
  public var categories: [String]

  public init(httpReferer: URL? = nil, title: String? = nil, categories: [String] = []) {
    self.httpReferer = httpReferer
    self.title = title
    self.categories = categories
  }

  var apiValue: AppAttribution {
    AppAttribution(httpReferer: httpReferer, title: title, categories: categories)
  }
}
