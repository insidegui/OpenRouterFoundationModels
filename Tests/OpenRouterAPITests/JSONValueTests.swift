import Foundation
import Testing

@testable import OpenRouterAPI

@Suite struct JSONValueTests {
  @Test func `parses and re-encodes arbitrary JSON`() throws {
    let value = try #require(JSONValue.parsed(#"{"a":1,"b":[true,null,"x"]}"#))
    guard case .object(let object) = value else {
      Issue.record("expected object")
      return
    }
    #expect(object["a"] == .number(1))
    #expect(object["b"] == .array([.bool(true), .null, .string("x")]))
    #expect(value.jsonString.contains(#""a":1"#))
  }

  @Test func `encodes Encodable values as JSONValue`() {
    struct Payload: Encodable {
      var name = "Ada"
      var count = 2
    }

    let value = JSONValue.encoded(Payload())
    guard case .object(let object)? = value else {
      Issue.record("expected encoded object")
      return
    }
    #expect(object["name"] == .string("Ada"))
    #expect(object["count"] == .number(2))
  }
}
