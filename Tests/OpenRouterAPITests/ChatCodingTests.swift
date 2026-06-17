import Foundation
import Testing

@testable import OpenRouterAPI

@Suite struct ChatCodingTests {
  @Test func `request encodes OpenRouter chat completion fields`() throws {
    let request = ChatCompletionRequest(
      model: "openai/gpt-5.2",
      messages: [
        .system("Be concise."),
        .user(.parts([.text("Describe this"), .imageURL(url: "data:image/jpeg;base64,abc", detail: .auto)])),
      ],
      maxTokens: 123,
      temperature: 0.2,
      topP: 0.9,
      topK: 4,
      seed: 42,
      tools: [.init(name: "lookup", description: "Lookup data", parameters: .object(["type": .string("object")]))],
      toolChoice: .required,
      responseFormat: .jsonSchema(
        name: "response",
        strict: true,
        schema: .object(["type": .string("object")])
      ),
      reasoning: .init(effort: .high, exclude: false),
      includeReasoning: true,
      stream: true
    )

    let data = try JSONEncoder().encode(request)
    let object = try jsonObject(from: data)
    #expect(object["model"] as? String == "openai/gpt-5.2")
    #expect(object["max_tokens"] as? Int == 123)
    #expect(object["top_p"] as? Double == 0.9)
    #expect(object["top_k"] as? Int == 4)
    #expect(object["seed"] as? Int == 42)
    #expect(object["tool_choice"] as? String == "required")
    #expect(object["include_reasoning"] as? Bool == true)

    let messages = try #require(object["messages"] as? [[String: Any]])
    #expect(messages[0]["role"] as? String == "system")
    let userContent = try #require(messages[1]["content"] as? [[String: Any]])
    #expect(userContent[1]["type"] as? String == "image_url")

    let tools = try #require(object["tools"] as? [[String: Any]])
    #expect(tools[0]["type"] as? String == "function")

    let responseFormat = try #require(object["response_format"] as? [String: Any])
    #expect(responseFormat["type"] as? String == "json_schema")

    let reasoning = try #require(object["reasoning"] as? [String: Any])
    #expect(reasoning["effort"] as? String == "high")
    #expect(reasoning["exclude"] as? Bool == false)
  }

  @Test func `tool choice can force a specific function`() throws {
    let data = try JSONEncoder().encode(ToolChoice.tool(name: "lookup"))
    let object = try jsonObject(from: data)
    #expect(object["type"] as? String == "function")
    let function = try #require(object["function"] as? [String: Any])
    #expect(function["name"] as? String == "lookup")
  }

  @Test func `streaming chunk decodes reasoning aliases and tool deltas`() throws {
    let json = #"""
    {
      "id": "gen",
      "choices": [{
        "index": 0,
        "delta": {
          "reasoning_content": "thinking",
          "tool_calls": [{
            "index": 0,
            "id": "call_1",
            "type": "function",
            "function": {"name": "lookup", "arguments": "{\"q\""}
          }]
        }
      }]
    }
    """#

    let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))
    #expect(chunk.choices[0].delta?.reasoning == "thinking")
    #expect(chunk.choices[0].delta?.toolCalls?[0].id == "call_1")
    #expect(chunk.choices[0].delta?.toolCalls?[0].function.name == "lookup")
  }
}
