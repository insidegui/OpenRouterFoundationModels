import Foundation
import FoundationModels
import OpenRouterFoundationModels

struct EmailSearchTool: Tool {
    let name = "Email Search"
    var description = "Search within the user's email messages"

    @Generable
    struct Arguments {
        @Guide(description: "The term to search for in the user's emails. Matches both subject and message contents.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> some PromptRepresentable {
        fputs("Tool invoked with query: \"\(arguments.query)\"\n", stderr)

        try await Task.sleep(for: .milliseconds(200))

        return [
            """
            Sender: John Appleseed
            Date: 2026-06-12
            Subject: Our last meeting
            Content Summary: John is excited about Buttercup, thinks it's going to be great
            """,
            """
            Sender: John Appleseed
            Date: 2026-06-10
            Subject: We need to talk
            Content Summary: John wants to schedule a meeting about the Buttercup project for the 12th
            """
        ]
    }
}

@main
struct OpenRouterExample {
    static func main() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] else {
            fputs("Set OPENROUTER_API_KEY to run the example.\n", stderr)
            return
        }

        let toolCall = CommandLine.arguments.contains("--tool-call")

        let model = OpenRouterLanguageModel(
            id: "google/gemini-3.5-flash",
            auth: .apiKey(apiKey),
            capabilities: .init(
                toolCalling: true,
                structuredOutput: true,
                reasoning: true,
                imageInput: true
            )
        )

        if toolCall {
            fputs("Testing tool call\n", stderr)
            let session = LanguageModelSession(model: model, tools: [EmailSearchTool()]) {
                """
                You are a personal assistant that's really good at using the available tools to achieve what the user wants.
                When searching for content, use keywords you'd use for a web search, not entire phrases.
                Your responses must be polite and concise. If you don't know something, just say you don't know it.
                DO NOT rely on your knowledge to answer, only answer with what's available in the current context.
                """
            }
            let response = try await session.respond(to: "Which project did John and I talk about recently?")
            print(response.content)
        } else {
            fputs("Testing basic request\n", stderr)
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: "Write one sentence about OpenRouter.")
            print(response.content)
        }
    }
}
