import Foundation

package struct Configuration: Sendable {
  package enum Auth: Hashable, Sendable {
    case apiKey(String)
    case none
  }

  package var auth: Auth
  package var baseURL: URL
  package var attribution: AppAttribution?

  package init(
    auth: Auth,
    baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
    attribution: AppAttribution? = nil
  ) {
    self.auth = auth
    self.baseURL = baseURL
    self.attribution = attribution
  }
}

package struct AppAttribution: Hashable, Sendable {
  package var httpReferer: URL?
  package var title: String?
  package var categories: [String]

  package init(httpReferer: URL? = nil, title: String? = nil, categories: [String] = []) {
    self.httpReferer = httpReferer
    self.title = title
    self.categories = categories
  }
}
