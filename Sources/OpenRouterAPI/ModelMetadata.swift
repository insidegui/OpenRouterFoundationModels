import Foundation

package struct ModelsResponse: Sendable, Hashable, Codable {
  package var data: [ModelInfo]
}

package struct ModelInfo: Sendable, Hashable, Codable {
  package var id: String
  package var name: String?
  package var description: String?
  package var architecture: Architecture?
  package var supportedParameters: [String]?
  package var contextLength: Int?
  package var topProvider: TopProvider?

  private enum CodingKeys: String, CodingKey {
    case id, name, description, architecture
    case supportedParameters = "supported_parameters"
    case contextLength = "context_length"
    case topProvider = "top_provider"
  }
}

package struct Architecture: Sendable, Hashable, Codable {
  package var inputModalities: [String]?
  package var outputModalities: [String]?
  package var modality: String?
  package var tokenizer: String?

  private enum CodingKeys: String, CodingKey {
    case modality, tokenizer
    case inputModalities = "input_modalities"
    case outputModalities = "output_modalities"
  }
}

package struct TopProvider: Sendable, Hashable, Codable {
  package var contextLength: Int?
  package var maxCompletionTokens: Int?
  package var isModerated: Bool?

  private enum CodingKeys: String, CodingKey {
    case contextLength = "context_length"
    case maxCompletionTokens = "max_completion_tokens"
    case isModerated = "is_moderated"
  }
}
