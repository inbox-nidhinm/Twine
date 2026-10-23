import Foundation

/// A tool an AI can call: its name, what it is for, and the shape of its
/// arguments as JSON Schema.
public struct AgentTool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(_ name: String, _ description: String, _ inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// What a tool hands back: text (usually JSON) and pictures.
public struct ToolOutput: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case text(String)
        case png(Data)
    }

    public var parts: [Part]
    public var isError: Bool

    public init(_ parts: [Part], isError: Bool = false) {
        self.parts = parts
        self.isError = isError
    }

    public static func json(_ value: JSONValue) -> ToolOutput { ToolOutput([.text(value.text())]) }
    public static func error(_ message: String) -> ToolOutput { ToolOutput([.text(message)], isError: true) }

    var json: JSONValue {
        let content: [JSONValue] = parts.map {
            switch $0 {
            case .text(let t): ["type": "text", "text": .string(t)]
            case .png(let d): ["type": "image", "data": .string(d.base64EncodedString()), "mimeType": "image/png"]
            }
        }
        return ["content": .array(content), "isError": .bool(isError)]
    }
}

/// A tool's refusal, said plainly so the AI can correct itself.
public struct AgentError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// What one message needs.
public enum MCPMessage: Sendable, Equatable {
    /// A notification, or a reply the client sent: nothing to answer.
    case silent
    /// The whole reply, worked out without the project.
    case answered(Data)
    /// A tool call, which needs the open project.
    case toolCall(id: JSONValue, name: String, arguments: JSONValue)
}

/// The Model Context Protocol's side of Twine: JSON-RPC 2.0 messages, one
/// per line, as MCP's stdio transport sends them. It keeps no state
/// between messages, so a bridge that reconnects after Twine relaunches
/// carries on without a second handshake.
@MainActor
public final class MCPServer {
    public typealias Call = @MainActor (_ name: String, _ arguments: JSONValue) async -> ToolOutput

    /// The versions of the protocol this server speaks, newest first.
    public nonisolated static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let name: String
    let version: String
    let instructions: String
    let tools: [AgentTool]
    let call: Call

    public init(name: String, version: String, instructions: String, tools: [AgentTool], call: @escaping Call) {
        self.name = name
        self.version = version
        self.instructions = instructions
        self.tools = tools
        self.call = call
    }

    /// The reply to one message, or nil for a notification (or a reply the
    /// client sent us, which needs none).
    public func handle(_ line: Data) async -> Data? {
        switch answer(line) {
        case .silent: return nil
        case .answered(let reply): return reply
        case .toolCall(let id, let tool, let arguments):
            let output = await call(tool, arguments)
            return Self.reply(id: id, result: output.json)
        }
    }

    /// `line` answered as far as it can be without calling a tool. Only a
    /// tool call needs the open project: everything else is answered from
    /// the tool list, which never changes, so the bridge answers it alone.
    public nonisolated func answer(_ line: Data) -> MCPMessage {
        guard let message = try? JSONValue.parse(line), case .object = message else {
            return .answered(Self.reply(id: .null, error: (-32700, "Parse error")))
        }
        // Batches were dropped from the protocol; one message at a time.
        guard let method = message["method"]?.string else { return .silent }
        let id = message["id"]
        let params = message["params"] ?? .object([:])
        guard let id else { return .silent }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.string
            let version = asked.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[0]
            return .answered(Self.reply(id: id, result: [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string(name), "version": .string(self.version)],
                "instructions": .string(instructions),
            ]))
        case "ping":
            return .answered(Self.reply(id: id, result: [:]))
        case "tools/list":
            let list: [JSONValue] = tools.map {
                ["name": .string($0.name), "description": .string($0.description), "inputSchema": $0.inputSchema]
            }
            return .answered(Self.reply(id: id, result: ["tools": .array(list)]))
        case "tools/call":
            guard let tool = params["name"]?.string else {
                return .answered(Self.reply(id: id, error: (-32602, "tools/call needs a name")))
            }
            guard tools.contains(where: { $0.name == tool }) else {
                return .answered(Self.reply(id: id, error: (-32602, "There is no tool called \(tool)")))
            }
            return .toolCall(id: id, name: tool, arguments: params["arguments"] ?? .object([:]))
        case "resources/list":
            return .answered(Self.reply(id: id, result: ["resources": []]))
        case "prompts/list":
            return .answered(Self.reply(id: id, result: ["prompts": []]))
        default:
            return .answered(Self.reply(id: id, error: (-32601, "Method not found: \(method)")))
        }
    }

    nonisolated static func reply(id: JSONValue, result: JSONValue) -> Data {
        line(["jsonrpc": "2.0", "id": id, "result": result])
    }

    nonisolated static func reply(id: JSONValue, error: (code: Int, message: String)) -> Data {
        line(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(error.code)), "message": .string(error.message)]])
    }

    /// One message on one line: JSON never has a raw newline outside a
    /// string, and the encoder escapes those inside.
    private nonisolated static func line(_ value: JSONValue) -> Data {
        var data = (try? value.data()) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }
}
