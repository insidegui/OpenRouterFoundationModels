import Foundation

struct ToolNameMapping: Sendable, Hashable {
  private var originalToWire: [String: String]
  private var wireToOriginal: [String: String]

  init(toolNames: [String]) {
    var originalToWire: [String: String] = [:]
    var wireToOriginal: [String: String] = [:]
    var usedWireNames: Set<String> = []

    for original in toolNames {
      guard originalToWire[original] == nil else { continue }
      let wire = Self.uniqueWireName(for: original, usedWireNames: usedWireNames)
      originalToWire[original] = wire
      wireToOriginal[wire] = original
      usedWireNames.insert(wire)
    }

    self.originalToWire = originalToWire
    self.wireToOriginal = wireToOriginal
  }

  var wireToOriginalNames: [String: String] {
    wireToOriginal
  }

  func wireName(for original: String) -> String {
    originalToWire[original] ?? Self.sanitizedWireName(original)
  }

  static func sanitizedWireName(_ name: String) -> String {
    var output = ""
    var previousWasReplacement = false

    for scalar in name.unicodeScalars {
      if isAllowedWireNameScalar(scalar) {
        output.unicodeScalars.append(scalar)
        previousWasReplacement = false
      } else if !previousWasReplacement {
        output.append("_")
        previousWasReplacement = true
      }
    }

    let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    let nonEmpty = trimmed.isEmpty ? "tool" : trimmed
    return String(nonEmpty.prefix(maxWireNameLength))
  }

  private static let maxWireNameLength = 64

  private static func uniqueWireName(for original: String, usedWireNames: Set<String>) -> String {
    let sanitized = sanitizedWireName(original)
    guard usedWireNames.contains(sanitized) else { return sanitized }

    var suffixNumber = 2
    while true {
      let suffix = "_\(suffixNumber)"
      let prefixLength = maxWireNameLength - suffix.count
      let candidate = String(sanitized.prefix(prefixLength)) + suffix
      if !usedWireNames.contains(candidate) {
        return candidate
      }
      suffixNumber += 1
    }
  }

  private static func isAllowedWireNameScalar(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 48...57, 65...90, 95, 97...122, 45:
      true
    default:
      false
    }
  }
}
